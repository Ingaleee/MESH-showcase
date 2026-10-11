class HttpMetrics
  BUCKETS = [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 ].freeze
  MUTEX = Mutex.new
  SERIES = {}

  def self.observe(payload, elapsed)
    controller = payload[:controller].to_s
    return unless controller.start_with?("Api::") || controller == "PublishingCallbacksController"
    action = payload[:action].to_s
    route = "#{controller}##{action}"
    method = %w[GET POST PATCH PUT DELETE HEAD OPTIONS].include?(payload[:method]) ? payload[:method] : "OTHER"
    status = (payload[:status] || (payload[:exception] ? 500 : 200)).to_i / 100
    outcome = [ 2, 3, 4, 5 ].include?(status) ? "#{status}xx" : "other"
    MUTEX.synchronize do
      # Controller/action names come from Rails, never from user paths or IDs.
      route = "other" if SERIES.length >= 200 && !SERIES.key?([ route, method ])
      row = SERIES[[ route, method ]] ||= { count: 0, total: 0.0, buckets: BUCKETS.to_h { |bound| [ bound, 0 ] }, outcomes: Hash.new(0) }
      row[:count] += 1
      row[:total] += elapsed
      row[:outcomes][outcome] += 1
      BUCKETS.each { |bound| row[:buckets][bound] += 1 if elapsed <= bound }
    end
  end

  def self.prometheus
    MUTEX.synchronize do
      lines = [ "# TYPE mesh_http_request_seconds histogram", "# TYPE mesh_http_responses_total counter" ]
      SERIES.each do |(route, method), row|
        labels = "route=\"#{route}\",method=\"#{method}\""
        BUCKETS.each { |bound| lines << "mesh_http_request_seconds_bucket{#{labels},le=\"#{bound}\"} #{row[:buckets][bound]}" }
        lines << "mesh_http_request_seconds_bucket{#{labels},le=\"+Inf\"} #{row[:count]}"
        lines << "mesh_http_request_seconds_sum{#{labels}} #{row[:total]}"
        lines << "mesh_http_request_seconds_count{#{labels}} #{row[:count]}"
        row[:outcomes].each { |outcome, count| lines << "mesh_http_responses_total{#{labels},outcome=\"#{outcome}\"} #{count}" }
      end
      lines.join("\n") + "\n"
    end
  end
end
