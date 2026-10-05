module Marketplace
  class SubmitProposal
    def self.call(actor:, project:, input:, key:)
      raise Platform::Error.new("PROFILE_REQUIRED", "Create a creator profile first.") unless Talent::Directory.eligible?(actor.id)
      raise Platform::Error.new("FORBIDDEN", "You cannot apply to your own project.", status: 403) if project.client_id == actor.id
      Platform::Idempotency.call(actor_id: actor.id, operation: "proposal:#{project.id}", key: key, input: input) do
        project.lock!
        raise Platform::Error.new("PROJECT_CLOSED", "This project is no longer open.", status: 409) unless project.state == "open"
        raise Platform::Error.new("PROPOSALS_PAUSED", "The client has paused proposals.", status: 409) unless project.accepting_proposals
        raise Platform::Error.new("STALE_BRIEF", "Read the current brief before applying.", status: 409) unless input[:brief_version] == project.brief_version
        if Proposal.exists?(project_id: project.id, creator_id: actor.id, brief_version: project.brief_version)
          raise Platform::Error.new("ALREADY_APPLIED", "You already applied to this brief.", status: 409)
        end
        Platform::Money.new(minor: input.fetch(:price_minor), currency: project.currency)
        example = if input[:example_id].present?
          ProposalExample.where(project_id: project.id, creator_id: actor.id, proposal_id: nil).lock.find(input[:example_id])
        end
        if example&.state == "rejected"
          raise Platform::Error.new("FILE_REJECTED", "Remove the rejected example before applying.", status: 409)
        end
        proposal = Proposal.create!(input.except(:example_id).merge(project_id: project.id, creator_id: actor.id))
        example&.update!(proposal: proposal)
        Platform::Events.emit(type: "proposal.submitted", aggregate: proposal, payload: { audience: [ project.client_id ], title: project.title, project_id: project.id })
        { id: proposal.id }
      end
    end
  end
end
