require "json"
require "digest"
require "fileutils"
require "uri"

module ArchitectureLab
  def self.guard!
    expected = ENV.fetch("MESH_LAB_DATABASE")
    actual = Platform::Record.connection_db_config.database
    raise "Architecture lab requires an isolated lab database" unless actual == expected && expected.match?(/\Amesh_lab_[a-f0-9]{12}(?:_restore)?\z/)

    queue = ENV.fetch("QUEUE_DATABASE_URL")
    raise "Architecture lab requires an isolated queue" unless URI(queue).path == "/#{expected}_queue"
    raise "Architecture lab requires payouts disabled" unless ENV.fetch("MESH_PAYOUTS_ENABLED") == "false"
  end

  def self.directory
    value = Rails.root.join("../../docs/evidence/showcase-architecture-lab").cleanpath
    FileUtils.mkdir_p(value)
    value
  end

  def self.report(name, data)
    File.write(directory.join("#{name}.json"), JSON.pretty_generate(data.merge(checked_at: Time.current.iso8601)) + "\n")
  end

  def self.state
    JSON.parse(File.read(ENV.fetch("MESH_LAB_STATE")))
  end

  def self.save_state(data)
    File.write(ENV.fetch("MESH_LAB_STATE"), JSON.pretty_generate(data) + "\n")
  end

  def self.measure
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    [ value, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3) ]
  end

  def self.wait(timeout: 120)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      raise "Lab condition did not complete within #{timeout} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 1
    end
  end
end
