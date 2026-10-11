require_relative "../config/environment"
require_relative "support/architecture_lab"
require "action_dispatch/testing/integration"

ArchitectureLab.guard!
raise "Expected the restored database" unless ENV.fetch("MESH_LAB_DATABASE").end_with?("_restore")
backup = Pathname.new(ENV.fetch("MESH_LAB_BACKUP"))
manifest = JSON.parse(File.read(backup.join("complete.json")))
raise "Database dump checksum differs" unless Digest::SHA256.file(backup.join("database.dump")).hexdigest == manifest.fetch("dump_sha256")
manifest.fetch("database_counts").each do |table, expected|
  raise "Unsafe manifest table" unless table.match?(/\A[a-z_]+\z/)
  actual = Platform::Record.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i
  raise "Restored table count differs: #{table}" unless actual == expected
end
verify = lambda do
  manifest.fetch("blobs").each do |row|
    key = row.fetch("key")
    raise "Unsafe manifest key" unless key.match?(/\A[a-zA-Z0-9_-]+\z/)
    blob = ActiveStorage::Blob.find_by!(key: key)
    path = blob.service.send(:path_for, key)
    raise "Missing blob" unless File.file?(path)
    raise "Wrong blob metadata" unless blob.byte_size == row.fetch("size") && blob.checksum == row.fetch("checksum")
    raise "Corrupted blob" unless File.size(path) == row.fetch("size") && Digest::SHA256.file(path).hexdigest == row.fetch("sha256")
  end
end
verify.call
first = manifest.fetch("blobs").first
blob = ActiveStorage::Blob.find_by!(key: first.fetch("key"))
path = blob.service.send(:path_for, blob.key)
probes = {}
begin
  File.rename(path, "#{path}.missing")
  probes[:missing] = begin
    verify.call
    false
  rescue RuntimeError => error
    error.message == "Missing blob"
  end
ensure
  File.rename("#{path}.missing", path) if File.exist?("#{path}.missing")
end
begin
  File.open(path, "r+b") do |file|
    byte = file.read(1).getbyte(0)
    file.rewind
    file.write((byte ^ 1).chr)
  end
  probes[:corrupted] = begin
    verify.call
    false
  rescue RuntimeError => error
    error.message == "Corrupted blob"
  end
ensure
  FileUtils.cp(backup.join("files/#{blob.key}.bin"), path)
end
raise "Integrity probes failed" unless probes.values.all?
verify.call
state = manifest.fetch("fixture")
submission = Engagements::Submission.find(state.fetch("submission_id"))
document = Platform::Idempotency.canonicalize({ title: submission.title, content: submission.content, ready_for_acceptance: submission.ready_for_acceptance, files: submission.files_manifest })
raise "Version manifest is inconsistent" unless Digest::SHA256.hexdigest(JSON.generate(document)) == submission.manifest_sha256
raise "Private files lost their version attachment" unless submission.work_files.pluck(:id).sort == state.fetch("file_ids").sort
immutable = begin
  submission.update_columns(title: "Tampered restore")
  false
rescue ActiveRecord::StatementInvalid
  true
end
raise "Restored immutability trigger is missing" unless immutable

session = ActionDispatch::Integration::Session.new(Rails.application)
session.host!("localhost:3200")
session.get("/api/v1/session")
token = JSON.parse(session.response.body).fetch("csrf_token")
session.post("/api/v1/session", params: { session: { email: "person20000@lab.test", password: "LabPassword2026!" } }, as: :json,
  headers: { "X-CSRF-Token" => token, "Origin" => "http://localhost:3200" })
raise "Restored author cannot sign in: #{session.response.status}" unless session.response.status == 200
downloads = state.fetch("file_ids").map do |id|
  item = Engagements::WorkFile.find(id)
  session.get("/api/v1/engagements/#{state.fetch('engagement_id')}/work_files/#{id}/download")
  raise "Restored private download failed: #{session.response.status}" unless session.response.status == 200
  raise "Restored private download bytes differ" unless Digest::SHA256.hexdigest(session.response.body) == item.sha256
  raise "Restored private download lost cache policy" unless session.response.headers["Cache-Control"] == "private, no-store"
  { bytes: session.response.body.bytesize, sha256: item.sha256, status: 200 }
end
ArchitectureLab.report("restore-verified", { counts_match: true, blobs_verified: manifest.fetch("blobs").size, integrity_probes: probes,
  submission_manifest_verified: true, immutable_trigger_verified: immutable, authenticated_private_downloads: downloads,
  http_scope: "Rails integration HTTP requests against restored DB/storage, including cookie sign-in, CSRF and controller download; no TLS proxy." })
puts "Restored DB, manifests, private downloads and both corruption probes verified."
