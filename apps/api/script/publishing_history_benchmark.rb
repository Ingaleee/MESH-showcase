require_relative "../config/environment"
require "digest"
require "fileutils"

abort "Use only the isolated test database" unless Rails.env.test? && Platform::Record.connection_db_config.database == "mesh_test"
count = Integer(ENV.fetch("MESH_BENCHMARK_ROWS", "50000"))
abort "Use 1000..100000 rows" unless count.between?(1000, 100000)
connection = Platform::Record.connection
report = nil
connection.transaction do
  connection.execute("SET LOCAL statement_timeout = '120s'")
  operator = Identity::Account.create!(email: "#{SecureRandom.uuid}@benchmark.test", display_name: "History benchmark", password: "Benchmark2026!", persona: "client", operator: true)
  partner = Publishing::Partner.create!(owner: operator, name: "Synthetic benchmark", origin: "http://partner:3216", credential_ref: "SHOWCASE")
  blob = ActiveStorage::Blob.create_before_direct_upload!(filename: "synthetic.zip", byte_size: 1, checksum: Digest::MD5.base64digest("x"), content_type: "application/zip")
  candidate = Publishing::Candidate.create!(partner: partner, artifact_blob: blob, manifest: {}, artifact_sha256: "a" * 64, manifest_sha256: "b" * 64, correlation_id: SecureRandom.uuid)
  validation = Publishing::Validation.create!(candidate: candidate, policy_version: "benchmark", input_fingerprint: "c" * 64, state: "passed", completed_at: Time.current, report: { checks: [] })
  base = Publishing::Deployment.create!(partner: partner, candidate: candidate, validation: validation, correlation_id: SecureRandom.uuid, state: "confirmed", remote_id: "synthetic", remote_sequence: 1, confirmed_at: Time.current, created_at: 1.year.ago)
  partner.update!(active_deployment: base, active_sequence: 1)
  connection.execute(<<~SQL)
    INSERT INTO publishing_deployments (partner_id,candidate_id,validation_id,rollback_of_id,kind,state,correlation_id,created_at,updated_at)
    SELECT #{connection.quote(partner.id)}::uuid, #{connection.quote(candidate.id)}::uuid,
      #{connection.quote(validation.id)}::uuid, #{connection.quote(base.id)}::uuid,
      'rollback','unknown',gen_random_uuid()::text,
      TIMESTAMP '2026-06-01' + i * INTERVAL '1 second', TIMESTAMP '2026-06-01'
    FROM generate_series(1,#{count}) i;
    ANALYZE publishing_deployments;
  SQL
  scope = Publishing::Deployment.where(partner_id: Publishing::Partner.where(owner: operator).select(:id))
  first = Publishing::HistoryPage.call(scope: scope, actor: operator, kind: "deployments")
  samples = 10.times.map do
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    page = Publishing::HistoryPage.call(scope: scope, actor: operator, kind: "deployments", cursor: first[:next_cursor])
    { elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3),
      allocations: GC.stat(:total_allocated_objects) - allocated, records: page[:records].size }
  end
  raise "History window included old active unexpectedly" if first[:records].include?(base)
  raise "Active read lost its old deployment" unless Publishing::Deployment.find(partner.reload.active_deployment_id).id == base.id
  last = first[:records].last
  sql = scope.where("(created_at,id) < (?,?)", last.created_at, last.id).order(created_at: :desc, id: :desc).limit(31).to_sql
  plan = connection.select_rows("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}").first.first
  report = { checked_at: Time.current.iso8601, environment: "shared Docker Desktop / mesh_test",
    historical_rows: count, warm_samples: samples, active_older_than_window_visible: true,
    query_plan: JSON.parse(plan), scope: "Single-owner single-partner SQL/Ruby read profile; no HTTP throughput or multi-tenant SLA claim." }
  raise ActiveRecord::Rollback
end
directory = Pathname.new(ENV.fetch("MESH_EVIDENCE_DIR", "/workspace/.cache/acceptance-evidence"))
FileUtils.mkdir_p(directory)
File.write(directory.join("publishing-history-benchmark.json"), JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.except(:query_plan, :warm_samples).merge(samples: report[:warm_samples]))
