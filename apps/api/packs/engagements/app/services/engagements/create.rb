module Engagements
  class Create
    def self.call(award_id:, client_id:, creator_id:, terms:)
      engagement = Engagement.create!(source_award_id: award_id, client_id: client_id, creator_id: creator_id, terms: terms)
      Platform::Events.emit(type: "engagement.created", aggregate: engagement, payload: { audience: [ client_id, creator_id ], title: terms.fetch("title"), engagement_id: engagement.id })
      engagement
    end
  end
end
