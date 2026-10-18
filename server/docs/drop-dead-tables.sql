-- Relevance cleanup (docs/relevance-saas.md §2): drop tables that the Varman
-- control plane does not reference and that are empty in our store.
--
-- VERIFIED against the Varman source (no `Repository<...>(conn, "<table>")` bind,
-- no FROM/INTO/UPDATE on the table):
--   endpoints          superseded by governed_endpoints (the live AI-endpoints table)
--   firewall_rules     superseded by content_rules (the live content firewall)
--   report_snapshots   no live path
--   entra_tenant_map   no live path
--
-- DO NOT drop these (they are LIVE, used by Varman features, despite the first
-- draft of relevance-saas.md listing them):
--   firewall_config    used by the Assurance / red-team feature
--   lineage_edges      used by the Monitoring feature
--   drift_counts       used by the Monitoring feature
--
-- WARNING: the `acp` database is SHARED with the Rust acp application. Varman not
-- referencing a table does NOT prove acp-Rust does not. Run this ONLY against a
-- database that Varman owns exclusively, or after confirming acp-Rust is retired.
-- Each drop is guarded so re-running is safe.

BEGIN;
DROP TABLE IF EXISTS endpoints;
DROP TABLE IF EXISTS firewall_rules;
DROP TABLE IF EXISTS report_snapshots;
DROP TABLE IF EXISTS entra_tenant_map;
COMMIT;
