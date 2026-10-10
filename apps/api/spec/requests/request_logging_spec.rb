require "rails_helper"

RSpec.describe "Structured request logs", type: :request do
  it "records the final error status, including rejected before actions, without query values" do
    events = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, *arguments, &block|
      message = arguments.first
      events << JSON.parse(message) if message.is_a?(String) && message.start_with?('{"event":"request.finished"')
      original.call(*arguments, &block)
    end

    get "/api/v1/operations"
    expect(response.status).to eq(401)
    get "/api/v1/projects/#{SecureRandom.uuid}"
    expect(response.status).to eq(404)
    allow(Marketplace::SearchProjects).to receive(:call).and_raise(StandardError, "Simulated failure")
    get "/api/v1/projects", params: { q: "private-query-value" }
    expect(response.status).to eq(500)

    expect(events.map { |event| event.fetch("status") }).to eq([ 401, 404, 500 ])
    expect(events).to all(include("request_id" => a_kind_of(String)))
    expect(events.to_json).not_to include("private-query-value")
  end
end
