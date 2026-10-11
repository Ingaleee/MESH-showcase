class EventDeliveryJob < ApplicationJob
  queue_as :events

  def perform(delivery_id, token = nil)
    delivery = Platform::Delivery.find_by(id: delivery_id)
    return unless delivery
    # Legacy queued jobs have no token; a current lease is recovered by the dispatcher.
    token ||= OutboxDispatcher.claim(delivery) if delivery.claim_token.nil?
    return unless token
    event = delivery.outbox_event
    context = OpenTelemetry.propagation.extract(event.trace_context)
    notifications = []

    OpenTelemetry::Context.with_current(context) do
      OpenTelemetry.tracer_provider.tracer("mesh.events").in_span("mesh.event.consume", kind: :consumer, attributes: { "mesh.event_type" => event.event_type }) do
        Platform::Current.set(correlation_id: event.correlation_id) do
          delivery.with_lock do
            return unless delivery.state == "enqueued" && delivery.claim_token == token

            notifications = Notifications::ConsumeEvent.call(event)
            delivery.update!(state: "processed", claim_token: nil, processed_at: Time.current, last_error: nil)
            Platform::Metrics.observe("notification_delivery", Time.current - delivery.created_at)
          end
        end
      end
    end

    notifications.each do |notification|
      begin
        ActionCable.server.broadcast("notifications:#{notification.account_id}", {
          type: "notification.created", id: notification.id
        })
      rescue StandardError => error
        Rails.logger.warn(JSON.generate(event: "notification.broadcast_failed", error: error.class.name))
      end
    end
  rescue StandardError => error
    if delivery
      delivery.with_lock do
        if delivery.state == "enqueued" && delivery.claim_token == token
          failures = delivery.failure_count + 1
          delivery.update!(
            failure_count: failures, last_error: error.class.name,
            state: failures >= 5 ? "failed" : "pending", claim_token: nil, available_at: [ 2**failures, 60 ].min.seconds.from_now
          )
        end
      end
    end
    raise
  end
end
