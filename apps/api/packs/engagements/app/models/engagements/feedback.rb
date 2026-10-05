module Engagements
  class Feedback < Platform::Record
    self.table_name = "engagements_feedback"
    belongs_to :engagement, class_name: "Engagements::Engagement"
    belongs_to :submission, class_name: "Engagements::Submission", optional: true
    belongs_to :actor, class_name: "Identity::Account"
    validates :content, presence: true, length: { maximum: 4000 }
  end
end
