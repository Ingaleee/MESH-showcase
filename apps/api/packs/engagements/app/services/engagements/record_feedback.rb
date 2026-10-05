module Engagements
  class RecordFeedback
    def self.call(actor:, engagement:, content:, submission_id:, kind:, key:)
      unless [ engagement.client_id, engagement.creator_id ].include?(actor.id)
        raise Platform::Error.new("FORBIDDEN", "Participant access required.", status: 403)
      end
      raise ArgumentError unless %w[comment changes_requested].include?(kind)
      if kind == "changes_requested" && actor.id != engagement.client_id
        raise Platform::Error.new("FORBIDDEN", "Only the client can request changes.", status: 403)
      end
      Platform::Idempotency.call(actor_id: actor.id, operation: "feedback:#{engagement.id}", key: key, input: { content: content, submission_id: submission_id, kind: kind }) do
        engagement.lock!
        submission = submission_id.present? ? engagement.submissions.find(submission_id) : nil
        if kind == "changes_requested"
          latest = engagement.submissions.order(version: :desc).first
          raise Platform::Error.new("STALE_SUBMISSION", "Review the latest version.", status: 409) unless submission && latest&.id == submission.id
          raise Platform::Error.new("INVALID_TRANSITION", "This version is not awaiting review.", status: 409) unless engagement.state == "submitted"
          engagement.transition!(to: "in_progress")
        end
        feedback = Feedback.create!(engagement: engagement, submission: submission, actor: actor, content: content, kind: kind)
        Platform::Events.audit(action: "work.#{kind}", resource: engagement, details: { feedback_id: feedback.id, submission_id: submission&.id })
        Platform::Events.emit(type: "work.#{kind}", aggregate: engagement, payload: { audience: [ engagement.client_id, engagement.creator_id ] - [ actor.id ], title: engagement.terms.fetch("title"), engagement_id: engagement.id })
        { id: feedback.id }
      end
    end
  end
end
