require_relative "../config/environment"

abort "Isolated restored runtime only" unless Rails.env.production? && ENV["GITHUB_ACTIONS"] == "true" && ENV["MESH_DR_RUNTIME_PROBE"] == "true"
role = Platform::Record.connection.select_value("SELECT current_user")
raise "Restricted runtime role required" unless role == "mesh_runtime"
if ARGV.fetch(0) == "role"
  puts JSON.generate(role: role)
elsif ARGV.fetch(0) == "check"
  report = JSON.parse(File.read("/recovery/evidence/restored.json"))
  project = Marketplace::Project.find(report.fetch("runtime_project_id"))
  events = Platform::OutboxEvent.where(aggregate_id: project.id, event_type: "project.published")
  deliveries = Platform::Delivery.where(outbox_event_id: events.select(:id), consumer: "notifications")
  effects = Notifications::Notification.where(outbox_event_id: events.select(:id))
  raise "Repeated event or notification" if events.count > 1 || effects.count > 1
  candidate = Publishing::Candidate.find(report.fetch("private_candidate_id"))
  partner = candidate.partner
  remote = Platform::HttpClient.new(origin: partner.origin, allow_http: true).request(method: :get, path: "/state", token: Publishing::Settings.token(partner)).body
  publish_count = remote.fetch("requests").find { |row| row.fetch("route") == "publish" }.fetch("count")
  raise "Restored worker repeated external publication" unless publish_count == report.fetch("external_post_count_after")
  puts JSON.generate(role: role, events: events.count, processed: deliveries.where(state: "processed").count,
    notifications: effects.count, external_post_count: publish_count,
    pending_deployments: Publishing::Deployment.where(partner: partner).where.not(state: %w[confirmed failed]).count)
else
  abort "Use role or check"
end
