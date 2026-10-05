require "rails_helper"
require "tempfile"

RSpec.describe "Private proposal examples", type: :request do
  let(:client) { create(:account) }
  let(:creator) { create(:account, persona: "creator") }
  let(:project) { Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id)) }
  let(:bytes) { "%PDF-1.4\nA private concept\n%%EOF" }

  before { Talent::Profile.create!(account: creator, headline: "Designer") }

  def upload(content = bytes, filename = "concept.pdf", key = SecureRandom.uuid)
    Tempfile.create([ "example", File.extname(filename) ]) do |file|
      file.binmode
      file.write(content)
      file.flush
      post "/api/v1/projects/#{project.id}/proposal_examples", params: { file: Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: filename) }, headers: { "Idempotency-Key" => key }
    end
  end

  def submit(example_id, key = SecureRandom.uuid)
    post "/api/v1/projects/#{project.id}/propose", params: { proposal: { price_minor: 95_005, delivery_days: 18, message: "My private approach.", brief_version: project.brief_version, example_id: example_id } }, headers: { "Idempotency-Key" => key }, as: :json
  end

  it "uploads once per intent, validates actual file content and keeps the draft private" do
    sign_in(creator)
    key = SecureRandom.uuid
    upload(bytes, "concept.pdf", key)
    expect(response).to have_http_status(:created)
    item = response.parsed_body
    expect(item).to include("state" => "quarantined", "filename" => "concept.pdf", "byte_size" => bytes.bytesize, "content_type" => "application/pdf")
    upload(bytes, "concept.pdf", key)
    expect(response.parsed_body.fetch("id")).to eq(item.fetch("id"))
    expect(Marketplace::ProposalExample.count).to eq(1)
    expect(Marketplace::ProposalExample.first.file.download).to eq(bytes)
    upload("<script>private</script>", "fake.pdf")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("code")).to eq("INVALID_FILE_TYPE")
    upload("", "empty.pdf")
    expect(response.parsed_body.fetch("code")).to eq("INVALID_FILE")
    sign_in(client)
    get "/api/v1/projects/#{project.id}/proposal_examples/#{item.fetch('id')}"
    expect(response).to have_http_status(:not_found)
  end

  it "shares a submitted example only with the two participants and downloads only after a clean scan" do
    sign_in(creator)
    upload
    item = Marketplace::ProposalExample.find(response.parsed_body.fetch("id"))
    key = SecureRandom.uuid
    2.times { submit(item.id, key); expect(response).to have_http_status(:created) }
    expect(Marketplace::Proposal.count).to eq(1)
    expect(item.reload.proposal.creator_id).to eq(creator.id)
    delete "/api/v1/projects/#{project.id}/proposal_examples/#{item.id}"
    expect(response).to have_http_status(:conflict)
    sign_in(client)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("proposals").first.fetch("example")).to include("id" => item.id, "filename" => "concept.pdf")
    get "/api/v1/projects/#{project.id}/proposal_examples/#{item.id}/download"
    expect(response).to have_http_status(:conflict)
    allow(Talent::FileScanner).to receive(:scan).with(bytes).and_return(:clean)
    ScanProposalExampleJob.perform_now(item.id)
    get "/api/v1/projects/#{project.id}/proposal_examples/#{item.id}/download"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(bytes)
    expect(response.headers["Content-Disposition"]).to start_with("attachment;")
    expect(response.headers["Cache-Control"]).to include("no-store")
    sign_in(create(:account, persona: "creator"))
    get "/api/v1/projects/#{project.id}/proposal_examples/#{item.id}/download"
    expect(response).to have_http_status(:not_found)
    get "/api/v1/projects/#{project.id}"
    expect(response.parsed_body.fetch("proposals")).to be_empty
    expect(response.body).not_to include("concept.pdf", "My private approach.")
  end

  it "does not attach another author's file, another project's file or a rejected example" do
    other = create(:account, persona: "creator")
    example = Marketplace::ProposalExample.create!(project: project, creator: other, sha256: "a" * 64)
    sign_in(creator)
    submit(example.id)
    expect(response).to have_http_status(:not_found)
    other_project = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id))
    example.update!(creator: creator, project: other_project)
    submit(example.id)
    expect(response).to have_http_status(:not_found)
    example.update!(project: project, state: "rejected")
    submit(example.id)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("FILE_REJECTED")
    expect(Marketplace::Proposal.count).to eq(0)
  end

  it "removes an unused example and blocks guest uploads and owner uploads" do
    upload
    expect(response).to have_http_status(:unauthorized)
    sign_in(client)
    upload
    expect(response).to have_http_status(:forbidden)
    sign_in(creator)
    upload
    id = response.parsed_body.fetch("id")
    delete "/api/v1/projects/#{project.id}/proposal_examples/#{id}"
    expect(response).to have_http_status(:no_content)
    expect(Marketplace::ProposalExample.exists?(id)).to be(false)
    submit(id)
    expect(response).to have_http_status(:not_found)
  end
end
