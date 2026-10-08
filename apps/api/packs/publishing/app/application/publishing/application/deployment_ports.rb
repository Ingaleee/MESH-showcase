module Publishing
  module Application
    module DeploymentPorts
      # These contracts express the consistency guarantees required by the use case.
      class Store
        # Atomically fence the claim; nil means no work. Return an immutable Domain Claim.
        def claim(id:, now:, token:)
          raise NotImplementedError
        end

        # Validate identity, lock partner before operation, fence stale workers and commit the effect.
        def confirm(claim:, observation:)
          raise NotImplementedError
        end

        # Change to unknown only while this token still owns the dispatching operation.
        def mark_unknown(claim:, code:)
          raise NotImplementedError
        end
      end

      class Partner
        def publish(claim:, bytes:)
          raise NotImplementedError
        end

        def lookup(claim:)
          raise NotImplementedError
        end
      end

      class Artifacts
        def read(claim:)
          raise NotImplementedError
        end
      end
    end
  end
end
