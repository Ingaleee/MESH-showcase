module Finance
  class ProviderObservation
    def self.matches?(operation, observation, terminal: false)
      return false unless observation.is_a?(Hash)
      return false unless observation["amount_minor"].is_a?(Integer)
      return false unless observation["id"].is_a?(String) && observation["id"].present?

      expected = {
        "key" => operation.id,
        "kind" => operation.kind,
        "amount_minor" => operation.amount_minor,
        "currency" => operation.currency
      }
      expected.merge!("state" => operation.state, "id" => operation.external_id) if terminal
      expected.all? { |key, value| observation[key] == value }
    end
  end
end
