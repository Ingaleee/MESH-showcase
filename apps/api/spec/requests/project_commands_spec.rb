require "rails_helper"

RSpec.describe "Project JSON commands", type: :request do
  it "revises a brief using the ISO date sent by the browser and preserves the previous version" do
    client = create(:account)
    sign_in(client)
    input = project_input.merge(deadline: project_input.fetch(:deadline).iso8601)
    post "/api/v1/projects", params: { project: input }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    project = Marketplace::Project.find(response.parsed_body.fetch("id"))

    patch "/api/v1/projects/#{project.id}",
      params: { project: input.merge(title: "Revised JSON brief"), version: project.lock_version },
      headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload.brief_version).to eq(2)
    expect(project.deadline).to eq(Date.iso8601(input.fetch(:deadline)))
    titles = Marketplace::BriefVersion.where(project_id: project.id).order(:version).pluck(:terms).map { |terms| terms.fetch("title") }
    expect(titles).to eq([ input.fetch(:title), "Revised JSON brief" ])
  end

  it "rejects fractional minor units before coercion and also guards direct use case callers" do
    client = create(:account)
    sign_in(client)
    input = project_input.merge(budget_minor: 100_005.75)
    post "/api/v1/projects", params: { project: input }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("code")).to eq("INVALID_INPUT")
    expect(Marketplace::Project.count).to eq(0)
    expect(Platform::IdempotencyRecord.count).to eq(0)
    expect { Marketplace::CreateProject.call(actor: client, input: input, key: SecureRandom.uuid) }.to raise_error(ArgumentError)
    expect(Marketplace::Project.count).to eq(0)
    expect(Platform::IdempotencyRecord.count).to eq(0)
  end
end
