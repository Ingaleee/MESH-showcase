module Publishing
  class DeploymentDiagnostic
    ACTIONS = {
      "inspect_confirmed" => "Inspect the confirmed operation and release history; this report does not query the partner's current state.",
      "await_lease" => "Wait for the current claim lease; do not start a competing publish.",
      "lookup_only" => "Lookup remote state by the same operation ID; a timeout or 404 does not authorize another POST.",
      "restore_configuration" => "Restore the approved credential or trust configuration, then resume the same operation; do not create another POST.",
      "revalidate" => "Request validation of the same artifact under the current configuration before requesting a release.",
      "await_dispatch" => "Allow the dispatcher to process the existing pending operation.",
      "inspect_failure" => "Inspect the failed operation and validation report before requesting any new release."
    }.freeze

    def self.call(deployment:, now: Time.current)
      # A local snapshot for support, never a command or an assertion of remote health.
      deployment.reload
      configuration_error = nil
      inputs_match = begin
        Settings.fingerprint(deployment.candidate) == deployment.validation.input_fingerprint
      rescue Platform::Error => error
        configuration_error = error.code
        nil
      end
      code = if deployment.state == "confirmed"
        "inspect_confirmed"
      elsif deployment.state == "failed"
        "inspect_failure"
      elsif configuration_error || deployment.last_error == "PARTNER_AUTH_REJECTED"
        "restore_configuration"
      elsif deployment.state == "dispatching" && deployment.lease_until && deployment.lease_until > now
        "await_lease"
      elsif %w[unknown dispatching].include?(deployment.state)
        "lookup_only"
      elsif inputs_match == false
        "revalidate"
      else
        "await_dispatch"
      end
      {
        schema_version: 1, operation_id: deployment.id, state: deployment.state, artifact_sha256: deployment.candidate.artifact_sha256,
        policy_version: deployment.validation.policy_version, input_fingerprint: deployment.validation.input_fingerprint,
        current_inputs_match: inputs_match, configuration_error: configuration_error,
        correlation_id: deployment.correlation_id, attempts: deployment.attempts, last_error: deployment.last_error,
        local_confirmed_at: deployment.confirmed_at, remote_sequence: deployment.remote_sequence,
        observed_at: now.iso8601(6), lease_until: deployment.lease_until, action_code: code,
        remote_state_queried: false, next_action: ACTIONS.fetch(code),
        support_update_en: "Local operation #{deployment.id} is #{deployment.state}. " \
          "Artifact SHA-256: #{deployment.candidate.artifact_sha256}. Correlation ID: #{deployment.correlation_id}. " \
          "Remote state was not queried by this report. #{ACTIONS.fetch(code)}",
        reproduce: "mesh-publish diagnose #{deployment.id}"
      }
    end
  end
end
