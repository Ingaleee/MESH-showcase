module Publishing
  class PartnerGateway
    def contract(partner)
      request(partner, :get, "/contract").body
    end

    def publish(deployment, bytes)
      request(deployment.partner, :post, "/deployments", {
        operation_id: deployment.id, partner_id: deployment.partner_id, candidate_id: deployment.candidate_id,
        artifact_sha256: deployment.candidate.artifact_sha256, contract_version: deployment.partner.contract_version,
        manifest: deployment.candidate.manifest, artifact_base64: Base64.strict_encode64(bytes),
        scenario: deployment.scenario, kind: deployment.kind
      }, request_id: deployment.correlation_id).body
    end

    def lookup(deployment)
      response = request(deployment.partner, :get, "/deployments/#{deployment.id}", statuses: [ 200, 404 ], request_id: deployment.correlation_id)
      response.status == 404 ? nil : response.body
    end

    private

    def request(partner, method, path, body = nil, statuses: [ 200 ], request_id: nil)
      Settings.origin!(partner.origin)
      client = Platform::HttpClient.new(
        origin: partner.origin, allow_http: Settings.http_allowed?(partner.origin),
        ca_file: ENV["MESH_PARTNER_CA_FILE"], deadline: 5
      )
      client.request(method: method, path: path, body: body, token: Settings.token(partner), statuses: statuses, request_id: request_id)
    end
  end
end
