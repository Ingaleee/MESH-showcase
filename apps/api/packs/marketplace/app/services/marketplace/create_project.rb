module Marketplace
  class CreateProject
    def self.call(actor:, input:, key:)
      Platform::Idempotency.call(actor_id: actor.id, operation: "create_project", key: key, input: input) do
        Platform::Money.new(minor: input.fetch(:budget_minor), currency: input.fetch(:currency))
        project = Project.create!(input.merge(client_id: actor.id))
        raise Platform::Error.new("INVALID_DEADLINE", "Deadline must be in the future.") if project.deadline < Date.current
        BriefVersion.create!(project_id: project.id, version: 1, terms: project.brief_snapshot)
        Platform::Events.audit(action: "project.published", resource: project)
        Platform::Events.emit(type: "project.published", aggregate: project, payload: { audience: [ actor.id ], title: project.title, project_id: project.id })
        { id: project.id }
      end
    end
  end
end
