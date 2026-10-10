require "digest"

module Publishing
  class Settings
    POLICY = "publishing-v1".freeze
    ARTIFACT_LIMIT = 2_000_000
    EXPANDED_LIMIT = 2_000_000
    ENTRY_LIMIT = 16

    def self.authorize!(actor, partner = nil)
      unless actor&.operator? && (!partner || partner.owner_id == actor.id)
        raise Platform::Error.new("FORBIDDEN", "Publishing requires the owning operator.", status: 403)
      end
    end

    def self.origin!(origin)
      allowed = ENV.fetch("MESH_PARTNER_ORIGINS", "").split(",")
      raise Platform::Error.new("PARTNER_ORIGIN_DENIED", "Choose an administrator-approved partner origin.") unless allowed.include?(origin)
      Platform::HttpClient.new(origin: origin, allow_http: http_allowed?(origin))
      origin
    rescue Platform::HttpClient::Failure => error
      raise Platform::Error.new(error.code, "Partner origin is not permitted.")
    end

    def self.http_allowed?(origin)
      ENV.fetch("MESH_PARTNER_HTTP_ORIGINS", "").split(",").include?(origin)
    end

    def self.token(partner)
      refs = ENV.fetch("MESH_PARTNER_CREDENTIAL_REFS", "SHOWCASE").split(",")
      unless refs.include?(partner.credential_ref)
        raise Platform::Error.new("PARTNER_CREDENTIAL_UNAVAILABLE", "Configure the approved credential reference.", status: 503)
      end
      ENV.fetch("MESH_PARTNER_TOKEN_#{partner.credential_ref}")
    rescue KeyError
      raise Platform::Error.new("PARTNER_CREDENTIAL_UNAVAILABLE", "Partner credential is unavailable.", status: 503)
    end

    def self.policy_version
      ENV.fetch("MESH_PUBLISHING_POLICY_VERSION", POLICY)
    end

    def self.trust_fingerprint
      file = ENV["MESH_PARTNER_CA_FILE"]
      file ? Digest::SHA256.file(file).hexdigest : "system-trust-store"
    rescue SystemCallError
      raise Platform::Error.new("PARTNER_TRUST_UNAVAILABLE", "Configured trust bundle is unavailable.", status: 503)
    end

    def self.fingerprint(candidate)
      partner = candidate.partner
      input = {
        artifact: candidate.artifact_sha256, manifest: candidate.manifest_sha256,
        contract: partner.contract_version, origin: partner.origin, policy: policy_version,
        approved_origins: ENV.fetch("MESH_PARTNER_ORIGINS", ""), http_origins: ENV.fetch("MESH_PARTNER_HTTP_ORIGINS", ""),
        credential: token(partner), trust: trust_fingerprint, generation: ENV.fetch("MESH_PUBLISHING_ENVIRONMENT_GENERATION", "local-v1")
      }
      Digest::SHA256.hexdigest(JSON.generate(Platform::Idempotency.canonicalize(input)))
    end
  end
end
