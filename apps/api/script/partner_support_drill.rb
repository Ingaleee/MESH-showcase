require "zip"

abort "Use only the isolated test database" unless Rails.env.test? && Platform::Record.connection_db_config.database == "mesh_test"
input = JSON.parse($stdin.read(16_384), max_nesting: 5)
origin = input.fetch("origin")
abort "Use the disposable support peer" unless origin.match?(/\Ahttp:\/\/mesh-support-[a-f0-9-]+:3216\z/)
ENV["MESH_PARTNER_ORIGINS"] = ENV["MESH_PARTNER_HTTP_ORIGINS"] = origin
ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = input.fetch("token")
ENV["MESH_PUBLISHING_FAILPOINTS"] = "true"
ActiveJob::Base.queue_adapter = :test

def assert_support(value, message)
  raise message unless value
end

def peer_state(origin)
  Platform::HttpClient.new(origin: origin, allow_http: true).request(
    method: :get, path: "/state", token: ENV.fetch("MESH_PARTNER_TOKEN_SHOWCASE")
  ).body
end

def publish_count(state)
  state.fetch("requests").find { |row| row["route"] == "publish" }&.fetch("count") || 0
end

def candidate_for(operator, partner, title)
  content = "<html><body>#{title}</body></html>"
  bytes = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("index.html"); zip.write(content) }.string
  manifest = { "schema_version" => 1, "title" => title, "version" => "1.0.0", "contract_version" => "1", "entrypoint" => "index.html",
    "files" => [ { "path" => "index.html", "size" => content.bytesize, "sha256" => Digest::SHA256.hexdigest(content) } ] }
  row = Publishing::SubmitCandidate.call(actor: operator, partner: partner, bytes: bytes, manifest: manifest, key: SecureRandom.uuid)
  candidate, validation = Publishing::Candidate.find(row.fetch(:id)), Publishing::Validation.find(row.fetch(:validation_id))
  Publishing::ValidateCandidate.call(validation_id: validation.id, scanner: ->(data) { Talent::FileScanner.scan(data) })
  assert_support(validation.reload.state == "passed", "Real scanner/partner validation failed")
  [ candidate, validation ]
end

def request_operation(operator, candidate, validation, scenario: "normal")
  row = Publishing::RequestDeployment.call(actor: operator, candidate: candidate, validation_id: validation.id, key: SecureRandom.uuid, scenario: scenario)
  Publishing::Deployment.find(row.fetch(:id))
end

report = { phase: input.fetch("phase"), checked_at: Time.current.iso8601(6), checks: {} }
case input.fetch("phase")
when "prepare"
  operator = Identity::Account.create!(email: "support-#{SecureRandom.uuid}@mesh.local", display_name: "Synthetic support operator",
    persona: "client", operator: true, password: SecureRandom.hex(32))
  partner = Publishing::Partner.find(Publishing::RegisterPartner.call(actor: operator, input: {
    name: "Disposable support studio", origin: origin, credential_ref: "SHOWCASE"
  }, key: SecureRandom.uuid).fetch(:id))
  candidate, validation = candidate_for(operator, partner, "Support rotation fixture")
  deployment = request_operation(operator, candidate, validation, scenario: "timeout_after_success")
  Publishing::ProcessDeployment.call(deployment_id: deployment.id)
  assert_support(deployment.reload.state == "unknown" && deployment.last_error == "HTTP_TIMEOUT", "Lost response was not retained")
  state = peer_state(origin)
  assert_support(publish_count(state) == 1 && state["deployments"]["count"] == 1, "Partner acceptance is absent or duplicated")
  report.merge!(partner_id: partner.id, operation_id: deployment.id, candidate_id: candidate.id, validation_id: validation.id)
  report[:checks] = { real_scanner_passed: true, remote_accepted_once_before_timeout: true, local_outcome_unknown: true }
