require_relative "../config/environment"
require "json"

abort "Dedicated deployment incident only." unless Rails.env.production? && Platform::Record.connection_db_config.database == "mesh_production" && ENV["MESH_DEPLOYMENT_PROBE"] == "true"
state = Rails.root.join("tmp/incident.json")
case ARGV.fetch(0)
when "burst"
  agreement = Engagements::Engagement.order(created_at: :desc).first!
  ids = 50.times.map do
    Platform::Record.transaction do
      Platform::Events.emit(type: "work.submitted", aggregate: agreement, payload: { audience: [ agreement.client_id ], title: "Synthetic incident", engagement_id: agreement.id }).id
    end
  end
  OutboxDispatcher.call
  snapshot = QueueMetrics.snapshot
  raise "A real backlog was not created." unless snapshot.fetch(:rows).any? { |row| row["queue_name"] == "events" && row["state"] == "ready" && row["count"].to_i >= 50 }
  File.write(state, JSON.generate(ids))
  puts JSON.pretty_generate(events: ids.size, queue: snapshot)
when "drain"
  ids = JSON.parse(File.read(state))
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
  until Platform::Delivery.where(outbox_event_id: ids, state: "processed").count == ids.size
    raise "Drain timeout." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 1
  end
  effects = Notifications::Notification.where(outbox_event_id: ids).group(:outbox_event_id).count
  raise "Missing or duplicate side effect." unless effects.size == 50 && effects.values.all? { |value| value == 1 }
  puts JSON.pretty_generate(events: ids.size, effects_per_event: effects.values.uniq, queue: QueueMetrics.snapshot)
else
  abort "Use burst or drain."
end
