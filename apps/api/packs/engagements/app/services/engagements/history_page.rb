module Engagements
  class HistoryPage
    def self.call(engagement:, actor:, versions_cursor: nil, feedback_cursor: nil, limit: 20)
      limit = Integer(limit.to_s, 10).clamp(1, 40)
      version_context = [ "work-versions", engagement.id, actor.id ]
      position = Platform::ReadCursor.decode(versions_cursor, context: version_context)
      versions = engagement.submissions.order(version: :desc)
      versions = versions.where("version < ?", position.fetch("version")) if position
      rows = versions.limit(limit + 1).includes(work_files: { file_attachment: :blob }).to_a
      submissions = rows.first(limit)
      next_version = rows.size > limit ? Platform::ReadCursor.encode({ "version" => submissions.last.version }, context: version_context) : nil

      feedback_context = [ "work-feedback", engagement.id, actor.id ]
      position = Platform::ReadCursor.decode(feedback_cursor, context: feedback_context)
      comments = engagement.feedback.order(created_at: :desc, id: :desc)
      comments = comments.where("(created_at, id) < (:time, :id)", time: position.fetch("time"), id: position.fetch("id")) if position
      rows = comments.limit(51).includes(:actor).to_a
      feedback = rows.first(50)
      next_feedback = if rows.size > 50
        last = feedback.last
        Platform::ReadCursor.encode({ "time" => last.created_at.iso8601(6), "id" => last.id }, context: feedback_context)
      end
      decisions = engagement.feedback.where(kind: "changes_requested", submission_id: submissions.map(&:id)).includes(:actor).to_a
      { submissions: submissions, feedback: (feedback + decisions).uniq(&:id), submissions_next_cursor: next_version, feedback_next_cursor: next_feedback }
    rescue ArgumentError, TypeError
      raise Platform::Error.new("INVALID_FILTER", "The page limit must be an integer.", status: 400)
    end
  end
end
