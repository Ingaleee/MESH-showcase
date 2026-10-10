require "zip"

module PublishingHelpers
  def package_fixture(contents: "<html><body>Studio preview</body></html>", path: "index.html", invalid_digest: false)
    bytes = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry(path)
      zip.write(contents)
    end.string
    manifest = {
      "schema_version" => 1, "title" => "Studio preview", "version" => "1.0.0",
      "contract_version" => "1", "entrypoint" => "index.html",
      "files" => [ { "path" => path, "size" => contents.bytesize, "sha256" => invalid_digest ? "0" * 64 : Digest::SHA256.hexdigest(contents) } ]
    }
    [ bytes, manifest ]
  end

  def publishing_candidate(invalid_digest: false, path: "index.html")
    operator = create(:account, operator: true)
    partner_id = Publishing::RegisterPartner.call(actor: operator, input: { name: "Test Studio", origin: "http://partner:3216", credential_ref: "SHOWCASE" }, key: SecureRandom.uuid).fetch(:id)
    partner = Publishing::Partner.find(partner_id)
    bytes, manifest = package_fixture(invalid_digest: invalid_digest, path: path)
    result = Publishing::SubmitCandidate.call(actor: operator, partner: partner, manifest: manifest, bytes: bytes, key: SecureRandom.uuid)
    [ operator, partner, Publishing::Candidate.find(result.fetch(:id)), Publishing::Validation.find(result.fetch(:validation_id)) ]
  end

  def passed_validation(validation)
    gateway = instance_double(Publishing::PartnerGateway, contract: { "contract_version" => "1", "capabilities" => %w[publish lookup signed_callbacks] })
    Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(_) { :clean }, gateway: gateway)
    expect(validation.reload.state).to eq("passed")
    validation
  end

  def deployment_for(operator, candidate, validation)
    Publishing::Deployment.find(Publishing::RequestDeployment.call(actor: operator, candidate: candidate, validation_id: validation.id, key: SecureRandom.uuid).fetch(:id))
  end

  def published_observation(deployment, sequence: 1)
    {
      "operation_id" => deployment.id, "candidate_id" => deployment.candidate_id,
      "artifact_sha256" => deployment.candidate.artifact_sha256, "contract_version" => "1",
      "state" => "active", "deployment_id" => "partner-#{deployment.id}", "sequence" => sequence
    }
  end

  def callback(partner, observation, event_id: SecureRandom.uuid)
    body = JSON.generate(observation)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", Publishing::Settings.token(partner), "#{timestamp}.#{event_id}.#{body}")
    Publishing::ReceiveCallback.call(partner: partner, event_id: event_id, timestamp: timestamp, signature: signature, bytes: body)
  end
end

RSpec.configure do |config|
  config.include PublishingHelpers
  config.around do |example|
    keys = %w[MESH_PUBLISHING_ENABLED MESH_PARTNER_ORIGINS MESH_PARTNER_HTTP_ORIGINS MESH_PARTNER_TOKEN_SHOWCASE MESH_PUBLISHING_FAILPOINTS MESH_PUBLISHING_POLICY_VERSION]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["MESH_PUBLISHING_ENABLED"] = "true"
    ENV["MESH_PARTNER_ORIGINS"] = ENV["MESH_PARTNER_HTTP_ORIGINS"] = "http://partner:3216"
    ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = "test-local-partner-token-without-live-access"
    ENV["MESH_PUBLISHING_FAILPOINTS"] = "true"
    example.run
  ensure
    original.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
