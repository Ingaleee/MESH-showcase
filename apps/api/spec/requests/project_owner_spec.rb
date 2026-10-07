require "rails_helper"
require "tempfile"

RSpec.describe "Project owner controls", type: :request do
  let(:client) { create(:account) }
  let(:creator) { create(:account, persona: "creator") }
  let(:project) { Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id)) }

  before { Talent::Profile.create!(account: creator, headline: "Brand designer", skills: [ "Branding" ]) }

  def propose(actor = creator, version = project.brief_version)
    Marketplace::SubmitProposal.call(
      actor: actor, project: project.reload, key: SecureRandom.uuid,
      input: { price_minor: 95_005, delivery_days: 18, message: "A private considered approach.", brief_version: version }
    ).fetch(:id)
  end

  def intake(accepting, version = project.lock_version, key = SecureRandom.uuid)
    post "/api/v1/projects/#{project.id}/intake", params: { accepting_proposals: accepting, version: version }, headers: { "Idempotency-Key" => key }, as: :json
  end

  it "pauses and resumes idempotently without changing the versioned brief" do
    sign_in(client)
    original = project.brief_snapshot
    key = SecureRandom.uuid
    version = project.lock_version
    2.times { intake(false, version, key); expect(response).to have_http_status(:ok) }
    expect(project.reload.accepting_proposals).to be(false)
    expect(project.lock_version).to eq(version + 1)
    expect(project.brief_snapshot).to eq(original)
    expect(Marketplace::BriefVersion.where(project_id: project.id).count).to eq(1)
    expect(Platform::AuditEntry.where(action: "project.intake_paused").count).to eq(1)
    intake(true, version)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("STALE_VERSION")
    intake("false", project.lock_version)
    expect(response).to have_http_status(:bad_request)
    intake(true, project.lock_version)
    expect(response).to have_http_status(:ok)
    expect(project.reload.accepting_proposals).to be(true)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("owner_context").fetch("events").map { |event| event.fetch("kind") }).to include("intake_paused", "intake_resumed", "published")
  end

  it "blocks new proposals and uploads while paused, but preserves and can select received offers" do
    proposal_id = propose
    sign_in(client)
    intake(false)
    expect(response).to have_http_status(:ok)
    sign_in(creator)
    post "/api/v1/projects/#{project.id}/propose", params: { proposal: { price_minor: 95_005, delivery_days: 18, message: "Another approach", brief_version: 1 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("PROPOSALS_PAUSED")
    Tempfile.create([ "concept", ".pdf" ]) do |file|
      file.write("%PDF-1.4\nPrivate concept\n%%EOF")
      file.flush
      post "/api/v1/projects/#{project.id}/proposal_examples", params: { file: Rack::Test::UploadedFile.new(file.path, "application/pdf") }, headers: { "Idempotency-Key" => SecureRandom.uuid }
    end
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("PROPOSALS_PAUSED")
    expect(Marketplace::ProposalExample.count).to eq(0)
    sign_in(client)
    post "/api/v1/projects/#{project.id}/award", params: { proposal_id: proposal_id, brief_version: 1 }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    engagement_id = response.parsed_body.fetch("id")
    intake(true, project.reload.lock_version)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("PROJECT_CLOSED")
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("proposals").map { |row| row.fetch("id") }).to eq([ proposal_id ])
    expect(response.parsed_body.fetch("owner_context").fetch("award")).to include("proposal_id" => proposal_id, "engagement_id" => engagement_id, "engagement_state" => "agreed")
    expect(project.reload.accepting_proposals).to be(false)
  end

  it "keeps owner events and other authors' offers private and loads the profile outside the catalog limit" do
    41.times do
      account = create(:account, persona: "creator")
      Talent::Profile.create!(account: account, headline: "Another author")
    end
    proposal_id = propose
    sign_in(client)
    get "/api/v1/projects/#{project.id}"
    offer = response.parsed_body.fetch("proposals").first
    expect(offer).to include("id" => proposal_id, "created_at" => Marketplace::Proposal.find(proposal_id).created_at.iso8601)
    expect(offer.fetch("profile")).to include("headline" => "Brand designer", "skills" => [ "Branding" ])
    expect(response.parsed_body.fetch("owner_context").fetch("events").map { |row| row.fetch("kind") }).to include("proposal_received")
    sign_in(creator)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("owner_context")).to be_nil
    expect(response.parsed_body.fetch("proposals").size).to eq(1)
    sign_in(create(:account))
    intake(false)
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("owner_context")).to be_nil
    expect(response.parsed_body.fetch("proposals")).to be_empty
    delete "/api/v1/session"
    intake(false)
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("owner_context")).to be_nil
    expect(response.body).not_to include("A private considered approach.", "Brand designer", "proposal_received")
  end

  it "retains old offers and rejects awarding a stale brief without creating an agreement" do
    original_id = propose
    Marketplace::ReviseBrief.call(actor: client, project: project.reload, input: project_input.merge(description: "New acceptance requirements."), version: project.lock_version, key: SecureRandom.uuid)
    sign_in(client)
    post "/api/v1/projects/#{project.id}/award", params: { proposal_id: original_id, brief_version: 1 }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("STALE_BRIEF")
    expect(Marketplace::Award.count).to eq(0)
    fresh_id = propose(creator, 2)
    post "/api/v1/projects/#{project.id}/award", params: { proposal_id: fresh_id, brief_version: 2 }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    terms = Engagements::Engagement.find(response.parsed_body.fetch("id")).terms
    expect(terms).to include("brief_version" => 2, "description" => "New acceptance requirements.", "price_minor" => 95_005, "delivery_days" => 18)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("proposals").map { |row| row.fetch("id") }).to contain_exactly(original_id, fresh_id)
    expect(Finance::PaymentOperation.count).to eq(0)
  end
end
