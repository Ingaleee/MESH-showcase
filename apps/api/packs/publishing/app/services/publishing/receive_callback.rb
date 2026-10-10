require "openssl"
require "digest"

module Publishing
  class ReceiveCallback
    def self.call(partner:, event_id:, timestamp:, signature:, bytes:)
      unless event_id.to_s.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/) && timestamp.to_s.match?(/\A\d{10}\z/) &&
          signature.to_s.match?(/\A[a-f0-9]{64}\z/) && bytes.bytesize <= 65_536 &&
          (Time.current.to_i - timestamp.to_i).abs <= 300
        raise Platform::Error.new("CALLBACK_AUTH_INVALID", "Invalid or expired callback.", status: 401)
      end
      expected = OpenSSL::HMAC.hexdigest("SHA256", Settings.token(partner), "#{timestamp}.#{event_id}.#{bytes}")
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        raise Platform::Error.new("CALLBACK_AUTH_INVALID", "Invalid callback signature.", status: 401)
      end
      observation = JSON.parse(bytes, max_nesting: 10)
      raise Platform::Error.new("CALLBACK_SCHEMA_INVALID", "Expected an object.", status: 400) unless observation.is_a?(Hash)
      body_sha = Digest::SHA256.hexdigest(bytes)
      Platform::Record.transaction do
        partner.lock!
        prior = CallbackReceipt.find_by(partner: partner, event_id: event_id)
        if prior
          raise Platform::Error.new("CALLBACK_REPLAY_CONFLICT", "Event ID belongs to different content.", status: 409) unless prior.body_sha256 == body_sha
          return { duplicate: true, deployment_id: prior.deployment_id }
        end
        deployment = partner.deployments.find(observation.fetch("operation_id"))
        ApplyObservation.call(deployment: deployment, observation: observation)
        CallbackReceipt.create!(partner: partner, event_id: event_id, deployment: deployment, body_sha256: body_sha)
        { duplicate: false, deployment_id: deployment.id }
      end
    rescue JSON::ParserError, JSON::NestingError, KeyError
      raise Platform::Error.new("CALLBACK_SCHEMA_INVALID", "Invalid callback schema.", status: 400)
    end
  end
end
