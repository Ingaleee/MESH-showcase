module Api
  module V1
    class FinanceController < ApplicationController
      def show
        engagement = find_engagement
        settlement = Finance::Settlement.find_by(engagement_id: engagement.id)
        operations = settlement ? settlement.payment_operations.order(created_at: :asc).to_a : []
        journals = Finance::LedgerTransaction.where(operation_key: operations.map(&:id)).includes(:entries)
        render json: {
          sandbox: true,
          settlement: settlement&.attributes&.slice("id", "funded", "hold", "hold_reason", "amount_minor", "currency"),
          operations: operations.map { |operation| Presenters.operation(operation) },
          ledger: journals.map do |journal|
            {
              id: journal.id, status: journal.status, description: journal.description,
              entries: journal.entries.map { |entry| entry.attributes.slice("account_key", "currency", "direction", "amount_minor") }
            }
          end
        }
      end

      def create
        engagement = find_engagement
        render json: Finance::RequestOperation.call(
          actor: current_account, engagement_id: engagement.id, kind: params.require(:kind),
          scenario: params.fetch(:scenario, "normal"), key: idempotency_key
        ), status: :created
      end

      def hold
        engagement = find_engagement
        render json: Finance::PlaceHold.call(
          actor: current_account, engagement_id: engagement.id, reason: params.require(:reason), key: idempotency_key
        )
      end

      private

      def find_engagement
        engagement = Engagements::Engagement.find(params[:engagement_id])
        authorize engagement, :show?
        engagement
      end
    end
  end
end
