require_relative "../config/environment" if File.exist?(File.expand_path("../config/environment.rb", __dir__))
require "json"
abort "Isolated Kubernetes probe only." unless Rails.env.production? && Platform::Record.connection_db_config.database == "mesh_kubernetes" && ENV["MESH_KUBERNETES_PROBE"] == "true"
phase, correlation = ARGV
raise "Invalid probe correlation" unless correlation.to_s.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
case phase
when "burst"
  actor = Identity::Account.find_or_create_by!(email: "kubernetes-probe@mesh.local") do |row|
    row.assign_attributes(display_name: "Isolated Kubernetes Probe", persona: "client", password: SecureRandom.hex(32))
  end
  project = Marketplace::CreateProject.call(actor: actor, key: correlation, input: {
    title: "Kubernetes controlled probe", category: "Дизайн", description: "Synthetic integration reliability project.",
    budget_minor: 100_000, currency: "RUB", deadline: 30.days.from_now.to_date
  })
  record = Marketplace::Project.find(project[:id])
  Platform::Current.set(correlation_id: correlation) do
    50.times do
      Platform::Record.transaction do
        Platform::Events.emit(type: "project.published", aggregate: record, payload: {
          audience: [ actor.id ], title: "Controlled Kubernetes notification", project_id: record.id
        })
      end
    end
  end
  OutboxDispatcher.call
  events = Platform::OutboxEvent.where(correlation_id: correlation)
  puts "MESH_KUBERNETES_REPORT=" + JSON.generate(events: events.count, queue: QueueMetrics.snapshot)
when "drain"
  events = Platform::OutboxEvent.where(correlation_id: correlation)
  ids = events.pluck(:id)
  raise "Missing controlled events" unless ids.size == 50
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
  until Platform::Record.uncached { Platform::Delivery.where(outbox_event_id: ids, state: "processed").count } == ids.size
    raise "Worker recovery timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 1
  end
  effects = Notifications::Notification.where(outbox_event_id: ids).group(:outbox_event_id).count
  raise "Missing/duplicate effects" unless effects.size == 50 && effects.values.all? { |count| count == 1 }
  puts "MESH_KUBERNETES_REPORT=" + JSON.generate(events: ids.size, effects_per_event: effects.values.uniq, queue: QueueMetrics.snapshot)
else
  abort "Use burst or drain."
end
