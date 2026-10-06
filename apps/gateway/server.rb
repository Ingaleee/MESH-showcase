require "json"
require "pg"
require "digest"
require "securerandom"
require "rack"

class MeshGateway
  def initialize
    connection do |database|
      database.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS operations (
          id text PRIMARY KEY, key text NOT NULL UNIQUE, fingerprint text NOT NULL,
          kind text NOT NULL, amount_minor bigint NOT NULL, currency text NOT NULL,
          state text NOT NULL, post_attempts integer NOT NULL DEFAULT 0,
          created_at timestamptz NOT NULL DEFAULT now()
        )
      SQL
    end
  end

  def call(environment)
    request = Rack::Request.new(environment)
    return json(200, { ready: true }) if request.path == "/health"
    unless request.get_header("HTTP_AUTHORIZATION") == "Bearer #{ENV.fetch('MESH_GATEWAY_SECRET')}"
      return json(401, { code: "UNAUTHORIZED" })
    end
    return create(request) if request.post? && request.path == "/operations"
    return show(request.path.split("/").last) if request.get? && request.path.start_with?("/operations/")

    json(404, { code: "NOT_FOUND" })
  rescue JSON::ParserError, KeyError, ArgumentError
    json(400, { code: "INVALID_INPUT" })
  end

  private

  def create(request)
    input = JSON.parse(request.body.read(8192))
    key = input.fetch("key")
    amount = Integer(input.fetch("amount_minor"))
    currency = input.fetch("currency")
    kind = input.fetch("kind")
    unless key.match?(/\A[0-9a-f-]{36}\z/) && amount.positive? && %w[fund payout].include?(kind) && %w[RUB USD EUR JPY].include?(currency)
      return json(400, { code: "INVALID_INPUT" })
    end
    fingerprint = Digest::SHA256.hexdigest(JSON.generate([kind, amount, currency]))
    row = nil
    conflict = false
    connection do |database|
      database.transaction do
        state = input["scenario"] == "decline" ? "failed" : "confirmed"
        database.exec_params(
          "INSERT INTO operations (id,key,fingerprint,kind,amount_minor,currency,state) VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (key) DO NOTHING",
          ["gw_#{SecureRandom.uuid}", key, fingerprint, kind, amount, currency, state]
        )
        row = database.exec_params("SELECT * FROM operations WHERE key=$1 FOR UPDATE", [key]).first
        conflict = row.fetch("fingerprint") != fingerprint
        row = database.exec_params("UPDATE operations SET post_attempts = post_attempts + 1 WHERE key=$1 RETURNING *", [key]).first
      end
    end
    return json(409, { code: "IDEMPOTENCY_CONFLICT" }) if conflict

    sleep 4 if input["scenario"] == "timeout_after_success"
    json(200, present(row))
  end

  def show(key)
    row = connection { |database| database.exec_params("SELECT * FROM operations WHERE key=$1", [key]).first }
    row ? json(200, present(row)) : json(404, { code: "NOT_FOUND" })
  end

  def present(row)
    row.slice("id", "key", "kind", "currency", "state").merge(
      "amount_minor" => row.fetch("amount_minor").to_i,
      "post_attempts" => row.fetch("post_attempts").to_i
    )
  end

  def connection
    database = PG.connect(ENV.fetch("GATEWAY_DATABASE_URL"))
    yield database
  ensure
    database&.close
  end

  def json(status, body)
    [status, { "content-type" => "application/json" }, [JSON.generate(body)]]
  end
end
