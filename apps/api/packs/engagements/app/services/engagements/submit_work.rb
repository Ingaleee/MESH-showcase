require "digest"
module Engagements
  class SubmitWork
    def self.call(actor:, engagement:, content:, key:, title: "", ready_for_acceptance: true, file_ids: [])
      raise Platform::Error.new("FORBIDDEN", "Only the author can submit work.", status: 403) unless engagement.creator_id == actor.id
      valid_text = title.is_a?(String) && content.is_a?(String)
      valid_files = file_ids.is_a?(Array) && file_ids.size <= 8 && file_ids.uniq.size == file_ids.size
      raise ArgumentError unless valid_text && valid_files && [ true, false ].include?(ready_for_acceptance)
      intent = { content: content }
      intent.merge!(title: title, ready_for_acceptance: ready_for_acceptance, file_ids: file_ids) unless title.empty? && ready_for_acceptance && file_ids.empty?
      Platform::Idempotency.call(actor_id: actor.id, operation: "submit:#{engagement.id}", key: key, input: intent) do
        engagement.lock!
        files = file_ids.map do |id|
          WorkFile.where(engagement_id: engagement.id, creator_id: actor.id, submission_id: nil).lock.find(id)
        end
        raise Platform::Error.new("FILE_REJECTED", "Remove rejected files.", status: 409) if files.any? { |file| file.state == "rejected" }
        manifest = files.map(&:manifest)
        document = Platform::Idempotency.canonicalize({ title: title, content: content, ready_for_acceptance: ready_for_acceptance, files: manifest })
        engagement.transition!(to: "submitted")
        version = engagement.submissions.maximum(:version).to_i + 1
        submission = Submission.create!(
          engagement_id: engagement.id, version: version, content: content, title: title,
          ready_for_acceptance: ready_for_acceptance, files_manifest: manifest,
          sha256: Digest::SHA256.hexdigest(content),
          manifest_sha256: Digest::SHA256.hexdigest(JSON.generate(document))
        )
        files.each { |file| file.update!(submission: submission) }
        Platform::Events.audit(action: "work.submitted", resource: engagement, details: { submission_id: submission.id, version: version })
        Platform::Events.emit(type: "work.submitted", aggregate: engagement, payload: { audience: [ engagement.client_id ], title: engagement.terms.fetch("title"), engagement_id: engagement.id })
        { id: submission.id, version: version }
      end
    end
  end
end
