module Publishing
  class ApplyObservation
    def self.call(deployment:, observation:, claim_token: nil)
      candidate = deployment.candidate
      Domain::DeploymentRules.verify_observation!(operation_id: deployment.id, candidate_id: candidate.id,
        artifact_sha256: candidate.artifact_sha256, contract_version: deployment.partner.contract_version, observation: observation)
      Platform::Record.transaction do
        partner = deployment.partner
        partner.lock!
        deployment.lock!
        decision = Domain::DeploymentRules.confirmation(state: deployment.state, current_token: deployment.claim_token,
          worker_token: claim_token, remote_id: deployment.remote_id, remote_sequence: deployment.remote_sequence, observation: observation)
        return deployment unless decision == :confirm
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
    rescue Domain::Failure => error
      raise Platform::Error.new(error.code, error.message, status: 409)
    end
  end
end
