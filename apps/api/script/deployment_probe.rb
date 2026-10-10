require_relative "../config/environment"
require "digest"

abort "Dedicated deployment probe only." unless Rails.env.production? && Platform::Record.connection_db_config.database == "mesh_production" && ENV["MESH_DEPLOYMENT_PROBE"] == "true"
connection = Platform::Record.connection
abort "Probe must use runtime role." unless connection.select_value("SELECT current_user") == "mesh_runtime"
key = SecureRandom.uuid
client = Identity::Account.create!(email: "client-#{key}@probe.test", display_name: "Deployment client", password: "ProbePassword2026!", persona: "client")
creator = Identity::Account.create!(email: "creator-#{key}@probe.test", display_name: "Deployment creator", password: "ProbePassword2026!", persona: "creator")
Talent::Profile.create!(account: creator, headline: "Probe author")
project_id = Marketplace::CreateProject.call(actor: client, key: key, input: {
  title: "Deployment identity #{key.first(8)}", category: "Дизайн", description: "Verify the deployed business workflow.",
  budget_minor: 100_005, currency: "RUB", deadline: 30.days.from_now.to_date
}).fetch(:id)
project = Marketplace::Project.find(project_id)
offer = Marketplace::SubmitProposal.call(actor: creator, project: project, key: key, input: { message: "Deliver a versioned identity.", price_minor: 100_005, delivery_days: 7, brief_version: 1 })
award = Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: offer.fetch(:id), brief_version: 1, key: key)
engagement = Engagements::Engagement.find(award.fetch(:id))
bytes = "%PDF-1.4\nSynthetic deployment probe\n%%EOF"
file = Engagements::WorkFile.create!(engagement: engagement, creator: creator, sha256: Digest::SHA256.hexdigest(bytes))
file.file.attach(io: StringIO.new(bytes), filename: "deployment-probe.pdf", content_type: "application/pdf")
ScanWorkFileJob.perform_now(file.id)
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
loop do
  state = Platform::Record.uncached { file.reload.state }
  break if state == "available"
  raise "Real scanner rejected the probe file." if state == "rejected"
  raise "Real scanner did not release the probe file." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 0.5
end
version = Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, title: "Probe identity", content: "A verified private result.", ready_for_acceptance: true, file_ids: [ file.id ], key: key)
Engagements::AcceptSubmission.call(actor: client, engagement: engagement.reload, submission_id: version.fetch(:id), key: key)
journal = Platform::Record.transaction do
  Finance::Ledger.post!(operation_key: "probe-#{key}", description: "Synthetic balanced deployment check", entries: [
    { account_key: "probe-source", currency: "RUB", direction: "debit", amount_minor: 100_005 },
    { account_key: "probe-result", currency: "RUB", direction: "credit", amount_minor: 100_005 }
  ])
end
denied = {}
{
  ddl: "CREATE TABLE runtime_should_not_create (id integer)",
  immutable_history: "UPDATE engagements_submissions SET title='Tampered' WHERE id=#{connection.quote(version.fetch(:id))}",
  posted_journal: "UPDATE finance_ledger_transactions SET description='Tampered' WHERE id=#{connection.quote(journal.id)}"
}.each do |name, sql|
  denied[name] = begin
    connection.execute(sql)
    false
  rescue ActiveRecord::StatementInvalid
    true
  end
end
raise "Runtime privilege or immutable guard failed." unless denied.values.all?
report = {
  checked_at: Time.current.iso8601, environment: "mesh-showcase-release production runtime role",
  business_workflow: "create -> propose -> award -> real file scan -> version -> accept",
  accepted: engagement.reload.state == "accepted", balanced_journal_posted: journal.reload.status == "posted",
  denied: denied, private_file_sha256: file.sha256, storage_file_exists: file.file.blob.service.exist?(file.file.blob.key),
  scope: "Synthetic accounts/results in the isolated production-shaped local deployment. No external payout."
}
puts JSON.pretty_generate(report)
