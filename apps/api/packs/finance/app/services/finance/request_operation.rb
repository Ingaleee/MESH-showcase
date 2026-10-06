module Finance
  class RequestOperation
    def self.call(actor:, engagement_id:, kind:, scenario:, key:)
      if Rails.env.production? && ENV.fetch("MESH_PAYMENTS_MODE", "disabled") != "sandbox"
        raise Platform::Error.new("PAYMENTS_DISABLED", "Payments have not been enabled in this environment.", status: 503)
      end
      basis = Engagements::ReadModel.basis(engagement_id, actor_id: actor.id)
      raise Platform::Error.new("FORBIDDEN", "Only the client can manage payments.", status: 403) unless basis[:client_id] == actor.id
      raise Platform::Error.new("INVALID_PAYMENT_KIND", "Invalid operation.") unless %w[fund payout].include?(kind)
      raise Platform::Error.new("INVALID_SCENARIO", "Invalid sandbox scenario.") unless %w[normal timeout_after_success decline].include?(scenario)
      Platform::Idempotency.call(actor_id: actor.id, operation: "#{kind}:#{engagement_id}", key: key, input: { scenario: scenario }) do
        settlement = Settlement.create_or_find_by!(engagement_id: engagement_id) do |row|
          row.amount_minor, row.currency = basis[:amount_minor], basis[:currency]
        end
        settlement.lock!
        if kind == "payout"
          basis = Engagements::ReadModel.basis(engagement_id, actor_id: actor.id)
          raise Platform::Error.new("WORK_NOT_ACCEPTED", "Accept the work before payout.", status: 409) unless basis[:state] == "accepted"
          raise Platform::Error.new("NOT_FUNDED", "Fund the agreement first.", status: 409) unless settlement.funded?
          raise Platform::Error.new("PAYOUT_HELD", "Resolve the dispute before payout.", status: 409) if settlement.hold?
        end
        existing = settlement.payment_operations.find_by(kind: kind)
        next({ id: existing.id }) if existing
        gross = Platform::Money.new(minor: settlement.amount_minor, currency: settlement.currency)
        fee = gross.commission(basis_points: basis[:commission_basis_points])
        amount = kind == "payout" ? gross - fee : gross
        operation = PaymentOperation.create!(settlement: settlement, kind: kind, amount_minor: amount.minor, currency: amount.currency, scenario: scenario)
        Platform::Events.audit(action: "payment.#{kind}.requested", resource: operation, details: { engagement_id: engagement_id })
        { id: operation.id }
      end
    end
  end
end
