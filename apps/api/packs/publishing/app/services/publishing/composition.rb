module Publishing
  # Composition root: Rails and adapters may depend on application contracts, never the reverse.
  module Composition
    def self.deployment(gateway:)
      Application::ProcessDeployment.new(
        store: Infrastructure::DeploymentStore.new, partner: Infrastructure::DeploymentPartner.new(gateway: gateway),
        artifacts: Infrastructure::DeploymentArtifacts.new, clock: -> { Time.current }, tokens: -> { SecureRandom.uuid }
      )
    end
  end
end
