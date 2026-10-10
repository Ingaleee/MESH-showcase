require_relative "../config/environment"
require_relative "support/architecture_lab"

ArchitectureLab.guard!
phase = ARGV.fetch(0)
raise "Invalid query measurement phase" unless %w[before after].include?(phase)
anchor = Marketplace::Project.find(Digest::MD5.hexdigest("lab-project-20000"))
deep_cursor = Rails.application.message_verifier("project_cursor").generate({
  "created_at" => anchor.created_at.iso8601(6), "id" => anchor.id,
  "query" => Digest::SHA256.hexdigest(JSON.generate([ nil, "", "" ]))
})
cases = {
  "feed" => -> { Marketplace::SearchProjects.call(actor: nil) },
  "deep_feed" => lambda {
    if phase == "before"
      # Preserve the former OR predicate as an explicit performance baseline.
      Marketplace::Project.where(state: "open")
        .where("created_at < :time OR (created_at = :time AND id < :id)", time: anchor.created_at, id: anchor.id)
        .includes(:client).order(created_at: :desc, id: :desc).limit(13).to_a.first(12)
    else
      Marketplace::SearchProjects.call(actor: nil, cursor: deep_cursor)
    end
  },
  "category" => -> { Marketplace::SearchProjects.call(actor: nil, category: "Дизайн") },
  "project_search" => -> { Marketplace::SearchProjects.call(actor: nil, query: "RareNeedle") },
  "creator_search" => -> { Talent::Directory.search(query: "RareNeedle").to_a }
}
results = cases.map do |name, command|
  3.times { command.call }
  samples = 30.times.map do
    queries = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next unless payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")

      binds = payload[:binds].map { |bind| Platform::Record.connection.quote(bind.value_for_database) }
      queries << payload[:sql].gsub(/\$(\d+)/) { binds.fetch(Regexp.last_match(1).to_i - 1) }
    end
    value, elapsed = ArchitectureLab.measure { Platform::Record.uncached { command.call } }
    ActiveSupport::Notifications.unsubscribe(subscription)
    records = value.is_a?(Hash) ? value.fetch(:records) : value
    { ms: elapsed, queries: queries, record_ids: records.map(&:id) }
  end
  times = samples.map { |sample| sample.fetch(:ms) }.sort
  sql = samples.first.fetch(:queries).find { |query| query.include?(name == "creator_search" ? '"talent_profiles"' : '"marketplace_projects"') }
  raw_plan = Platform::Record.connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}")
  plan = raw_plan.is_a?(String) ? JSON.parse(raw_plan) : raw_plan
  { name: name, p50_ms: times[times.size / 2], p95_ms: times[(times.size * 0.95).ceil - 1], max_ms: times.last,
    sql_count: samples.map { |sample| sample.fetch(:queries).length }.uniq, record_ids: samples.first.fetch(:record_ids), sql: sql, plan: plan }
end
if phase == "after"
  previous = JSON.parse(File.read(ArchitectureLab.directory.join("queries-before.json")))
  raise "Indexes changed query results" unless previous.fetch("cases").map { |row| row.fetch("record_ids") } == results.map { |row| row.fetch(:record_ids) }
  state = ArchitectureLab.state
  state["deep_cursor"] = deep_cursor
  ArchitectureLab.save_state(state)
end
ArchitectureLab.report("queries-#{phase}", { samples: 30, warmup_per_case: 3, cases: results, scope: "Ruby read models on isolated PostgreSQL; SQL includes eager loading. Deep feed cursor is after synthetic project 20000, behind roughly 68000 open rows. Warm application and PostgreSQL cache, no TLS/SSR or network. EXPLAIN ANALYZE itself changes buffer cache; 30 samples are a small diagnostic sample, not a tail-latency SLA." })
puts "#{phase} SQL/read-model timing complete."
