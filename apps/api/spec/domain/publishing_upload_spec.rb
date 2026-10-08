require "rails_helper"

RSpec.describe "Publishing durable uploads" do
  it "uploads without an open transaction and returns the same candidate after response loss" do
    operator, partner, _, _ = publishing_candidate
    bytes, manifest = package_fixture(contents: "<html>Durable upload</html>")
    key = SecureRandom.uuid
    service = ActiveStorage::Blob.service
    allow(service).to receive(:upload).and_wrap_original do |original, *args, **options|
      expect(Platform::Record.connection.transaction_open?).to eq(false)
      original.call(*args, **options)
    end
    first = Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: key)
    second = Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: key)
    expect(second).to eq(first)
    expect(Publishing::UploadIntent.find_by!(request_key: key).state).to eq("finalized")
    expect(Publishing::Candidate.find(first[:id]).artifact_blob.download).to eq(bytes)
    expect {
      Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes + "x", manifest: manifest, key: key)
    }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("IDEMPOTENCY_CONFLICT") }
  end

  it "recovers bytes written before a killed upload finishes its durable state" do
    operator, partner, _, _ = publishing_candidate
    bytes, manifest = package_fixture(contents: "<html>Crash recovery</html>")
    service = ActiveStorage::Blob.service
    allow(service).to receive(:upload).and_wrap_original do |original, *args, **options|
      original.call(*args, **options)
      raise "synthetic crash after storage"
    end
    key = SecureRandom.uuid
    expect {
      Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: key)
    }.to raise_error(RuntimeError, /synthetic crash/)
    intent = Publishing::UploadIntent.find_by!(request_key: key)
    expect(intent.state).to eq("uploading")
    expect(intent.artifact_blob.download).to eq(bytes)
    expect {
      Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: key)
    }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("UPLOAD_IN_PROGRESS") }
    intent.update!(lease_until: 1.second.ago)
    allow(service).to receive(:upload).and_call_original
    response = Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: key)
    expect(Publishing::Candidate.find(response[:id]).artifact_blob_id).to eq(intent.artifact_blob_id)
  end

  it "rejects new direct references once cleanup has tombstoned an abandoned upload" do
    _, partner, candidate, _ = publishing_candidate
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("abandoned"), filename: "abandoned.zip")
    intent = Publishing::UploadIntent.create!(partner: partner, request_key: SecureRandom.uuid,
      fingerprint: "d" * 64, artifact_blob: blob, state: "discarded")
    expect {
      Publishing::Candidate.create!(partner: partner, artifact_blob: blob, manifest: {},
        artifact_sha256: "a" * 64, manifest_sha256: "b" * 64, correlation_id: SecureRandom.uuid)
    }.to raise_error(ActiveRecord::StatementInvalid, /reclaimed publishing blob/)
    expect {
      ActiveStorage::Attachment.create!(record: candidate, name: "artifact", blob: blob)
    }.to raise_error(ActiveRecord::StatementInvalid, /reclaimed publishing blob/)
    expect(intent.reload.state).to eq("discarded")
  end

  it "reclaims only old abandoned uploads and never purges direct candidate references or leases" do
    _, _, candidate, _ = publishing_candidate
    safe_blob = candidate.artifact_blob
    intent = Publishing::UploadIntent.find_by!(artifact_blob_id: safe_blob.id)
    # Even an inconsistent maintenance state must not permit deleting a directly referenced candidate blob.
    intent.update!(state: "discarded", updated_at: 3.days.ago)
    abandoned_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("orphan"), filename: "orphan.zip")
    orphan = Publishing::UploadIntent.create!(partner: candidate.partner, request_key: SecureRandom.uuid,
      fingerprint: "a" * 64, artifact_blob: abandoned_blob, state: "ready", updated_at: 3.days.ago)
    leased_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("leased"), filename: "leased.zip")
    leased = Publishing::UploadIntent.create!(partner: candidate.partner, request_key: SecureRandom.uuid,
      fingerprint: "b" * 64, artifact_blob: leased_blob, state: "uploading", claim_token: SecureRandom.uuid,
      lease_until: 1.minute.from_now, updated_at: 3.days.ago)
    expect(Publishing::ReclaimUploads.call[:reclaimed]).to eq([])
    expect(abandoned_blob.reload.download).to eq("orphan")
    result = Publishing::ReclaimUploads.call(dry_run: false)
    expect(result[:reclaimed]).to eq([ orphan.id ])
    expect(orphan.reload.state).to eq("discarded")
    expect(orphan.artifact_blob_id).to be_nil
    expect(safe_blob.reload.download).to be_present
    expect(leased.reload.state).to eq("uploading")
  end
end
