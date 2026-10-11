class QueueMetrics
  QUEUES = %w[critical events files default].freeze

  def self.snapshot
    SolidQueue::Record.connection_pool.with_connection do |connection|
      connection.transaction(requires_new: true) do
        connection.execute("SET LOCAL statement_timeout = '1000ms'")
        rows = connection.select_all(<<~SQL).to_a
          SELECT jobs.queue_name, 'ready' AS state, COUNT(*) AS count,
            EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - MIN(executions.created_at)) AS oldest_seconds
          FROM solid_queue_ready_executions executions JOIN solid_queue_jobs jobs ON jobs.id = executions.job_id
          GROUP BY jobs.queue_name
          UNION ALL
          SELECT jobs.queue_name, 'claimed', COUNT(*), 0
          FROM solid_queue_claimed_executions executions JOIN solid_queue_jobs jobs ON jobs.id = executions.job_id
          GROUP BY jobs.queue_name
          UNION ALL
          SELECT jobs.queue_name, 'failed', COUNT(*), 0
          FROM solid_queue_failed_executions executions JOIN solid_queue_jobs jobs ON jobs.id = executions.job_id
          GROUP BY jobs.queue_name
          UNION ALL
          SELECT jobs.queue_name, 'scheduled', COUNT(*), 0
          FROM solid_queue_scheduled_executions executions JOIN solid_queue_jobs jobs ON jobs.id = executions.job_id
          GROUP BY jobs.queue_name
        SQL
        workers = connection.select_value("SELECT COUNT(*) FROM solid_queue_processes WHERE kind = 'Worker' AND last_heartbeat_at > CURRENT_TIMESTAMP - INTERVAL '90 seconds'")
        { available: true, workers: workers.to_i, rows: rows }
      end
    end
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn(JSON.generate(event: "queue_metrics.unavailable", error: error.class.name))
    { available: false }
  end

  def self.prometheus
    data = snapshot
    lines = [ "# TYPE mesh_queue_up gauge", "mesh_queue_up #{data[:available] ? 1 : 0}" ]
    return lines.join("\n") + "\n" unless data[:available]

    lines += [ "# TYPE mesh_queue_workers gauge", "mesh_queue_workers #{data[:workers]}" ]
    %w[ready claimed failed scheduled].each do |state|
      name = "mesh_queue_#{state}"
      lines << "# TYPE #{name} gauge"
      QUEUES.each do |queue|
        count = data[:rows].find { |row| row["queue_name"] == queue && row["state"] == state }&.fetch("count", 0).to_i
        lines << "#{name}{queue=\"#{queue}\"} #{count}"
      end
    end
    lines << "# TYPE mesh_queue_oldest_ready_seconds gauge"
    QUEUES.each do |queue|
      age = data[:rows].find { |row| row["queue_name"] == queue && row["state"] == "ready" }&.fetch("oldest_seconds", 0).to_f
      lines << "mesh_queue_oldest_ready_seconds{queue=\"#{queue}\"} #{[ age, 0 ].max.round(3)}"
    end
    lines.join("\n") + "\n"
  end
end
