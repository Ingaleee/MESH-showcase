require_relative "../config/environment"
require_relative "support/architecture_lab"

ArchitectureLab.guard!
connection = Platform::Record.connection
connection.execute("SET statement_timeout = '300000ms'")
require_relative "../db/migrate/20261008060000_index_project_substring_search"
IndexProjectSubstringSearch.new.migrate(:up)
connection.execute("INSERT INTO schema_migrations (version) VALUES ('20261008060000') ON CONFLICT DO NOTHING")
connection.execute("ANALYZE marketplace_projects")
sizes = connection.select_all("SELECT indexrelname AS name, pg_relation_size(indexrelid) AS bytes FROM pg_stat_user_indexes WHERE indexrelname IN ('project_title_trigram', 'project_description_trigram')").to_a
ArchitectureLab.report("indexes", { indexes: sizes, scope: "Two GIN indexes preserve the existing title OR description substring semantics; extra disk and write maintenance are the cost." })
puts "Candidate project search indexes built."
