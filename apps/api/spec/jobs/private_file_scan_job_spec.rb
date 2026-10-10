require "rails_helper"
require "timeout"

RSpec.describe "Fenced private file scanning" do
  let(:item) do
    account = create(:account)
    row = Talent::PortfolioItem.create!(account: account, title: "Private sample", sha256: Digest::SHA256.hexdigest("sample"))
    row.file.attach(io: StringIO.new("sample"), filename: "sample.txt", content_type: "text/plain")
    row
  end

  def paused_scan(token)
    started = Queue.new
    release = Queue.new
    scans = 0
    mutex = Mutex.new
    allow(Talent::FileScanner).to receive(:scan) do
      first = mutex.synchronize { scans += 1; scans == 1 }
      if first
        started << true
        release.pop
        :clean
      else
        :infected
      end
    end
    id = item.id
    thread = Thread.new do
      Platform::Record.connection_pool.with_connection { ScanPortfolioJob.perform_now(id, token) }
    end
    Timeout.timeout(10) { started.pop }
    yield
  ensure
    release << true if release && thread&.alive?
    if thread
      raise "scan thread did not finish" unless thread.join(10)
      thread.value
    end
  end

  it "runs duplicate queued jobs only once without holding a database lock during the network call" do
    token = FileScanDispatcher.claim(item)
    paused_scan(token) do
      ScanPortfolioJob.perform_now(item.id, token)
      expect(item.reload.state).to eq("quarantined")
      expect(item.scan_attempts).to eq(1)
      expect(Talent::FileScanner).to have_received(:scan).once
    end
    expect(item.reload.state).to eq("available")
  end

  it "prevents a stale clean result from replacing the rejection by a newer scanner attempt" do
    token = FileScanDispatcher.claim(item)
    paused_scan(token) do
      item.reload.update!(scan_lease_until: 1.second.ago)
      newer_token = FileScanDispatcher.claim(item)
      ScanPortfolioJob.perform_now(item.id, newer_token)
      expect(item.reload.state).to eq("rejected")
    end
    expect(item.reload.state).to eq("rejected")
    expect(item.scan_error).to eq("malware_detected")
    expect(item.scan_attempts).to eq(2)
  end

  it "rejects changed file bytes before calling the scanner" do
    item.file.blob.service.upload(item.file.blob.key, StringIO.new("tampered bytes"))
    allow(Talent::FileScanner).to receive(:scan).and_return(:clean)
    ScanPortfolioJob.perform_now(item.id)
    expect(item.reload.state).to eq("rejected")
    expect(item.scan_error).to eq("integrity_mismatch")
    expect(Talent::FileScanner).not_to have_received(:scan)
  end

  it "persists scanner outage backoff and resumes when the scanner recovers" do
    allow(Talent::FileScanner).to receive(:scan).and_raise(Talent::FileScanner::Unavailable)
    ScanPortfolioJob.perform_now(item.id)
    expect(item.reload.state).to eq("quarantined")
    expect(item.scan_retry_at).to be > Time.current
    expect(FileScanDispatcher.claim(item)).to be_nil
    item.update!(scan_retry_at: 1.second.ago)
    allow(Talent::FileScanner).to receive(:scan).and_return(:clean)
    ScanPortfolioJob.perform_now(item.id)
    expect(item.reload.state).to eq("available")
    expect(item.scan_error).to be_nil
  end

  it "does not erase a newer file claim when an old enqueue fails" do
    row = item
    newer_token = nil
    allow(ScanPortfolioJob).to receive(:perform_later) do
      row.reload.update!(scan_lease_until: 1.second.ago)
      newer_token = FileScanDispatcher.claim(row)
      raise "lost enqueue response"
    end
    FileScanDispatcher.call
    expect(row.reload.scan_token).to eq(newer_token)
    expect(row.scan_lease_until).to be > Time.current
  end

  it "recovers a lost enqueue after its lease and tolerates a removed draft" do
    token = FileScanDispatcher.claim(item)
    item.update!(scan_lease_until: 1.second.ago)
    FileScanDispatcher.call
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ScanPortfolioJob }
    expect(jobs.size).to eq(1)
    expect(jobs.first.fetch(:args)).to eq([ item.id, item.reload.scan_token ])
    expect(item.scan_token).not_to eq(token)
    item.destroy!
    expect { ScanPortfolioJob.perform_now(item.id, token) }.not_to raise_error
  end
end
