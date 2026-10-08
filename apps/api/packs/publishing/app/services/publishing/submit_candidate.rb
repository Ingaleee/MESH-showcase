require "digest"
require "stringio"
require "timeout"

module Publishing
  class SubmitCandidate
    UPLOAD_TIMEOUT = 30
    LEASE = 60.seconds

    def self.call(actor:, partner:, manifest:, bytes:, key:)
      Settings.authorize!(actor, partner)
      unless manifest.is_a?(Hash) && JSON.generate(manifest).bytesize <= 16_384 && bytes.is_a?(String) &&
          bytes.bytesize.between?(1, Settings::ARTIFACT_LIMIT)
        raise Platform::Error.new("PACKAGE_LIMIT", "Use a manifest up to 16 KiB and a ZIP up to 2 MB.")
      end
      if !key.is_a?(String) || key.empty? || key.bytesize > 200
        raise Platform::Error.new("IDEMPOTENCY_KEY_REQUIRED", "A key up to 200 bytes is required.", status: 400)
      end
      artifact_sha = Digest::SHA256.hexdigest(bytes)
      manifest_sha = Digest::SHA256.hexdigest(JSON.generate(Platform::Idempotency.canonicalize(manifest)))
      fingerprint = Digest::SHA256.hexdigest("#{artifact_sha}:#{manifest_sha}")
      intent = reserve(partner, key, fingerprint, bytes, artifact_sha)
      return intent.response.deep_symbolize_keys if intent.state == "finalized"
      upload(intent, bytes) unless intent.state == "ready"

      Platform::Idempotency.call(actor_id: actor.id, operation: "publishing.candidate:#{partner.id}", key: key, input: { artifact: artifact_sha, manifest: manifest_sha }) do
        intent.lock!
        if intent.state == "finalized"
          intent.response
        else
          raise Platform::Error.new("UPLOAD_NOT_READY", "Retry the same upload key.", status: 409) unless intent.state == "ready"
          candidate = Candidate.create!(
            partner: partner, artifact_blob: intent.artifact_blob, manifest: manifest, artifact_sha256: artifact_sha,
            manifest_sha256: manifest_sha, correlation_id: Platform::Current.correlation_id || SecureRandom.uuid
          )
          validation = Validation.create!(candidate: candidate, policy_version: Settings.policy_version, input_fingerprint: Settings.fingerprint(candidate))
          Platform::Events.audit(action: "publishing.candidate.submitted", resource: candidate, details: { artifact_sha256: artifact_sha, validation_id: validation.id })
          response = { id: candidate.id, validation_id: validation.id }
          intent.update!(state: "finalized", response: response)
          response
        end
      end
    end

    def self.reserve(partner, key, fingerprint, bytes, artifact_sha)
      intent = UploadIntent.create_or_find_by!(partner: partner, request_key: key) { |row| row.fingerprint = fingerprint }
      intent.with_lock do
        unless intent.fingerprint == fingerprint
          raise Platform::Error.new("IDEMPOTENCY_CONFLICT", "This key belongs to different bytes or manifest.", status: 409)
        end
        raise Platform::Error.new("UPLOAD_EXPIRED", "This abandoned upload was reclaimed. Use a new key.", status: 409) if intent.state == "discarded"
        unless intent.artifact_blob_id
          blob = ActiveStorage::Blob.create_before_direct_upload!(
            key: "pub#{intent.id.delete('-')}", filename: "#{artifact_sha}.zip", byte_size: bytes.bytesize,
            checksum: Digest::MD5.base64digest(bytes), content_type: "application/zip"
          )
          intent.update!(artifact_blob: blob)
        end
      end
      intent
    end
    private_class_method :reserve

    def self.upload(intent, bytes)
      token = SecureRandom.uuid
      intent.with_lock do
        return if %w[ready finalized].include?(intent.state)
        if intent.state == "uploading" && intent.lease_until > Time.current
          raise Platform::Error.new("UPLOAD_IN_PROGRESS", "An upload owns this key. Retry the same key shortly.", status: 409)
        end
        raise Platform::Error.new("UPLOAD_EXPIRED", "Use a new upload key.", status: 409) if intent.state == "discarded"
        intent.update!(state: "uploading", claim_token: token, lease_until: LEASE.from_now)
      end
      # Blob metadata and intent are committed before storage I/O. Replays write only identical bytes to the same key.
      Timeout.timeout(UPLOAD_TIMEOUT) { intent.artifact_blob.upload_without_unfurling(StringIO.new(bytes)) }
      intent.with_lock do
        unless intent.state == "uploading" && intent.claim_token == token
          raise Platform::Error.new("UPLOAD_CLAIM_LOST", "Retry the same key after the current upload.", status: 409)
        end
        intent.update!(state: "ready", claim_token: nil, lease_until: nil, last_error: nil)
      end
    rescue Timeout::Error, IOError, SystemCallError, ActiveStorage::IntegrityError => error
      intent.with_lock do
        if intent.state == "uploading" && intent.claim_token == token
          intent.update!(state: "reserved", claim_token: nil, lease_until: nil, last_error: error.class.name)
        end
      end
      raise Platform::Error.new("UPLOAD_UNAVAILABLE", "Storage is unavailable; retry the same upload key.", status: 503)
    end
    private_class_method :upload
  end
end
