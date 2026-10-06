require "rails_helper"

RSpec.describe "Durable event delivery" do
  it "commits the notification exactly once across duplicate job invocations" do
    client, = build_workflow
    delivery = Platform::Delivery.joins(:outbox_event).find_by!(platform_outbox_events: { event_type: "project.published" })
    2.times { EventDeliveryJob.perform_now(delivery.id) }
    expect(Notifications::Notification.where(account_id: client.id, outbox_event_id: delivery.outbox_event_id).count).to eq(1)
    expect(delivery.reload.state).to eq("processed")
  end

  it "keeps the committed notification if realtime broadcasting fails" do
    build_workflow
    delivery = Platform::Delivery.first
    allow(ActionCable.server).to receive(:broadcast).and_raise("socket unavailable")
    EventDeliveryJob.perform_now(delivery.id)
    expect(delivery.reload.state).to eq("processed")
    expect(Notifications::Notification.count).to be_positive
  end

  it "recovers a lost enqueue and reclaims stale dispatch claims" do
    build_workflow
    delivery = Platform::Delivery.first
    delivery.update!(state: "enqueued", enqueued_at: 2.minutes.ago)
    OutboxDispatcher.call
    expect(delivery.reload.enqueued_at).to be > 1.minute.ago
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:args].first }).to include(delivery.id)
    allow(EventDeliveryJob).to receive(:perform_later).and_raise("queue database unavailable")
    delivery.update!(state: "pending", enqueued_at: nil)
    OutboxDispatcher.call
    expect(delivery.reload.state).to eq("pending")
  end

  it "fails closed when the file scanner is unavailable" do
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
    expect { Talent::FileScanner.scan("content") }.to raise_error(Talent::FileScanner::Unavailable)
  end

  it "parks a poison event after five durable failures instead of retrying forever" do
    build_workflow
    delivery = Platform::Delivery.first
    delivery.outbox_event.update!(schema_version: 999)
    5.times do
      delivery.reload.update!(available_at: nil)
      expect { EventDeliveryJob.perform_now(delivery.id) }.to raise_error(Platform::Error, /Unsupported event version/)
    end
    expect(delivery.reload.state).to eq("failed")
    expect(delivery.failure_count).to eq(5)
    EventDeliveryJob.perform_now(delivery.id)
    expect(delivery.reload.failure_count).to eq(5)
  end

  it "ignores a job from an expired claim and consumes only the current attempt" do
    build_workflow
    delivery = Platform::Delivery.joins(:outbox_event).find_by!(platform_outbox_events: { event_type: "project.published" })
    old_token = OutboxDispatcher.claim(delivery)
    delivery.update!(enqueued_at: 2.minutes.ago)
    current_token = OutboxDispatcher.claim(delivery)
    EventDeliveryJob.perform_now(delivery.id, old_token)
    expect(delivery.reload.state).to eq("enqueued")
    expect(Notifications::Notification.count).to eq(0)
    EventDeliveryJob.perform_now(delivery.id, current_token)
    expect(delivery.reload.state).to eq("processed")
    expect(Notifications::Notification.count).to eq(1)
  end

  it "does not let an old enqueue failure erase a newer claim" do
    build_workflow
    delivery = Platform::Delivery.first
    Platform::Delivery.where.not(id: delivery.id).update_all(state: "processed")
    current_token = nil
    allow(EventDeliveryJob).to receive(:perform_later) do
      delivery.reload.update!(enqueued_at: 2.minutes.ago)
      current_token = OutboxDispatcher.claim(delivery)
      raise "lost response from old enqueue"
    end
    OutboxDispatcher.call
    expect(delivery.reload.state).to eq("enqueued")
    expect(delivery.claim_token).to eq(current_token)
    EventDeliveryJob.perform_now(delivery.id, current_token)
    expect(delivery.reload.state).to eq("processed")
  end

  it "counts one poison failure per claim and honors persisted backoff for duplicate jobs" do
    build_workflow
    delivery = Platform::Delivery.first
    delivery.outbox_event.update!(schema_version: 999)
    token = OutboxDispatcher.claim(delivery)
    expect { EventDeliveryJob.perform_now(delivery.id, token) }.to raise_error(Platform::Error)
    2.times { EventDeliveryJob.perform_now(delivery.id, token) }
    expect(delivery.reload.failure_count).to eq(1)
    expect(delivery.state).to eq("pending")
    expect(OutboxDispatcher.claim(delivery)).to be_nil
    expect(delivery.available_at).to be > Time.current
  end

  it "recovers an enqueue rejected without an exception" do
    build_workflow
    delivery = Platform::Delivery.first
    allow(EventDeliveryJob).to receive(:perform_later).and_return(false)
    OutboxDispatcher.call
    expect(delivery.reload.state).to eq("pending")
    expect(delivery.claim_token).to be_nil
    expect(delivery.available_at).to be > Time.current
  end
end
