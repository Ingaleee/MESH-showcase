module Publishing
  class ProcessDeployment
    def self.call(deployment_id:, gateway: PartnerGateway.new)
      Composition.deployment(gateway: gateway).call(id: deployment_id)
      Deployment.find(deployment_id)
    end
  end
end
