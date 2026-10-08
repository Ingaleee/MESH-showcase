module Publishing
  module Infrastructure
    class DeploymentArtifacts < Application::DeploymentPorts::Artifacts
      def read(claim:)
        ValidateCandidate.read_bytes(Deployment.find(claim.id).candidate)
      rescue Platform::Error => error
        raise Domain::Failure.new(error.code, error.message)
      end
    end
  end
end
