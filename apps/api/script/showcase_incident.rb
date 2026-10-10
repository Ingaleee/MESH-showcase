require_relative "../config/environment"
require "json"

abort "Isolated showcase development drill only." unless Rails.env.development? && Platform::Record.connection_db_config.database == "mesh_development" && ENV["MESH_SHOWCASE_INCIDENT"] == "true"
state = Rails.root.join("tmp/showcase-incident.json")
def notification_count
  Platform::Metrics.snapshot.find { |row| row["name"] == "notification_delivery" }&.fetch("observations") || 0
end
case ARGV.fetch(0)
when "burst"
  actor = Identity::Account.find_by!(email: "client@mesh.local")
  project = Marketplace::Project.where(client_id: actor.id).first!
  before = notification_count
  ids = 50.times.map do
    Platform::Record.transaction do
      Platform::Events.emit(type: "project.published", aggregate: project, payload: {
        audience: [ actor.id ], title: "Controlled showcase incident", project_id: project.id
      }).id
    end
  end
  OutboxDispatcher.call
  File.write(state, JSON.generate(ids: ids, observations_before: before))
  puts "MESH_INCIDENT_REPORT=" + JSON.generate(events: ids.size, queue: QueueMetrics.snapshot, observations_before: before)
when "drain"
  data = JSON.parse(File.read(state))
  ids = data.fetch("ids")
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
  until Platform::Delivery.where(outbox_event_id: ids, state: "processed").count == ids.size
    raise "Drain timeout." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 1
  end
  effects = Notifications::Notification.where(outbox_event_id: ids).group(:outbox_event_id).count
  raise "Missing or duplicate effect." unless effects.size == 50 && effects.values.all? { |value| value == 1 }
  before_replay = notification_count
  Platform::Delivery.where(outbox_event_id: ids).each { |row| EventDeliveryJob.perform_now(row.id, SecureRandom.uuid) }
  raise "Replay changed durable metrics." unless notification_count == before_replay
  puts "MESH_INCIDENT_REPORT=" + JSON.generate(events: ids.size, effects_per_event: effects.values.uniq,
    observations_added: before_replay - data.fetch("observations_before"), replay_observations_added: notification_count - before_replay,
    queue: QueueMetrics.snapshot)
else
  abort "Use burst or drain."
end
