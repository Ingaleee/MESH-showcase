module Publishing
  module Infrastructure
    class DeploymentPartner < Application::DeploymentPorts::Partner
      def initialize(gateway:)
        @gateway = gateway
      end

      def publish(claim:, bytes:)
        @gateway.publish(Deployment.find(claim.id), bytes)
      rescue Platform::HttpClient::Failure => error
        raise Domain::DeploymentRules::IntegrationFailure.new(integration_code(error), "External publication has an uncertain outcome.")
      end

      def lookup(claim:)
        @gateway.lookup(Deployment.find(claim.id))
      rescue Platform::HttpClient::Failure => error
        raise Domain::DeploymentRules::IntegrationFailure.new(integration_code(error), "External lookup is unavailable.")
      end

      private

      def integration_code(error)
        [ 401, 403 ].include?(error.status) ? "PARTNER_AUTH_REJECTED" : error.code
      end
    end
  end
end
