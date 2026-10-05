module Marketplace
  class ProposalExample < Platform::Record
    self.table_name = "marketplace_proposal_examples"
    belongs_to :project, class_name: "Marketplace::Project"
    belongs_to :creator, class_name: "Identity::Account"
    belongs_to :proposal, class_name: "Marketplace::Proposal", optional: true
    has_one_attached :file
    validates :state, inclusion: { in: %w[quarantined available rejected] }
    validates :sha256, presence: true

    def visible_to?(actor)
      creator_id == actor.id || (proposal_id.present? && project.client_id == actor.id)
    end
  end
end
