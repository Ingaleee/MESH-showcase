-- Apply once after migrations as the owner, through psql with variables:
-- -v runtime_role=mesh_runtime -v database_name=mesh_production -v migration_owner=mesh_owner
-- Set the login password separately. No deployment password is stored here.
CREATE ROLE :"runtime_role" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
GRANT CONNECT ON DATABASE :"database_name" TO :"runtime_role";
GRANT USAGE ON SCHEMA public TO :"runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"runtime_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"runtime_role";
REVOKE UPDATE, DELETE ON marketplace_brief_versions, engagements_submissions,
  engagements_acceptances, engagements_feedback, platform_audit_entries FROM :"runtime_role";
REVOKE INSERT, UPDATE, DELETE ON schema_migrations, ar_internal_metadata FROM :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_owner" IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_owner" IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO :"runtime_role";
-- Queue database requires its own CONNECT/schema/table/sequence grants.
-- Never grant CREATE on public, TRUNCATE, ownership or permission to disable triggers.
