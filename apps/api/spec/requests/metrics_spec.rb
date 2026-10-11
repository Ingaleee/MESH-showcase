require "rails_helper"

RSpec.describe "Metrics boundary", type: :request do
  it "denies public scrapes and exposes aggregate counters only to the collector" do
    get "/internal/metrics"
    expect(response).to have_http_status(:unauthorized)
    get "/internal/metrics", headers: { "Authorization" => "Bearer #{ENV.fetch("MESH_METRICS_TOKEN", "local-mesh-metrics-only")}" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("mesh_outbox_pending 0", "mesh_payment_unknown 0")
    expect(response.body).not_to include("email", "password", "amount_minor")
  end

  it "separates poison events from delivery backlog and reports quarantined file errors" do
    build_workflow
    Platform::Delivery.update_all(state: "processed")
    Platform::Delivery.first.update!(state: "failed", created_at: 1.hour.ago)
    account = create(:account)
    Talent::PortfolioItem.create!(account: account, title: "Private", scan_error: "scanner_offline", created_at: 10.minutes.ago)
    get "/internal/metrics", headers: { "Authorization" => "Bearer #{ENV.fetch("MESH_METRICS_TOKEN", "local-mesh-metrics-only")}" }
    expect(response.body).to include("mesh_outbox_pending 0\n", "mesh_outbox_oldest_seconds 0\n", "mesh_outbox_failed 1\n")
    expect(response.body).to include("mesh_files_quarantined 1\n", "mesh_files_scan_errors 1\n")
    expect(response.body.match(/mesh_files_oldest_seconds (\d+)/)[1].to_i).to be >= 600
  end
end
