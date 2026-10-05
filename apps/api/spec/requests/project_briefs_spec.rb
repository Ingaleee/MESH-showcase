require "rails_helper"

RSpec.describe "Structured public briefs", type: :request do
  let(:client) { create(:account) }
  let(:input) do
    project_input.merge(
      expected_result: "Editable sources ready for print.", deliverables: [ "Logo", "Brand guide" ],
      requirements: [ "Print preparation experience" ], skills: [ "Branding" ], reference_urls: [ "https://example.com/brief.pdf" ]
    )
  end

  def publish
    sign_in(client)
    post "/api/v1/projects", params: { project: input }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    Marketplace::Project.find(response.parsed_body.fetch("id"))
  end

  it "versions structured sections and freezes them in the selected agreement" do
    project = publish
    original = Marketplace::BriefVersion.find_by!(project_id: project.id, version: 1).terms
    patch "/api/v1/projects/#{project.id}", params: { project: input.merge(expected_result: "Updated acceptance criteria."), version: project.lock_version }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:ok)
    expect(Marketplace::BriefVersion.find_by!(project_id: project.id, version: 1).terms).to eq(original)
    creator = create(:account, persona: "creator")
    Talent::Profile.create!(account: creator, headline: "Designer")
    proposal = Marketplace::SubmitProposal.call(actor: creator, project: project.reload, input: { price_minor: 100_005, delivery_days: 7, message: "A clear approach.", brief_version: 2 }, key: SecureRandom.uuid)
    result = Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal.fetch(:id), brief_version: 2, key: SecureRandom.uuid)
    terms = Engagements::Engagement.find(result.fetch(:id)).terms
    expect(terms.fetch("expected_result")).to eq("Updated acceptance criteria.")
    expect(terms.fetch("deliverables")).to eq([ "Logo", "Brand guide" ])
    expect(terms.fetch("reference_urls")).to eq([ "https://example.com/brief.pdf" ])
  end

  it "exposes real counts and change metadata without another author's proposal or old text" do
    project = publish
    creator = create(:account, persona: "creator")
    Talent::Profile.create!(account: creator, headline: "Designer")
    Marketplace::SubmitProposal.call(actor: creator, project: project, input: { price_minor: 100_005, delivery_days: 7, message: "Private approach.", brief_version: 1 }, key: SecureRandom.uuid)
    patch "/api/v1/projects/#{project.id}", params: { project: input.merge(requirements: [ "New requirement" ]), version: project.lock_version }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:ok)
    delete "/api/v1/session"
    get "/api/v1/projects/#{project.id}"
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.fetch("proposal_count")).to eq(1)
    expect(body.fetch("proposals")).to be_empty
    expect(body.fetch("brief_history").last.fetch("changed_fields")).to eq([ "requirements" ])
    expect(body.fetch("brief_history").first.fetch("created_at")).to eq(Marketplace::BriefVersion.find_by!(project_id: project.id, version: 1).created_at.iso8601)
    expect(response.body).not_to include("Private approach.", "terms", "Print preparation experience", client.email, creator.email)
  end

  it "rejects executable URLs, URL credentials and excessive section sizes without publishing" do
    sign_in(client)
    [ { reference_urls: [ "javascript:alert(1)" ] }, { reference_urls: [ "https://user:secret@example.com/file" ] }, { deliverables: [ "a" * 501 ] }, { skills: Array.new(21, "Branding") } ].each do |invalid|
      post "/api/v1/projects", params: { project: input.merge(invalid) }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(Marketplace::Project.count).to eq(0)
    expect(Marketplace::BriefVersion.count).to eq(0)
  end

  it "limits history to 50 versions while comparing the oldest included update correctly" do
    project = publish
    51.times do |index|
      Marketplace::ReviseBrief.call(actor: client, project: project.reload, input: input.merge(title: "Title #{index}"), version: project.lock_version, key: SecureRandom.uuid)
    end
    history = Marketplace::BriefHistory.call(project: project.reload)
    expect(history.size).to eq(50)
    expect(history.first.fetch(:version)).to eq(3)
    expect(history.first.fetch(:changed_fields)).to eq([ "title" ])
    expect(history.last.fetch(:version)).to eq(52)
  end
end
