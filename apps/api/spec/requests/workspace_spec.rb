require "rails_helper"
require "tempfile"
require "zip"

RSpec.describe "Versioned project workspace", type: :request do
  let(:workflow) { build_workflow }
  let(:client) { workflow[0] }
  let(:creator) { workflow[1] }
  let(:engagement) { workflow[3] }
  let(:base) { "/api/v1/engagements/#{engagement.id}" }

  def command(path, input = {}, key = SecureRandom.uuid)
    post "#{base}/#{path}", params: input, headers: { "Idempotency-Key" => key }, as: :json
  end

  def upload(bytes = "%PDF-1.4\nVersioned result\n%%EOF", name = "result.pdf")
    Tempfile.create([ "result", ".pdf" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      post "#{base}/work_files", params: { file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: name) }, headers: { "Idempotency-Key" => SecureRandom.uuid }
    end
    expect(response).to have_http_status(:created)
    response.parsed_body.fetch("id")
  end

  def submit(content = "Versioned result", **options)
    command("submit", { content: content, title: "NORA identity", ready_for_acceptance: true }.merge(options))
    expect(response).to have_http_status(:created)
    response.parsed_body.fetch("id")
  end

  it "starts once and presents frozen conditions and public participant names without emails" do
    sign_in(client)
    command("start")
    expect(response).to have_http_status(:forbidden)
    sign_in(creator)
    2.times { command("start", {}, "start-once"); expect(response).to have_http_status(:ok) }
    expect(engagement.reload.state).to eq("in_progress")
    expect(engagement.started_at).to be_present
    expect(Platform::AuditEntry.where(action: "work.started").count).to eq(1)
    command("start")
    expect(response).to have_http_status(:conflict)
    get base
    body = response.parsed_body
    expect(body.fetch("project_id")).to eq(workflow[2].id)
    expect(body.fetch("client")).not_to have_key("email")
    expect(body.fetch("creator")).not_to have_key("email")
    expect(body.fetch("terms").fetch("price_minor")).to eq(100_005)
  end

  it "keeps author draft files private and prevents removing or moving submitted files" do
    sign_in(creator)
    file_id = upload
    get "#{base}/work_files/#{file_id}/download"
    expect(response).to have_http_status(:conflict)
    sign_in(client)
    get "#{base}/work_files/#{file_id}"
    expect(response).to have_http_status(:not_found)
    get "#{base}/work_files"
    expect(response.parsed_body.fetch("data")).to be_empty
    sign_in(creator)
    submission_id = submit(file_ids: [ file_id ])
    file = Engagements::WorkFile.find(file_id)
    expect(file.submission_id).to eq(submission_id)
    expect { file.update_columns(submission_id: nil) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    delete "#{base}/work_files/#{file_id}"
    expect(response).to have_http_status(:conflict)
    sign_in(client)
    get "#{base}/work_files/#{file_id}"
    expect(response).to have_http_status(:ok)
    sign_in(create(:account))
    get base
    expect(response).to have_http_status(:forbidden)
    get "#{base}/work_files/#{file_id}/download"
    expect(response).to have_http_status(:forbidden)
    delete "/api/v1/session"
    get "#{base}/work_files/#{file_id}/download"
    expect(response).to have_http_status(:unauthorized)
  end

  it "freezes actual file digests and makes every version append-only" do
    sign_in(creator)
    file_id = upload
    first = submit("First", file_ids: [ file_id ])
    submission = Engagements::Submission.find(first)
    manifest = submission.files_manifest
    expect(manifest.first).to include("id" => file_id, "sha256" => Digest::SHA256.hexdigest("%PDF-1.4\nVersioned result\n%%EOF"))
    expect(submission.manifest_format).to eq("canonical-json-v1")
    expect(submission.manifest_sha256).to eq(Digest::SHA256.hexdigest(JSON.generate(Platform::Idempotency.canonicalize({ title: "NORA identity", content: "First", ready_for_acceptance: true, files: manifest }))))
    expect { submission.update_columns(title: "Tampered") }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    command("submit", content: "Again", file_ids: [ file_id ])
    expect(response).to have_http_status(:not_found)
    command("submit", content: "Duplicate IDs", file_ids: [ file_id, file_id ])
    expect(response).to have_http_status(:bad_request)
    next_file = upload
    Engagements::WorkFile.find(next_file).update!(state: "rejected")
    command("submit", content: "Rejected", file_ids: [ next_file ])
    expect(response.parsed_body.fetch("code")).to eq("FILE_REJECTED")
    _, other_author, _, other_engagement = build_workflow
    expect { Engagements::WorkFile.create!(engagement: other_engagement, creator: other_author, submission_id: first, sha256: "a" * 64) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(engagement.reload.submissions.count).to eq(1)
  end

  it "records one changes decision per version, then accepts only a ready latest result" do
    sign_in(creator)
    first = submit
    command("feedback", content: "Author cannot decide", kind: "changes_requested", submission_id: first)
    expect(response).to have_http_status(:forbidden)
    sign_in(client)
    2.times { command("feedback", { content: "Make the sign softer", kind: "changes_requested", submission_id: first }, "changes-once"); expect(response).to have_http_status(:created) }
    expect(engagement.reload.state).to eq("in_progress")
    feedback = engagement.feedback.first
    expect { feedback.update_columns(content: "Altered") }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    command("accept", submission_id: first)
    expect(response).to have_http_status(:conflict)
    sign_in(creator)
    second = submit("For discussion", ready_for_acceptance: false)
    sign_in(client)
    command("accept", submission_id: second)
    expect(response.parsed_body.fetch("code")).to eq("NOT_READY")
    command("feedback", content: "Old decision", kind: "changes_requested", submission_id: first)
    expect(response.parsed_body.fetch("code")).to eq("STALE_SUBMISSION")
    command("feedback", content: "We like this direction", submission_id: second)
    expect(response).to have_http_status(:created)
    sign_in(creator)
    third = submit("Final ready version")
    sign_in(client)
    command("accept", submission_id: second)
    expect(response.parsed_body.fetch("code")).to eq("STALE_SUBMISSION")
    command("accept", submission_id: third)
    expect(response).to have_http_status(:ok)
    get base
    expect(response.parsed_body.fetch("accepted_submission_id")).to eq(third)
    expect(response.parsed_body.fetch("feedback").map { |row| row.fetch("submission_id") }).to eq([ first, second ])
    expect(Engagements::Feedback.where(kind: "changes_requested").count).to eq(1)
    [ "work.comment", "work.changes_requested" ].each do |kind|
      event = Platform::OutboxEvent.find_by!(event_type: kind)
      2.times { Notifications::ConsumeEvent.call(event) }
      notification = Notifications::Notification.find_by!(outbox_event_id: event.id)
      expect(notification.resource_path).to eq("/workspace?engagement=#{engagement.id}")
      expect(Notifications::Notification.where(outbox_event_id: event.id).count).to eq(1)
    end
  end

  it "serializes acceptance against a changes request with only one winning decision" do
    submission = Engagements::SubmitWork.call(actor: creator, engagement: engagement, content: "Ready", key: "ready")
    results = race(
      -> { Engagements::AcceptSubmission.call(actor: client, engagement: Engagements::Engagement.find(engagement.id), submission_id: submission[:id], key: "accept") },
      -> { Engagements::RecordFeedback.call(actor: client, engagement: Engagements::Engagement.find(engagement.id), content: "Change the sign", submission_id: submission[:id], kind: "changes_requested", key: "request") }
    )
    expect(results.count { |result| result.is_a?(Hash) }).to eq(1)
    expect(results.grep(Platform::Error).size).to eq(1)
    expect([ "INVALID_TRANSITION", "CHANGES_REQUESTED" ]).to include(results.grep(Platform::Error).first.code)
    expect(Engagements::Acceptance.count + Engagements::Feedback.where(kind: "changes_requested").count).to eq(1)
  end

  it "downloads a real ZIP only after all files pass scanning and preserves duplicate names safely" do
    sign_in(creator)
    ids = [ upload("%PDF-1.4\nFirst\n%%EOF", "../same.pdf"), upload("%PDF-1.4\nSecond\n%%EOF", "..\\same.pdf") ]
    submission = submit(file_ids: ids)
    get "#{base}/archive", params: { submission_id: submission }
    expect(response.parsed_body.fetch("code")).to eq("FILE_QUARANTINED")
    allow(Talent::FileScanner).to receive(:scan).and_return(:clean)
    ids.each { |id| ScanWorkFileJob.perform_now(id) }
    sign_in(client)
    get "#{base}/archive", params: { submission_id: submission }
    expect(response.media_type).to eq("application/zip")
    expect(response.headers["Cache-Control"]).to include("no-store")
    entries = []
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (entry = zip.get_next_entry)
        entries << [ entry.name, zip.read ]
      end
    end
    expect(entries.map(&:first).sort).to eq([ "1-same.pdf", "2-same.pdf" ])
    expect(entries.map(&:last)).to contain_exactly("%PDF-1.4\nFirst\n%%EOF", "%PDF-1.4\nSecond\n%%EOF")
    expect(Talent::FileScanner).to have_received(:scan).twice
  end

  it "rejects false file types and treats scanner outages as quarantine rather than success" do
    sign_in(creator)
    Tempfile.create([ "fake", ".pdf" ]) do |file|
      file.write("<html>Not a PDF</html>"); file.flush
      post "#{base}/work_files", params: { file: Rack::Test::UploadedFile.new(file.path, "application/pdf") }, headers: { "Idempotency-Key" => SecureRandom.uuid }
    end
    expect(response.parsed_body.fetch("code")).to eq("INVALID_FILE_TYPE")
    id = upload
    allow(Talent::FileScanner).to receive(:scan).and_raise(Talent::FileScanner::Unavailable, "scanner offline")
    ScanWorkFileJob.perform_now(id)
    expect(Engagements::WorkFile.find(id).state).to eq("quarantined")
  end

  it "blocks acceptance until every file passes verification without committing an acceptance or closing the project" do
    sign_in(creator)
    id = upload
    submission = submit(file_ids: [ id ])
    sign_in(client)
    command("accept", { submission_id: submission }, "accept-after-scan")
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("FILES_NOT_VERIFIED")
    expect(engagement.reload.state).to eq("submitted")
    expect(Engagements::Acceptance.count).to eq(0)
    allow(Talent::FileScanner).to receive(:scan).and_return(:clean)
    ScanWorkFileJob.perform_now(id)
    command("accept", { submission_id: submission }, "accept-after-scan")
    expect(response).to have_http_status(:ok)
    expect(Engagements::Acceptance.count).to eq(1)
  end

  it "never accepts a result containing a rejected file" do
    sign_in(creator)
    id = upload
    submission = submit(file_ids: [ id ])
    allow(Talent::FileScanner).to receive(:scan).and_return(:infected)
    ScanWorkFileJob.perform_now(id)
    sign_in(client)
    command("accept", { submission_id: submission })
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("code")).to eq("FILES_NOT_VERIFIED")
    expect(Engagements::Acceptance.count).to eq(0)
    expect(engagement.reload.state).to eq("submitted")
  end

  it "replays a lost submit response without attaching a file twice and blocks oversized archive downloads" do
    sign_in(creator)
    file_id = upload
    input = { content: "Ready result", title: "Identity", file_ids: [ file_id ], ready_for_acceptance: true }
    2.times { command("submit", input, "same-transmission"); expect(response).to have_http_status(:created) }
    expect(engagement.submissions.count).to eq(1)
    command("submit", input.merge(title: "Changed intent"), "same-transmission")
    expect(response.parsed_body.fetch("code")).to eq("IDEMPOTENCY_CONFLICT")
    item = Engagements::WorkFile.find(file_id)
    item.update!(state: "available")
    item.file.blob.update!(byte_size: 51.megabytes)
    get "#{base}/archive", params: { submission_id: engagement.submissions.first.id }
    expect(response.parsed_body.fetch("code")).to eq("ZIP_LIMIT")
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
