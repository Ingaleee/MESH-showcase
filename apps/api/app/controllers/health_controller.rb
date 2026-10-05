class HealthController < ActionController::Base
  def ready
    response.headers["Cache-Control"] = "no-store"
    Platform::Record.connection_pool.with_connection do |connection|
      connection.transaction(requires_new: true) do
        connection.execute("SET LOCAL statement_timeout = '1000ms'")
        connection.select_value("SELECT 1")
      end
    end
    render json: { status: "ready" }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn(JSON.generate(event: "readiness.unavailable", error: error.class.name))
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
