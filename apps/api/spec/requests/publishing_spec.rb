require "rails_helper"
require "tempfile"

RSpec.describe "Publishing API boundary", type: :request do
  it "requires appointed operators and scopes private reports to their integrations" do
    operator, _, candidate, _ = publishing_candidate
    sign_in(create(:account))
    get "/api/v1/publishing"
    expect(response).to have_http_status(:forbidden)
    sign_in(create(:account, operator: true))
    post "/api/v1/publishing/candidates/#{candidate.id}/validate", params: {}, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:not_found)
    sign_in(operator)
    get "/api/v1/publishing"
    expect(response.parsed_body.fetch("candidates").map { |row| row["id"] }).to include(candidate.id)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.body).not_to include(Publishing::Settings.token(candidate.partner))
  end

  it "accepts bounded multipart uploads and preserves artifact digest on repeated command" do
    operator, partner, _, _ = publishing_candidate
    sign_in(operator)
    bytes, manifest = package_fixture(contents: "<html>HTTP artifact</html>")
    Tempfile.create([ "mesh-package", ".zip" ]) do |file|
      file.binmode; file.write(bytes); file.flush
      key = SecureRandom.uuid
      2.times do
        post "/api/v1/publishing/partners/#{partner.id}/candidates",
          params: { artifact: Rack::Test::UploadedFile.new(file.path, "application/zip"), manifest: JSON.generate(manifest) },
          headers: { "Idempotency-Key" => key }
        expect(response).to have_http_status(:created)
      end
      candidate = Publishing::Candidate.find(response.parsed_body.fetch("id"))
      expect(candidate.artifact_sha256).to eq(Digest::SHA256.hexdigest(bytes))
      expect(Publishing::Candidate.count).to eq(2)
    end
  end

  it "authenticates callbacks independently of a browser session and rejects replay conflicts" do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    observation = published_observation(deployment)
    bytes = JSON.generate(observation)
    event_id, timestamp = SecureRandom.uuid, Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", Publishing::Settings.token(partner), "#{timestamp}.#{event_id}.#{bytes}")
    headers = { "Content-Type" => "application/json", "X-Event-ID" => event_id, "X-Callback-Timestamp" => timestamp, "X-Callback-Signature" => signature }
    post "/api/v1/publishing/callbacks/#{partner.id}", params: bytes, headers: headers.merge("X-Callback-Signature" => "0" * 64)
    expect(response).to have_http_status(:unauthorized)
    2.times do
      post "/api/v1/publishing/callbacks/#{partner.id}", params: bytes, headers: headers
      expect(response).to have_http_status(:ok)
    end
    expect(response.parsed_body["duplicate"]).to eq(true)
    expect(Publishing::CallbackReceipt.count).to eq(1)
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  it "rejects oversized declared bodies before reading them" do
    input = double("unread input")
    expect(input).not_to receive(:read)
    status, _, _ = PublishingRequestBudget.new(->(_) { raise "must not reach parsing" }).call(
      "PATH_INFO" => "/api/v1/publishing/partners", "REQUEST_METHOD" => "POST",
      "CONTENT_LENGTH" => "9000000", "rack.input" => input
    )
    expect(status).to eq(413)
  end
end
