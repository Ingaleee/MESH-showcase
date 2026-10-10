module Publishing
  class ProcessDeployment
    def self.call(deployment_id:, gateway: PartnerGateway.new)
      deployment = Deployment.find(deployment_id)
      token = nil
      lookup_only = false
      deployment.with_lock do
        return deployment if %w[confirmed failed].include?(deployment.state)
        return deployment if deployment.state == "dispatching" && deployment.lease_until && deployment.lease_until > Time.current
        lookup_only = deployment.state != "pending"
        if !lookup_only && deployment.validation.input_fingerprint != Settings.fingerprint(deployment.candidate)
          deployment.update!(state: "failed", last_error: "VALIDATION_STALE")
          return deployment
        end
        token = SecureRandom.uuid
        deployment.update!(state: "dispatching", claim_token: token, lease_until: 60.seconds.from_now, attempts: deployment.attempts + 1)
      end
      if lookup_only
        observation = gateway.lookup(deployment)
      else
        bytes = ValidateCandidate.read_bytes(deployment.candidate)
        unless Digest::SHA256.hexdigest(bytes) == deployment.candidate.artifact_sha256
          raise Platform::Error.new("ARTIFACT_DIGEST_CHANGED", "Stored bytes changed; publication is blocked.")
        end
        observation = gateway.publish(deployment, bytes)
      end
      raise Platform::HttpClient::Failure.new("PARTNER_OUTCOME_UNKNOWN") unless observation
      ApplyObservation.call(deployment: deployment, observation: observation, claim_token: token)
    rescue Platform::HttpClient::Failure, Platform::Error => error
      if deployment && token
        deployment.with_lock do
          if deployment.state == "dispatching" && deployment.claim_token == token
            deployment.update!(
              state: "unknown", claim_token: nil, lease_until: nil, last_error: error.code,
              consecutive_failures: deployment.consecutive_failures + 1, next_enqueue_at: 10.seconds.from_now
            )
          end
        end
      end
      deployment
    end
  end
end
