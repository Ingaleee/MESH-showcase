require "socket"
require "timeout"
module Talent
  class FileScanner
    class Unavailable < StandardError; end

    def self.scan(bytes)
      host = ENV.fetch("MESH_CLAMAV_HOST", "scanner")
      port = Integer(ENV.fetch("MESH_CLAMAV_PORT", "3310"))
      response = Timeout.timeout(10) do
        Socket.tcp(host, port, connect_timeout: 3) do |socket|
          socket.write("zINSTREAM\0")
          offset = 0
          while offset < bytes.bytesize
            content = bytes.byteslice(offset, 65536)
            socket.write([ content.bytesize ].pack("N"))
            socket.write(content)
            offset += content.bytesize
          end
          socket.write([ 0 ].pack("N"))
          socket.gets("\0", 4096).to_s
        end
      end
      return :clean if response == "stream: OK\0"
      return :infected if response.match?(/\Astream: [^\0\r\n]+ FOUND\0\z/)

      raise Unavailable, "scanner returned an unsupported result"
    rescue SocketError, SystemCallError, Timeout::Error => error
      raise Unavailable, error.class.name
    end
  end
end
