class UserOutcomeMetrics
  WINDOW_SECONDS = 86_400
  OBJECTIVES = { "notification" => { deadline: 30 }.freeze, "validation" => { deadline: 60 }.freeze, "deployment" => { deadline: 120 }.freeze }.freeze
  FIELDS = %w[total good unfinished failed overdue oldest_seconds].freeze
  QUERY = <<~SQL.freeze
    WITH accepted AS (
      SELECT 'notification' AS operation, created_at, processed_at AS completed_at,
        state = 'processed' AS finished, state = 'failed' AS failed, :notification_deadline AS deadline
      FROM platform_deliveries WHERE consumer = 'notifications'
      UNION ALL
      SELECT 'validation', created_at, completed_at, state IN ('passed','rejected'), state = 'failed', :validation_deadline
      FROM publishing_validations
      UNION ALL
      SELECT 'deployment', created_at, confirmed_at, state = 'confirmed', state = 'failed', :deployment_deadline
      FROM publishing_deployments
    )
    SELECT operation,
      COUNT(*) FILTER (WHERE created_at >= :lower AND created_at <= CAST(:now AS timestamp) - deadline * INTERVAL '1 second') AS total,
      COUNT(*) FILTER (WHERE created_at >= :lower AND created_at <= CAST(:now AS timestamp) - deadline * INTERVAL '1 second'
        AND finished AND completed_at <= created_at + deadline * INTERVAL '1 second') AS good,
      COUNT(*) FILTER (WHERE NOT finished AND NOT failed) AS unfinished,
      COUNT(*) FILTER (WHERE failed) AS failed,
      COUNT(*) FILTER (WHERE NOT finished AND created_at < CAST(:now AS timestamp) - deadline * INTERVAL '1 second') AS overdue,
      COALESCE(EXTRACT(EPOCH FROM CAST(:now AS timestamp) - MIN(created_at) FILTER (WHERE NOT finished AND NOT failed)),0) AS oldest_seconds
    FROM accepted GROUP BY operation
  SQL

  def self.snapshot(now: Time.current)
    values = OBJECTIVES.to_h { |name, config| [ :"#{name}_deadline", config.fetch(:deadline) ] }.merge(now: now, lower: now - WINDOW_SECONDS)
    sql = Platform::Record.sanitize_sql_array([ QUERY, values ])
    connection = Platform::Record.connection
    rows = connection.transaction(requires_new: true) do
      connection.execute("SET LOCAL statement_timeout = '1000ms'")
      connection.select_all(sql).to_a.index_by { |row| row.fetch("operation") }
    end
    OBJECTIVES.to_h do |name, _|
      row = rows.fetch(name, {})
      [ name, FIELDS.to_h { |field| [ field, row.fetch(field, 0).to_f ] } ]
    end
  end

  def self.prometheus
    data = snapshot
    lines = [ "# TYPE mesh_user_sli_up gauge", "mesh_user_sli_up 1" ]
    FIELDS.each do |field|
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
