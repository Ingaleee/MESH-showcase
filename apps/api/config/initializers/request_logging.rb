ActiveSupport::Notifications.monotonic_subscribe("process_action.action_controller") do |_, started, finished, _, payload|
  HttpMetrics.observe(payload, finished - started)
  next unless payload[:controller].start_with?("Api::")

  Rails.logger.info(JSON.generate(
    event: "request.finished", method: payload[:method],
    path: payload[:path].split("?", 2).first, status: payload[:status],
    duration_ms: ((finished - started) * 1000).round(2),
    request_id: payload[:request].request_id
  ))
end
