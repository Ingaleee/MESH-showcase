require "rails_helper"

RSpec.describe "Runtime health", type: :request do
  it "reports readiness without a session and restores the connection timeout setting" do
    previous = Platform::Record.connection.select_value("SHOW statement_timeout")
    get "/ready"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ready")
    expect(response.headers.fetch("Cache-Control")).to eq("no-store")
    expect(Platform::Record.connection.select_value("SHOW statement_timeout")).to eq(previous)
  end

  it "keeps liveness separate from a failed database readiness check without exposing errors" do
    allow(Platform::Record.connection_pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionNotEstablished, "private database endpoint")
    get "/ready"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("status" => "unavailable")
    expect(response.body).not_to include("private database", "ActiveRecord")
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
