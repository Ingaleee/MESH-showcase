module Publishing
  module Domain
    class DeploymentRules
      Claim = Data.define(:id, :token, :lookup_only, :artifact_sha256)
      IntegrationFailure = Class.new(Failure)

      def self.claim_mode(state:, lease_until:, now:, current_fingerprint:, validated_fingerprint:)
        return :skip if %w[confirmed failed].include?(state)
        return :skip if state == "dispatching" && lease_until && lease_until > now
        return :stale if state == "pending" && current_fingerprint != validated_fingerprint
        state == "pending" ? :publish : :lookup
      end

      def self.verify_observation!(operation_id:, candidate_id:, artifact_sha256:, contract_version:, observation:)
        valid = observation.is_a?(Hash) && observation["operation_id"] == operation_id &&
          observation["candidate_id"] == candidate_id && observation["artifact_sha256"] == artifact_sha256 &&
          observation["contract_version"] == contract_version && observation["state"] == "active" &&
          observation["sequence"].is_a?(Integer) && observation["sequence"].positive? &&
          observation["deployment_id"].is_a?(String) && observation["deployment_id"].match?(/\A[a-zA-Z0-9\-]{1,100}\z/)
        raise Failure.new("PARTNER_OBSERVATION_INVALID", "Remote identity or outcome does not match the operation.") unless valid
      end

      def self.confirmation(state:, current_token:, worker_token:, remote_id:, remote_sequence:, observation:)
        return :ignore if worker_token && (state != "dispatching" || current_token != worker_token)
        if state == "confirmed"
          unless remote_id == observation["deployment_id"] && remote_sequence == observation["sequence"]
            raise Failure.new("PARTNER_OBSERVATION_CONFLICT", "Remote identity changed after confirmation.")
          end
          return :replay
        end
        raise Failure.new("DEPLOYMENT_CLOSED", "This operation is closed.") if state == "failed"
        :confirm
      end
    end
  end
end
