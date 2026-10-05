ENV["OTEL_TRACES_EXPORTER"] ||= "none"
ENV["OTEL_SERVICE_NAME"] ||= "mesh-api"
OpenTelemetry::SDK.configure do |config|
  config.use "OpenTelemetry::Instrumentation::Rails"
  config.use "OpenTelemetry::Instrumentation::Rack"
  config.use "OpenTelemetry::Instrumentation::ActionPack"
  config.use "OpenTelemetry::Instrumentation::ActiveJob"
  config.use "OpenTelemetry::Instrumentation::PG"
end
