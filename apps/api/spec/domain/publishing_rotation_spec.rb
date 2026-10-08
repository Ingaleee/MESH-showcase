require "rails_helper"

RSpec.describe "Publishing credential rotation" do
  it "invalidates new publishes but reconciles old unknown operations under the rotated credential" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    pending = deployment_for(operator, candidate, validation)
    observation = published_observation(pending)
    pending.update!(state: "unknown")
    old_token = Publishing::Settings.token(partner)
    ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = SecureRandom.hex(48)
    expect(Publishing::Settings.fingerprint(candidate)).not_to eq(validation.input_fingerprint)
    expect { deployment_for(operator, candidate, validation) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("VALIDATION_REQUIRED") }
    gateway = instance_double(Publishing::PartnerGateway)
    expect(gateway).not_to receive(:publish)
    expect(gateway).to receive(:lookup).with(instance_of(Publishing::Deployment)) do
      expect(Publishing::Settings.token(partner)).not_to eq(old_token)
      observation
    end
    Publishing::ProcessDeployment.call(deployment_id: pending.id, gateway: gateway)
    expect(pending.reload.state).to eq("confirmed")

    timestamp, event_id, bytes = Time.current.to_i.to_s, SecureRandom.uuid, JSON.generate(observation)
    old_signature = OpenSSL::HMAC.hexdigest("SHA256", old_token, "#{timestamp}.#{event_id}.#{bytes}")
    expect {
      Publishing::ReceiveCallback.call(partner: partner, timestamp: timestamp, event_id: event_id, bytes: bytes, signature: old_signature)
    }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("CALLBACK_AUTH_INVALID") }
    expect(callback(partner, observation, event_id: event_id)).to include(duplicate: false)
    expect(callback(partner, observation, event_id: event_id)).to include(duplicate: true)
    expect(Publishing::CallbackReceipt.count).to eq(1)
  end
end
