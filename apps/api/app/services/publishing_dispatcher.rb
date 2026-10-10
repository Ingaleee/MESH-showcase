class PublishingDispatcher
  def self.call
    return unless ENV.fetch("MESH_PUBLISHING_ENABLED", "false") == "true"
    now = Time.current
    validations = Publishing::Validation.where(state: %w[pending running])
      .where("lease_until IS NULL OR lease_until <= ?", now).where("next_enqueue_at IS NULL OR next_enqueue_at <= ?", now).order(:created_at).limit(20)
    deployments = Publishing::Deployment.where(state: %w[pending unknown dispatching])
      .where("lease_until IS NULL OR lease_until <= ?", now).where("next_enqueue_at IS NULL OR next_enqueue_at <= ?", now)
      .where("consecutive_failures < 5").order(:created_at).limit(20)
    [ [ validations, PublishingValidationJob ], [ deployments, PublishingDeploymentJob ] ].each do |scope, job|
      scope.each do |row|
        row.update!(next_enqueue_at: 30.seconds.from_now)
        job.perform_later(row.id)
      rescue StandardError => error
        Rails.logger.warn(JSON.generate(event: "publishing.enqueue_failed", error: error.class.name))
      end
    end
  end
end