when "rotated"
  deployment = Publishing::Deployment.find(input.fetch("operation_id"))
  partner, candidate, validation = deployment.partner, deployment.candidate, deployment.validation
  ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = input.fetch("old_token")
  Publishing::ProcessDeployment.call(deployment_id: deployment.id)
  auth_diagnostic = Publishing::DeploymentDiagnostic.call(deployment: deployment)
  assert_support(deployment.reload.state == "unknown" && deployment.last_error == "PARTNER_AUTH_REJECTED", "Auth rejection obscured the uncertain operation")
  assert_support(auth_diagnostic[:action_code] == "restore_configuration", "Rejected credential has no support action")
  ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = input.fetch("token")
  assert_support(Publishing::Settings.fingerprint(candidate) != validation.input_fingerprint, "Rotation did not invalidate validation")
  old_denied = begin
    Platform::HttpClient.new(origin: origin, allow_http: true).request(method: :get, path: "/contract", token: input.fetch("old_token"))
    false
  rescue Platform::HttpClient::Failure => error
    error.status == 401
  end
  assert_support(old_denied && Publishing::PartnerGateway.new.contract(partner)["contract_version"] == "1", "Real HTTP credential rotation failed")
  blocked = begin
    request_operation(partner.owner, candidate, validation)
    false
  rescue Platform::Error => error
    error.code == "VALIDATION_REQUIRED"
  end
  assert_support(blocked, "Stale validation allowed publication")
  store = Publishing::Infrastructure::DeploymentStore.new
  stale = store.claim(id: deployment.id, now: 61.seconds.ago, token: SecureRandom.uuid)
  current = store.claim(id: deployment.id, now: Time.current, token: SecureRandom.uuid)
  assert_support(stale.lookup_only && current.lookup_only && stale.token != current.token, "Expired claims did not fence")
  observation = Publishing::PartnerGateway.new.lookup(deployment.reload)
  store.confirm(claim: stale, observation: observation)
  assert_support(deployment.reload.state == "dispatching" && deployment.claim_token == current.token, "Stale lookup overwrote the new worker")
  store.confirm(claim: current, observation: observation)
  store.mark_unknown(claim: stale, code: "HTTP_TIMEOUT")
  assert_support(deployment.reload.state == "confirmed", "Stale failure overwrote confirmation")

  bytes, timestamp, event_id = JSON.generate(observation), Time.current.to_i.to_s, SecureRandom.uuid
  # Rack owns/reset its executor; keep HTTP request context off the runner thread.
  Thread.new do
    session = ActionDispatch::Integration::Session.new(Rails.application)
    headers = { "Content-Type" => "application/json", "X-Event-ID" => event_id, "X-Callback-Timestamp" => timestamp }
    signature = ->(token) { OpenSSL::HMAC.hexdigest("SHA256", token, "#{timestamp}.#{event_id}.#{bytes}") }
    session.post("/api/v1/publishing/callbacks/#{partner.id}", params: bytes,
      headers: headers.merge("X-Callback-Signature" => signature.call(input.fetch("old_token"))))
    assert_support(session.response.status == 401, "Old callback signature was accepted")
    2.times do
      session.post("/api/v1/publishing/callbacks/#{partner.id}", params: bytes,
        headers: headers.merge("X-Callback-Signature" => signature.call(input.fetch("token"))))
      assert_support(session.response.status == 200, "Rotated callback failed")
    end
    assert_support(session.response.parsed_body["duplicate"] == true && Publishing::CallbackReceipt.where(deployment: deployment).count == 1, "Callback replay duplicated")
  end.value
  ENV.delete("MESH_PARTNER_TOKEN_SHOWCASE")
  diagnostic = Publishing::DeploymentDiagnostic.call(deployment: deployment)
  assert_support(diagnostic[:configuration_error] == "PARTNER_CREDENTIAL_UNAVAILABLE" && diagnostic[:state] == "confirmed", "Secret outage hid local history")
  ENV["MESH_PARTNER_TOKEN_SHOWCASE"] = input.fetch("token")

  second, fresh_validation = candidate_for(partner.owner, partner, "Never dispatched support fixture")
  absent = request_operation(partner.owner, second, fresh_validation)
  store.claim(id: absent.id, now: 61.seconds.ago, token: SecureRandom.uuid)
  assert_support(publish_count(peer_state(origin)) == 1, "Rotation/reconciliation repeated a publish")
  report.merge!(operation_id: deployment.id, uncertain_operation_id: absent.id, diagnostic: diagnostic, rejected_credential_diagnostic: auth_diagnostic)
  report[:checks] = { auth_rejection_kept_unknown: true, old_http_credential_denied: true, new_http_credential_accepted: true, stale_validation_blocked: true,
    old_worker_result_fenced: true, old_failure_fenced: true, expired_lease_looked_up: true,
    old_callback_denied: true, rotated_callback_replay_once: true, secret_outage_preserved_local_report: true, remote_posts: 1 }
when "unavailable"
  deployment = Publishing::Deployment.find(input.fetch("uncertain_operation_id"))
  Publishing::ProcessDeployment.call(deployment_id: deployment.id)
  assert_support(deployment.reload.state == "unknown" && %w[HTTP_CONNECTION_FAILED HTTP_TIMEOUT].include?(deployment.last_error), "Unavailable peer was not retained as uncertain")
  report[:diagnostic] = Publishing::DeploymentDiagnostic.call(deployment: deployment)
  assert_support(report[:diagnostic][:action_code] == "lookup_only", "Support suggested unsafe retry")
  report[:checks] = { unavailable_peer_kept_unknown: true, original_operation_preserved: true }
when "absent"
  deployment = Publishing::Deployment.find(input.fetch("uncertain_operation_id"))
  Publishing::ProcessDeployment.call(deployment_id: deployment.id)
  assert_support(deployment.reload.state == "unknown" && deployment.last_error == "PARTNER_OUTCOME_UNKNOWN", "404 authorized unsafe retry")
  before = peer_state(origin)
  diagnostic = Publishing::DeploymentDiagnostic.call(deployment: deployment)
  after = peer_state(origin)
  assert_support(before.fetch("requests") == after.fetch("requests") && before.fetch("deployments") == after.fetch("deployments"), "Diagnostics contacted or mutated the partner")
  assert_support(publish_count(after) == 1 && after["deployments"]["count"] == 1, "Missing outcome caused another POST")
  assert_support(diagnostic[:action_code] == "lookup_only", "404 next action is unsafe")
  report.merge!(diagnostic: diagnostic, remote_posts: publish_count(after), remote_effects: after["deployments"]["count"])
  report[:checks] = { absent_lookup_kept_unknown: true, no_republication: true, read_only_diagnostic: true }
else
  raise "Unknown support phase"
end
report[:success] = true
puts "MESH_SUPPORT_REPORT=" + JSON.generate(report)
