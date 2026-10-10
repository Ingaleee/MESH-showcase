module Publishing
  class RegisterPartner
    def self.call(actor:, input:, key:)
      Settings.authorize!(actor)
      values = input.symbolize_keys.slice(:name, :origin, :credential_ref)
      Settings.origin!(values.fetch(:origin))
      Platform::Idempotency.call(actor_id: actor.id, operation: "publishing.partner", key: key, input: values) do
        partner = Partner.create!(values.merge(owner_id: actor.id, contract_version: "1"))
        Settings.token(partner)
        Platform::Events.audit(action: "publishing.partner.created", resource: partner)
        { id: partner.id }
      end
    end
  end
end
