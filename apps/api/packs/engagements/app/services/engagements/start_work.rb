module Engagements
  class StartWork
    def self.call(actor:, engagement:, key:)
      raise Platform::Error.new("FORBIDDEN", "Only the author can start work.", status: 403) unless actor.id == engagement.creator_id
      Platform::Idempotency.call(actor_id: actor.id, operation: "start:#{engagement.id}", key: key, input: {}) do
        engagement.lock!
        raise Platform::Error.new("INVALID_TRANSITION", "Work has already started.", status: 409) unless engagement.state == "agreed"
        engagement.transition!(to: "in_progress")
        engagement.update!(started_at: Time.current)
        Platform::Events.audit(action: "work.started", resource: engagement)
        { id: engagement.id }
      end
    end
  end
end
