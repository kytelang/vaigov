# Varman console and schema: relevance for the SaaS product

This note judges every console screen and database table against the product
direction: a **SaaS AI-governance product on Azure Container Apps** whose core
value is "govern every AI call": register AI endpoints, author policy and content
rules, enforce at the edge (OPA plus the content firewall), and capture decisions
and signed evidence.

It is a scope and packaging judgement, not a correctness one. The compliance and
GRC surface is real and well built; the question is only what belongs in the
focused SaaS first release versus a later module or tier. Everything is judged on
the product's own inventory.

Grounding: the live schema has 44 tables; the row counts below are from the
development database (`acp`). Empty does not by itself mean irrelevant, but empty
plus no live product path is a strong signal.

---

## 1. Core: the actual product (keep)

The enforcement and evidence loop, and the only part with real data in the store:

| Screen | Tables | Rows (dev) |
|---|---|---|
| AI endpoints | `governed_endpoints` | 3 |
| Policy, Policy versions | `policy_rules`, `artifacts`, `artifact_versions`, `rule_controls` | 6 rules |
| Policy packs | `tenant_policy_packs`, `control_packs` | - |
| Content firewall | `content_rules` | 8 |
| Decisions | `decisions`, `violation_events` | 0 (runtime feed) |
| Integration (OPA wiring) | - | - |
| Overview | derived | - |
| Organisation / tenant | `tenant_settings` | - |
| Trust / signing | `revoked_sessions`, keys | - |

These stay in the default console.

## 2. Clearly irrelevant: duplicate or superseded schema

Verified against the Varman source (a table is "dead" only if there is no
`Repository<...>(conn, "<table>")` bind and no FROM/INTO/UPDATE on it). The first
draft of this section over-claimed; the corrected picture:

**Truly unreferenced by Varman and empty (safe to drop):**
- **`endpoints`** superseded by `governed_endpoints` (the live AI-endpoints
  table). The only `"endpoints"` match in code is a JSON response key, not a
  table bind.
- **`firewall_rules`** superseded by `content_rules` (the content firewall).
- **`report_snapshots`**, **`entra_tenant_map`** have no live path.

The drops are staged as a reviewable migration at
`server/docs/drop-dead-tables.sql`, not applied automatically.

**Correction, these are LIVE (do not drop):**
- **`firewall_config`** is used by the Assurance / red-team feature.
- **`lineage_edges`** and **`drift_counts`** are used by the Monitoring feature.
  (These features are not in the console nav, but their tables are real.)

**Shared-database caveat:** the `acp` database is shared with the Rust acp
application. Varman not referencing a table does not prove acp-Rust does not. The
drop migration must run only against a database Varman owns exclusively, or after
acp-Rust is retired.

## 3. Over-scoped for the MVP: the GRC and compliance-registry side

This is the big one, and worth being honest about: most of the screens recently
brought to faithful parity sit here. All are empty in the development store, and
together they form a separate product (EU AI Act and ISO 42001 governance
tooling) layered on the enforcement core.

| Screen(s) | Tables | Verdict |
|---|---|---|
| AI systems, System detail, SoA, Evidence | `ai_systems`, `system_roles`, `soa_entries`, `evidence`, `grc_audit` | Compliance module, not the enforcement MVP |
| Governance workspace (risks, assessments, model cards, datasets) | `grc_records`, `grc_comments`, `grc_links`, `ingested_evidence` | Compliance module |
| Acts and controls, Coverage, Reports | `acts`, `act_countries`, `control_crosswalk` (185), `conformance_checklist`, `control_packs` | Framework and reporting, heavy for MVP |
| Models, Vendors, Apps, Agents | `models`, `vendors`, `apps`, `agents` (all 0) | Inventory screens of unclear MVP value; **Models overlaps AI endpoints** |
| Ticketing | `ticket_rules`, `tickets` | Integration nicety, post-MVP |

Recommendation: gate this entire surface behind a **Compliance module** or an
**Enterprise tier** rather than showing it in the default console. This is a
navigation and packaging decision, not a deletion. The work already done stays
useful the moment that module is switched on.

## 4. The real gap: what a SaaS needs and the console lacks

The product is pitched as SaaS on Azure Container Apps, yet the console has none
of the surfaces a SaaS requires:

- **No pricing, plans, subscription or billing.** No screens, no tables.
- **No self-serve signup.** Authentication is dev-login plus Microsoft Entra; the
  public Register page is the only onboarding and is not built yet.
- **No usage metering or quotas** (for example calls governed, decisions per
  month), which is both the billing basis and a natural customer dashboard.

These are absent, so they are "irrelevantly missing": the thing the product is
sold as has no home in the current UI or schema.

## 5. Bottom line

- **Cut now (safe):** `endpoints`, `firewall_rules`, `firewall_config`,
  `lineage_edges`, `drift_counts`, `report_snapshots`, `entra_tenant_map`; fold
  **Models** into AI endpoints.
- **Gate behind a Compliance or Enterprise module:** the whole GRC and
  framework-reporting surface (AI systems, Governance, Acts, Coverage, Reports,
  Vendors, Apps, Agents, Ticketing).
- **Build for SaaS:** plans and billing, self-serve signup, usage metering.

The net effect is a default console that is the enforcement product (endpoints,
policy, content firewall, decisions, evidence) plus the SaaS shell (signup,
plans, billing, usage), with the deep compliance tooling available as a module
for customers who need EU AI Act or ISO 42001 artefacts.
