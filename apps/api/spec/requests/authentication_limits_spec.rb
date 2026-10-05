require "rails_helper"

RSpec.describe "Shared authentication budget", type: :request do
  it "limits sign-in and registration together, provides Retry-After, and leaves session reads available" do
    15.times do
      post "/api/v1/session", params: { session: { email: "missing@mesh.test", password: "wrong" } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
    post "/api/v1/accounts", params: {}, as: :json
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body.fetch("code")).to eq("RATE_LIMITED")
    expect(response.headers.fetch("Retry-After").to_i).to be_between(1, 180)
    Rails.cache.clear
    post "/api/v1/session", params: { session: { email: "missing@mesh.test", password: "wrong" } }, as: :json
    expect(response).to have_http_status(:too_many_requests)
    get "/api/v1/session"
    expect(response).to have_http_status(:ok)
  end
end
