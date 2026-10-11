require_relative "../config/environment"
require "pg"
require "open3"
require "fileutils"
require "uri"

abort "Restore drill requires development and the dedicated local database." unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == "mesh_development"
abort "Stop the dispatcher before the drill so it cannot claim the test operation." if ENV["MESH_DRILL_DISPATCHER_STOPPED"] != "true"

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
correlation_id = SecureRandom.uuid
client = Identity::Account.find_by!(email: "client@mesh.local")
creator = Identity::Account.find_by!(email: "creator@mesh.local")
operation = nil
Platform::Current.set(actor_id: client.id, correlation_id: correlation_id) do
  project_id = Marketplace::CreateProject.call(
    actor: client, key: correlation_id,
    input: { title: "Restore drill #{correlation_id.first(8)}", category: "Тексты", description: "Verify recovery after an independently committed provider operation.", budget_minor: 10_005, currency: "RUB", deadline: 30.days.from_now.to_date }
  ).fetch(:id)
  project = Marketplace::Project.find(project_id)
  proposal = Marketplace::SubmitProposal.call(actor: creator, project: project, key: correlation_id, input: { message: "Recovery exercise", delivery_days: 1, price_minor: 10_005, brief_version: 1 })
  agreement = Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal.fetch(:id), brief_version: 1, key: correlation_id)
  payment = Finance::RequestOperation.call(actor: client, engagement_id: agreement.fetch(:id), kind: "fund", scenario: "normal", key: correlation_id)
  operation = Finance::PaymentOperation.find(payment.fetch(:id))
end

source_url = ENV.fetch("DATABASE_URL")
restore_name = "mesh_restore_#{SecureRandom.hex(6)}"
abort "Unexpected restore database name." unless restore_name.match?(/\Amesh_restore_[a-f0-9]{12}\z/)
restore_uri = URI(source_url)
restore_uri.path = "/#{restore_name}"
admin_uri = URI(source_url)
admin_uri.path = "/postgres"
output = Rails.root.join("../../.cache/restore-drill")
FileUtils.mkdir_p(output)
dump = output.join("#{restore_name}.dump").to_s

def execute!(*command)
  _, errors, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{errors.lines.last}" unless status.success?
end

begin
  execute!("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", source_url, "--file", dump)
  gateway = Finance::SandboxGateway.new
  provider = gateway.execute(operation)
  Finance::ApplyObservation.call(operation_id: operation.id, observation: provider)
  admin = PG.connect(admin_uri.to_s)
  admin.exec("CREATE DATABASE #{PG::Connection.quote_ident(restore_name)}")
  admin.close
  execute!("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", restore_uri.to_s, dump)

  ENV["MESH_PAYOUTS_ENABLED"] = "false"
  ActiveRecord::Base.establish_connection(restore_uri.to_s)
  restored = Finance::PaymentOperation.find(operation.id)
  before = restored.state
  raise "Snapshot already contained the confirmation." unless before == "requested"
  raise "Snapshot already contained the journal." if Finance::LedgerTransaction.exists?(operation_key: operation.id)
  Platform::Current.set(correlation_id: correlation_id) do
    Finance::Reconcile.call(gateway: gateway)
    raise "Reconciliation did not recover the restored operation." unless restored.reload.state == "confirmed"
    Finance::ApplyObservation.call(operation_id: operation.id, observation: gateway.lookup(operation.id))
  end
  journals = Finance::LedgerTransaction.where(operation_key: operation.id).count
  provider = gateway.lookup(operation.id)
  raise "Recovery created duplicate effects." unless journals == 1 && provider.fetch("post_attempts") == 1
  immutable = begin
    Finance::LedgerTransaction.find_by!(operation_key: operation.id).update_columns(description: "Tampered")
    false
  rescue ActiveRecord::StatementInvalid
    true
  end
  raise "Restored database lost the immutability trigger." unless immutable
  result = {
    drill: "snapshot_before_provider_commit", timestamp: Time.current.iso8601,
    restored_state_before: before, restored_state_after: restored.reload.state,
    provider_post_attempts: provider.fetch("post_attempts"), recovered_journals: journals,
    restored_trigger_verified: immutable, payouts_disabled_during_recovery: true,
    recovered_by_reconciliation_before_duplicate_replay: true,
    dump_sha256: Digest::SHA256.file(dump).hexdigest,
    elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
  }
  evidence = Pathname.new(ENV.fetch("MESH_EVIDENCE_DIR", "/workspace/docs/evidence"))
  FileUtils.mkdir_p(evidence)
  File.write(evidence.join("restore-drill.json"), JSON.pretty_generate(result) + "\n")
  puts JSON.pretty_generate(result)
ensure
  ActiveRecord::Base.establish_connection(source_url)
  admin = PG.connect(admin_uri.to_s)
  admin.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(restore_name)} WITH (FORCE)")
  admin.close
end
