module Platform
  class Metrics
    NAMES = %w[notification_delivery validation_completion].freeze
    BUCKETS = [ 0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60 ].freeze

    def self.observe(name, seconds)
      raise ArgumentError unless NAMES.include?(name) && seconds.finite?
      value = [ seconds, 0 ].max
      connection = Record.connection
      raise "durable observations require the effect transaction" unless connection.transaction_open?
      buckets = BUCKETS.to_h { |bound| [ bound.to_s, value <= bound ? 1 : 0 ] }
      json = connection.quote(JSON.generate(buckets))
      additions = BUCKETS.map { |bound|
        key = connection.quote(bound.to_s)
        "#{key}, COALESCE((platform_metric_totals.buckets->>#{key})::bigint, 0) + (EXCLUDED.buckets->>#{key})::bigint"
      }.join(", ")
      connection.execute(<<~SQL)
        INSERT INTO platform_metric_totals (name, observations, total_seconds, buckets, updated_at)
        VALUES (#{connection.quote(name)}, 1, #{connection.quote(value)}, #{json}::jsonb, CURRENT_TIMESTAMP)
        ON CONFLICT (name) DO UPDATE SET observations = platform_metric_totals.observations + 1,
          total_seconds = platform_metric_totals.total_seconds + EXCLUDED.total_seconds,
          buckets = jsonb_build_object(#{additions}), updated_at = CURRENT_TIMESTAMP
      SQL
    end

    def self.snapshot
      Record.connection.select_all("SELECT name, observations, total_seconds, buckets FROM platform_metric_totals").to_a
    end

    def self.prometheus
      snapshot.to_h { |row| [ row["name"], row ] }.then do |rows|
        NAMES.map do |name|
          row = rows[name] || { "observations" => 0, "total_seconds" => 0, "buckets" => {} }
          buckets = row["buckets"].is_a?(String) ? JSON.parse(row["buckets"]) : row["buckets"]
          metric = "mesh_#{name}_seconds"
          lines = [ "# TYPE #{metric} histogram" ]
          BUCKETS.each { |bound| lines << "#{metric}_bucket{le=\"#{bound}\"} #{buckets.fetch(bound.to_s, 0)}" }
          lines << "#{metric}_bucket{le=\"+Inf\"} #{row['observations']}"
          lines << "#{metric}_sum #{row['total_seconds']}"
          lines << "#{metric}_count #{row['observations']}"
          lines.join("\n") + "\n"
        end.join
      end
    end
  end
end
