require "json"
require "thread"

# Bound application processing before reading request bodies. Limits are per Puma process.
class RequestAdmission
  MUTEX = Mutex.new
  STATS = { active: 0, rejected: 0 }

  def initialize(app, limit: nil)
    @app = app
    threads = Integer(ENV.fetch("RAILS_MAX_THREADS", 3))
    @limit = limit || Integer(ENV.fetch("MESH_API_CONCURRENCY", [ threads - 1, 1 ].max))
    raise ArgumentError, "Reserve a Puma thread for health and admission" unless @limit.positive? && @limit < threads
  end

  def call(env)
    return @app.call(env) unless env["PATH_INFO"].start_with?("/api/v1/")
    admitted = MUTEX.synchronize do
      if STATS[:active] >= @limit
        STATS[:rejected] += 1
        false
      else
        STATS[:active] += 1
        true
      end
    end
    unless admitted
      return [ 429, { "content-type" => "application/json", "cache-control" => "no-store", "retry-after" => "1" },
        [ JSON.generate(code: "CAPACITY_LIMIT", message: "Retry later using the same request key.") ] ]
    end
    begin
      @app.call(env)
    ensure
      MUTEX.synchronize { STATS[:active] -= 1 }
    end
  end

  def self.prometheus
    MUTEX.synchronize do
      "# TYPE mesh_api_admission_active gauge\nmesh_api_admission_active #{STATS[:active]}\n" \
        "# TYPE mesh_api_admission_rejected_total counter\nmesh_api_admission_rejected_total #{STATS[:rejected]}\n"
    end
  end
end
