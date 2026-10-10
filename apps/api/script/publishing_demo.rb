require "time"
load File.expand_path("../bin/mesh-publish", __dir__)
require "zip"
require "digest"
require "fileutils"

raise "Run only the isolated development showcase" unless ENV.fetch("MESH_DEMO_ORIGIN", "") == "http://127.0.0.1:3000"
directory = File.expand_path("../../../.cache/publishing-fixtures", __dir__)
FileUtils.mkdir_p(directory)
client = PublishingCLI.new
def command(client, *args)
  client.call(args, print_result: false)
end
def wait_for(client, group, id, state)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 70
  loop do
    row = command(client, "list").fetch(group).find { |item| item["id"] == id }
    return row if row && Array(state).include?(row["state"])
    raise "Timed out waiting for #{group}/#{state}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.5
  end
end
def fixture(directory, name, version, bad: false)
  contents = "<!doctype html><html><title>Studio artifact #{version}</title><body>Trusted demo #{version}</body></html>"
  zip = Zip::OutputStream.write_buffer { |stream| stream.put_next_entry("index.html"); stream.write(contents) }.string
  manifest = { schema_version: 1, title: "MESH Studio Preview", version: version, contract_version: "1", entrypoint: "index.html",
    files: [ { path: "index.html", size: contents.bytesize, sha256: bad ? "0" * 64 : Digest::SHA256.hexdigest(contents) } ] }
  archive, metadata = File.join(directory, "#{name}.zip"), File.join(directory, "#{name}.json")
  File.binwrite(archive, zip); File.write(metadata, JSON.generate(manifest))
  [ archive, metadata ]
end

report = { checked_at: Time.now.utc.iso8601, environment: "mesh-showcase", phases: {} }
partner = command(client, "list")["partners"].find { |row| row["name"] == "MESH Demo Studio" }
partner ||= command(client, "register")
partner_id = partner.fetch("id")
bad = command(client, "submit", partner_id, *fixture(directory, "bad", "0.1.0", bad: true))
rejected = wait_for(client, "validations", bad.fetch("validation_id"), %w[rejected failed])
raise "Defect did not produce the right rejection" unless rejected["state"] == "rejected" && rejected["report"]["checks"].any? { |row| row["code"] == "FILE_DIGEST" && row["ok"] == false }
blocked = false
begin
  command(client, "publish", bad["id"], bad["validation_id"])
rescue Platform::HttpClient::Failure => error
  blocked = error.code == "VALIDATION_REQUIRED"
end
raise "Rejected artifact could be published" unless blocked
report[:phases][:defective_candidate] = { candidate_id: bad["id"], state: rejected["state"], publish_blocked: blocked, checks: rejected["report"]["checks"] }

first = command(client, "submit", partner_id, *fixture(directory, "v1", "1.0.0"))
passed = wait_for(client, "validations", first["validation_id"], %w[passed rejected failed])
raise "Valid artifact rejected" unless passed["state"] == "passed"
release = command(client, "publish", first["id"], first["validation_id"])
confirmed = wait_for(client, "deployments", release["id"], %w[confirmed failed])
raise "Initial release failed" unless confirmed["state"] == "confirmed"
report[:phases][:normal_release] = confirmed.merge("artifact_sha256" => passed["report"]["artifact_sha256"])

second = command(client, "submit", partner_id, *fixture(directory, "v2", "2.0.0"))
passed_second = wait_for(client, "validations", second["validation_id"], %w[passed rejected failed])
raise "Second candidate failed" unless passed_second["state"] == "passed"
uncertain = command(client, "publish", second["id"], second["validation_id"], "timeout_after_success")
unknown = wait_for(client, "deployments", uncertain["id"], %w[unknown confirmed failed])
raise "Lost-response state was not observed" unless unknown["state"] == "unknown"
diagnostic = command(client, "diagnose", uncertain["id"])
raise "Unknown outcome not diagnosed" unless diagnostic["state"] == "unknown" && diagnostic["last_error"] == "HTTP_TIMEOUT"
command(client, "reconcile", uncertain["id"])
recovered = wait_for(client, "deployments", uncertain["id"], %w[confirmed failed])
raise "Lookup recovery failed" unless recovered["state"] == "confirmed"
report[:phases][:lost_response] = { unknown: unknown, diagnostic: diagnostic, recovered: recovered,
  artifact_sha256: passed_second["report"]["artifact_sha256"] }

rollback = command(client, "rollback", first["id"], first["validation_id"], release["id"])
rolled_back = wait_for(client, "deployments", rollback["id"], %w[confirmed failed])
raise "Rollback failed" unless rolled_back["state"] == "confirmed"
report[:phases][:rollback] = rolled_back.merge("artifact_sha256" => passed["report"]["artifact_sha256"])
report[:partner_id] = partner_id
report[:success] = true
report[:scope] = "Real authenticated API + ordinary dispatcher/worker + ClamAV + independent SQLite partner; no external studio or uploaded code execution."
puts "MESH_PUBLISHING_REPORT=" + JSON.generate(report)
