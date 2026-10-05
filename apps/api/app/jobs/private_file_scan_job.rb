require "digest"

class PrivateFileScanJob < ApplicationJob
  queue_as :files
  MAX_BYTES = 20.megabytes

  def perform(item_id, token = nil)
    item = file_model.find_by(id: item_id)
    return unless item

    token ||= FileScanDispatcher.claim(item)
    return unless token
    item.with_lock do
      return unless item.state == "quarantined" && item.scan_token == token

      # Rotate the queued claim so duplicate jobs cannot scan concurrently.
      token = SecureRandom.uuid
      item.update!(scan_token: token, scan_lease_until: FileScanDispatcher::LEASE.from_now, scan_attempts: item.scan_attempts + 1)
    end

    unless item.file.attached?
      return settle(item, token, state: "rejected", scan_error: "missing_attachment")
    end
    item.file.open do |file|
      bytes = file.binmode.read(MAX_BYTES + 1)
      digest = Digest::SHA256.hexdigest(bytes)
      if bytes.bytesize > MAX_BYTES || (item.sha256.present? && item.sha256 != digest)
        return settle(item, token, state: "rejected", scan_error: "integrity_mismatch")
      end

      result = Talent::FileScanner.scan(bytes)
      raise Talent::FileScanner::Unavailable, "unsupported scan result" unless %i[clean infected].include?(result)

      settle(item, token, state: result == :clean ? "available" : "rejected", sha256: digest, scan_error: result == :clean ? nil : "malware_detected")
    end
  rescue Talent::FileScanner::Unavailable => error
    postpone(item, token, error)
  rescue ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError
    settle(item, token, state: "rejected", scan_error: "integrity_mismatch")
  rescue ActiveRecord::RecordNotFound
    # An unused draft may be removed while its scan is running.
    nil
  rescue StandardError => error
    postpone(item, token, error) if item && token
    raise
  end

  private

  def settle(item, token, **attributes)
    file_model.where(id: item.id, state: "quarantined", scan_token: token).update_all(
      { scan_token: nil, scan_lease_until: nil, scan_retry_at: nil, updated_at: Time.current }.merge(attributes)
    )
  end

  def postpone(item, token, error)
    delay = [ 2**[ item.scan_attempts, 9 ].min, 300 ].min.seconds
    settle(item, token, scan_error: error.class.name, scan_retry_at: delay.from_now)
    Rails.logger.warn(JSON.generate(event: "file_scan.postponed", file_id: item.id, error: error.class.name))
  end
end
