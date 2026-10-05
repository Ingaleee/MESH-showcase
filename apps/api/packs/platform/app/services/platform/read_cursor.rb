require "digest"

module Platform
  class ReadCursor
    def self.decode(token, context:)
      return nil if token.blank?
      payload = token.is_a?(String) && token.bytesize <= 2048 && verifier.verified(token)
      unless payload.is_a?(Hash) && payload["scope"] == fingerprint(context) && payload["position"].is_a?(Hash)
        raise Error.new("INVALID_CURSOR", "This cursor expired or belongs to another read.", status: 400)
      end
      payload.fetch("position")
    end

    def self.encode(position, context:)
      verifier.generate({ "scope" => fingerprint(context), "position" => position }, expires_in: 30.minutes)
    end

    def self.verifier
      Rails.application.message_verifier("bounded_read_cursor")
    end

    def self.fingerprint(context)
      Digest::SHA256.hexdigest(JSON.generate(context))
    end
  end
end
