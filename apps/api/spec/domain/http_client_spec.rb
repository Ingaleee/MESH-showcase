require "rails_helper"
require "tempfile"

RSpec.describe Platform::HttpClient do
  def serve(response:, slow: false, tls: false, certificate: nil, key: nil)
    tcp = TCPServer.new("127.0.0.1", 0)
    listener = tcp
    if tls
      context = OpenSSL::SSL::SSLContext.new
      context.cert, context.key = certificate, key
      listener = OpenSSL::SSL::SSLServer.new(tcp, context)
    end
    thread = Thread.new do
      socket = listener.accept
      request = +""
      while (line = socket.gets)
        request << line
        break if request.end_with?("\r\n\r\n")
      end
      if slow
        response.each_byte { |byte| socket.write(byte.chr); sleep 0.015 }
      else
        socket.write(response)
      end
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    ensure
      socket&.close
    end
    yield "#{tls ? 'https' : 'http'}://localhost:#{tcp.addr[1]}"
  ensure
    tcp&.close
    thread&.join(1)
    thread&.kill if thread&.alive?
  end

  def reply(body, type: "application/json", status: "200 OK", headers: "")
    "HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n#{headers}\r\n#{body}"
  end

  def get(origin, **options)
    described_class.new(origin: origin, allow_http: true, **options).request(method: :get, path: "/contract", token: "local-fixture-only")
  end

  it "streams within a byte budget and returns validated JSON without following redirects" do
    serve(response: reply('{"ready":true}')) { |origin| expect(get(origin).body).to eq("ready" => true) }
    serve(response: reply('{}', status: "302 Found", headers: "Location: http://invalid.example/\r\n")) do |origin|
      expect { get(origin) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq("HTTP_STATUS_UNEXPECTED") }
    end
  end

  it "rejects oversized, malformed, nested and wrongly typed bodies" do
    [
      [ reply('{"padding":"' + "a" * 500 + '"}'), "HTTP_RESPONSE_TOO_LARGE" ],
      [ reply("broken"), "HTTP_JSON_INVALID" ],
      [ reply('{"ready":true}', type: "text/html"), "HTTP_CONTENT_TYPE_INVALID" ],
      [ reply("[]"), "HTTP_SCHEMA_INVALID" ],
      [ reply('{"a":' * 25 + "0" + "}" * 25), "HTTP_RESPONSE_TOO_LARGE" ]
    ].each do |response, code|
      serve(response: response) do |origin|
        expect { get(origin, response_limit: 100) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq(code) }
      end
    end
    serve(response: reply('{"a":' * 25 + "0" + "}" * 25)) do |origin|
      expect { get(origin) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq("HTTP_JSON_INVALID") }
    end
  end

  it "enforces a whole-operation deadline even when each read makes progress" do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    serve(response: reply('{"ready":true}'), slow: true) do |origin|
      expect { get(origin, deadline: 0.2, timeout: 0.1) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq("HTTP_TIMEOUT") }
    end
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 1.2
  end

  it "validates the TLS certificate and hostname using an explicit trust root" do
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version, cert.serial = 2, 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=localhost")
    cert.public_key = key.public_key
    cert.not_before, cert.not_after = Time.now - 60, Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new
    extensions.subject_certificate = extensions.issuer_certificate = cert
    cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(extensions.create_extension("subjectAltName", "DNS:localhost"))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    serve(response: reply('{"ready":true}'), tls: true, certificate: cert, key: key) do |origin|
      expect { get(origin) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq("HTTP_TLS_FAILED") }
    end
    Tempfile.create("mesh-fixture-ca") do |file|
      file.write(cert.to_pem); file.flush
      serve(response: reply('{"ready":true}'), tls: true, certificate: cert, key: key) do |origin|
        expect(get(origin, ca_file: file.path).body).to eq("ready" => true)
      end
      serve(response: reply('{"ready":true}'), tls: true, certificate: cert, key: key) do |origin|
        expect { get(origin.sub("localhost", "127.0.0.1"), ca_file: file.path) }.to raise_error(described_class::Failure) { |error| expect(error.code).to eq("HTTP_TLS_FAILED") }
      end
    end
  end
end
