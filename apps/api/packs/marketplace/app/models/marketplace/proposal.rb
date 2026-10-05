module Marketplace
  class Proposal < Platform::Record
    self.table_name = "marketplace_proposals"
    belongs_to :project, class_name: "Marketplace::Project"
    belongs_to :creator, class_name: "Identity::Account"
    has_one :example, class_name: "Marketplace::ProposalExample"
    validates :message, presence: true, length: { maximum: 5000 }
    validates :price_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000_000_000 }
    validates :delivery_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  end
end
