require "stringio"

class PublishingRequestBudget
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"].start_with?("/api/v1/publishing") && env["REQUEST_METHOD"] == "POST"
      limit = env["PATH_INFO"].include?("/callbacks/") ? 65_536 : 2_100_000
      length = env["CONTENT_LENGTH"].to_s
      return reject(411, "CONTENT_LENGTH_REQUIRED") unless length.match?(/\A\d+\z/)
      return reject(413, "PACKAGE_LIMIT") if length.to_i > limit
      input = env.fetch("rack.input")
      input.rewind if input.respond_to?(:rewind)
      bytes = input.read(limit + 1).to_s
      return reject(413, "PACKAGE_LIMIT") if bytes.bytesize > limit
      return reject(400, "CONTENT_LENGTH_MISMATCH") unless bytes.bytesize == length.to_i
      env["rack.input"] = StringIO.new(bytes)
    end
    @app.call(env)
  end

  private

  def reject(status, code)
    [ status, { "content-type" => "application/json", "cache-control" => "no-store" }, [ JSON.generate(code: code, message: "Request exceeds the publishing boundary.") ] ]
  end
end
