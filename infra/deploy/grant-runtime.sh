#!/bin/sh
set -eu
for database in mesh_production mesh_queue; do
  psql -v ON_ERROR_STOP=1 --dbname "$database" -v database="$database" <<'SQL'
GRANT CONNECT ON DATABASE :"database" TO mesh_runtime;
GRANT USAGE ON SCHEMA public TO mesh_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, mesh_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mesh_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mesh_runtime;
SELECT format('REVOKE UPDATE, DELETE ON %I FROM mesh_runtime', relname)
FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname IN
('marketplace_brief_versions', 'engagements_submissions', 'engagements_acceptances', 'engagements_feedback', 'platform_audit_entries', 'publishing_candidates', 'publishing_callback_receipts')
\gexec
REVOKE INSERT, UPDATE, DELETE ON schema_migrations, ar_internal_metadata FROM mesh_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE mesh_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mesh_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE mesh_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mesh_runtime;
SQL
done
