module Talent
  class Profile < Platform::Record
    self.table_name = "talent_profiles"
    belongs_to :account, class_name: "Identity::Account"
    validates :headline, presence: true, length: { maximum: 160 }
    validates :bio, length: { maximum: 5000 }
  end
end
