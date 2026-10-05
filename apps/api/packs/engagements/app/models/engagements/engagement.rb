module Engagements
  class Engagement < Platform::Record
    self.table_name = "engagements_engagements"
    has_many :submissions, class_name: "Engagements::Submission"
    has_one :acceptance, class_name: "Engagements::Acceptance"
    has_many :feedback, class_name: "Engagements::Feedback"
    belongs_to :client, class_name: "Identity::Account"
    belongs_to :creator, class_name: "Identity::Account"

    def transition!(to:)
      allowed = {
        "agreed" => %w[in_progress submitted cancelled],
        "in_progress" => %w[submitted cancelled],
        "submitted" => %w[submitted in_progress accepted],
        "accepted" => [], "cancelled" => []
      }
      raise Platform::Error.new("INVALID_TRANSITION", "This action is not available.", status: 409) unless allowed.fetch(state).include?(to)
      update!(state: to)
    end
  end
end
