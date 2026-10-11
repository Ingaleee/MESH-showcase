require "rails_helper"

RSpec.describe Talent::FileScanner do
  def with_scanner_response(reply)
    server = TCPServer.new("127.0.0.1", 0)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MESH_CLAMAV_HOST", "scanner").and_return("127.0.0.1")
    allow(ENV).to receive(:fetch).with("MESH_CLAMAV_PORT", "3310").and_return(server.addr[1].to_s)
    wire = { payload: "".b, chunks: [] }
    reader = Thread.new do
      socket = server.accept
      wire[:command] = socket.gets("\0")
      loop do
        length = socket.read(4).unpack1("N")
        break if length.zero?

        wire[:chunks] << length
        wire[:payload] << socket.read(length)
      end
      socket.write(reply)
    ensure
      socket&.close
    end
    yield wire
  ensure
    server&.close
    if reader
      raise "Scanner fixture did not finish." unless reader.join(2)

      reader.value
    end
  end

  it "streams binary content in bounded network-order frames and recognizes a complete clean reply" do
    bytes = ("\0\xFF".b * 40_000)
    with_scanner_response("stream: OK\0") do |wire|
      expect(described_class.scan(bytes)).to eq(:clean)
      expect(wire[:command]).to eq("zINSTREAM\0")
      expect(wire[:payload]).to eq(bytes)
      expect(wire[:chunks]).to eq([ 65536, 14464 ])
    end
  end

  it "does not confuse a detected signature named OK with a clean result" do
    with_scanner_response("stream: OK FOUND\0") do
      expect(described_class.scan("content")).to eq(:infected)
    end
  end

  it "fails closed on truncated replies, unknown responses and scanner errors" do
    [ "stream: OK", "unknown OK\0", "stream: Access denied ERROR\0", "" ].each do |reply|
      with_scanner_response(reply) do
        expect { described_class.scan("content") }.to raise_error(described_class::Unavailable)
      end
    end
  end
end
