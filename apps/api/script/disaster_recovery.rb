require_relative "../config/environment"
require_relative "../lib/portable_snapshot"
require "pg"
require "open3"
require "zip"

abort "Hosted isolated recovery only" unless Rails.env.production? && ENV["GITHUB_ACTIONS"] == "true" && ENV["MESH_RECOVERY_QUIESCED"] == "true"
root = Pathname.new("/recovery")
key_text = ENV.fetch("MESH_DR_KEY")
abort "Independent recovery key is missing" unless key_text.match?(/\A[a-f0-9]{64}\z/)
key = [ key_text ].pack("H*")
source = ENV.fetch("DATABASE_URL")
queue = ENV.fetch("QUEUE_DATABASE_URL")
fixture = root.join("fixture.json")

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

def create_package(operator, partner, version)
  content = "<html>Independent VM recovery #{version}</html>"
  bytes = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("index.html"); zip.write(content) }.string
  manifest = { "schema_version" => 1, "title" => "Portable studio", "version" => version, "contract_version" => "1", "entrypoint" => "index.html",
    "files" => [ { "path" => "index.html", "size" => content.bytesize, "sha256" => Digest::SHA256.hexdigest(content) } ] }
  row = Publishing::SubmitCandidate.call(actor: operator, partner: partner, manifest: manifest, bytes: bytes, key: SecureRandom.uuid)
  candidate = Publishing::Candidate.find(row.fetch(:id))
  validation = Publishing::Validation.find(row.fetch(:validation_id))
  Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(data) { Talent::FileScanner.scan(data) })
  raise "Actual scanner/contract validation failed" unless validation.reload.state == "passed"
  deployment = Publishing::Deployment.find(Publishing::RequestDeployment.call(actor: operator, candidate: candidate,
    validation_id: validation.id, scenario: version == "2.0.0" ? "timeout_after_success" : "normal", key: SecureRandom.uuid).fetch(:id))
  [ candidate, deployment ]
end

def partner_state(partner)
  Platform::HttpClient.new(origin: partner.origin, allow_http: true).request(method: :get, path: "/state", token: Publishing::Settings.token(partner)).body
end

case ARGV.fetch(0)
when "source"
  operator = Identity::Account.create!(email: "dr-operator@probe.test", display_name: "Recovery operator", password: "RecoveryProbe2026!", persona: "client", operator: true)
  partner = Publishing::Partner.find(Publishing::RegisterPartner.call(actor: operator, input: { name: "Portable Studio", origin: "http://partner:3216", credential_ref: "SHOWCASE" }, key: SecureRandom.uuid).fetch(:id))
  _, baseline = create_package(operator, partner, "1.0.0")
  Publishing::ProcessDeployment.call(deployment_id: baseline.id)
  raise "Baseline publication failed" unless baseline.reload.state == "confirmed"
  candidate, pending = create_package(operator, partner, "2.0.0")
  data = { operator_id: operator.id, partner_id: partner.id, candidate_id: candidate.id, baseline_id: baseline.id, pending_id: pending.id }
  fixture.write(JSON.generate(data))
  snapshot = root.join("snapshot")
  FileUtils.mkdir_p(snapshot.join("files"))
  command!("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", source, "--file", snapshot.join("primary.dump").to_s)
  command!("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", queue, "--file", snapshot.join("queue.dump").to_s)
  blobs = ActiveStorage::Blob.order(:key).map do |blob|
    raise "Unsafe storage key" unless blob.key.match?(/\A[a-zA-Z0-9_-]+\z/)
    bytes = blob.download
    raise "Private file size mismatch" unless bytes.bytesize == blob.byte_size
    snapshot.join("files/#{blob.key}.bin").binwrite(bytes)
    { key: blob.key, sha256: Digest::SHA256.hexdigest(bytes), size: bytes.bytesize }
  end
  snapshot.join("fixture.json").write(JSON.generate(data))
  PortableSnapshot.seal(snapshot, root.join("transfer/application.meshbak"), key: key, kind: "application",
    metadata: { primary_counts: counts(source), queue_counts: counts(queue), blobs: blobs, snapshot_at: Time.current.iso8601, revision: ENV.fetch("MESH_RELEASE_REVISION"), run_id: ENV.fetch("GITHUB_RUN_ID") })
  # A post-snapshot local marker is deliberately outside the stated RPO.
  Identity::Account.create!(email: "post-snapshot@probe.test", display_name: "Not backed up", password: "RecoveryProbe2026!", persona: "client")
  Publishing::ProcessDeployment.call(deployment_id: pending.id)
  raise "Lost response fixture failed" unless pending.reload.state == "unknown"
  observation = Publishing::PartnerGateway.new.lookup(pending)
  raise "Partner did not commit after application snapshot" unless observation
  state = partner_state(partner)
  root.join("external-expectation.json").write(JSON.generate(observation: observation, post_count: state.fetch("requests").find { |row| row.fetch("route") == "publish" }.fetch("count")))
  root.join("transfer/source.json").write(JSON.pretty_generate(
    checked_at: Time.current.iso8601, source_job: ENV.fetch("GITHUB_JOB"), run_id: ENV.fetch("GITHUB_RUN_ID"),
    snapshot_primary_tables: counts(source).size, snapshot_queue_tables: counts(queue).size,
    private_objects: blobs.size, private_bytes: blobs.sum { |blob| blob[:size] },
    source_revision: ENV.fetch("MESH_RELEASE_REVISION"), quiescent_rpo_seconds: 0,
    application_sha256: Digest::SHA256.file(root.join("transfer/application.meshbak")).hexdigest,
    key_location: "Repository Actions secret MESH_DR_RECOVERY_KEY (not in the artifact/checkout)") + "\n")
