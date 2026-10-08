require "digest"

module Publishing
  module Application
    class ProcessDeployment
      def initialize(store:, partner:, artifacts:, clock:, tokens:)
        @store, @partner, @artifacts, @clock, @tokens = store, partner, artifacts, clock, tokens
      end

      def call(id:)
        claim = @store.claim(id: id, now: @clock.call, token: @tokens.call)
        return unless claim
        if claim.lookup_only
          observation = @partner.lookup(claim: claim)
        else
          bytes = @artifacts.read(claim: claim)
          unless Digest::SHA256.hexdigest(bytes) == claim.artifact_sha256
            raise Domain::Failure.new("ARTIFACT_DIGEST_CHANGED", "Stored bytes changed; publication is blocked.")
          end
          observation = @partner.publish(claim: claim, bytes: bytes)
        end
        raise Domain::DeploymentRules::IntegrationFailure.new("PARTNER_OUTCOME_UNKNOWN", "Lookup has no definitive outcome.") unless observation
        @store.confirm(claim: claim, observation: observation)
      rescue Domain::Failure => error
        @store.mark_unknown(claim: claim, code: error.code) if claim
      end
    end
  end
end
