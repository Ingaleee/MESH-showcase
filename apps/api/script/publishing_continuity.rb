require_relative "../config/environment"
require_relative "../lib/recovery_archive"
require "pg"
require "open3"
require "fileutils"
require "zip"

abort "Dedicated quiescent showcase only" unless Rails.env.development? && Platform::Record.connection_db_config.database == "mesh_development" && ENV["MESH_RECOVERY_QUIESCED"] == "true"
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
source = ENV.fetch("DATABASE_URL")
queue = ENV.fetch("QUEUE_DATABASE_URL")
suffix = SecureRandom.hex(6)
directory = Rails.root.join("../../.cache/continuity/#{suffix}")
snapshot = directory.join("snapshot")
restored_storage = directory.join("restored-files")
FileUtils.mkdir_p(snapshot.join("files"))

def command!(*args)
  _, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error.lines.last}" unless status.success?
end

def counts(url)
  database = PG.connect(url)
  tables = database.exec("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").map { |row| row.fetch("tablename") }
  tables.to_h { |table| [ table, database.exec("SELECT COUNT(*) FROM #{PG::Connection.quote_ident(table)}").first.fetch("count").to_i ] }
ensure
  database&.close
end

def candidate_for(operator, partner, version)
  html = "<html>Portable recovery #{version}</html>"
  bytes = Zip::OutputStream.write_buffer { |archive| archive.put_next_entry("index.html"); archive.write(html) }.string
  manifest = { "schema_version" => 1, "title" => "Recovery fixture", "version" => version, "contract_version" => "1", "entrypoint" => "index.html",
    "files" => [ { "path" => "index.html", "size" => html.bytesize, "sha256" => Digest::SHA256.hexdigest(html) } ] }
  submitted = Publishing::SubmitCandidate.call(actor: operator, partner: partner, manifest: manifest, bytes: bytes, key: SecureRandom.uuid)
  candidate = Publishing::Candidate.find(submitted.fetch(:id))
  validation = Publishing::Validation.find(submitted.fetch(:validation_id))
  Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(data) { Talent::FileScanner.scan(data) })
  raise "Real validation failed" unless validation.reload.state == "passed"
  [ candidate, validation ]
end

operator = Identity::Account.create!(email: "restore-#{suffix}@probe.test", display_name: "Recovery operator", password: "RestoreProbe2026!", persona: "client", operator: true)
partner = Publishing::Partner.find(Publishing::RegisterPartner.call(actor: operator,
  input: { name: "Recovery studio #{suffix}", origin: "http://partner:3216", credential_ref: "SHOWCASE" }, key: SecureRandom.uuid).fetch(:id))
first, validation = candidate_for(operator, partner, "1.0.0")
base = Publishing::Deployment.find(Publishing::RequestDeployment.call(actor: operator, candidate: first, validation_id: validation.id, key: SecureRandom.uuid).fetch(:id))
Publishing::ProcessDeployment.call(deployment_id: base.id)
raise "Initial external publication failed" unless base.reload.state == "confirmed"
second, validation2 = candidate_for(operator, partner, "2.0.0")
pending = Publishing::Deployment.find(Publishing::RequestDeployment.call(actor: operator, candidate: second, validation_id: validation2.id, scenario: "timeout_after_success", key: SecureRandom.uuid).fetch(:id))

primary_counts = counts(source)
queue_counts = counts(queue)
command!("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", source, "--file", snapshot.join("primary.dump").to_s)
command!("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", queue, "--file", snapshot.join("queue.dump").to_s)
inventory = ActiveStorage::Blob.order(:key).map do |blob|
  raise "Unsafe storage key" unless blob.key.match?(/\A[a-zA-Z0-9_-]+\z/)
  bytes = blob.download
  raise "Stored size mismatch" unless bytes.bytesize == blob.byte_size
  target = snapshot.join("files/#{blob.key}.bin")
  File.binwrite(target, bytes)
  { key: blob.key, size: blob.byte_size, sha256: Digest::SHA256.hexdigest(bytes) }
end
manifest = { schema_version: 1, checked_at: Time.current.iso8601, primary_counts: primary_counts, queue_counts: queue_counts, blobs: inventory,
  databases: %w[primary queue].to_h { |name| [ name, Digest::SHA256.file(snapshot.join("#{name}.dump")).hexdigest ] } }
