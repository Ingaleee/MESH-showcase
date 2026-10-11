require "rails_helper"

RSpec.describe QueueMetrics do
  it "separates queue states, emits bounded labels and omits unknown counters during an outage" do
    allow(described_class).to receive(:snapshot).and_return(
      available: true, workers: 3,
      rows: [ { "queue_name" => "events", "state" => "ready", "count" => 12, "oldest_seconds" => 90.125 }, { "queue_name" => "untrusted-label", "state" => "failed", "count" => 5 } ]
    )
    text = described_class.prometheus
    expect(text).to include('mesh_queue_ready{queue="events"} 12', 'mesh_queue_oldest_ready_seconds{queue="events"} 90.125', "mesh_queue_workers 3")
    expect(text).not_to include("untrusted-label")
    allow(described_class).to receive(:snapshot).and_return(available: false)
    expect(described_class.prometheus).to eq("# TYPE mesh_queue_up gauge\nmesh_queue_up 0\n")
  end

  it "reports a failed queue connection without making primary metrics unavailable" do
    allow(SolidQueue::Record.connection_pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect(described_class.snapshot).to eq(available: false)
  end
end
