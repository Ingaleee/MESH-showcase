module Marketplace
  class ReviseBrief
    def self.call(actor:, project:, input:, version:, key:)
      raise Platform::Error.new("FORBIDDEN", "Only the client can revise this brief.", status: 403) unless project.client_id == actor.id
      Platform::Idempotency.call(actor_id: actor.id, operation: "revise_brief:#{project.id}", key: key, input: input.merge(version: version)) do
        project.lock!
        raise Platform::Error.new("PROJECT_CLOSED", "Project is already awarded.", status: 409) unless project.state == "open"
        raise Platform::Error.new("STALE_VERSION", "The brief has changed.", status: 409) unless project.lock_version == version
        if input.fetch(:currency) != project.currency
          raise Platform::Error.new("CURRENCY_FIXED", "Currency is fixed when the project is created.")
        end
        Platform::Money.new(minor: input.fetch(:budget_minor), currency: project.currency)
        project.assign_attributes(input.merge(brief_version: project.brief_version + 1))
        if project.deadline && project.deadline < Date.current
          raise Platform::Error.new("INVALID_DEADLINE", "Deadline must be in the future.")
        end
        project.save!
        BriefVersion.create!(project_id: project.id, version: project.brief_version, terms: project.brief_snapshot)
        Platform::Events.audit(action: "project.revised", resource: project)
        { id: project.id, version: project.lock_version }
      end
    end
  end
end
