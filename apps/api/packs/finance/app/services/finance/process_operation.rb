module Finance
  class ProcessOperation
    def self.call(operation_id:, gateway: SandboxGateway.new)
      operation = PaymentOperation.find(operation_id)
      lookup_only = false
      should_run = false
      Platform::Record.transaction do
        settlement = operation.settlement
        settlement.lock!
        operation.lock!
        next if %w[confirmed failed].include?(operation.state)
        next if operation.state == "dispatching" && operation.lease_until && operation.lease_until > Time.current
        if operation.kind == "payout" && (settlement.hold? || ENV.fetch("MESH_PAYOUTS_ENABLED", "true") != "true")
          operation.update!(next_retry_at: 10.seconds.from_now)
          next
        end
        lookup_only = operation.state != "requested"
        operation.update!(state: "dispatching", lease_until: 30.seconds.from_now, attempts: operation.attempts + 1)
        should_run = true
      end
      return operation unless should_run
      observation = lookup_only ? gateway.lookup(operation.id) : gateway.execute(operation)
      if observation.nil? && operation.created_at > 24.hours.ago
        observation = gateway.execute(operation)
      end
      raise SandboxGateway::Unavailable, "provider outcome remains unknown" unless observation
      ApplyObservation.call(operation_id: operation.id, observation: observation)
    rescue SandboxGateway::Unavailable, Platform::Error => error
      if operation
        operation.with_lock do
          unless %w[confirmed failed].include?(operation.state)
            operation.update!(state: "unknown", lease_until: nil, last_error: error.message, next_retry_at: 5.seconds.from_now)
          end
        end
      end
      operation
    end
  end
end
