require "net/http"
require "openssl"
require "json"
require "timeout"

module Platform
  class HttpClient
    class Failure < StandardError
      attr_reader :code, :status

      def initialize(code, status: nil)
        @code, @status = code, status
        super(code)
      end
    end

    Response = Data.define(:status, :body, :headers)
    class DeadlineExceeded < StandardError; end

    def initialize(origin:, allow_http: false, ca_file: nil, deadline: 5, timeout: 2, response_limit: 65_536, request_limit: 3_000_000)
      @origin = URI(origin)
      unless %w[http https].include?(@origin.scheme) && @origin.host && !@origin.userinfo &&
          [ "", "/" ].include?(@origin.path) && !@origin.query && !@origin.fragment
        raise Failure.new("HTTP_ORIGIN_INVALID")
      end
      raise Failure.new("HTTPS_REQUIRED") if @origin.scheme == "http" && !allow_http
      @ca_file, @deadline, @timeout = ca_file, Float(deadline), Float(timeout)
      @response_limit, @request_limit = Integer(response_limit), Integer(request_limit)
      raise ArgumentError unless @deadline.positive? && @timeout.positive? && @response_limit.positive? && @request_limit.positive?
    rescue URI::InvalidURIError
      raise Failure.new("HTTP_ORIGIN_INVALID")
    end

    def request(method:, path:, token: nil, body: nil, raw_body: nil, content_type: "application/json", headers: {}, statuses: [ 200 ], request_id: nil)
      unless %i[get post].include?(method) && path.match?(/\A\/[A-Za-z0-9_\/.\-]+\z/) && !path.start_with?("//") && !path.include?("..")
        raise Failure.new("HTTP_PATH_INVALID")
      end
      raise Failure.new("HTTP_CREDENTIAL_INVALID") if token && (!token.is_a?(String) || token.blank? || token.match?(/[\r\n]/))
      uri = @origin.dup
      uri.path = path
      request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      request["Accept"] = "application/json"
      request["Accept-Encoding"] = "identity"
      request["Content-Type"] = content_type
      request["Authorization"] = "Bearer #{token}" if token
      headers.each do |name, value|
        unless %w[Cookie X-CSRF-Token Idempotency-Key X-Request-ID].include?(name) && value.is_a?(String) && value.bytesize <= 4096 && !value.match?(/[\r\n]/)
          raise Failure.new("HTTP_HEADER_INVALID")
        end
        request[name] = value unless value.empty?
      end
      request["X-Request-ID"] = request_id if request_id.to_s.match?(/\A[a-zA-Z0-9\-]{1,100}\z/)
      request.body = raw_body || (body.nil? ? nil : JSON.generate(body))
      raise Failure.new("HTTP_REQUEST_TOO_LARGE") if request.body.to_s.bytesize > @request_limit

      # This isolated I/O block owns the timeout; no database transaction surrounds it.
      Timeout.timeout(@deadline, DeadlineExceeded) do
        http = Net::HTTP.new(uri.hostname, uri.port, nil)
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = @ca_file if @ca_file
        http.open_timeout = http.read_timeout = http.write_timeout = @timeout
        http.max_retries = 0
        result = nil
        http.start do
          http.request(request) do |response|
            status = response.code.to_i
            raise Failure.new("HTTP_STATUS_UNEXPECTED", status: status) unless statuses.include?(status)
            return Response.new(status: status, body: nil, headers: {}) if status == 404
            if response["content-length"] && Integer(response["content-length"], exception: false).to_i > @response_limit
              raise Failure.new("HTTP_RESPONSE_TOO_LARGE")
            end
            unless response["content-type"].to_s.split(";", 2).first.to_s.strip.downcase == "application/json"
              raise Failure.new("HTTP_CONTENT_TYPE_INVALID")
            end
            unless [ nil, "", "identity" ].include?(response["content-encoding"])
              raise Failure.new("HTTP_ENCODING_UNSUPPORTED")
            end
            bytes = +"".b
            response.read_body do |chunk|
              raise Failure.new("HTTP_RESPONSE_TOO_LARGE") if bytes.bytesize + chunk.bytesize > @response_limit
              bytes << chunk
            end
            parsed = JSON.parse(bytes, max_nesting: 20, allow_nan: false)
            raise Failure.new("HTTP_SCHEMA_INVALID") unless parsed.is_a?(Hash)
            result = Response.new(status: status, body: parsed, headers: { "set-cookie" => response.get_fields("set-cookie") || [] })
          end
        end
        result
      end
    rescue DeadlineExceeded, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error
      raise Failure.new("HTTP_TIMEOUT"), cause: nil
    rescue OpenSSL::SSL::SSLError
      raise Failure.new("HTTP_TLS_FAILED"), cause: nil
    rescue JSON::ParserError, JSON::NestingError
      raise Failure.new("HTTP_JSON_INVALID"), cause: nil
    rescue SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse
      raise Failure.new("HTTP_CONNECTION_FAILED"), cause: nil
    end
  end
end
