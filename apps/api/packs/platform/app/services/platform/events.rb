module Platform
  class Events
    def self.emit(type:, aggregate:, payload:)
      raise "events must be emitted inside a business transaction" unless Record.connection.transaction_open?
      carrier = {}
      OpenTelemetry.propagation.inject(carrier)
      event = OutboxEvent.create!(
        event_type: type, aggregate_type: aggregate.class.name, aggregate_id: aggregate.id,
        aggregate_version: aggregate.try(:lock_version) || 0, payload: payload,
        correlation_id: Current.correlation_id || SecureRandom.uuid, trace_context: carrier
      )
      Delivery.create!(outbox_event: event, consumer: "notifications")
      event
    end

    def self.audit(action:, resource:, details: {})
      AuditEntry.create!(
        actor_id: Current.actor_id, action: action, resource_type: resource.class.name,
        resource_id: resource.id, details: details, correlation_id: Current.correlation_id || SecureRandom.uuid
      )
    end
  end
end
