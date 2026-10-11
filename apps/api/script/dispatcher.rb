require_relative "../config/environment"

stopping = false
next_cleanup = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Signal.trap("TERM") { stopping = true }
Signal.trap("INT") { stopping = true }

until stopping
  begin
    Rails.application.executor.wrap do
      OutboxDispatcher.call
      PublishingDispatcher.call
      now = Time.current
      operations = Finance::PaymentOperation.where(state: %w[requested unknown dispatching])
        .where("next_retry_at IS NULL OR next_retry_at <= ?", now)
        .where("lease_until IS NULL OR lease_until <= ?", now)
        .order(created_at: :asc).limit(50)

      operations.each do |operation|
        operation.update!(next_retry_at: 30.seconds.from_now)
        PaymentOperationJob.perform_later(operation.id)
      end
      Finance::WebhookReceipt.where(processed_at: nil)
        .where("next_enqueue_at IS NULL OR next_enqueue_at <= ?", now).limit(30).each do |receipt|
        receipt.update!(next_enqueue_at: 30.seconds.from_now)
        WebhookReceiptJob.perform_later(receipt.id)
      end
      if ENV.fetch("MESH_SCAN_FILES", "false") == "true"
        FileScanDispatcher.call
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= next_cleanup
        Platform::RateLimiter.purge_expired
        next_cleanup = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
      end
    end
  rescue StandardError => error
    Rails.logger.error(JSON.generate(event: "dispatcher.error", error: error.class.name))
  end
  sleep 1
end
