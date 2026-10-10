module Publishing
  class ValidateCandidate
    LEASE = 60.seconds

    def self.call(validation_id:, scanner:, gateway: PartnerGateway.new)
      validation = Validation.find(validation_id)
      token = nil
      validation.with_lock do
        return validation if %w[passed rejected failed].include?(validation.state)
        return validation if validation.state == "running" && validation.lease_until && validation.lease_until > Time.current
        token = SecureRandom.uuid
        validation.update!(state: "running", claim_token: token, lease_until: LEASE.from_now, attempts: validation.attempts + 1)
      end
      candidate = validation.candidate
      bytes = read_bytes(candidate)
      checks = PackageValidator.call(candidate, bytes)
      if checks.all? { |row| row[:ok] }
        result = scanner.call(bytes)
        checks << { code: "ANTIVIRUS", ok: result == :clean, expected: "clean", observed: result.to_s, fix: "Use a clean artifact; scanner availability must be restored before retry." }
      end
      if checks.all? { |row| row[:ok] }
        contract = gateway.contract(candidate.partner)
        supported = contract["contract_version"] == candidate.partner.contract_version &&
          contract["capabilities"].is_a?(Array) && %w[publish lookup signed_callbacks].all? { |item| contract["capabilities"].include?(item) }
        checks << { code: "PARTNER_CONTRACT", ok: supported, expected: "v1 / publish, lookup, signed_callbacks", observed: supported ? "compatible" : "incompatible", fix: "Implement the documented partner HTTP contract." }
      end
      finish(validation, token, checks)
    rescue StandardError => error
      if validation && token
        validation.with_lock do
          if validation.state == "running" && validation.claim_token == token
            code = error.respond_to?(:code) ? error.code : error.class.name
            validation.update!(
              state: validation.attempts >= 5 ? "failed" : "pending", claim_token: nil, lease_until: nil,
              next_enqueue_at: 5.seconds.from_now, last_error: code
            )
          end
        end
      end
      raise
    end

    def self.read_bytes(candidate)
      bytes = +"".b
      candidate.artifact_blob.download do |chunk|
        raise Platform::Error.new("ARTIFACT_TOO_LARGE", "Stored artifact exceeds the budget.") if bytes.bytesize + chunk.bytesize > Settings::ARTIFACT_LIMIT
        bytes << chunk
      end
      bytes
    end

    def self.finish(validation, token, checks)
      validation.with_lock do
        return validation unless validation.state == "running" && validation.claim_token == token
        unless Settings.fingerprint(validation.candidate) == validation.input_fingerprint
          checks << { code: "INPUTS_CHANGED", ok: false, expected: "same policy/configuration fingerprint", observed: "changed", fix: "Request a new validation under the current configuration." }
        end
        state = checks.all? { |row| row[:ok] } ? "passed" : "rejected"
        validation.update!(
          state: state, claim_token: nil, lease_until: nil, completed_at: Time.current,
          report: { policy: validation.policy_version, input_fingerprint: validation.input_fingerprint,
            artifact_sha256: validation.candidate.artifact_sha256, checks: checks }, last_error: nil
        )
        Platform::Metrics.observe("validation_completion", Time.current - validation.created_at)
        Platform::Events.audit(action: "publishing.validation.#{state}", resource: validation)
      end
      validation
    end
  end
end
