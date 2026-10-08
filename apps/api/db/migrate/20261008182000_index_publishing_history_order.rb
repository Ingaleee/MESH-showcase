class IndexPublishingHistoryOrder < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    previous = connection.select_value("SHOW statement_timeout")
    execute "SET statement_timeout = '300000ms'"
    { publishing_partners: [ :owner_id, :created_at, :id ],
      publishing_candidates: [ :created_at, :id ],
      publishing_deployments: [ :created_at, :id ] }.each do |table, columns|
      name = "#{table}_history_order"
      add_index table, columns, name: name, algorithm: :concurrently, if_not_exists: true
      valid = connection.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass")
      raise "#{name} is invalid; drop concurrently and retry" unless valid
    end
  ensure
    execute "SET statement_timeout = #{connection.quote(previous)}" if previous
  end

  def down
    %i[publishing_partners publishing_candidates publishing_deployments].each do |table|
      remove_index table, name: "#{table}_history_order", algorithm: :concurrently, if_exists: true
    end
  end
end
