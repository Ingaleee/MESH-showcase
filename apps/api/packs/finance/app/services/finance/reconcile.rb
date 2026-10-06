module Finance
  class Reconcile
    def self.call(gateway: SandboxGateway.new)
      result = { checked: 0, recovered: 0, exceptions: 0 }
      PaymentOperation.order(Arel.sql("reconciled_at ASC NULLS FIRST, created_at ASC")).limit(25).each do |operation|
        result[:checked] += 1
        observation = gateway.lookup(operation.id)
        if observation
          if %w[requested dispatching unknown].include?(operation.state)
            ApplyObservation.call(operation_id: operation.id, observation: observation)
            result[:recovered] += 1
          elsif !ProviderObservation.matches?(operation, observation, terminal: true)
            exception!(operation, "TERMINAL_PROVIDER_MISMATCH")
            result[:exceptions] += 1
          else
            operation.reconciliation_exceptions.where(resolved_at: nil).update_all(resolved_at: Time.current)
          end
        elsif %w[confirmed failed].include?(operation.state)
          exception!(operation, "TERMINAL_PROVIDER_MISSING")
          result[:exceptions] += 1
        end
      rescue SandboxGateway::Unavailable, Platform::Error => error
        exception!(operation, "RECONCILIATION_UNAVAILABLE", error.class.name)
        result[:exceptions] += 1
      ensure
        operation.update_column(:reconciled_at, Time.current)
      end
      result
    end
    def self.exception!(operation, code, error_class = nil)
      exception = ReconciliationException.create_or_find_by!(payment_operation_id: operation.id, code: code) do |row|
        row.details = { error_class: error_class }.compact
      end
      exception.with_lock do
        exception.update!(resolved_at: nil, details: { error_class: error_class }.compact)
      end
      exception
    end
  end
end
