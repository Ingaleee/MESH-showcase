module Talent
  class PortfolioItem < Platform::Record
    self.table_name = "talent_portfolio_items"
    belongs_to :account, class_name: "Identity::Account"
    has_one_attached :file
    validates :title, presence: true, length: { maximum: 160 }
  end
end
