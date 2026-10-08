require "openssl"
require "fileutils"

# Streaming authenticated encryption. Nothing is extracted before GCM authentication succeeds.
module RecoveryArchive
  MAGIC = "MESHBAK1".b.freeze

  def self.encrypt(source, target, key:)
    raise ArgumentError, "Use a 32-byte recovery key" unless key.bytesize == 32
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key
    iv = cipher.random_iv
    cipher.auth_data = MAGIC
    File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
      output.binmode
      output.write(MAGIC + iv)
      File.open(source, "rb") do |input|
        while (chunk = input.read(65536))
          output.write(cipher.update(chunk))
        end
      end
      output.write(cipher.final + cipher.auth_tag)
      output.flush
      output.fsync
    end
  end

  def self.decrypt(source, target, key:)
    raise ArgumentError, "Use a 32-byte recovery key" unless key.bytesize == 32
    created = false
    target = target.to_s
    temporary = target + ".partial"
    raise "Refuse an existing recovery target" if File.exist?(target) || File.exist?(temporary)
    File.open(source, "rb") do |input|
      raise "Invalid backup format" unless input.read(8) == MAGIC && input.size >= 36
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = input.read(12)
      input.seek(-16, IO::SEEK_END)
      cipher.auth_tag = input.read(16)
      cipher.auth_data = MAGIC
      input.seek(20)
      remaining = input.size - 36
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
        created = true
        output.binmode
        while remaining.positive?
          chunk = input.read([ remaining, 65536 ].min)
          remaining -= chunk.bytesize
          output.write(cipher.update(chunk))
        end
        output.write(cipher.final)
        output.flush
        output.fsync
      end
    end
    File.rename(temporary, target)
  ensure
    File.delete(temporary) if created && temporary && File.exist?(temporary)
  end
end
