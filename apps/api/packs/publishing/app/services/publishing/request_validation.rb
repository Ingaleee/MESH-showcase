module Publishing
  class RequestValidation
    def self.call(actor:, candidate:, key:)
      Settings.authorize!(actor, candidate.partner)
      fingerprint = Settings.fingerprint(candidate)
      Platform::Idempotency.call(actor_id: actor.id, operation: "publishing.validate:#{candidate.id}", key: key, input: { fingerprint: fingerprint }) do
        candidate.lock!
        validation = Validation.create_or_find_by!(candidate: candidate, input_fingerprint: fingerprint) { |row| row.policy_version = Settings.policy_version }
        { id: validation.id }
      end
    end
  end
end
