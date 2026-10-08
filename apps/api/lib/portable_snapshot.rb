require "json"
require "digest"
require "fileutils"
require "pathname"
require "open3"
require "rubygems/package"
require_relative "recovery_archive"

module PortableSnapshot
  MAX_BYTES = 100 * 1024 * 1024
  MAX_FILES = 500

  def self.unpack(archive, target, key:)
    created = false
    plain_created = false
    target = Pathname.new(target)
    raise "Recovery directory already exists" if target.exist?
    plain = target.to_s + ".authenticated.tar"
    RecoveryArchive.decrypt(archive, plain, key: key)
    plain_created = true
    entries = []
    File.open(plain, "rb") do |input|
      Gem::Package::TarReader.new(input) do |tar|
        tar.each do |entry|
          name = entry.full_name.sub(/\A\.\//, "")
          next if entry.directory? && [ "", "." ].include?(name)
          raise "Unsafe archive member" unless entry.file? || entry.directory?
          raise "Unsafe archive path" unless name.match?(/\A[a-zA-Z0-9_.\/-]+\z/) &&
            !name.start_with?("/") && !name.split("/").include?("..")
          next if entry.directory?
          raise "Duplicate member" if entries.any? { |row| row[:name] == name }
          entries << { name: name, bytes: entry.header.size }
          raise "Recovery budget exceeded" if entries.size > MAX_FILES || entries.sum { |row| row[:bytes] } > MAX_BYTES
        end
      end
    end
    FileUtils.mkdir_p(target)
    created = true
    File.open(plain, "rb") do |input|
      Gem::Package::TarReader.new(input) do |tar|
        tar.each do |entry|
          next unless entry.file?
          file = target.join(entry.full_name.sub(/\A\.\//, ""))
          FileUtils.mkdir_p(file.dirname)
          File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
            while (chunk = entry.read(65_536)) && !chunk.empty?
              output.write(chunk)
            end
          end
        end
      end
    end
    verify!(target)
  rescue StandardError
    FileUtils.remove_entry_secure(target.to_s) if created && target&.directory?
    raise
  ensure
    File.delete(plain) if plain_created && File.exist?(plain)
  end

  def self.verify!(root)
    root = Pathname.new(root)
    manifest = JSON.parse(root.join("complete.json").read)
    raise "Unsupported snapshot" unless manifest.fetch("schema_version") == 2 && %w[application partner].include?(manifest.fetch("kind"))
    files = manifest.fetch("files")
    raise "Invalid snapshot inventory" unless files.is_a?(Array) && files.size <= MAX_FILES
    names = files.map { |row| row.fetch("name") }
    raise "Repeated inventory path" unless names.uniq == names
    names.each { |name| raise "Unsafe inventory path" unless name.match?(/\A[a-zA-Z0-9_.\/-]+\z/) && !name.start_with?("/") && !name.split("/").include?("..") }
    actual = root.glob("**/*").select(&:file?).map { |file| file.relative_path_from(root).to_s }.sort
    raise "Missing or unexpected snapshot object" unless actual == (names + [ "complete.json" ]).sort
    files.each do |row|
      file = root.join(row.fetch("name"))
      raise "Private snapshot object is missing or corrupt" unless file.size == row.fetch("size") && Digest::SHA256.file(file).hexdigest == row.fetch("sha256")
    end
    manifest
  end

  def self.seal(root, target, key:, kind:, metadata:)
    root = Pathname.new(root)
    files = root.glob("**/*").select(&:file?).map do |file|
      { name: file.relative_path_from(root).to_s, size: file.size, sha256: Digest::SHA256.file(file).hexdigest }
    end
    root.join("complete.json").write(JSON.pretty_generate(schema_version: 2, kind: kind, files: files, metadata: metadata) + "\n")
    verify!(root)
    plain = target.to_s + ".tar"
    raise "Archive target exists" if File.exist?(plain) || File.exist?(target)
    plain_owned = true
    _, error, status = Open3.capture3("tar", "-cf", plain, "-C", root.to_s, ".")
    raise "Snapshot packing failed: #{error.lines.last}" unless status.success?
    RecoveryArchive.encrypt(plain, target, key: key)
  ensure
    File.delete(plain) if plain_owned && File.exist?(plain)
  end
end
