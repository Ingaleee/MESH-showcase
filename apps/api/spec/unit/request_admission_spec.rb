require_relative "../../lib/request_admission"

RSpec.describe RequestAdmission do
  it "rejects excess work without reading its body and releases permits even on exceptions" do
    entered = Queue.new
    finish = Queue.new
    app = ->(env) { entered << true; finish.pop; raise "failure" if env["fail"]; [ 200, {}, [ "ok" ] ] }
    middleware = described_class.new(app, limit: 1)
    worker = Thread.new { middleware.call("PATH_INFO" => "/api/v1/projects", "fail" => true) rescue :failed }
    entered.pop
    begin
      response = middleware.call("PATH_INFO" => "/api/v1/projects")
      expect(response[0]).to eq(429)
      expect(response[1]["retry-after"]).to eq("1")
      expect(described_class.prometheus).to include("mesh_api_admission_active 1")
    ensure
      finish << true
      expect(worker.value).to eq(:failed)
    end
    expect(described_class.prometheus).to include("mesh_api_admission_active 0")
  end

  it "allows readiness traffic to bypass application permits" do
    app = ->(_) { [ 200, {}, [ "ready" ] ] }
    expect(described_class.new(app, limit: 1).call("PATH_INFO" => "/ready")[0]).to eq(200)
  end
end
