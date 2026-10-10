module Publishing
  class RequestDeployment
    def self.call(actor:, candidate:, validation_id:, key:, scenario: "normal", rollback_of_id: nil)
      Settings.authorize!(actor, candidate.partner)
      unless %w[normal timeout_after_success].include?(scenario)
        raise Platform::Error.new("INVALID_SCENARIO", "Unsupported simulator scenario.")
      end
      if scenario != "normal" && ENV.fetch("MESH_PUBLISHING_FAILPOINTS", "false") != "true"
        raise Platform::Error.new("FAILPOINTS_DISABLED", "Failure injection is disabled.")
      end
      values = { validation_id: validation_id, scenario: scenario, rollback_of_id: rollback_of_id, fingerprint: Settings.fingerprint(candidate) }
      Platform::Idempotency.call(actor_id: actor.id, operation: "publishing.deploy:#{candidate.id}", key: key, input: values) do
        candidate.lock!
        validation = candidate.validations.find(validation_id)
        unless validation.state == "passed" && validation.input_fingerprint == values[:fingerprint]
          raise Platform::Error.new("VALIDATION_REQUIRED", "Validate the exact artifact under the current policy and configuration.", status: 409)
        end
        rollback_of = rollback_of_id && candidate.partner.deployments.find(rollback_of_id)
        if rollback_of && (rollback_of.state != "confirmed" || rollback_of.candidate_id != candidate.id)
          raise Platform::Error.new("ROLLBACK_BASIS_INVALID", "Choose a confirmed deployment of this artifact.", status: 409)
        end
        deployment = rollback_of ? Deployment.create!(candidate: candidate, partner: candidate.partner, validation: validation, rollback_of: rollback_of, kind: "rollback", scenario: scenario, correlation_id: Platform::Current.correlation_id || SecureRandom.uuid) :
          Deployment.create_or_find_by!(candidate: candidate, kind: "publish") { |row|
            row.assign_attributes(partner: candidate.partner, validation: validation, scenario: scenario, correlation_id: Platform::Current.correlation_id || SecureRandom.uuid)
          }
        Platform::Events.audit(action: "publishing.deployment.requested", resource: deployment)
        { id: deployment.id }
      end
    end
  end
end
