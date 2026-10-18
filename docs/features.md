# Varman feature list

This lists the features that actually exist in the code today, grouped by the
two planes. The control plane is the Kyte web application in `server/` (backed by
Postgres); the sidecar is the Kyte application in `sidecar/` that runs next to the
data plane (Envoy) at each governed edge. Deterministic content matchers are
shared by both through `packages/varman-core/src/cfmatch.ky`, so authoring and
enforcement cannot drift.

The three planes at a glance: the control plane authors and signs configuration
and holds the system of record; the sidecar pulls that signed configuration,
drives Envoy, enforces the content firewall, and records signed evidence; the
redteam/assurance path exercises the policies. "Control plane authors, edge
enforces and reports."

---

## Control plane (`server/`)

A hypermedia web application (Datastar `.kyx` views plus JSON endpoints for
machines), one feature folder per capability, Postgres repositories, Ed25519
signing of everything the edge consumes.

### Identity, access and tenancy
- **Auth**: login/logout, session, dev-login and dev-token for local use;
  Microsoft Entra sign-in (consent URL, callback, bindings, whoami).
- **SCIM v2**: Users and Groups provisioning endpoints for directory sync.
- **Multi-tenancy**: tenant registration, per-tenant settings, tenant listing;
  all resources are tenant-scoped.
- **Admin**: administrative metadata endpoint for the console shell.

### Governed inventory (the things being governed)
- **AI endpoints**: register, list, view, update, delete the AI providers/hosts
  under governance (the set the sidecar turns into Envoy upstreams).
- **Apps**, **Agents**, **Models**, **Principals**, **Vendors**, **Systems**:
  CRUD inventories for the applications, calling agents (with key resolve/verify),
  models, identities, third parties, and governed systems.
- **Agents**: resolve-key and verify flows so a calling agent can authenticate.

### Policy and rules
- **Policy**: author/save/delete policies; compiled into the OPA bundle.
- **Rules**: author rules and attach **controls** to them (control mapping).
- **Content rules (content firewall)**: author/save/toggle/delete and **test**
  deterministic content rules (regex, substring, size, PII, secret); the test box
  runs the same `cfmatch` matchers the edge uses. Served to the edge as a signed
  **ActiveSet**.
- **Policy packs**: install/uninstall curated packs onto a tenant or system.
- **OPA**: serve the signed OPA bundle (`/v1/bundles/{name}`) and policy
  evaluation/logs for the data plane.

### Decisions, approvals and tickets
- **Decisions**: record and summarise policy decisions; decision timeline.
- **Approvals**: register an approval request, list pending, approve/deny, check
  status (human-in-the-loop gate).
- **Ticketing**: ticket list, ticket rules (toggle/delete), Jira integration and a
  tickets callback, so violations can raise tickets.
- **Monitoring**: alerts and an event timeline.

### Governance, risk and compliance (GRC)
- **Compliance**: coverage and decision-summary reporting.
- **Assurance / GRC**: GRC records (save/delete), applicable regulatory **acts**,
  per-act checklists, statement-of-applicability (SoA) per framework.
- **Evidence**: per-system evidence collection and an **audit pack** export.
- **Reports**: framework reports (`/report/framework/{name}`,
  `/systems/{id}/report/{framework}`), reports view.
- **Redteam**: configure a target, run red-team suites, list runs (adversarial
  assurance against the governed endpoints).
- **Vendors**: third-party review workflow.

### Artifacts and trust
- **Artifacts**: versioned artifact store with baseline/activate and version
  history.
- **Signing and trust**: `/trust` publishes the control-plane public key;
  AI-endpoint lists, policy packs, the OPA bundle and the content-rule ActiveSet
  are Ed25519-signed (JCS-canonical) so the edge can verify them fail-closed.
- **Retrieval / verify**: retrieval check and a verify endpoint for signed
  payloads.

### Console
- Datastar-driven operator console (`/console/...`) with forms and CRUD for
  endpoints, models, policy, content rules, policy packs, systems, GRC and the
  organisation profile, plus overview/reports/timeline views.