File.write(snapshot.join("complete.json"), JSON.pretty_generate(manifest) + "\n")

key_root = Rails.root.join("../../.cache/recovery-keys")
FileUtils.mkdir_p(key_root)
key_file = key_root.join("#{suffix}.key")
key = SecureRandom.random_bytes(32)
File.open(key_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.binmode; file.write(key) }
plain = directory.join("snapshot.tar")
encrypted = directory.join("snapshot.meshbak")
command!("tar", "-cf", plain.to_s, "-C", snapshot.to_s, "complete.json", "primary.dump", "queue.dump", "files")
RecoveryArchive.encrypt(plain, encrypted, key: key)
wrong_key_denied = begin
  RecoveryArchive.decrypt(encrypted, directory.join("wrong-key.tar"), key: SecureRandom.random_bytes(32)); false
rescue OpenSSL::Cipher::CipherError
  true
end
corrupt = directory.join("corrupt.meshbak")
FileUtils.cp(encrypted, corrupt)
File.open(corrupt, "r+b") { |file| file.seek(-17, IO::SEEK_END); byte = file.read(1).ord; file.seek(-17, IO::SEEK_END); file.write((byte ^ 1).chr) }
corruption_denied = begin
  RecoveryArchive.decrypt(corrupt, directory.join("corrupt.tar"), key: key); false
rescue OpenSSL::Cipher::CipherError
  true
end
raise "Backup authentication failed its negative controls" unless wrong_key_denied && corruption_denied
decrypted = directory.join("authenticated.tar")
RecoveryArchive.decrypt(encrypted, decrypted, key: File.binread(key_file))
verified = directory.join("verified")
FileUtils.mkdir_p(verified)
command!("tar", "-xf", decrypted.to_s, "-C", verified.to_s, "--no-same-owner", "--no-same-permissions")
read_manifest = JSON.parse(File.read(verified.join("complete.json")))
read_manifest.fetch("databases").each { |name, hash| raise "Dump integrity mismatch" unless Digest::SHA256.file(verified.join("#{name}.dump")).hexdigest == hash }

# External partner commits after the snapshot. It is never rewound with the local databases.
Publishing::ProcessDeployment.call(deployment_id: pending.id)
raise "Lost response not observed" unless pending.reload.state == "unknown"
gateway = Publishing::PartnerGateway.new
remote_before = gateway.lookup(pending)
partner_state = -> { Platform::HttpClient.new(origin: partner.origin, allow_http: true).request(method: :get, path: "/state", token: Publishing::Settings.token(partner)).body }
post_count = -> { partner_state.call.fetch("requests").find { |row| row.fetch("route") == "publish" }.fetch("count") }
posts_before_recovery = post_count.call
raise "Partner did not commit" unless remote_before && remote_before["operation_id"] == pending.id

