require "digest"
require "stringio"

module Publishing
  class SubmitCandidate
    def self.call(actor:, partner:, manifest:, bytes:, key:)
      Settings.authorize!(actor, partner)
      unless manifest.is_a?(Hash) && JSON.generate(manifest).bytesize <= 16_384 && bytes.is_a?(String) &&
          bytes.bytesize.between?(1, Settings::ARTIFACT_LIMIT)
        raise Platform::Error.new("PACKAGE_LIMIT", "Use a manifest up to 16 KiB and a ZIP up to 2 MB.")
      end
      artifact_sha = Digest::SHA256.hexdigest(bytes)
      manifest_sha = Digest::SHA256.hexdigest(JSON.generate(Platform::Idempotency.canonicalize(manifest)))
      Platform::Idempotency.call(actor_id: actor.id, operation: "publishing.candidate:#{partner.id}", key: key, input: { artifact: artifact_sha, manifest: manifest_sha }) do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "#{artifact_sha}.zip", content_type: "application/zip", identify: false)
        candidate = Candidate.create!(
          partner: partner, artifact_blob: blob, manifest: manifest, artifact_sha256: artifact_sha,
          manifest_sha256: manifest_sha, correlation_id: Platform::Current.correlation_id || SecureRandom.uuid
        )
        validation = Validation.create!(candidate: candidate, policy_version: Settings.policy_version, input_fingerprint: Settings.fingerprint(candidate))
        Platform::Events.audit(action: "publishing.candidate.submitted", resource: candidate, details: { artifact_sha256: artifact_sha, validation_id: validation.id })
        { id: candidate.id, validation_id: validation.id }
      end
    end
  end
end
