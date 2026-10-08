require "rails_helper"

RSpec.describe "Publishing history", type: :request do
  it "paginates deterministic ties, scopes cursors and keeps old active releases visible" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    active = deployment_for(operator, candidate, validation)
    Publishing::ApplyObservation.call(deployment: active, observation: published_observation(active))
    moment = Time.current.change(usec: 0)
    35.times do
      Publishing::Deployment.create!(partner: partner, candidate: candidate, validation: validation,
        kind: "rollback", rollback_of: active, state: "pending", correlation_id: SecureRandom.uuid, created_at: moment)
    end
    sign_in(operator)
    get "/api/v1/publishing", params: { limit: 10 }
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    ids = first.fetch("deployments").map { |row| row.fetch("id") }
    expect(ids.length).to eq(10)
    expect(first.fetch("active_deployments").map { |row| row.fetch("id") }).to eq([ active.id ])
    inserted = Publishing::Deployment.create!(partner: partner, candidate: candidate, validation: validation,
      kind: "rollback", rollback_of: active, state: "pending", correlation_id: SecureRandom.uuid, created_at: moment + 1.second)
    cursor = first.fetch("next_cursors").fetch("deployments")
    while cursor
      get "/api/v1/publishing", params: { limit: 10, deployments_cursor: cursor }
      expect(response).to have_http_status(:ok)
      page = response.parsed_body
      ids.concat(page.fetch("deployments").map { |row| row.fetch("id") })
      cursor = page.fetch("next_cursors").fetch("deployments")
    end
    expect(ids.uniq.length).to eq(36)
    expect(ids.length).to eq(36)
    expect(ids).not_to include(inserted.id)
    get "/api/v1/publishing", params: { limit: 10 }
    expect(response.parsed_body.fetch("deployments").first.fetch("id")).to eq(inserted.id)
    sign_in(create(:account, operator: true))
    get "/api/v1/publishing", params: { deployments_cursor: first.fetch("next_cursors").fetch("deployments") }
    expect(response).to have_http_status(:bad_request)
  end

  it "loads candidates for owned partners beyond the partner page and rejects cursor kind substitution" do
    operator, partner, candidate, _ = publishing_candidate
    31.times do |index|
      Publishing::Partner.create!(owner_id: operator.id, name: "Studio #{index}", origin: partner.origin,
        credential_ref: partner.credential_ref, contract_version: "1")
    end
    sign_in(operator)
    get "/api/v1/publishing", params: { limit: 1 }
    page = response.parsed_body
    expect(page.fetch("candidates").map { |row| row.fetch("id") }).to include(candidate.id)
    expect(page.fetch("next_cursors").fetch("partners")).to be_present
    get "/api/v1/publishing", params: { candidates_cursor: page.fetch("next_cursors").fetch("partners") }
    expect(response).to have_http_status(:bad_request)
  end
end
