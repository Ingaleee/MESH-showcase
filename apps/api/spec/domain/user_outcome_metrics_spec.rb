require "rails_helper"

RSpec.describe UserOutcomeMetrics do
  include ActiveSupport::Testing::TimeHelpers
  it "includes failed and unfinished mature validations in the denominator, not just successful histograms" do
    now = Time.current.change(usec: 0)
    _, _, candidate, = travel_to(now - 90) { publishing_candidate }
    completed = Publishing::Validation.create!(candidate: candidate, state: "rejected", policy_version: "probe", input_fingerprint: "b" * 64,
      created_at: now - 90, completed_at: now - 50, report: { checks: [] })
    Publishing::Validation.create!(candidate: candidate, state: "failed", policy_version: "probe", input_fingerprint: "c" * 64, created_at: now - 90)
    late = Publishing::Validation.create!(candidate: candidate, state: "passed", policy_version: "probe", input_fingerprint: "d" * 64,
      created_at: now - 90, completed_at: now - 10, report: { checks: [] })
    row = described_class.snapshot(now: now).fetch("validation")
    expect(row).to include("total" => 4.0, "good" => 1.0, "unfinished" => 1.0, "failed" => 1.0, "overdue" => 2.0)
    expect(row.fetch("oldest_seconds")).to be_within(0.01).of(90)
    expect(completed.state).to eq("rejected")
    expect(late.state).to eq("passed")
  end

  it "excludes immature operations and expired cohorts without hiding unfinished age" do
    now = Time.current.change(usec: 0)
    _, _, candidate, = travel_to(now - 10) { publishing_candidate }
    Publishing::Validation.create!(candidate: candidate, policy_version: "probe", input_fingerprint: "e" * 64, created_at: now - 90_000)
    row = described_class.snapshot(now: now).fetch("validation")
    expect(row).to include("total" => 0.0, "good" => 0.0, "unfinished" => 2.0, "overdue" => 1.0)
    expect(described_class.prometheus).to include('operation="validation"').and include("mesh_user_sli_up 1")
  end
end
