module Finance
  class SandboxGateway
    class Unavailable < StandardError; end

    def execute(operation)
      request(:post, "/operations", { key: operation.id, kind: operation.kind, amount_minor: operation.amount_minor, currency: operation.currency, scenario: operation.scenario })
    end

    def lookup(operation_id)
      request(:get, "/operations/#{operation_id}")
    end

    private

    def request(method, path, data = nil)
      origin = ENV.fetch("MESH_GATEWAY_URL", "http://localhost:3202")
      http = Platform::HttpClient.new(origin: origin, allow_http: URI(origin).scheme == "http")
      result = http.request(method: method, path: path, body: data, token: ENV.fetch("MESH_GATEWAY_SECRET"), statuses: [ 200, 404 ])
      return nil if result.status == 404
      raise Unavailable, "HTTP_SCHEMA_INVALID" unless result.body["key"].is_a?(String) && %w[confirmed failed].include?(result.body["state"])
      result.body
    rescue Platform::HttpClient::Failure => error
      raise Unavailable, error.code
    end
  end
end
