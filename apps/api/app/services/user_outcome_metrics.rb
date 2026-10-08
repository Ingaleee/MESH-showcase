class UserOutcomeMetrics
  WINDOW_SECONDS = 86_400
  OBJECTIVES = {
    "notification" => { table: "platform_deliveries", completion: "processed_at", finished: %w[processed], deadline: 30, filter: "consumer = 'notifications'" },
    "validation" => { table: "publishing_validations", completion: "completed_at", finished: %w[passed rejected], deadline: 60, filter: "TRUE" },
    "deployment" => { table: "publishing_deployments", completion: "confirmed_at", finished: %w[confirmed], deadline: 120, filter: "TRUE" }
  }.freeze

  def self.snapshot(now: Time.current)
    connection = Platform::Record.connection
    connection.transaction(requires_new: true) do
      connection.execute("SET LOCAL statement_timeout = '1000ms'")
      OBJECTIVES.to_h do |name, config|
        current = connection.quote(now)
        lower = connection.quote(now - WINDOW_SECONDS)
        mature = connection.quote(now - config.fetch(:deadline))
        finished = config.fetch(:finished).map { |state| connection.quote(state) }.join(",")
        duration = config.fetch(:deadline)
        table = connection.quote_table_name(config.fetch(:table))
        completed = connection.quote_column_name(config.fetch(:completion))
        row = connection.select_one(<<~SQL)
          SELECT
            COUNT(*) FILTER (WHERE created_at >= #{lower} AND created_at <= #{mature}) AS total,
            COUNT(*) FILTER (WHERE created_at >= #{lower} AND created_at <= #{mature}
              AND state IN (#{finished}) AND #{completed} <= created_at + INTERVAL '#{duration} seconds') AS good,
            COUNT(*) FILTER (WHERE state NOT IN (#{finished}) AND state <> 'failed') AS unfinished,
            COUNT(*) FILTER (WHERE state = 'failed') AS failed,
            COUNT(*) FILTER (WHERE state NOT IN (#{finished}) AND created_at < #{mature}) AS overdue,
            COALESCE(EXTRACT(EPOCH FROM #{current}::timestamp - MIN(created_at) FILTER (WHERE state NOT IN (#{finished}) AND state <> 'failed')),0) AS oldest_seconds
          FROM #{table} WHERE #{config.fetch(:filter)}
        SQL
        [ name, row.transform_values { |value| value.to_f } ]
      end
    end
  end

  def self.prometheus
    data = snapshot
    names = %w[total good unfinished failed overdue oldest_seconds]
    lines = [ "# TYPE mesh_user_sli_up gauge", "mesh_user_sli_up 1" ]
    names.each do |field|
      lines << "# TYPE mesh_user_sli_#{field} gauge"
      data.each { |name, row| lines << "mesh_user_sli_#{field}{operation=\"#{name}\"} #{[ row.fetch(field), 0 ].max}" }
    end
    lines << "# TYPE mesh_user_sli_deadline_seconds gauge"
    OBJECTIVES.each { |name, config| lines << "mesh_user_sli_deadline_seconds{operation=\"#{name}\"} #{config.fetch(:deadline)}" }
    lines << "# TYPE mesh_user_sli_window_seconds gauge"
    lines << "mesh_user_sli_window_seconds #{WINDOW_SECONDS}"
    lines.join("\n") + "\n"
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn(JSON.generate(event: "user_sli.unavailable", error: error.class.name))
    "# TYPE mesh_user_sli_up gauge\nmesh_user_sli_up 0\n"
  end
end
