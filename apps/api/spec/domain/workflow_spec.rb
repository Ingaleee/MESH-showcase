require "rails_helper"

RSpec.describe "Marketplace consistency" do
  it "serializes concurrent repeated requests and rejects reuse with changed input" do
    client = create(:account)
    commands = Array.new(2) { -> { Marketplace::CreateProject.call(actor: client, input: project_input, key: "repeat") } }
    results = race(*commands)
    expect(results).to all(be_a(Hash))
    expect(results.map { |result| result[:id] }.uniq.size).to eq(1)
    expect(Marketplace::Project.count).to eq(1)
    expect(Platform::OutboxEvent.count).to eq(1)
    expect { Marketplace::CreateProject.call(actor: client, input: project_input.merge(title: "Changed"), key: "repeat") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("IDEMPOTENCY_CONFLICT") }
  end

  it "allows only one winner when two award commands race" do
    client = create(:account)
    project = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: "project")[:id])
    proposals = 2.times.map do
      creator = create(:account, persona: "creator")
      Talent::Profile.create!(account: creator, headline: "Author")
      Marketplace::SubmitProposal.call(actor: creator, project: project.reload, input: { price_minor: 100_005, delivery_days: 7, message: "I can help.", brief_version: 1 }, key: SecureRandom.uuid)[:id]
    end
    results = race(*proposals.map { |id| -> { Marketplace::AwardProposal.call(actor: client, project: Marketplace::Project.find(project.id), proposal_id: id, brief_version: 1, key: SecureRandom.uuid) } })
    expect(results.count { |result| result.is_a?(Hash) }).to eq(1)
    expect(results.grep(Platform::Error).map(&:code)).to eq([ "ALREADY_AWARDED" ])
    expect(Marketplace::Award.count).to eq(1)
    expect(Engagements::Engagement.count).to eq(1)
  end

  it "rolls the award back if its outbox cannot be persisted" do
    client, creator, project, engagement = build_workflow
    expect(engagement).to be_persisted
    second = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input.merge(title: "Second"), key: "second")[:id])
    proposal = Marketplace::SubmitProposal.call(actor: creator, project: second, input: { price_minor: 100_005, delivery_days: 7, message: "Again.", brief_version: 1 }, key: "second-proposal")
    allow(Platform::Events).to receive(:emit).and_raise("outbox failure")
    expect { Marketplace::AwardProposal.call(actor: client, project: second, proposal_id: proposal[:id], brief_version: 1, key: "failed-award") }.to raise_error("outbox failure")
    expect(second.reload.state).to eq("open")
    expect(Marketplace::Award.where(project_id: second.id)).to be_empty
    expect(Engagements::Engagement.count).to eq(1)
    expect(Platform::IdempotencyRecord.where(key: "failed-award")).to be_empty
  end

  it "rejects stale proposals and keeps every brief version immutable" do
    client = create(:account)
    creator = create(:account, persona: "creator")
    Talent::Profile.create!(account: creator, headline: "Author")
    project = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: "project")[:id])
    proposal = Marketplace::SubmitProposal.call(actor: creator, project: project, input: { price_minor: 100_005, delivery_days: 7, message: "Proposal", brief_version: 1 }, key: "proposal")
    Marketplace::ReviseBrief.call(actor: client, project: project.reload, input: project_input.merge(description: "New requirements"), version: 0, key: "revision")
    expect { Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal[:id], brief_version: 2, key: "award") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("STALE_BRIEF") }
    expect(Marketplace::BriefVersion.count).to eq(2)
    fresh = Marketplace::SubmitProposal.call(actor: creator, project: project.reload, input: { price_minor: 110_000, delivery_days: 8, message: "New brief, new proposal", brief_version: 2 }, key: "fresh-proposal")
    expect(Marketplace::Proposal.find(fresh.fetch(:id)).brief_version).to eq(2)
    expect { Marketplace::BriefVersion.first.update_columns(terms: {}) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "accepts only the latest submission and rejects alteration of agreed terms" do
    client, creator, _, engagement = build_workflow
    first = Engagements::SubmitWork.call(actor: creator, engagement: engagement, content: "First", key: "first")
    Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, content: "Second", key: "second")
    expect { Engagements::AcceptSubmission.call(actor: client, engagement: engagement.reload, submission_id: first[:id], key: "stale") }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("STALE_SUBMISSION") }
    expect { engagement.update_columns(terms: {}) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { Engagements::Submission.first.update_columns(content: "Tampered") }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "rejects SQL-level acceptance of a submission from another agreement" do
    client, creator, _, first = build_workflow
    _, second_creator, _, second = build_workflow
    submission = Engagements::SubmitWork.call(actor: second_creator, engagement: second, content: "Other", key: "other")
    expect { Engagements::Acceptance.create!(engagement_id: first.id, submission_id: submission[:id]) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
