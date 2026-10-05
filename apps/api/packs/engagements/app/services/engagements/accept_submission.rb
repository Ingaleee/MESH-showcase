module Engagements
  class AcceptSubmission
    def self.call(actor:, engagement:, submission_id:, key:)
      raise Platform::Error.new("FORBIDDEN", "Only the client can accept work.", status: 403) unless engagement.client_id == actor.id
      Platform::Idempotency.call(actor_id: actor.id, operation: "accept:#{engagement.id}", key: key, input: { submission_id: submission_id }) do
        engagement.lock!
        submission = engagement.submissions.find(submission_id)
        latest = engagement.submissions.order(version: :desc).first
        raise Platform::Error.new("STALE_SUBMISSION", "A newer submission is available.", status: 409) unless latest.id == submission.id
        raise Platform::Error.new("NOT_READY", "The author shared this version for discussion.", status: 409) unless submission.ready_for_acceptance
        if engagement.feedback.exists?(submission_id: submission.id, kind: "changes_requested")
          raise Platform::Error.new("CHANGES_REQUESTED", "Wait for a new version.", status: 409)
        end
        files = WorkFile.where(submission_id: submission.id).order(:id).lock.to_a
        if files.any? { |file| file.state != "available" }
          raise Platform::Error.new("FILES_NOT_VERIFIED", "All result files must pass verification before acceptance.", status: 409)
        end
        engagement.transition!(to: "accepted")
        acceptance = Acceptance.create!(engagement_id: engagement.id, submission_id: submission.id)
        Platform::Events.audit(action: "work.accepted", resource: engagement, details: { submission_id: submission.id, sha256: submission.sha256 })
        Platform::Events.emit(type: "work.accepted", aggregate: engagement, payload: { audience: [ engagement.client_id, engagement.creator_id ], title: engagement.terms.fetch("title"), engagement_id: engagement.id })
        { id: acceptance.id }
      end
    end
  end
end
