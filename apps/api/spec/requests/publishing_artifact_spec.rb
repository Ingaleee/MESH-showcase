require "rails_helper"

RSpec.describe "Publishing artifact download", type: :request do
  it "keeps ZIP bytes private and rejects corrupt stored bytes" do
    operator, _, candidate, _ = publishing_candidate
    path = "/api/v1/publishing/candidates/#{candidate.id}/artifact"
    sign_in(create(:account, operator: true))
    get path
    expect(response).to have_http_status(:not_found)
    sign_in(operator)
    get path
    expect(response).to have_http_status(:ok)
    expect(Digest::SHA256.hexdigest(response.body)).to eq(candidate.artifact_sha256)
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    candidate.artifact_blob.service.upload(candidate.artifact_blob.key, StringIO.new("corrupt"))
    get path
    expect(response).to have_http_status(:conflict)
  end
end
