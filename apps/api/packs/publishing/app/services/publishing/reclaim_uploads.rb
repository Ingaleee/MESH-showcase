module Publishing
  class ReclaimUploads
    MINIMUM_GRACE = 2.days

    def self.call(dry_run: true, grace: MINIMUM_GRACE, limit: 100)
      raise ArgumentError unless grace >= MINIMUM_GRACE && limit.between?(1, 1000)
      cutoff = Time.current - grace
      result = { dry_run: dry_run, inspected: 0, eligible: [], reclaimed: [], preserved: [] }
      UploadIntent.where(state: %w[reserved ready discarded]).where("updated_at < ?", cutoff).order(:updated_at, :id).limit(limit).each do |intent|
        eligible = false
        intent.with_lock do
          result[:inspected] += 1
          unless %w[reserved ready discarded].include?(intent.state) && intent.updated_at < cutoff && !referenced?(intent)
            result[:preserved] << intent.id
            next
          end
          eligible = true
          result[:eligible] << intent.id
          next if dry_run
          # Tombstone first. Concurrent requests are then rejected before they can upload or finalize.
          intent.update!(state: "discarded", claim_token: nil, lease_until: nil)
          Platform::Events.audit(action: "publishing.upload.discarded", resource: intent)
        end
        next if dry_run || !eligible || intent.state != "discarded"
        blob = intent.artifact_blob
        next unless blob
        # No SQL transaction surrounds storage deletion. The tombstone supports retry after a crash.
        blob.service.delete(blob.key)
        eligible = false
        intent.with_lock do
          if !referenced?(intent) && intent.state == "discarded"
            intent.update!(artifact_blob_id: nil)
            blob.destroy!
            result[:reclaimed] << intent.id
          end
        end
      end
      result
    end

    def self.referenced?(intent)
      return false unless intent.artifact_blob_id
      Candidate.exists?(artifact_blob_id: intent.artifact_blob_id) ||
        ActiveStorage::Attachment.exists?(blob_id: intent.artifact_blob_id)
    end
    private_class_method :referenced?
  end
end
