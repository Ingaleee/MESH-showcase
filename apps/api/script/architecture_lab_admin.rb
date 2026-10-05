require "pg"
require "open3"
require "uri"

name = ENV.fetch("MESH_LAB_DATABASE")
abort "Invalid isolated database name" unless name.match?(/\Amesh_lab_[a-f0-9]{12}\z/)
source = URI(ENV.fetch("DATABASE_URL"))
abort "Unexpected source database" unless source.path == "/#{name}"
admin = source.dup
admin.path = "/postgres"
connection = PG.connect(admin.to_s)
databases = [ name, "#{name}_queue", "#{name}_restore", "#{name}_restore_queue" ]
case ARGV.fetch(0)
when "create"
  databases.each do |database|
    connection.exec("CREATE DATABASE #{PG::Connection.quote_ident(database)}")
    next if database.end_with?("_restore")

    target = source.dup
    target.path = "/#{database}"
    schema = database.end_with?("_queue") ? "queue_structure.sql" : "structure.sql"
    _, error, status = Open3.capture3("psql", "--quiet", "--set", "ON_ERROR_STOP=1", "--dbname", target.to_s, "--file", File.expand_path("../db/#{schema}", __dir__))
    raise "Schema load failed: #{error.lines.last}" unless status.success?
  end
when "drop"
  databases.each { |database| connection.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(database)} WITH (FORCE)") }
else
  raise "Invalid lab admin action"
end
connection.close
puts "Isolated database administration completed."
