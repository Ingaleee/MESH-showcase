require "rails_helper"

RSpec.describe "Payment recovery and accounting" do
  it "recovers a successful provider operation after timeout without sending it twice" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    gateway = instance_double(Finance::SandboxGateway)
    allow(gateway).to receive(:execute).with(operation).and_raise(Finance::SandboxGateway::Unavailable, "response lost")
    Finance::ProcessOperation.call(operation_id: operation.id, gateway: gateway)
    expect(operation.reload.state).to eq("unknown")
    expect(Finance::LedgerTransaction.count).to eq(0)
    allow(gateway).to receive(:lookup).with(operation.id).and_return(confirmed(operation))
    Finance::ProcessOperation.call(operation_id: operation.id, gateway: gateway)
    expect(gateway).to have_received(:execute).once
    expect(operation.reload.state).to eq("confirmed")
    expect(operation.settlement.reload).to be_funded
    expect(Finance::LedgerTransaction.count).to eq(1)
  end

  it "posts one balanced journal when duplicate provider confirmations race" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    results = race(*Array.new(2) { -> { Finance::ApplyObservation.call(operation_id: operation.id, observation: confirmed(operation)) } })
    expect(results).to all(be_a(Finance::PaymentOperation))
    expect(Finance::LedgerTransaction.count).to eq(1)
    expect(Finance::LedgerEntry.count).to eq(2)
    expect(Platform::OutboxEvent.where(event_type: "payment.confirmed").count).to eq(1)
  end

  it "enforces acceptance, funding and holds before author payout" do
    client, creator, _, engagement = build_workflow
    expect { request_payment(client, engagement, kind: "payout") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("WORK_NOT_ACCEPTED") }
    accept_work(client, creator, engagement)
    expect { request_payment(client, engagement, kind: "payout") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("NOT_FUNDED") }
    fund = request_payment(client, engagement)
    Finance::ApplyObservation.call(operation_id: fund.id, observation: confirmed(fund))
    Finance::PlaceHold.call(actor: creator, engagement_id: engagement.id, reason: "Unresolved disagreement", key: "hold")
    expect { request_payment(client, engagement, kind: "payout") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("PAYOUT_HELD") }
  end

  it "serializes the hold against the external dispatch cutoff" do
    client, creator, _, engagement = build_workflow
    accept_work(client, creator, engagement)
    fund = request_payment(client, engagement)
    Finance::ApplyObservation.call(operation_id: fund.id, observation: confirmed(fund))
    payout = request_payment(client, engagement, kind: "payout")
    gateway = instance_double(Finance::SandboxGateway)
    allow(gateway).to receive(:execute).and_return(confirmed(payout))
    results = race(
      -> { Finance::ProcessOperation.call(operation_id: payout.id, gateway: gateway) },
      -> { Finance::PlaceHold.call(actor: creator, engagement_id: engagement.id, reason: "Race dispute", key: "race-hold") }
    )
    if payout.reload.state == "confirmed"
      expect(payout.settlement.reload.hold).to be(false)
      expect(results.grep(Platform::Error).map(&:code)).to eq([ "PAYOUT_ALREADY_STARTED" ])
    else
      expect(payout.state).to eq("requested")
      expect(payout.settlement.reload.hold).to be(true)
      expect(gateway).not_to have_received(:execute)
    end
  end

  it "splits gross, net and rounded commission and prevents editing posted journals" do
    client, creator, _, engagement = build_workflow
    accept_work(client, creator, engagement)
    fund = request_payment(client, engagement)
    Finance::ApplyObservation.call(operation_id: fund.id, observation: confirmed(fund))
    payout = request_payment(client, engagement, kind: "payout")
    expect(payout.amount_minor).to eq(90_004)
    Finance::ApplyObservation.call(operation_id: payout.id, observation: confirmed(payout))
    journal = Finance::LedgerTransaction.find_by!(operation_key: payout.id)
    expect(journal.entries.find_by!(account_key: "platform_revenue").amount_minor).to eq(10_001)
    expect(journal.entries.sum { |entry| entry.direction == "debit" ? entry.amount_minor : -entry.amount_minor }).to eq(0)
    expect { journal.entries.first.update_columns(amount_minor: 1) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { journal.destroy! }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "rejects unbalanced journals at commit even when application checks are bypassed" do
    expect do
      Platform::Record.transaction do
        journal = Finance::LedgerTransaction.create!(operation_key: "bad", description: "Bad journal")
        Finance::LedgerEntry.create!(ledger_transaction_id: journal.id, account_key: "cash", currency: "RUB", direction: "debit", amount_minor: 100)
        journal.update!(status: "posted")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /unbalanced/)
    expect(Finance::LedgerTransaction.count).to eq(0)
  end

  it "rejects an observation with a different amount and records reconciliation exceptions" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    expect { Finance::ApplyObservation.call(operation_id: operation.id, observation: confirmed(operation).merge("amount_minor" => 1)) }.to raise_error(Platform::Error, /does not match/)
    expect { Finance::ApplyObservation.call(operation_id: operation.id, observation: confirmed(operation).merge("amount_minor" => operation.amount_minor.to_f)) }.to raise_error(Platform::Error, /does not match/)
    Finance::ApplyObservation.call(operation_id: operation.id, observation: confirmed(operation))
    gateway = instance_double(Finance::SandboxGateway, lookup: nil)
    expect(Finance::Reconcile.call(gateway: gateway)).to include(exceptions: 1)
    Finance::Reconcile.call(gateway: gateway)
    expect(Finance::ReconciliationException.count).to eq(1)
  end

  it "never resubmits an unresolved operation outside the configured provider retention window" do
    client, _, _, engagement = build_workflow
    operation = request_payment(client, engagement)
    operation.update!(state: "unknown", created_at: 25.hours.ago)
    gateway = instance_double(Finance::SandboxGateway, lookup: nil)
    expect(gateway).not_to receive(:execute)
    Finance::ProcessOperation.call(operation_id: operation.id, gateway: gateway)
    expect(operation.reload.state).to eq("unknown")
  end
end
