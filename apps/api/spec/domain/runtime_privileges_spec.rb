require "rails_helper"

RSpec.describe "Restricted PostgreSQL runtime role" do
  it "permits runtime data access and denies history mutations, DDL and TRUNCATE using the deployment template" do
    connection = Platform::Record.connection
    role = "mesh_runtime_spec_#{SecureRandom.hex(6)}"
    variables = {
      "runtime_role" => role,
      "database_name" => connection.select_value("SELECT current_database()"),
      "migration_owner" => connection.select_value("SELECT current_user")
    }
    template = Rails.root.join("../../infra/runtime-role.sql").read
    variables.each { |name, value| template = template.gsub(":\"#{name}\"", connection.quote_column_name(value)) }
    connection.transaction do
      connection.execute(template)
      connection.execute("SET LOCAL ROLE #{connection.quote_column_name(role)}")
      expect(connection.select_value("SELECT current_user")).to eq(role)
      expect(connection.select_value("SELECT count(*) FROM engagements_submissions")).to eq(0)
      connection.execute("INSERT INTO platform_rate_limit_buckets (key_digest, attempts, expires_at) VALUES ('runtime-probe', 1, CURRENT_TIMESTAMP)")
      [
        "TRUNCATE identity_accounts CASCADE",
        "CREATE TABLE forbidden_runtime_probe (id integer)",
        "ALTER TABLE engagements_submissions DISABLE TRIGGER USER",
        "UPDATE engagements_submissions SET content = 'changed' WHERE FALSE",
        "DELETE FROM engagements_feedback WHERE FALSE",
        "DELETE FROM platform_audit_entries WHERE FALSE",
        "INSERT INTO schema_migrations (version) VALUES ('forbidden')"
      ].each do |sql|
        expect { connection.transaction(requires_new: true) { connection.execute(sql) } }.to raise_error(ActiveRecord::StatementInvalid, /permission denied|must be owner/)
      end
      raise ActiveRecord::Rollback
    end
    expect(connection.select_value("SELECT count(*) FROM pg_roles WHERE rolname = #{connection.quote(role)}")).to eq(0)
  end
end
