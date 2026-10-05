require "rails_helper"
require "opentelemetry/sdk/trace/export/in_memory_span_exporter"

RSpec.describe "Outbox trace propagation" do
  it "continues the original trace when the event is consumed later" do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    OpenTelemetry.tracer_provider.add_span_processor(processor)
    tracer = OpenTelemetry.tracer_provider.tracer("mesh.spec")
    client = create(:account)
    request_trace = nil
    tracer.in_span("request.original") do |span|
      request_trace = span.context.trace_id
      Marketplace::CreateProject.call(actor: client, input: project_input, key: "trace")
    end
    event = Platform::OutboxEvent.first
    expect(event.trace_context.fetch("traceparent")).to include(request_trace.unpack1("H*"))
    EventDeliveryJob.perform_now(event.deliveries.first.id)
    consumed = exporter.finished_spans.find { |span| span.name == "mesh.event.consume" }
    expect(consumed.trace_id).to eq(request_trace)
  end
end
