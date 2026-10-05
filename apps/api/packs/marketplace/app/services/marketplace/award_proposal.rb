module Marketplace
  class AwardProposal
    def self.call(actor:, project:, proposal_id:, brief_version:, key:)
      raise Platform::Error.new("FORBIDDEN", "Only the client can select an author.", status: 403) unless project.client_id == actor.id
      Platform::Idempotency.call(actor_id: actor.id, operation: "award:#{project.id}", key: key, input: { proposal_id: proposal_id, brief_version: brief_version }) do
        project.lock!
        raise Platform::Error.new("ALREADY_AWARDED", "An author has already been selected.", status: 409) unless project.state == "open"
        proposal = project.proposals.find(proposal_id)
        unless proposal.brief_version == project.brief_version && brief_version == project.brief_version
          raise Platform::Error.new("STALE_BRIEF", "Proposal belongs to an older brief.", status: 409)
        end
        award = Award.create!(project_id: project.id, proposal_id: proposal.id)
        engagement = Engagements::Create.call(
          award_id: award.id, client_id: actor.id, creator_id: proposal.creator_id,
          terms: project.brief_snapshot.merge("price_minor" => proposal.price_minor, "delivery_days" => proposal.delivery_days, "proposal_id" => proposal.id, "commission_basis_points" => 1000, "commission_policy" => "standard-v1")
        )
        project.update!(state: "awarded", accepting_proposals: false)
        Platform::Events.audit(action: "proposal.awarded", resource: project, details: { proposal_id: proposal.id, engagement_id: engagement.id })
        { id: engagement.id }
      end
    end
  end
end
