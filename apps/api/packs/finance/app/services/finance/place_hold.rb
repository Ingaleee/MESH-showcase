module Finance
  class PlaceHold
    def self.call(actor:, engagement_id:, reason:, key:)
      basis = Engagements::ReadModel.basis(engagement_id, actor_id: actor.id)
      raise Platform::Error.new("REASON_REQUIRED", "Explain the dispute.") unless reason.to_s.length.between?(5, 2000)
      Platform::Idempotency.call(actor_id: actor.id, operation: "hold:#{engagement_id}", key: key, input: { reason: reason }) do
        settlement = Settlement.create_or_find_by!(engagement_id: engagement_id) do |row|
          row.amount_minor, row.currency = basis[:amount_minor], basis[:currency]
        end
        settlement.lock!
        payout = settlement.payment_operations.find_by(kind: "payout")
        if payout && %w[dispatching unknown confirmed].include?(payout.state)
          raise Platform::Error.new("PAYOUT_ALREADY_STARTED", "The external payout has already started; operator review is required.", status: 409)
        end
        settlement.update!(hold: true, hold_reason: reason)
        Platform::Events.audit(action: "settlement.held", resource: settlement)
        Platform::Events.emit(type: "settlement.held", aggregate: settlement, payload: { audience: [ basis[:client_id], basis[:creator_id] ], title: basis[:title], engagement_id: engagement_id })
        { id: settlement.id }
      end
    end
  end
end
