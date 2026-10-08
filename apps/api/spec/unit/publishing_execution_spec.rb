require_relative "../../packs/publishing/app/domain/publishing/domain/failure"
require_relative "../../packs/publishing/app/domain/publishing/domain/deployment_rules"
require_relative "../../packs/publishing/app/application/publishing/application/deployment_ports"
require_relative "../../packs/publishing/app/application/publishing/application/process_deployment"

RSpec.describe Publishing::Application::ProcessDeployment do
  let(:claim) { Publishing::Domain::DeploymentRules::Claim.new(id: "operation", token: "fence", lookup_only: false, artifact_sha256: Digest::SHA256.hexdigest("package")) }
  let(:store) { instance_double(Publishing::Application::DeploymentPorts::Store, claim: claim) }
  let(:partner) { instance_double(Publishing::Application::DeploymentPorts::Partner) }
  let(:artifacts) { instance_double(Publishing::Application::DeploymentPorts::Artifacts) }
  subject(:use_case) { described_class.new(store: store, partner: partner, artifacts: artifacts, clock: -> { Time.at(100) }, tokens: -> { "fence" }) }

  it "runs without Rails or a database and performs I/O only after the fenced claim" do
    expect(store).to receive(:claim).with(id: "operation", now: Time.at(100), token: "fence").ordered.and_return(claim)
    expect(artifacts).to receive(:read).with(claim: claim).ordered.and_return("package")
    expect(partner).to receive(:publish).with(claim: claim, bytes: "package").ordered.and_return({ "state" => "active" })
    expect(store).to receive(:confirm).with(claim: claim, observation: { "state" => "active" }).ordered
    use_case.call(id: "operation")
  end

  it "never republishes an uncertain intent, even when lookup returns no result" do
    uncertain = claim.with(lookup_only: true)
    allow(store).to receive(:claim).and_return(uncertain)
    expect(artifacts).not_to receive(:read)
    expect(partner).not_to receive(:publish)
    expect(partner).to receive(:lookup).with(claim: uncertain).and_return(nil)
    expect(store).to receive(:mark_unknown).with(claim: uncertain, code: "PARTNER_OUTCOME_UNKNOWN")
    use_case.call(id: "operation")
  end

  it "blocks corrupted private bytes before contacting the partner" do
    expect(artifacts).to receive(:read).and_return("corrupt")
    expect(partner).not_to receive(:publish)
    expect(store).to receive(:mark_unknown).with(claim: claim, code: "ARTIFACT_DIGEST_CHANGED")
    use_case.call(id: "operation")
  end

  it "does no I/O when a concurrent worker owns the lease" do
    allow(store).to receive(:claim).and_return(nil)
    expect(partner).not_to receive(:publish)
    expect(artifacts).not_to receive(:read)
    use_case.call(id: "operation")
  end
end

RSpec.describe Publishing::Domain::DeploymentRules do
  it "distinguishes new publication, stale validation, live lease and expired lease" do
    inputs = { state: "pending", lease_until: nil, now: Time.at(100), current_fingerprint: "a", validated_fingerprint: "a" }
    expect(described_class.claim_mode(**inputs)).to eq(:publish)
    expect(described_class.claim_mode(**inputs.merge(current_fingerprint: "b"))).to eq(:stale)
    expect(described_class.claim_mode(**inputs.merge(state: "dispatching", lease_until: Time.at(101)))).to eq(:skip)
    expect(described_class.claim_mode(**inputs.merge(state: "dispatching", lease_until: Time.at(100)))).to eq(:lookup)
    expect(described_class.claim_mode(**inputs.merge(state: "confirmed"))).to eq(:skip)
  end

  it "fences results and refuses to overwrite a confirmed identity" do
    values = { state: "dispatching", current_token: "new", worker_token: "old", remote_id: nil, remote_sequence: nil, observation: {} }
    expect(described_class.confirmation(**values)).to eq(:ignore)
    expect { described_class.confirmation(**values.merge(state: "confirmed", worker_token: nil, remote_id: "x", remote_sequence: 1)) }.to raise_error(Publishing::Domain::Failure) { |error| expect(error.code).to eq("PARTNER_OBSERVATION_CONFLICT") }
  end
end
