module Publishing
  class ApplyObservation
    def self.call(deployment:, observation:, claim_token: nil)
      candidate = deployment.candidate
      valid = observation.is_a?(Hash) && observation["operation_id"] == deployment.id &&
        observation["candidate_id"] == candidate.id && observation["artifact_sha256"] == candidate.artifact_sha256 &&
        observation["contract_version"] == deployment.partner.contract_version && observation["state"] == "active" &&
        observation["sequence"].is_a?(Integer) && observation["sequence"].positive? &&
        observation["deployment_id"].to_s.match?(/\A[a-zA-Z0-9\-]{1,100}\z/)
      raise Platform::Error.new("PARTNER_OBSERVATION_INVALID", "Remote identity or outcome does not match the operation.", status: 409) unless valid
      Platform::Record.transaction do
        partner = deployment.partner
        partner.lock!
        deployment.lock!
        return deployment if claim_token && (deployment.state != "dispatching" || deployment.claim_token != claim_token)
        if deployment.state == "confirmed"
          unless deployment.remote_id == observation["deployment_id"] && deployment.remote_sequence == observation["sequence"]
            raise Platform::Error.new("PARTNER_OBSERVATION_CONFLICT", "Remote identity changed after confirmation.", status: 409)
          end
          return deployment
        end
        raise Platform::Error.new("DEPLOYMENT_CLOSED", "This operation is closed.", status: 409) if deployment.state == "failed"
        deployment.update!(
          state: "confirmed", claim_token: nil, lease_until: nil, confirmed_at: Time.current,
          remote_id: observation["deployment_id"], remote_sequence: observation["sequence"], last_error: nil
        )
        if observation["sequence"] > partner.active_sequence
          partner.update!(active_deployment: deployment, active_sequence: observation["sequence"])
        end
        Platform::Events.audit(action: "publishing.deployment.confirmed", resource: deployment, details: { sequence: observation["sequence"] })
      end
      deployment
    end
  end
end
