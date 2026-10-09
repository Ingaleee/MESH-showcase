require_relative "../../lib/portable_snapshot"
require "tmpdir"
require "securerandom"

RSpec.describe PortableSnapshot do
  around do |example|
    previous_internal = Encoding.default_internal
    Encoding.default_internal = Encoding::UTF_8
    Dir.mktmpdir("mesh-portable-") do |path|
      @root = Pathname.new(path)
      @key = SecureRandom.random_bytes(32)
      example.run
    end
  ensure
    Encoding.default_internal = previous_internal
  end

  it "authenticates bytes and detects a missing inventory object before importing anything" do
    source = @root.join("source")
    FileUtils.mkdir_p(source.join("files"))
    bytes = (0..255).to_a.pack("C*")
    source.join("files/object.bin").binwrite(bytes)
    archive = @root.join("snapshot.meshbak")
    described_class.seal(source, archive, key: @key, kind: "application", metadata: {})
    target = @root.join("restored")
    expect(described_class.unpack(archive, target, key: @key).fetch("kind")).to eq("application")
    expect(target.join("files/object.bin").binread).to eq(bytes)
    target.join("files/object.bin").delete
    expect { described_class.verify!(target) }.to raise_error(/Missing or unexpected/)
  end

  it "does not delete pre-existing recovery directories or partial files on refusal" do
    target = @root.join("existing")
    FileUtils.mkdir_p(target)
    target.join("keep").write("keep")
    expect { described_class.unpack(@root.join("absent"), target, key: @key) }.to raise_error(/already exists/)
    expect(target.join("keep").read).to eq("keep")
    link = @root.join("dangling")
    File.symlink(@root.join("missing"), link)
    expect { described_class.unpack(@root.join("absent"), link, key: @key) }.to raise_error(/already exists/)
    expect(link).to be_symlink
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

  it "refuses an unsafe shared parent before decrypting or creating a target" do
    shared = @root.join("shared")
    FileUtils.mkdir_p(shared)
    File.chmod(0o777, shared)
    expect { described_class.unpack(@root.join("absent"), shared.join("restored"), key: @key) }.to raise_error(/private or sticky/)
    expect(shared.children).to be_empty
  end

  it "cleans rejected authenticated inventories in a sticky shared parent" do
    shared = @root.join("shared")
    FileUtils.mkdir_p(shared)
    File.chmod(0o1777, shared)
    manifest = JSON.generate(schema_version: 2, kind: "application", files: [ { name: "missing", size: 1, sha256: Digest::SHA256.hexdigest("x") } ])
    tar = @root.join("invalid.tar")
    File.open(tar, "wb") do |file|
      Gem::Package::TarWriter.new(file) do |writer|
        writer.add_file_simple("complete.json", 0o600, manifest.bytesize) { |entry| entry.write(manifest) }
      end
    end
    archive = @root.join("invalid.meshbak")
    RecoveryArchive.encrypt(tar, archive, key: @key)
    expect { described_class.unpack(archive, shared.join("restored"), key: @key) }.to raise_error(/Missing or unexpected/)
    expect(shared.children).to be_empty
  end
end
