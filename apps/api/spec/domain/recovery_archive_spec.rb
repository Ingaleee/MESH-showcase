require "rails_helper"
require_relative "../../lib/recovery_archive"
require "tmpdir"

RSpec.describe RecoveryArchive do
  it "authenticates a binary multi-chunk backup before exposing plaintext" do
    Dir.mktmpdir("mesh-crypto-") do |root|
      plain = Pathname.new(root).join("plain.tar")
      encrypted = Pathname.new(root).join("snapshot.meshbak")
      restored = Pathname.new(root).join("restored.tar")
      bytes = SecureRandom.random_bytes(131071)
      key = SecureRandom.random_bytes(32)
      File.binwrite(plain, bytes)
      described_class.encrypt(plain, encrypted, key: key)
      described_class.decrypt(encrypted, restored, key: key)
      expect(File.binread(restored)).to eq(bytes)
      denied = Pathname.new(root).join("denied.tar")
      expect { described_class.decrypt(encrypted, denied, key: SecureRandom.random_bytes(32)) }.to raise_error(OpenSSL::Cipher::CipherError)
      expect(denied).not_to exist
      expect(Pathname.new("#{denied}.partial")).not_to exist
      File.open(encrypted, "r+b") do |file|
        file.seek(-17, IO::SEEK_END)
        byte = file.read(1).ord
        file.seek(-17, IO::SEEK_END)
        file.write((byte ^ 1).chr)
      end
      expect { described_class.decrypt(encrypted, denied, key: key) }.to raise_error(OpenSSL::Cipher::CipherError)
      expect(denied).not_to exist
    end
  end
end
