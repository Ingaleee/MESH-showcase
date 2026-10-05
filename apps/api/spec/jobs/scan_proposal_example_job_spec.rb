require "rails_helper"

RSpec.describe ScanProposalExampleJob do
  let(:client) { create(:account) }
  let(:creator) { create(:account, persona: "creator") }
  let(:item) do
    project = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id))
    item = Marketplace::ProposalExample.create!(project: project, creator: creator, sha256: Digest::SHA256.hexdigest("sample"))
    item.file.attach(io: StringIO.new("sample"), filename: "sample.pdf", content_type: "application/pdf")
    item
  end

  it "leaves files quarantined when the scanner is unavailable and retries" do
    allow(Talent::FileScanner).to receive(:scan).and_raise(Talent::FileScanner::Unavailable)
    described_class.perform_now(item.id)
    expect(item.reload.state).to eq("quarantined")
    expect(item.scan_error).to eq("Talent::FileScanner::Unavailable")
    expect(item.scan_retry_at).to be > Time.current
  end

  it "rejects detected malware and does not rescan a terminal result" do
    allow(Talent::FileScanner).to receive(:scan).and_return(:infected)
    2.times { described_class.perform_now(item.id) }
    expect(item.reload.state).to eq("rejected")
    expect(item.scan_error).to eq("malware_detected")
    expect(Talent::FileScanner).to have_received(:scan).once
  end
end
