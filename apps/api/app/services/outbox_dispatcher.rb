class OutboxDispatcher
  LEASE = 45.seconds

  def self.call
    scope = Platform::Delivery.where(state: "pending").or(
      Platform::Delivery.where(state: "enqueued").where("enqueued_at < ?", LEASE.ago)
    )
    scope.where("available_at IS NULL OR available_at <= ?", Time.current).order(created_at: :asc).limit(100).each do |delivery|
      token = claim(delivery)
      next unless token

      job = EventDeliveryJob.perform_later(delivery.id, token)
      raise "event enqueue was rejected" unless job
    rescue StandardError => error
      delivery.with_lock do
        if token && delivery.state == "enqueued" && delivery.claim_token == token
          delivery.update!(state: "pending", claim_token: nil, available_at: 5.seconds.from_now, last_error: error.class.name)
        end
      end
      Rails.logger.warn(JSON.generate(event: "outbox.enqueue_failed", delivery_id: delivery.id, error: error.class.name))
    end
  end

  def self.claim(delivery)
    token = nil
    delivery.with_lock do
      next if %w[processed failed].include?(delivery.state)
      next if delivery.available_at && delivery.available_at > Time.current
      next if delivery.state == "enqueued" && delivery.enqueued_at && delivery.enqueued_at > LEASE.ago

      token = SecureRandom.uuid
      delivery.update!(state: "enqueued", claim_token: token, enqueued_at: Time.current, attempts: delivery.attempts + 1)
    end
    token
  end
end
