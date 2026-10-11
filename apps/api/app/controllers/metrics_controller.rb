class MetricsController < ActionController::Base
  def show
    expected = ENV.fetch("MESH_METRICS_TOKEN", "local-mesh-metrics-only")
    supplied = request.headers["Authorization"].to_s
    unless ActiveSupport::SecurityUtils.secure_compare(supplied, "Bearer #{expected}")
      return head :unauthorized
    end

    pending = Platform::Delivery.where(state: %w[pending enqueued])
    oldest = pending.minimum(:created_at)
    files = [ Engagements::WorkFile, Marketplace::ProposalExample, Talent::PortfolioItem ].map { |model| model.where(state: "quarantined") }
    oldest_file = files.filter_map { |scope| scope.minimum(:created_at) }.min
    values = {
      mesh_publishing_unknown: Publishing::Deployment.where(state: "unknown").count,
      mesh_publishing_validation_pending: Publishing::Validation.where(state: %w[pending running]).count,
      mesh_outbox_pending: pending.count,
      mesh_outbox_oldest_seconds: oldest ? (Time.current - oldest).round : 0,
      mesh_outbox_failed: Platform::Delivery.where(state: "failed").count,
      mesh_files_quarantined: files.sum(&:count),
      mesh_files_oldest_seconds: oldest_file ? (Time.current - oldest_file).round : 0,
      mesh_files_scan_errors: files.sum { |scope| scope.where.not(scan_error: nil).count },
      mesh_payment_unknown: Finance::PaymentOperation.where(state: "unknown").count,
      mesh_reconciliation_exceptions: Finance::ReconciliationException.where(resolved_at: nil).count,
      mesh_ledger_posted: Finance::LedgerTransaction.where(status: "posted").count
    }
    text = values.map { |name, value| "# TYPE #{name} gauge\n#{name} #{value}\n" }.join + QueueMetrics.prometheus + HttpMetrics.prometheus + Platform::Metrics.prometheus
    render plain: text, content_type: "text/plain; version=0.0.4"
  end
end
