require_relative "../config/environment"
require_relative "support/architecture_lab"
require "open3"

ArchitectureLab.guard!
raise "Stop all lab writers before the snapshot" unless ENV["MESH_LAB_QUIESCED"] == "true"
backup = Pathname.new(ENV.fetch("MESH_LAB_BACKUP"))
expected_root = Rails.root.join("../../.cache/architecture-lab").cleanpath.to_s + "/"
raise "Backup path is outside the lab" unless backup.cleanpath.to_s.start_with?(expected_root)
raise "Backup directory already contains data" if backup.exist?
FileUtils.mkdir_p(backup.join("files"))
source = ENV.fetch("DATABASE_URL")
target = URI(source)
target.path += "_restore"
dump = backup.join("database.dump")
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
_, error, status = Open3.capture3("pg_dump", "--format=custom", "--no-owner", "--no-acl", "--dbname", source, "--file", dump.to_s)
raise "Database snapshot failed: #{error.lines.last}" unless status.success?

tables = %w[identity_accounts talent_profiles marketplace_projects marketplace_proposals engagements_engagements engagements_submissions engagements_work_files active_storage_blobs active_storage_attachments platform_outbox_events platform_deliveries notifications_notifications]
counts = tables.to_h { |table| [ table, Platform::Record.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i ] }
blobs = ActiveStorage::Blob.order(:key).map do |blob|
  raise "Unsafe storage key" unless blob.key.match?(/\A[a-zA-Z0-9_-]+\z/)
  path = blob.service.send(:path_for, blob.key)
  raise "Source blob size is inconsistent" unless File.size(path) == blob.byte_size
  FileUtils.cp(path, backup.join("files/#{blob.key}.bin"))
  { key: blob.key, size: blob.byte_size, checksum: blob.checksum, sha256: Digest::SHA256.file(path).hexdigest }
end
manifest = { database_counts: counts, blobs: blobs, fixture: ArchitectureLab.state,
  dump_sha256: Digest::SHA256.file(dump).hexdigest, dump_bytes: File.size(dump),
  backup_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
  consistency: "Quiescent isolated writers; queue is deliberately excluded and rebuilt empty. Not an online multi-database snapshot." }
# The manifest is the completion marker; a partial directory is never considered a backup.
File.write(backup.join("complete.json"), JSON.pretty_generate(manifest) + "\n")
ArchitectureLab.report("backup", manifest.except(:fixture))

restore_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
_, error, status = Open3.capture3("pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", target.to_s, dump.to_s)
raise "Database restoration failed: #{error.lines.last}" unless status.success?
destination = ActiveStorage::Service::DiskService.new(root: "/lab-restored-storage")
blobs.each do |blob|
  path = destination.send(:path_for, blob.fetch(:key))
  raise "Restore volume is not empty" if File.exist?(path)
  FileUtils.mkdir_p(File.dirname(path))
  FileUtils.cp(backup.join("files/#{blob.fetch(:key)}.bin"), path)
end
ArchitectureLab.report("restore-copy", { database_restore_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - restore_started).round(3),
  blobs_copied: blobs.size, total_file_bytes: blobs.sum { |blob| blob.fetch(:size) }, dump_sha256: manifest.fetch(:dump_sha256) })
puts "Database and private file bytes restored into isolated targets."