---

## Sidecar (`sidecar/`)

A small Kyte web application that runs at each edge next to Envoy. It pulls signed
configuration from the control plane, drives Envoy, enforces the content firewall,
and keeps a signed, tamper-evident violation log. Fails safe when the control
plane is unreachable by serving the last-good configuration from disk.

### Configuration sync (pull from control plane)
- Background **poll loop** (`sync.ky`) pulls the OPA bundle, the AI-endpoint
  registry, installed policy packs, and the content-rule ActiveSet.
- Every pulled payload is **verified against the control-plane public key and is
  fail-closed**: an unsigned or mis-signed payload is rejected.
- **Last-good on disk**: endpoints, packs and content rules are cached so a cold
  start with the control plane down still renders Envoy and serves policy.

### Data-plane control (Envoy)
- Renders Envoy **LDS/CDS** config from the endpoint registry (`envoy.ky`): one
  TLS-bump filter chain per governed host, the content-check cluster, and a
  default splice chain.
- Serves the OPA bundle (`/policy/bundle`) and raw rego (`/policy/rego`) and the
  AI-endpoint list (`/ai-endpoints`) to the local data plane.

### Content firewall (F1)
- `POST /cf/check`: the Envoy ext_authz / Lua check over the request body. Answers
  200 allow or 403 deny.
- Deterministic engine (`cfengine.ky` + shared `cfmatch.ky`): regex, substring,
  size, **PII** (email, SSN, Luhn-checked card, with `+`/encoded-separator
  handling) and **secret** (key-prefix and tuned entropy) matchers.
- Four-way verdict precedence: **deny > step_up > shadow > allow**; shadow allows
  the request through but still records it (trial mode).
- On a non-allow verdict it records a signed violation carrying the prompt, the
  rule that fired, the verdict and severity.

### Signed, tamper-evident evidence (R1 + R4)
- Append-only violation log (`vstore.ky` + `violation.ky`): each record is
  Ed25519-signed over its JCS-canonical core and **chain-linked** to the previous
  record's signature, so editing, deleting or reordering is detectable.
- **Startup chain self-check** (`firstBrokenId`): verifies the whole chain at boot
  and logs "verified intact" or a loud warning on corruption.
- Durable framing (length-prefixed) survives a torn trailing frame on crash; a
  flush cursor ships confirmed records to the control plane without losing local
  history.
- Prompt-retention mode: verbatim or redacted-preview, with the full-prompt hash
  always kept.

### Operator console
- `/console` plus JSON endpoints (`/console/violations.json`,
  `/console/violation/{id}`, `/console/policy.json`): a dependency-free view of the
  captured violations, each shown with its live verify status.

### Ticketing and ingest
- Background **ticket loop** raises a ticket for violations whose verdict is in the
  configured set, via `ticketing.ky` (generic / Jira / ServiceNow adapters over the
  Kyte HTTP client), idempotently (`raiseOnce`).
- Background **flush loop** ships unconfirmed violations to the control plane and
  advances the cursor.
- `POST /violations` and `/logs` ingest decision-log records from the data plane.
- `GET /healthz` health probe.

### Browser coverage (test extension, `.e2e/cf-extension`)
- A Chrome MV3 extension that hooks the chat UI's own `fetch` and
  `XMLHttpRequest`, checks the prompt against `/cf/check` through its service
  worker, and blocks the send in-browser before the prompt leaves. Verified live
  against Gemini (XHR/batchexecute) and ChatGPT (fetch). This is the browser-shaped
  front end to the same engine, rules and signed evidence as the API-host data
  plane.

---

## Shared foundation (`packages/varman-core`)
- `cfmatch.ky`: the one implementation of the deterministic content matchers, used
  by both the sidecar edge engine and the control-plane rule-test box.
- `sign` / `canonical`: Ed25519 signing over JCS-canonical bytes, used to sign
  everything the control plane publishes and everything the sidecar records.
