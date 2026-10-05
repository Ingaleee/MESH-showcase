module Platform
  class RateLimitBucket < Record
    self.table_name = "platform_rate_limit_buckets"
    self.primary_key = "key_digest"
  end
end
