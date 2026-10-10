require "rails_helper"
require "openssl"

RSpec.describe "API trust boundaries", type: :request do
  it "requires authentication and denies unrelated participants and normal users in the operations console" do
    _, _, _, engagement = build_workflow
    get "/api/v1/engagements/#{engagement.id}"
    expect(response).to have_http_status(:unauthorized)
    sign_in(create(:account))
    get "/api/v1/engagements/#{engagement.id}"
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/operations"
    expect(response).to have_http_status(:forbidden)
  end

  it "does not expose another creator's private proposal" do
    client, creator, project, = build_workflow
    sign_in(create(:account))
    get "/api/v1/projects/#{project.id}"
    expect(response).to have_http_status(:forbidden)
    sign_in(creator)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("proposals").length).to eq(1)
    expect(response.parsed_body.fetch("project").fetch("client")).not_to include("email", "operator")
  end

  it "enforces CSRF for browser commands" do
    ActionController::Base.allow_forgery_protection = true
    post "/api/v1/accounts", params: { account: { email: "csrf@mesh.test", display_name: "Person", persona: "client", password: "TestPassword2026!" } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.fetch("code")).to eq("CSRF_INVALID")
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "rejects tampered and old webhooks and deduplicates signed receipts" do
    _, _, _, engagement = build_workflow
    operation = request_payment(Identity::Account.find(engagement.client_id), engagement)
    body = JSON.generate(event_id: "evt-1", operation_id: operation.id)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("MESH_WEBHOOK_SECRET"), "#{timestamp}.#{body}")
    headers = { "CONTENT_TYPE" => "application/json", "X-Mesh-Timestamp" => timestamp, "X-Mesh-Signature" => signature }
    2.times do
      post "/api/v1/webhooks/sandbox", params: body, headers: headers
      expect(response).to have_http_status(:ok)
    end
    expect(Finance::WebhookReceipt.count).to eq(1)
    post "/api/v1/webhooks/sandbox", params: body.sub("evt-1", "evt-2"), headers: headers
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/webhooks/sandbox", params: body, headers: headers.merge("X-Mesh-Timestamp" => 10.minutes.ago.to_i.to_s)
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects downloading a quarantined attachment" do
    account = create(:account)
    item = Talent::PortfolioItem.create!(account: account, title: "Private sample")
    item.file.attach(io: StringIO.new("safe-looking content"), filename: "sample.txt", content_type: "text/plain")
    sign_in(account)
    get "/api/v1/portfolio/#{item.id}/download"
    expect(response).to have_http_status(:conflict)
  end
end
