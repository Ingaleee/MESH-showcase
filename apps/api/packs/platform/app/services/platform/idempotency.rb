require "digest"

module Platform
  class Idempotency
    def self.call(actor_id:, operation:, key:, input:)
      raise Error.new("IDEMPOTENCY_KEY_REQUIRED", "A key is required.", status: 400) if key.to_s.empty? || key.to_s.bytesize > 200
      canonical = canonicalize(input)
      fingerprint = Digest::SHA256.hexdigest(JSON.generate(canonical))
      result = nil
      Record.transaction do
        record = IdempotencyRecord.create_or_find_by!(actor_id: actor_id, operation: operation, key: key) do |row|
          row.fingerprint = fingerprint
        end
        record.lock!
        unless record.fingerprint == fingerprint
          raise Error.new("IDEMPOTENCY_CONFLICT", "This key belongs to different input.", status: 409)
        end
        result = record.response || yield
        record.update!(response: result) unless record.response
      end
      result.deep_symbolize_keys
    end

    def self.canonicalize(value)
      case value
      when Hash
        value.stringify_keys.sort.to_h.transform_values { |item| canonicalize(item) }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end
  end
end
