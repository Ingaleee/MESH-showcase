module Api
  module V1
    class OperationsController < ApplicationController
      before_action :require_operator!

      def index
        pending = Platform::Delivery.where.not(state: "processed")
        render json: {
          sandbox: true,
          metrics: {
            pending_deliveries: pending.count,
            oldest_delivery_seconds: pending.minimum(:created_at).then { |time| time ? (Time.current - time).round : 0 },
            processed_deliveries: Platform::Delivery.where(state: "processed").count,
            unknown_payments: Finance::PaymentOperation.where(state: "unknown").count,
            reconciliation_exceptions: Finance::ReconciliationException.where(resolved_at: nil).count,
            ledger_transactions: Finance::LedgerTransaction.where(status: "posted").count
          },
          payments: Finance::PaymentOperation.order(updated_at: :desc).limit(20).map { |row| Presenters.operation(row) },
          events: Platform::OutboxEvent.order(created_at: :desc).limit(20).map { |row| row.attributes.slice("id", "event_type", "correlation_id", "aggregate_id", "created_at") },
          audit: Platform::AuditEntry.order(created_at: :desc).limit(20).map { |row| row.attributes.slice("id", "action", "resource_id", "correlation_id", "created_at") },
          deliveries: pending.order(created_at: :asc).limit(20).map { |row| row.attributes.slice("id", "state", "attempts", "last_error") }
        }
      end

      def reconcile
        render json: Finance::Reconcile.call
      end

      def release_hold
        settlement = Finance::Settlement.find(params[:id])
        reason = params.require(:reason).to_s
        raise Platform::Error.new("REASON_REQUIRED", "Provide a resolution reason.") unless reason.length.between?(5, 2000)

        settlement.with_lock do
          settlement.update!(hold: false, hold_reason: nil)
          Platform::Events.audit(action: "settlement.hold_released", resource: settlement, details: { reason: reason })
        end
        render json: { id: settlement.id }
      end

      def retry_delivery
        delivery = Platform::Delivery.find(params[:id])
        delivery.with_lock do
          raise Platform::Error.new("ALREADY_PROCESSED", "Delivery is already processed.", status: 409) if delivery.state == "processed"

          delivery.update!(state: "pending", claim_token: nil, enqueued_at: nil, failure_count: 0, available_at: nil, last_error: nil)
          Platform::Events.audit(action: "delivery.retried", resource: delivery)
        end
        render json: { id: delivery.id }
      end
    end
  end
end
