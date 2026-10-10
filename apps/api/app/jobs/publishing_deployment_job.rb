class PublishingDeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment_id)
    Publishing::ProcessDeployment.call(deployment_id: deployment_id)
  end
end
