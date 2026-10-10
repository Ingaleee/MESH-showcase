require "rails_helper"

RSpec.describe "Reconciliation coverage" do
  it "recovers requested operations from a snapshot taken before provider execution" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    gateway = instance_double(Finance::SandboxGateway, lookup: confirmed(operation))
    expect(Finance::Reconcile.call(gateway: gateway)).to include(recovered: 1)
    expect(operation.reload.state).to eq("confirmed")
    expect(operation.reconciled_at).to be_present
  end

  it "detects mismatched provider identity and clears the exception only after a clean observation" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    observation = confirmed(operation)
    Finance::ApplyObservation.call(operation_id: operation.id, observation: observation)
    gateway = instance_double(Finance::SandboxGateway, lookup: observation.merge("id" => "another-operation"))
    expect(Finance::Reconcile.call(gateway: gateway)).to include(exceptions: 1)
    expect(Finance::ReconciliationException.where(resolved_at: nil).count).to eq(1)
    allow(gateway).to receive(:lookup).and_return(observation)
    Finance::Reconcile.call(gateway: gateway)
    expect(Finance::ReconciliationException.where(resolved_at: nil).count).to eq(0)
    allow(gateway).to receive(:lookup).and_return(observation.merge("id" => "another-operation"))
    Finance::Reconcile.call(gateway: gateway)
    expect(Finance::ReconciliationException.count).to eq(1)
    expect(Finance::ReconciliationException.where(resolved_at: nil).count).to eq(1)
  end

  it "records one active incident when concurrent observations find the same mismatch" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    results = race(
      -> { Finance::Reconcile.exception!(operation, "RECONCILIATION_UNAVAILABLE", "Timeout::Error") },
      -> { Finance::Reconcile.exception!(operation, "RECONCILIATION_UNAVAILABLE", "Timeout::Error") }
    )
    expect(results).to all(be_a(Finance::ReconciliationException))
    expect(Finance::ReconciliationException.count).to eq(1)
    expect(Finance::ReconciliationException.sole.resolved_at).to be_nil
  end
end
