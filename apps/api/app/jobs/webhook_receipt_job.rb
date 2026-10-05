class WebhookReceiptJob < ApplicationJob
  queue_as :critical
  limits_concurrency to: 1, key: ->(receipt_id) { receipt_id }, duration: 1.minute
  retry_on Finance::SandboxGateway::Unavailable, wait: 5.seconds, attempts: 5

  def perform(receipt_id)
    receipt = Finance::WebhookReceipt.find(receipt_id)
    return if receipt.processed_at

    operation_id = receipt.payload.fetch("operation_id")
    observation = Finance::SandboxGateway.new.lookup(operation_id)
    return unless observation

    receipt.with_lock do
      return if receipt.processed_at

      Finance::ApplyObservation.call(operation_id: operation_id, observation: observation)
      receipt.update!(processed_at: Time.current)
    end
  end
end
