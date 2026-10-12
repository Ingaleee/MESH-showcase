GRANT CONNECT ON DATABASE :"database" TO mesh_showcase_kubernetes_runtime;
GRANT USAGE ON SCHEMA public TO mesh_showcase_kubernetes_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, mesh_showcase_kubernetes_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mesh_showcase_kubernetes_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mesh_showcase_kubernetes_runtime;
SELECT format('REVOKE UPDATE, DELETE ON %I FROM mesh_showcase_kubernetes_runtime', relname)
FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname IN
('marketplace_brief_versions', 'engagements_submissions', 'engagements_acceptances', 'engagements_feedback', 'platform_audit_entries', 'publishing_candidates', 'publishing_callback_receipts')
\gexec
REVOKE INSERT, UPDATE, DELETE ON schema_migrations, ar_internal_metadata FROM mesh_showcase_kubernetes_runtime;