when "partner"
  snapshot = root.join("partner-snapshot")
  FileUtils.mkdir_p(snapshot)
  FileUtils.cp(root.join("external-expectation.json"), snapshot.join("expectation.json"))
  Pathname.new("/partner-data").glob("partner.sqlite*").each { |file| FileUtils.cp(file, snapshot.join(file.basename)) }
  raise "Simulator state missing" unless snapshot.join("partner.sqlite").file?
  PortableSnapshot.seal(snapshot, root.join("transfer/partner.meshbak"), key: key, kind: "partner", metadata: { recorded_at: Time.current.iso8601, revision: ENV.fetch("MESH_RELEASE_REVISION"), run_id: ENV.fetch("GITHUB_RUN_ID") })
when "authenticate"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  archive = root.join("transfer/application.meshbak")
  denied = {}
  {
    wrong_key: -> { PortableSnapshot.unpack(archive, root.join("wrong-key"), key: SecureRandom.random_bytes(32)) },
    truncated: -> {
      file = root.join("truncated.meshbak")
      file.binwrite(archive.binread[0...-5])
      PortableSnapshot.unpack(file, root.join("truncated"), key: key)
    },
    tampered: -> {
      file = root.join("tampered.meshbak")
      bytes = archive.binread
      bytes.setbyte(25, bytes.getbyte(25) ^ 1)
      file.binwrite(bytes)
      PortableSnapshot.unpack(file, root.join("tampered"), key: key)
    }
  }.each do |name, action|
    denied[name] = begin
      action.call
      false
    rescue OpenSSL::Cipher::CipherError
      true
    end
  end
  raise "Archive authentication negative control failed" unless denied.values.all?
  manifest = PortableSnapshot.unpack(archive, root.join("verified"), key: key)
  raise "Wrong snapshot source" unless manifest.fetch("kind") == "application" && manifest.fetch("metadata").fetch("revision") == ENV.fetch("MESH_RELEASE_REVISION") && manifest.fetch("metadata").fetch("run_id") == ENV.fetch("GITHUB_RUN_ID")
  missing = root.join("missing-object")
  FileUtils.cp_r(root.join("verified"), missing)
  blob = manifest.fetch("metadata").fetch("blobs").first
  missing.join("files/#{blob.fetch('key')}.bin").delete
  denied[:missing_object] = begin
    PortableSnapshot.verify!(missing)
    false
  rescue RuntimeError
    true
  end
  raise "Missing private bytes did not block activation" unless denied[:missing_object]
  partner = PortableSnapshot.unpack(root.join("transfer/partner.meshbak"), root.join("verified-partner"), key: key)
  raise "Wrong simulator snapshot kind or source" unless partner.fetch("kind") == "partner" && partner.fetch("metadata").fetch("revision") == ENV.fetch("MESH_RELEASE_REVISION") && partner.fetch("metadata").fetch("run_id") == ENV.fetch("GITHUB_RUN_ID")
  root.join("verified-partner").glob("partner.sqlite*").each do |file|
    target = Pathname.new("/partner-data").join(file.basename)
    FileUtils.cp(file, target)
    FileUtils.chmod(0o660, target)
  end
  root.join("negative-controls.json").write(JSON.generate(denied))
  puts JSON.generate(authenticated: true, denied: denied, elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
when "import"
  snapshot = root.join("verified")
  manifest = PortableSnapshot.verify!(snapshot)
  metadata = manifest.fetch("metadata")
  command!("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", source, snapshot.join("primary.dump").to_s)
  command!("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", queue, snapshot.join("queue.dump").to_s)
  raise "Primary rows differ" unless counts(source) == metadata.fetch("primary_counts")
  raise "Queue rows differ" unless counts(queue) == metadata.fetch("queue_counts")
  metadata.fetch("blobs").each do |blob|
    bytes = snapshot.join("files/#{blob.fetch('key')}.bin").binread
    raise "Private bytes differ" unless Digest::SHA256.hexdigest(bytes) == blob.fetch("sha256")
    ActiveStorage::Blob.service.upload(blob.fetch("key"), StringIO.new(bytes))
  end
  raise "Post-snapshot marker unexpectedly survived" if Identity::Account.exists?(email: "post-snapshot@probe.test")
  Publishing::Deployment.where(state: %w[pending dispatching]).find_each do |row|
    row.update!(state: "unknown", claim_token: nil, lease_until: nil, last_error: "SNAPSHOT_RECONCILIATION_REQUIRED")
  end
  puts JSON.generate(primary_tables: metadata.fetch("primary_counts").size, queue_tables: metadata.fetch("queue_counts").size, files: metadata.fetch("blobs").size)
when "verify"
  snapshot = root.join("verified")
  metadata = PortableSnapshot.verify!(snapshot).fetch("metadata")
  data = JSON.parse(snapshot.join("fixture.json").read)
  expected = JSON.parse(root.join("verified-partner/expectation.json").read)
  partner = Publishing::Partner.find(data.fetch("partner_id"))
  pending = Publishing::Deployment.find(data.fetch("pending_id"))
  before = partner_state(partner)
  Publishing::ProcessDeployment.call(deployment_id: pending.id)
  raise "Pending reconciliation failed" unless pending.reload.state == "confirmed"
  raise "Remote identity changed" unless Publishing::PartnerGateway.new.lookup(pending) == expected.fetch("observation")
  after = partner_state(partner)
  count = ->(state) { state.fetch("requests").find { |row| row.fetch("route") == "publish" }.fetch("count") }
  raise "Duplicate remote publication" unless count.call(before) == count.call(after) && count.call(after) == expected.fetch("post_count")
  metadata.fetch("blobs").each do |blob|
    raise "Restored private file differs" unless Digest::SHA256.hexdigest(ActiveStorage::Blob.find_by!(key: blob.fetch("key")).download) == blob.fetch("sha256")
  end
  observation = expected.fetch("observation")
  bytes = JSON.generate(observation)
  event = SecureRandom.uuid
  timestamp = Time.current.to_i.to_s
  signature = OpenSSL::HMAC.hexdigest("SHA256", Publishing::Settings.token(partner), "#{timestamp}.#{event}.#{bytes}")
  receipt = Publishing::ReceiveCallback.call(partner: partner, event_id: event, timestamp: timestamp, signature: signature, bytes: bytes)
  replay = Publishing::ReceiveCallback.call(partner: partner, event_id: event, timestamp: timestamp, signature: signature, bytes: bytes)
  raise "Callback replay changed state" unless receipt.fetch(:duplicate) == false && replay.fetch(:duplicate) == true && partner.reload.active_deployment_id == pending.id
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! "localhost"
  client.https!
  client.get "/api/v1/session"
  csrf = JSON.parse(client.response.body).fetch("csrf_token")
  client.post "/api/v1/session", params: { session: { email: "dr-operator@probe.test", password: "RecoveryProbe2026!" } }.to_json,
    headers: { "Content-Type" => "application/json", "X-CSRF-Token" => csrf, "HTTP_ORIGIN" => "https://localhost" }
  raise "Restored operator login failed" unless client.response.status == 200
  client.get "/api/v1/publishing/candidates/#{data.fetch('candidate_id')}/artifact"
  candidate = Publishing::Candidate.find(data.fetch("candidate_id"))
  raise "Private HTTP bytes differ" unless client.response.status == 200 && Digest::SHA256.hexdigest(client.response.body) == candidate.artifact_sha256
  report = { checked_at: Time.current.iso8601, environment: "Fresh hosted Ubuntu VM; source job already completed",
    primary_tables_verified: metadata.fetch("primary_counts").size, queue_tables_verified: metadata.fetch("queue_counts").size,
    private_objects_verified: metadata.fetch("blobs").size, private_bytes_verified: metadata.fetch("blobs").sum { |blob| blob.fetch("size") },
    restored_pending_reconciled: true, private_http_artifact_verified: true, callback_replay_deduplicated: true,
    external_post_count_before: count.call(before), external_post_count_after: count.call(after),
    post_snapshot_local_marker_lost_as_declared: true, negative_controls: JSON.parse(root.join("negative-controls.json").read),
    source_snapshot_at: metadata.fetch("snapshot_at"), source_revision: ENV.fetch("MESH_RELEASE_REVISION"),
    rpo_scope: "Zero at quiescent snapshot; no online WAL/PITR promise",
    key_custody: "GitHub repository secret outside source VM; not an independent provider KMS",
    partner_scope: "Separately encrypted simulator state ahead of app backup; continuous external partner availability not claimed" }
  root.join("evidence/restored.json").write(JSON.pretty_generate(report) + "\n")
  puts JSON.generate(restored: true, external_posts: count.call(after))
else
  abort "Use source, partner, authenticate, import or verify"
end
