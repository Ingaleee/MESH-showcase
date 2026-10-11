require "rails_helper"

RSpec.describe "Durable latency metrics" do
  it "records exactly one notification observation in the effect transaction" do
    build_workflow
    delivery = Platform::Delivery.first
    2.times { EventDeliveryJob.perform_now(delivery.id) }
    metrics = Platform::Metrics.snapshot.find { |row| row["name"] == "notification_delivery" }
    expect(metrics["observations"]).to eq(1)
    expect(Platform::Metrics.prometheus).to include("mesh_notification_delivery_seconds_count 1")
  end

  it "rolls a metric observation back together with a failed transaction" do
    Platform::Record.transaction do
      Platform::Metrics.observe("notification_delivery", 0.5)
      raise ActiveRecord::Rollback
    end
    expect(Platform::Metrics.snapshot).to be_empty
  end

  it "exports controller action labels instead of account and project IDs" do
    payload = { controller: "Api::V1::PublishingController", action: "index", method: "GET", status: 200 }
    HttpMetrics.observe(payload, 0.02)
    output = HttpMetrics.prometheus
    expect(output).to include('route="Api::V1::PublishingController#index"')
    expect(output).not_to include("account_id", "project_id", "email", "correlation_id")
  end
end