admin_uri = URI(source)
admin_uri.path = "/postgres"
restore_url = URI(source)
restore_url.path = "/mesh_continuity_#{suffix}"
queue_url = URI(queue)
queue_url.path = "/mesh_continuity_queue_#{suffix}"
created = []
begin
  admin = PG.connect(admin_uri.to_s)
  [ restore_url, queue_url ].each do |url|
    name = url.path.delete_prefix("/")
    admin.exec("CREATE DATABASE #{PG::Connection.quote_ident(name)}")
    created << name
  end
  admin.close
  command!("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", restore_url.to_s, verified.join("primary.dump").to_s)
  command!("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", queue_url.to_s, verified.join("queue.dump").to_s)
  raise "Primary rows lost" unless counts(restore_url.to_s) == primary_counts
  raise "Queue metadata lost" unless counts(queue_url.to_s) == queue_counts
  service = ActiveStorage::Service::DiskService.new(root: restored_storage)
  inventory.each do |blob|
    bytes = File.binread(verified.join("files/#{blob[:key]}.bin"))
    raise "File integrity mismatch" unless Digest::SHA256.hexdigest(bytes) == blob[:sha256]
    service.upload(blob[:key], StringIO.new(bytes))
  end
  ActiveRecord::Base.establish_connection(restore_url.to_s)
  ActiveStorage::Blob.services = { "local" => service }
  ActiveStorage::Blob.service = service
  restored = Publishing::Deployment.find(pending.id)
  raise "Wrong snapshot state" unless restored.state == "pending"
  raise "Initial active state lost" unless Publishing::Partner.find(partner.id).active_deployment_id == base.id
  # Recovery mode marks all unconfirmed snapshot intents as unknown before any workers are enabled.
  Publishing::Deployment.where(state: %w[pending dispatching]).find_each do |row|
    row.update!(state: "unknown", claim_token: nil, lease_until: nil, last_error: "SNAPSHOT_RECONCILIATION_REQUIRED")
  end
  Publishing::ProcessDeployment.call(deployment_id: restored.id)
  raise "Reconciliation failed" unless restored.reload.state == "confirmed"
  raise "External state differs" unless restored.remote_id == remote_before["deployment_id"]
  remote_after = gateway.lookup(restored)
  raise "Repeated external effect" unless remote_after == remote_before
  posts_after_recovery = post_count.call
  raise "Recovery made another external POST" unless posts_after_recovery == posts_before_recovery
  candidate = Publishing::Candidate.find(second.id)
  raise "Private bytes differ" unless Digest::SHA256.hexdigest(candidate.artifact_blob.download) == candidate.artifact_sha256
  browser = ActionDispatch::Integration::Session.new(Rails.application)
  browser.host! "localhost"
  browser.get "/api/v1/session"
  csrf = JSON.parse(browser.response.body).fetch("csrf_token")
  browser.post "/api/v1/session", params: { session: { email: operator.email, password: "RestoreProbe2026!" } },
    headers: { "X-CSRF-Token" => csrf }, as: :json
  raise "Restored operator could not sign in" unless browser.response.status == 200
  browser.get "/api/v1/publishing/candidates/#{candidate.id}/artifact"
  raise "Restored private HTTP artifact differs" unless browser.response.status == 200 &&
    Digest::SHA256.hexdigest(browser.response.body) == candidate.artifact_sha256
  Publishing::ApplyObservation.call(deployment: restored, observation: remote_after)
  raise "Replay changed active version" unless Publishing::Partner.find(partner.id).active_deployment_id == pending.id
  report = { checked_at: Time.current.iso8601, schema_version: 1, environment: "isolated Docker Desktop",
    partner_publish_requests_before_recovery: posts_before_recovery, partner_publish_requests_after_recovery: posts_after_recovery,
    primary_tables_verified: primary_counts.size, queue_tables_verified: queue_counts.size,
    private_objects_verified: inventory.size, private_bytes: inventory.sum { |row| row[:size] },
    private_http_artifact_verified: true, restored_pending_reconciled: true, remote_identity_unchanged: true, replay_preserved_active: true,
    wrong_key_denied: wrong_key_denied, ciphertext_corruption_denied: corruption_denied,
    encrypted_backup_sha256: Digest::SHA256.file(encrypted).hexdigest,
    elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
    backup_key_path: key_file.to_s, encrypted_backup_path: encrypted.to_s,
    rpo: "Quiescent snapshot of primary and queue; all local writers stopped.",
    scope: "Two newly created databases and a clean private-file directory on the same PostgreSQL host. Independent partner process remains live. No whole-host/offsite disaster claim." }
  evidence = Pathname.new(ENV.fetch("MESH_EVIDENCE_DIR", "/workspace/.cache/acceptance-evidence"))
  FileUtils.mkdir_p(evidence)
  File.write(evidence.join("publishing-continuity.json"), JSON.pretty_generate(report) + "\n")
  puts JSON.pretty_generate(report.except(:backup_key_path, :encrypted_backup_path))
ensure
  ActiveRecord::Base.establish_connection(source)
  # Bring the source operation up to date before normal callbacks/workers resume.
  Publishing::ProcessDeployment.call(deployment_id: pending.id)
  admin = PG.connect(admin_uri.to_s)
  created.each { |name| admin.exec("DROP DATABASE #{PG::Connection.quote_ident(name)} WITH (FORCE)") }
  admin.close
end
