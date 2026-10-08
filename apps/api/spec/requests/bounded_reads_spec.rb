require "rails_helper"

RSpec.describe "Bounded private project reads", type: :request do
  let(:workflow) { build_workflow }
  let(:client) { workflow[0] }
  let(:creator) { workflow[1] }
  let(:project) { workflow[2] }
  let(:engagement) { workflow[3] }

  def seed_offers(count = 45)
    time = Time.utc(2026, 10, 1)
    count.times do |index|
      author = create(:account, persona: "creator", display_name: "Page author #{index}")
      Marketplace::Proposal.create!(project: project, creator: author, price_minor: 100_000 + index % 3, delivery_days: 10 + index % 2, message: "Approach #{index}", brief_version: 1, created_at: time)
    end
  end

  it "pages every tied proposal once and binds the cursor to actor, project and filters" do
    seed_offers
    sign_in(client)
    seen = []
    cursor = nil
    first_cursor = nil
    loop do
      get "/api/v1/projects/#{project.id}", params: { limit: 7, sort: "price", cursor: cursor }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.fetch("proposals").size).to be <= 7
      seen.concat(body.fetch("proposals").map { |row| row.fetch("id") })
      cursor = body.fetch("next_proposal_cursor")
      first_cursor ||= cursor
      break unless cursor
    end
    expect(seen.uniq).to eq(seen)
    expect(seen.sort).to eq(project.proposals.pluck(:id).sort)
    get "/api/v1/projects/#{project.id}", params: { cursor: first_cursor, sort: "days" }
    expect(response).to have_http_status(:bad_request)
    sign_in(creator)
    get "/api/v1/projects/#{project.id}", params: { cursor: first_cursor, sort: "price" }
    expect(response).to have_http_status(:bad_request)
    get "/api/v1/projects/#{project.id}", params: { limit: 5000 }
    expect(response.parsed_body.fetch("proposals").map { |row| row.fetch("creator").fetch("id") }.uniq).to eq([ creator.id ])
  end

  it "searches the full proposal collection, validates filters, and does not materialize the collection" do
    seed_offers
    sign_in(client)
    get "/api/v1/projects/#{project.id}", params: { q: "Page author 44", sort: "days" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("matched_proposal_count")).to eq(1)
    expect(response.parsed_body.fetch("proposals").first.fetch("creator").fetch("display_name")).to eq("Page author 44")
    author = Identity::Account.find_by!(display_name: "Page author 44")
    Talent::Profile.create!(account: author, headline: "Designer", bio: "Print specialist", skills: [ "Typography" ])
    %w[Print Typography].each do |query|
      get "/api/v1/projects/#{project.id}", params: { q: query }
      expect(response.parsed_body.fetch("matched_proposal_count")).to eq(1)
      expect(response.parsed_body.fetch("proposals").first.fetch("creator").fetch("id")).to eq(author.id)
    end
    get "/api/v1/projects/#{project.id}", params: { ids: "" }
    expect(response.parsed_body.fetch("proposals")).to be_empty
    get "/api/v1/projects/#{project.id}", params: { sort: "injected SQL" }
    expect(response).to have_http_status(:bad_request)
    get "/api/v1/projects/#{project.id}", params: { cursor: "tampered" }
    expect(response).to have_http_status(:bad_request)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/projects/#{project.id}", params: { limit: 5 }
    end
    loaded = queries.select { |sql| sql.match?(/SELECT.*"marketplace_proposals"\.\*/i) }
    expect(loaded).not_to be_empty
    expect(loaded).to all(match(/LIMIT/i))
    expect(response.parsed_body.fetch("owner_context").fetch("events").size).to be <= 50
  end

  it "keeps work lists small and pages immutable versions and feedback without hiding changes decisions" do
    workflow
    sign_in(creator)
    25.times do |index|
      Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, content: "Version #{index}", title: "Identity", ready_for_acceptance: true, file_ids: [], key: SecureRandom.uuid)
    end
    latest = engagement.submissions.order(version: :desc).first
    Engagements::RecordFeedback.call(actor: client, engagement: engagement.reload, content: "Please change the mark.", submission_id: latest.id, kind: "changes_requested", key: SecureRandom.uuid)
    55.times do |index|
      Engagements::RecordFeedback.call(actor: client, engagement: engagement.reload, content: "Comment #{index}", submission_id: latest.id, kind: "comment", key: SecureRandom.uuid)
    end
    get "/api/v1/engagements"
    expect(response.parsed_body.fetch("data").first.fetch("submissions")).to be_empty
    get "/api/v1/engagements/#{engagement.id}"
    body = response.parsed_body
    expect(body.fetch("submissions").size).to eq(20)
    expect(body.fetch("feedback").size).to be <= 70
    expect(body.fetch("feedback").any? { |row| row.fetch("kind") == "changes_requested" }).to be(true)
    versions_cursor = body.fetch("submissions_next_cursor")
    feedback_cursor = body.fetch("feedback_next_cursor")
    get "/api/v1/engagements/#{engagement.id}", params: { versions_cursor: versions_cursor }
    expect(response.parsed_body.fetch("submissions").size).to eq(5)
    expect(response.parsed_body.fetch("submissions_next_cursor")).to be_nil
    get "/api/v1/engagements/#{engagement.id}", params: { feedback_cursor: feedback_cursor }
    expect(response.parsed_body.fetch("feedback_next_cursor")).to be_nil
    expect(response.parsed_body.fetch("feedback").size).to eq(6)
    get "/api/v1/engagements/#{engagement.id}", params: { versions_cursor: feedback_cursor }
    expect(response).to have_http_status(:bad_request)
    _, _, _, other = build_workflow
    get "/api/v1/engagements/#{other.id}", params: { versions_cursor: versions_cursor }
    expect(response).to have_http_status(:forbidden)
  end
end
