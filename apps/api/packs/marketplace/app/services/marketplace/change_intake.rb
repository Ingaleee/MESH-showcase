module Marketplace
  class ChangeIntake
    def self.call(actor:, project:, accepting:, version:, key:)
      raise Platform::Error.new("FORBIDDEN", "Only the client can manage intake.", status: 403) unless project.client_id == actor.id
      raise ArgumentError unless [ true, false ].include?(accepting)

      Platform::Idempotency.call(actor_id: actor.id, operation: "intake:#{project.id}", key: key, input: { accepting: accepting, version: version }) do
        project.lock!
        raise Platform::Error.new("PROJECT_CLOSED", "An author has already been selected.", status: 409) unless project.state == "open"
        raise Platform::Error.new("STALE_VERSION", "The project has changed.", status: 409) unless project.lock_version == version

        if project.accepting_proposals != accepting
          project.update!(accepting_proposals: accepting)
          Platform::Events.audit(action: accepting ? "project.intake_resumed" : "project.intake_paused", resource: project)
        end
        { id: project.id, version: project.lock_version }
      end
    end
  end
end
