class IndexProjectSubstringSearch < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    previous_timeout = connection.select_value("SHOW statement_timeout")
    execute "SET statement_timeout = '300000ms'"
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
    { title: "project_title_trigram", description: "project_description_trigram" }.each do |column, name|
      add_index :marketplace_projects, column, using: :gin, opclass: :gin_trgm_ops,
        name: name, algorithm: :concurrently, if_not_exists: true
      valid = connection.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass")
      raise "#{name} is invalid; drop the invalid index concurrently and retry" unless valid
    end
  ensure
    execute "SET statement_timeout = #{connection.quote(previous_timeout)}" if previous_timeout
  end

  def down
    remove_index :marketplace_projects, name: "project_title_trigram", algorithm: :concurrently, if_exists: true
    remove_index :marketplace_projects, name: "project_description_trigram", algorithm: :concurrently, if_exists: true
    # pg_trgm can be used by other domains; rollback only owns these indexes.
  end
end
