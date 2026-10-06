class PaymentOperationJob < ApplicationJob
  queue_as :critical
  limits_concurrency to: 1, key: ->(operation_id) { operation_id }, duration: 1.minute

  def perform(operation_id)
    entry = Platform::AuditEntry.where(resource_id: operation_id).order(created_at: :asc).first
    Platform::Current.set(correlation_id: entry&.correlation_id || SecureRandom.uuid) do
      Finance::ProcessOperation.call(operation_id: operation_id)
    end
  end
end
