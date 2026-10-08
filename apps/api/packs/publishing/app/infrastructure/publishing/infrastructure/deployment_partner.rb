module Publishing
  module Infrastructure
    class DeploymentPartner < Application::DeploymentPorts::Partner
      def initialize(gateway:)
        @gateway = gateway
      end

      def publish(claim:, bytes:)
        @gateway.publish(Deployment.find(claim.id), bytes)
      rescue Platform::HttpClient::Failure => error
        raise Domain::DeploymentRules::IntegrationFailure.new(error.code, "External publication has an uncertain outcome.")
      end

      def lookup(claim:)
        @gateway.lookup(Deployment.find(claim.id))
      rescue Platform::HttpClient::Failure => error
        raise Domain::DeploymentRules::IntegrationFailure.new(error.code, "External lookup is unavailable.")
      end
    end
  end
end
