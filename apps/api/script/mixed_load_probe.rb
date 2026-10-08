require_relative "../config/environment"

abort "Isolated hosted release only" unless Rails.env.production? && ENV["GITHUB_ACTIONS"] == "true" && ENV["MESH_LOAD_PROBE"] == "true"
file = "/tmp/mixed-load-fixture.json"
connection = Platform::Record.connection
case ARGV.fetch(0)
when "prepare"
  suffix = SecureRandom.uuid
  account = Identity::Account.create!(email: "load-#{suffix}@probe.test", display_name: "Mixed load owner", password: "LoadProbe2026!", persona: "client")
  connection.execute(<<~SQL)
    INSERT INTO marketplace_projects (client_id,title,category,description,budget_minor,currency,deadline,created_at,updated_at)
    SELECT #{connection.quote(account.id)}::uuid, 'Catalog fixture ' || i, 'Дизайн', repeat('Synthetic catalog. ', 20),
      100005,'RUB',CURRENT_DATE + 30, CURRENT_TIMESTAMP - i * INTERVAL '1 second',CURRENT_TIMESTAMP
    FROM generate_series(1,10000) i;
    ANALYZE marketplace_projects;
  SQL
  data = { id: account.id, email: account.email, password: "LoadProbe2026!", prefix: "load-#{suffix}-", seeded_projects: 10000 }
  File.write(file, JSON.generate(data))
  puts JSON.generate(data)
when "verify"
  data = JSON.parse(File.read(file))
  projects = Marketplace::Project.where(client_id: data.fetch("id")).where("title LIKE ?", "#{data.fetch('prefix')}%")
  ids = projects.pluck(:id)
  events = Platform::OutboxEvent.where(aggregate_id: ids, event_type: "project.published")
  deliveries = Platform::Delivery.where(outbox_event_id: events.select(:id))
  notifications = Notifications::Notification.where(outbox_event_id: events.select(:id))
  duplicates = events.group(:aggregate_id).having("COUNT(*) <> 1").count.size
  duplicate_effects = notifications.group(:outbox_event_id).having("COUNT(*) <> 1").count.size
  puts JSON.generate(projects: projects.count, events: events.count, processed: deliveries.where(state: "processed").count,
    pending: deliveries.where.not(state: "processed").count, notifications: notifications.count,
    duplicate_events: duplicates, duplicate_effects: duplicate_effects, user_outcomes: UserOutcomeMetrics.snapshot)
when "contend"
  connection.transaction do
    connection.execute("LOCK TABLE marketplace_projects IN SHARE MODE")
    puts "CONTENTION_READY"
    STDOUT.flush
    connection.execute("SELECT pg_sleep(6)")
  end
else
  abort "Use prepare, verify or contend"
end
