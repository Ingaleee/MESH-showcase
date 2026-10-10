require "rails_helper"

RSpec.describe "Publishing guarantees" do
  it "rejects a package with mismatched bytes and blocks publication" do
    operator, _, candidate, validation = publishing_candidate(invalid_digest: true)
    gateway = instance_double(Publishing::PartnerGateway)
    expect(gateway).not_to receive(:contract)
    Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(_) { :clean }, gateway: gateway)
    expect(validation.reload.state).to eq("rejected")
    expect(validation.report.fetch("checks")).to include(hash_including("code" => "FILE_DIGEST", "ok" => false))
    expect { deployment_for(operator, candidate, validation) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("VALIDATION_REQUIRED") }
  end

  it "rejects unsafe archive paths without extracting any entry" do
    _, _, candidate, validation = publishing_candidate(path: "../escape.html")
    checks = Publishing::PackageValidator.call(candidate, Publishing::ValidateCandidate.read_bytes(candidate))
    expect(checks).to include(hash_including(code: "MANIFEST_FILES", ok: false))
    expect(validation.state).to eq("pending")
  end

  it "binds validation to policy/configuration and protects immutable bytes in SQL" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    ENV["MESH_PUBLISHING_POLICY_VERSION"] = "publishing-v2"
    expect { deployment_for(operator, candidate, validation) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("VALIDATION_REQUIRED") }
    fresh = Publishing::RequestValidation.call(actor: operator, candidate: candidate, key: SecureRandom.uuid)
    expect(fresh[:id]).not_to eq(validation.id)
    expect { candidate.update_columns(artifact_sha256: "0" * 64) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { partner.update_columns(origin: "http://unapproved:80") }.to raise_error(ActiveRecord::StatementInvalid, /protected/)
    expect { validation.update_columns(state: "pending") }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "creates one publish intent for concurrent commands and preserves idempotency" do
    operator, _, candidate, validation = publishing_candidate
    passed_validation(validation)
    results = race(*2.times.map { -> { Publishing::RequestDeployment.call(actor: operator, candidate: Publishing::Candidate.find(candidate.id), validation_id: validation.id, key: SecureRandom.uuid) } })
    expect(results).to all(be_a(Hash))
    expect(results.map { |row| row[:id] }.uniq.length).to eq(1)
    expect(Publishing::Deployment.count).to eq(1)
  end

  it "looks up an uncertain operation without posting again and leaves missing outcomes unknown" do
    operator, _, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    gateway = instance_double(Publishing::PartnerGateway)
    expect(gateway).to receive(:publish).once.and_raise(Platform::HttpClient::Failure.new("HTTP_TIMEOUT"))
    Publishing::ProcessDeployment.call(deployment_id: deployment.id, gateway: gateway)
    expect(deployment.reload.state).to eq("unknown")
    expect(gateway).to receive(:lookup).with(instance_of(Publishing::Deployment)).and_return(nil, published_observation(deployment))
    Publishing::ProcessDeployment.call(deployment_id: deployment.id, gateway: gateway)
    expect(deployment.reload.state).to eq("unknown")
    Publishing::ProcessDeployment.call(deployment_id: deployment.id, gateway: gateway)
    expect(deployment.reload.state).to eq("confirmed")
  end

  it "fences stale worker results and ignores stale error completion after a callback" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    old = SecureRandom.uuid
    deployment.update!(state: "dispatching", claim_token: SecureRandom.uuid, lease_until: 1.minute.from_now)
    Publishing::ApplyObservation.call(deployment: deployment, observation: published_observation(deployment), claim_token: old)
    expect(deployment.reload.state).to eq("dispatching")
    callback(partner, published_observation(deployment))
    expect(deployment.reload.state).to eq("confirmed")
    Publishing::ApplyObservation.call(deployment: deployment, observation: published_observation(deployment), claim_token: old)
    expect(deployment.reload.state).to eq("confirmed")
  end

  it "deduplicates signed callbacks, rejects conflicting replays and preserves active ordering" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    older = deployment_for(operator, candidate, validation)
    bytes, manifest = package_fixture(contents: "<html>Second release</html>")
    result = Publishing::SubmitCandidate.call(actor: operator, partner: partner, manifest: manifest, bytes: bytes, key: SecureRandom.uuid)
    second = Publishing::Candidate.find(result[:id])
    second_validation = passed_validation(Publishing::Validation.find(result[:validation_id]))
    newer = deployment_for(operator, second, second_validation)
    event_id = SecureRandom.uuid
    observation = published_observation(newer, sequence: 2)
    expect(callback(partner, observation, event_id: event_id)).to include(duplicate: false)
    expect(callback(partner, observation, event_id: event_id)).to include(duplicate: true)
    expect { callback(partner, observation.merge("sequence" => 3), event_id: event_id) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("CALLBACK_REPLAY_CONFLICT") }
    callback(partner, published_observation(older, sequence: 1))
    expect(partner.reload.active_deployment_id).to eq(newer.id)
    expect(Publishing::CallbackReceipt.count).to eq(2)
    expect { newer.update_columns(remote_sequence: 8) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "rejects unsigned/expired callbacks, mismatched remote identity and unauthorized origins" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    expect { Publishing::ReceiveCallback.call(partner: partner, event_id: SecureRandom.uuid, timestamp: 1.hour.ago.to_i.to_s, signature: "0" * 64, bytes: "{}") }.to raise_error(Platform::Error)
    expect { callback(partner, published_observation(deployment).merge("artifact_sha256" => "0" * 64)) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("PARTNER_OBSERVATION_INVALID") }
    expect { Publishing::RegisterPartner.call(actor: operator, input: { name: "Denied", origin: "http://169.254.169.254", credential_ref: "SHOWCASE" }, key: SecureRandom.uuid) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("PARTNER_ORIGIN_DENIED") }
    expect { Publishing::RequestValidation.call(actor: create(:account), candidate: candidate, key: SecureRandom.uuid) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("FORBIDDEN") }
  end

  it "records validation latency once despite duplicate worker invocation" do
    _, _, _, validation = publishing_candidate
    passed_validation(validation)
    gateway = instance_double(Publishing::PartnerGateway)
    expect(gateway).not_to receive(:contract)
    Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(_) { raise "must not scan twice" }, gateway: gateway)
    expect(Platform::Metrics.snapshot.find { |row| row["name"] == "validation_completion" }["observations"]).to eq(1)
  end
  it "treats a real HTTP 404 lookup as an absent outcome rather than an invalid observation" do
    _, partner, _, validation = publishing_candidate
    passed_validation(validation)
    deployment = Publishing::Deployment.create!(partner: partner, candidate: validation.candidate, validation: validation,
      kind: "publish", state: "pending", scenario: "normal", correlation_id: SecureRandom.uuid)
    client = instance_double(Platform::HttpClient)
    allow(Platform::HttpClient).to receive(:new).and_return(client)
    expect(client).to receive(:request).with(hash_including(method: :get, statuses: [ 200, 404 ])).and_return(
      Platform::HttpClient::Response.new(status: 404, body: { "code" => "NOT_FOUND" }, headers: {}))
    expect(Publishing::PartnerGateway.new.lookup(deployment)).to be_nil
  end
end
