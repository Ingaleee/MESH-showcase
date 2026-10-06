module Finance
  class ApplyObservation
    def self.call(operation_id:, observation:)
      operation = PaymentOperation.find(operation_id)
      basis = Engagements::ReadModel.basis(operation.settlement.engagement_id)
      Platform::Record.transaction do
        settlement = operation.settlement
        settlement.lock!
        operation.lock!
        next operation if %w[confirmed failed].include?(operation.state)
        unless ProviderObservation.matches?(operation, observation)
          raise Platform::Error.new("PROVIDER_MISMATCH", "Provider observation does not match the operation.")
        end
        unless %w[confirmed failed].include?(observation["state"])
          raise Platform::Error.new("PROVIDER_STATE_INVALID", "Provider state is unsupported.")
        end
        if observation.fetch("state") == "confirmed"
          entries = if operation.kind == "fund"
            [
              { account_key: "provider_cash", direction: "debit", amount_minor: operation.amount_minor, currency: operation.currency },
              { account_key: "client_funds:#{settlement.id}", direction: "credit", amount_minor: operation.amount_minor, currency: operation.currency }
            ]
          else
            fee = settlement.amount_minor - operation.amount_minor
            rows = [
              { account_key: "client_funds:#{settlement.id}", direction: "debit", amount_minor: settlement.amount_minor, currency: operation.currency },
              { account_key: "provider_cash", direction: "credit", amount_minor: operation.amount_minor, currency: operation.currency }
            ]
            rows << { account_key: "platform_revenue", direction: "credit", amount_minor: fee, currency: operation.currency } if fee.positive?
            rows
          end
          Ledger.post!(operation_key: operation.id, description: "Sandbox #{operation.kind}", entries: entries)
          settlement.update!(funded: true) if operation.kind == "fund"
        end
        operation.update!(state: observation.fetch("state"), external_id: observation.fetch("id"), lease_until: nil, next_retry_at: nil, last_error: nil)
        Platform::Events.emit(type: "payment.#{operation.state}", aggregate: operation, payload: { audience: [ basis[:client_id], basis[:creator_id] ], title: basis[:title], engagement_id: settlement.engagement_id, kind: operation.kind })
        Platform::Events.audit(action: "payment.#{operation.state}", resource: operation)
      end
      operation.reload
    end
  end
end
