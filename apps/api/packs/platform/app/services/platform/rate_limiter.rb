require "openssl"

module Platform
  class RateLimiter
    Decision = Data.define(:allowed, :retry_after)

    def self.consume(scope:, identity:, limit:, period:)
      raise ArgumentError unless limit.is_a?(Integer) && limit.positive? && period.positive?

      digest = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{scope}\0#{identity}")
      Record.transaction do
        bucket = RateLimitBucket.create_or_find_by!(key_digest: digest) do |row|
          row.expires_at = period.from_now
        end
        bucket.lock!
        now = Time.current
        expired = bucket.expires_at <= now
        attempts = expired ? 1 : [ bucket.attempts + 1, limit + 1 ].min
        expires_at = expired ? now + period : bucket.expires_at
        bucket.update!(attempts: attempts, expires_at: expires_at)
        Decision.new(allowed: attempts <= limit, retry_after: [ (expires_at - now).ceil, 1 ].max)
      end
    end

    def self.purge_expired
      expired = RateLimitBucket.where("expires_at < ?", 1.day.ago).order(:expires_at).limit(1000).select(:key_digest)
      RateLimitBucket.where(key_digest: expired).where("expires_at < ?", 1.day.ago).delete_all
    end
  end
end
