require_relative "../config/environment"
require "bcrypt"
require "objspace"

abort "Use only the showcase test database." unless Rails.env.test? && Platform::Record.connection_db_config.database == "mesh_test"
count = Integer(ENV.fetch("MESH_BENCHMARK_ROWS", "50000"))
abort "Use 1000..100000 synthetic rows." unless (1000..100000).cover?(count)
connection = Platform::Record.connection
prefix = SecureRandom.hex(8)
report = nil
connection.transaction(requires_new: true) do
  connection.execute("SET LOCAL statement_timeout = '120s'")
  owner = Identity::Account.create!(email: "#{prefix}@bench.test", display_name: "Benchmark owner", password: "BenchmarkPassword2026!", persona: "client")
  project = Marketplace::Project.create!(client: owner, title: "Bounded read benchmark", category: "Дизайн", description: "Synthetic measurement", budget_minor: 10_000_000, currency: "RUB", deadline: Date.new(2027, 1, 1))
  password = connection.quote(BCrypt::Password.create("BenchmarkPassword2026!", cost: 4))
  seed = connection.quote(prefix)
  connection.execute(<<~SQL)
    INSERT INTO identity_accounts (id, email, display_name, password_digest, persona, created_at, updated_at)
    SELECT md5(#{seed} || '-author-' || i)::uuid, #{seed} || i || '@bench.test', 'Author ' || i,
      #{password}, 'creator', TIMESTAMP '2026-01-01', TIMESTAMP '2026-01-01'
    FROM generate_series(1, #{count}) i;
    INSERT INTO marketplace_proposals (id, project_id, creator_id, brief_version, price_minor, delivery_days, message, created_at, updated_at)
    SELECT md5(#{seed} || '-offer-' || i)::uuid, #{connection.quote(project.id)}::uuid,
      md5(#{seed} || '-author-' || i)::uuid, 1, 100000 + i % 100, 7 + i % 21,
      repeat('Synthetic proposal approach. ', 12), TIMESTAMP '2026-01-01' + i * INTERVAL '1 second', TIMESTAMP '2026-01-01'
    FROM generate_series(1, #{count}) i;
    ANALYZE marketplace_proposals;
  SQL
  cases = {
    former_unbounded: -> { project.proposals.includes(:creator, example: { file_attachment: :blob }).order(created_at: :desc, id: :desc).to_a },
    bounded_page: -> { Marketplace::ProposalPage.call(project: project, actor: owner, limit: 20).fetch(:records) }
  }
  measured = cases.map do |name, read|
    read.call
    samples = 5.times.map do
      GC.start
      before = GC.stat(:total_allocated_objects)
      records = nil
      queries = []
      callback = lambda do |*, payload|
        next unless payload[:sql].start_with?("SELECT") && !payload[:cached]
        binds = payload[:binds].map { |bind| connection.quote(bind.value_for_database) }
        queries << payload[:sql].gsub(/\$(\d+)/) { binds.fetch(Regexp.last_match(1).to_i - 1) }
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Platform::Record.uncached { records = read.call }
      end
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      allocations = GC.stat(:total_allocated_objects) - before
      payload = records.map { |row| Api::Presenters.proposal(row) }
      { read_ms: elapsed.round(3), allocations: allocations, loaded_records: records.size,
        json_bytes: JSON.generate(payload).bytesize, sql_count: queries.size, queries: queries }
    end
    times = samples.map { |row| row.fetch(:read_ms) }.sort
    sql = samples.first.fetch(:queries).find { |row| row.include?('"marketplace_proposals".*') }
    plan = connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}")
    { name: name, median_read_ms: times[2], samples: samples.map { |row| row.except(:queries) },
      plan: plan.is_a?(String) ? JSON.parse(plan) : plan }
  end
  report = { checked_at: Time.current.iso8601, environment: "MESH-showcase; Ruby #{RUBY_VERSION}; PostgreSQL #{connection.select_value('SHOW server_version')}", rows: count, page_limit: 20, cases: measured,
    scope: "Same synthetic single-project data, warm process/cache, 5 diagnostic samples. Read timing excludes JSON serialization; payload bytes measured separately. Allocations are objects, not RSS. No network, TLS or production latency claim. Transaction rolls all fixture writes back." }
  raise ActiveRecord::Rollback
end
directory = Rails.root.join("../../docs/evidence")
FileUtils.mkdir_p(directory)
File.write(directory.join("bounded-read-benchmark.json"), JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.except(:cases).merge(cases: report.fetch(:cases).map { |row| row.except(:plan) }))
