module Publishing
  module Infrastructure
    class DeploymentStore < Application::DeploymentPorts::Store
      def claim(id:, now:, token:)
        row = Deployment.find(id)
        row.with_lock do
          mode = Domain::DeploymentRules.claim_mode(state: row.state, lease_until: row.lease_until, now: now,
            current_fingerprint: row.state == "pending" ? Settings.fingerprint(row.candidate) : nil,
            validated_fingerprint: row.validation.input_fingerprint)
          return if mode == :skip
          if mode == :stale
            row.update!(state: "failed", last_error: "VALIDATION_STALE")
            return
          end
          row.update!(state: "dispatching", claim_token: token, lease_until: now + 60, attempts: row.attempts + 1)
          Domain::DeploymentRules::Claim.new(id: row.id, token: token, lookup_only: mode == :lookup, artifact_sha256: row.candidate.artifact_sha256)
        end
      end

      def confirm(claim:, observation:)
        ApplyObservation.call(deployment: Deployment.find(claim.id), observation: observation, claim_token: claim.token)
      rescue Platform::Error => error
        raise Domain::Failure.new(error.code, error.message)
      end

      def mark_unknown(claim:, code:)
        row = Deployment.find(claim.id)
        row.with_lock do
          if row.state == "dispatching" && row.claim_token == claim.token
            row.update!(state: "unknown", claim_token: nil, lease_until: nil, last_error: code,
              consecutive_failures: row.consecutive_failures + 1, next_enqueue_at: 10.seconds.from_now)
          end
        end
      end
    end
  end
end
