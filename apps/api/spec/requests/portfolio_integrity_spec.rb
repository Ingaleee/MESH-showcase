require "rails_helper"
require "tempfile"

RSpec.describe "Portfolio file integrity", type: :request do
  it "stores the byte digest at upload, normalizes Windows filenames and serves privately after verification" do
    account = create(:account)
    sign_in(account)
    bytes = "%PDF-1.4\nPrivate sample\n%%EOF"
    Tempfile.create([ "portfolio", ".pdf" ]) do |file|
      file.write(bytes)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "..\\private.pdf")
      post "/api/v1/portfolio", params: { title: "Sample", file: upload }
    end
    expect(response).to have_http_status(:created)
    item = Talent::PortfolioItem.find(response.parsed_body.fetch("id"))
    expect(item.sha256).to eq(Digest::SHA256.hexdigest(bytes))
    expect(item.file.filename.to_s).to eq("private.pdf")
    allow(Talent::FileScanner).to receive(:scan).and_return(:clean)
    ScanPortfolioJob.perform_now(item.id)
    get "/api/v1/portfolio/#{item.id}/download"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(bytes)
    expect(response.headers.fetch("Cache-Control")).to eq("private, no-store")
  end

  it "rolls back the metadata if attaching its file fails" do
    sign_in(create(:account))
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(IOError, "storage unavailable")
    Tempfile.create([ "portfolio", ".pdf" ]) do |file|
      file.write("%PDF-1.4\nSample\n%%EOF")
      file.flush
      post "/api/v1/portfolio", params: { title: "Sample", file: Rack::Test::UploadedFile.new(file.path, "application/pdf") }
    end
    expect(response).to have_http_status(:internal_server_error)
    expect(Talent::PortfolioItem.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
  end
end
