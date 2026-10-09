require "rails_helper"

RSpec.describe "Publishing support diagnostic", type: :request do
  def operation
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    sign_in(operator)
    [ partner, deployment_for(operator, candidate, validation) ]
  end

  def diagnose(deployment)
    get "/api/v1/publishing/deployments/#{deployment.id}/diagnose"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    response.parsed_body
  end

  it "preserves a useful unknown report when the credential is missing, without contacting the partner" do
    _, deployment = operation
    deployment.update!(state: "unknown", last_error: "HTTP_TIMEOUT")
    ENV.delete("MESH_PARTNER_TOKEN_SHOWCASE")
    expect(Publishing::PartnerGateway).not_to receive(:new)
    report = diagnose(deployment)
    expect(report).to include("state" => "unknown", "configuration_error" => "PARTNER_CREDENTIAL_UNAVAILABLE",
      "current_inputs_match" => nil, "action_code" => "restore_configuration", "remote_state_queried" => false)
    expect(report["support_update_en"]).to include(deployment.id, deployment.correlation_id, "do not create another POST")
    expect(deployment.reload.state).to eq("unknown")
  end

  it "distinguishes a live lease, expired claim, stale validation and confirmed history" do
    partner, deployment = operation
    deployment.update!(state: "dispatching", claim_token: SecureRandom.uuid, lease_until: 1.minute.from_now)
    expect(diagnose(deployment)["action_code"]).to eq("await_lease")
    deployment.update!(lease_until: 1.second.ago)
    expect(diagnose(deployment)["action_code"]).to eq("lookup_only")
    Publishing::ApplyObservation.call(deployment: deployment, observation: published_observation(deployment))
    report = diagnose(deployment)
    expect(report).to include("action_code" => "inspect_confirmed", "remote_sequence" => 1)
    expect(report["support_update_en"]).not_to include("partner is healthy")
    expect(response.body).not_to include(Publishing::Settings.token(partner))
  end

  it "separates a configuration change from an uncertain external outcome" do
    _, deployment = operation
    ENV["MESH_PUBLISHING_POLICY_VERSION"] = "changed-policy"
    expect(diagnose(deployment)).to include("current_inputs_match" => false, "action_code" => "revalidate")
    deployment.update!(state: "unknown")
    expect(diagnose(deployment)["action_code"]).to eq("lookup_only")
  end

  it "fails closed for empty, oversized and header-breaking credentials while keeping the report readable" do
    partner, deployment = operation
    [ "", "a" * 257, "a" * 32 + "\n" ].each do |value|
      ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = value
      expect { Publishing::Settings.token(partner) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("PARTNER_CREDENTIAL_UNAVAILABLE") }
      expect(diagnose(deployment)).to include("current_inputs_match" => nil, "configuration_error" => "PARTNER_CREDENTIAL_UNAVAILABLE")
    end
  end

  it "does not recommend resuming a closed failure even when configuration is missing" do
    _, deployment = operation
    deployment.update!(state: "failed", last_error: "VALIDATION_STALE")
    ENV.delete("MESH_PARTNER_TOKEN_SHOWCASE")
    expect(diagnose(deployment)).to include("state" => "failed", "action_code" => "inspect_failure",
      "configuration_error" => "PARTNER_CREDENTIAL_UNAVAILABLE")
  end

  it "does not reveal an operation to another operator" do
    _, deployment = operation
    sign_in(create(:account, operator: true))
    get "/api/v1/publishing/deployments/#{deployment.id}/diagnose"
    expect(response).to have_http_status(:not_found)
  end
end
