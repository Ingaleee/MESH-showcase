require "uri"

module Api
  class DeploymentConfiguration
    SECRETS = { "SECRET_KEY_BASE" => 64, "MESH_METRICS_TOKEN" => 32, "MESH_GATEWAY_SECRET" => 32, "MESH_WEBHOOK_SECRET" => 32 }.freeze
    DEMO_SECRETS = %w[local-mesh-metrics-only local-sandbox-only-change-for-deployment local-webhook-only-change-for-deployment].freeze

    def self.validate!(environment)
      origin = URI.parse(environment.fetch("MESH_PUBLIC_ORIGIN", ""))
      unless origin.is_a?(URI::HTTPS) && origin.host.present? && origin.userinfo.nil? && origin.query.nil? && origin.fragment.nil? && [ "", "/" ].include?(origin.path)
        raise ArgumentError, "MESH_PUBLIC_ORIGIN must be an HTTPS origin without credentials, path, query or fragment."
      end
      SECRETS.each do |name, minimum|
        secret = environment.fetch(name, "")
        raise ArgumentError, "#{name} must contain at least #{minimum} characters and must not use a demo value." if secret.length < minimum || DEMO_SECRETS.include?(secret)
      end
      if SECRETS.keys.map { |name| environment.fetch(name) }.uniq.size != SECRETS.size
        raise ArgumentError, "Production secrets must be different for each purpose."
      end
      true
    rescue URI::InvalidURIError
      raise ArgumentError, "MESH_PUBLIC_ORIGIN is not a valid HTTPS origin."
    end
  end
end
