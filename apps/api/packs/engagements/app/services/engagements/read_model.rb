module Engagements
  class ReadModel
    def self.for_award(award_id, actor_id:)
      engagement = Engagement.find_by!(source_award_id: award_id)
      basis(engagement.id, actor_id: actor_id).slice(:id, :state, :creator_name)
    end

    def self.basis(id, actor_id: nil)
      engagement = Engagement.find(id)
      if actor_id && ![ engagement.client_id, engagement.creator_id ].include?(actor_id)
        raise Platform::Error.new("FORBIDDEN", "This engagement is private.", status: 403)
      end
      {
        id: engagement.id, client_id: engagement.client_id, creator_id: engagement.creator_id,
        state: engagement.state, amount_minor: engagement.terms.fetch("price_minor"),
        currency: engagement.terms.fetch("currency"), commission_basis_points: engagement.terms.fetch("commission_basis_points"),
        title: engagement.terms.fetch("title"), creator_name: engagement.creator.display_name
      }
    end
  end
end
