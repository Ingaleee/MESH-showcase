require_relative "../../lib/portable_snapshot"
require "tmpdir"
require "securerandom"

RSpec.describe PortableSnapshot do
  around do |example|
    Dir.mktmpdir("mesh-portable-") do |path|
      @root = Pathname.new(path)
      @key = SecureRandom.random_bytes(32)
      example.run
    end
  end

  it "authenticates bytes and detects a missing inventory object before importing anything" do
    source = @root.join("source")
    FileUtils.mkdir_p(source.join("files"))
    source.join("files/object.bin").binwrite("private")
    archive = @root.join("snapshot.meshbak")
    described_class.seal(source, archive, key: @key, kind: "application", metadata: {})
    target = @root.join("restored")
    expect(described_class.unpack(archive, target, key: @key).fetch("kind")).to eq("application")
    expect(target.join("files/object.bin").binread).to eq("private")
    target.join("files/object.bin").delete
    expect { described_class.verify!(target) }.to raise_error(/Missing or unexpected/)
  end

  it "does not delete pre-existing recovery directories or partial files on refusal" do
    target = @root.join("existing")
    FileUtils.mkdir_p(target)
    target.join("keep").write("keep")
    expect { described_class.unpack(@root.join("absent"), target, key: @key) }.to raise_error(/already exists/)
    expect(target.join("keep").read).to eq("keep")
    partial = @root.join("plain.partial")
    partial.write("keep")
    expect { RecoveryArchive.decrypt(@root.join("absent"), @root.join("plain"), key: @key) }.to raise_error(/existing/)
    expect(partial.read).to eq("keep")
  end

  it "denies authenticated path traversal before creating the destination" do
    tar = @root.join("malicious.tar")
    File.open(tar, "wb") do |file|
      Gem::Package::TarWriter.new(file) { |writer| writer.add_file_simple("../escape", 0o600, 1) { |entry| entry.write("x") } }
    end
    archive = @root.join("malicious.meshbak")
    RecoveryArchive.encrypt(tar, archive, key: @key)
    target = @root.join("restored")
    expect { described_class.unpack(archive, target, key: @key) }.to raise_error(/Unsafe archive path/)
    expect(target).not_to exist
    expect(@root.join("escape")).not_to exist
  end
end
