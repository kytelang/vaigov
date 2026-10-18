# Varman design refinements

This document captures a set of refinements to the Varman (ACP) Kyte port, agreed in the session of
2026-10-10. It builds on `verman-design.md` (the migration plan) and assumes that document's
invariants: fail-closed posture, preserved wire and storage formats, trusted/untrusted context
separation, and the four-way verdict semantics.

The refinements here are about the **sidecar** and its place on the data plane: how it is provisioned
with what to enforce, and what happens to a **policy violation** after Envoy and OPA have decided it.
There are five, and they are related:

1. Violations seen at the OPA/Envoy edge are persisted in the sidecar's own store (as structured
   records, not just a forwarding queue), and each record carries the prompt, the policy it violated,
   and the ticket raised against it.
2. The sidecar is built as a proper Kyte web app and carries a small console of its own, including a
   screen that lists every violation it has captured.
3. The sidecar talks to the external ticketing system directly, using the Kyte web framework's HTTP
   client.
4. Violation and evidence records are cryptographically signed, so the record is tamper-evident, the
   way the Rust implementation signs its evidence ledger.
5. The AI endpoints, policy packs and policies are pulled from the control-plane database, persisted
   in the sidecar's own store, and from there the endpoints are rendered into Envoy configuration and
   the policies into the OPA bundle the opa-envoy-plugin enforces.

Taken together these make the sidecar a self-contained, auditable edge agent rather than a thin relay.
R1 to R4 own the inbound path (what happens after a call is judged); R5 owns the outbound path (how the
edge is provisioned with what to enforce). The sidecar store (R1) is the pivot: it is both the read
model for captured violations and the local source of truth for the provisioned configuration.

A sixth refinement sits on a different axis. Varman is to ship as a **SaaS product on Azure Container
Apps**: a public marketing site, published pricing, and self-serve registration where a visitor
chooses a plan and onboards. That reframes the whole system from a single-tenant control plane into a
multi-tenant, metered, billed service. Section 9 writes up that product shape, the commercial and
tenancy layer the ported `acp` schema does not yet have, and how it wraps the governance core without
changing it.

## System at a glance: the three planes

Before the refinement detail, here is the whole system in one model. Varman is three planes: a central
**control plane** where governance is authored, an edge **sidecar** that enforces it and reports back,
and a **redteam** that proves the enforcement actually works. The refinements in this document are
almost all about the sidecar (R1 to R5) plus the commercial wrapper (section 9); this overview places
them in the larger picture and marks honestly what is built.

### Control plane (central, multi-tenant) — largely built

Where a customer's governance is defined. It is the most complete part of the system today.

- **Tenant registration and settings** (`Admin/TenantRegister`, `TenantsList`, `TenantSettings*`,
  `Orgs`). Built, admin-driven. (Self-serve signup, plans and billing are the SaaS gap, section 9.)
- **Jurisdiction mapping**: by the tenant's country, the applicable acts are proposed
  (`Admin/ActsApplicable`, `Admin/Countries`). Built.
- **Choosing standards**: the tenant enables the specific acts / frameworks (and therefore ISO and
  similar standards) that apply to them (`enabled_acts`, the organisation panel). Built.
- **Predefined policy packs per act** (`PolicyPacks`: catalogue, install, uninstall) and **custom
  policies** (`Policy`, `Rules`). Built.
- **AI endpoint registry** (`Endpoints` / `/ai-endpoints`). Built, and already consumed by the sidecar.
- **Reports** (`Compliance/Report`, `ReportsView`) and **governance records** (`Grc`, Ed25519-signed).
  Built.
- Plus a broader surface not always named in the product summary: agent **Assurance**, identity
  (**Auth**/Entra, **Scim**, **Trust** keypair), **Approvals**, and the **Agents / Apps / Principals /
  Vendors** registries, and **Decisions / Evidence / Monitoring**. Mixed: some load-bearing, some
  vestigial (see the implementation status and the earlier relevance analysis).

### Sidecar (per customer edge) — this is what the refinements build

The agent that sits in the customer's egress path and turns authored governance into live enforcement.
Its full shape is R1 to R5:

- **Pulls policies and packs** from the control plane, stores them locally, and configures the
  **opa-envoy-plugin** (R5). **Partly built** (bundle pull and OPA serve work; packs-as-a-distinct-pull
  and the local structured store do not).
- **Pulls AI endpoints**, stores them locally, and configures **Envoy** (R5). **Built.**
- **Web console showing violations** with the prompt that violated and the policy it matched (R1, R2).
  **Not built** (sidecar is a web app on `app.run`, but has no console).
- **Raises tickets per violation** via the customer's ticketing system (R3), and **pushes violations**
  (ticket number, policy violated, verdict) to the control plane. **Flush to control plane exists
  (opaque); ticket creation does not.**
- **Signs** every violation record so it is tamper-evident (R4). **Not built** (the signing primitive
  exists server-side for GRC; the sidecar signs nothing).

### Redteam — proves the policies actually catch violations

The validation plane. Its **intended** job (and the right design) is: send attack prompts at the
configured AI endpoints through the live enforcement path, and report whether the configured policies
and packs actually catch them, so a customer has evidence the controls work, not just that they are
switched on.

**Status, stated honestly: not yet that.** Today `Assurance/RedteamRun` runs a **small built-in corpus
through an in-process keyword content check**, scores a catch-rate / false-positive-rate, and signs an
attestation. It does **not** drive traffic through Envoy and OPA to a real endpoint, so it does not
validate the live enforcement path end to end. Its own code calls itself a "faithful-shaped
approximation" of the acp content check. A true redteam, as described above, is genuine missing work and
is **blocked on content-aware policy** (section 10): there is little at the content level to catch until
that firewall exists, so the end-to-end redteam and the content firewall advance together. The acp
primitives it would build on (the signed attestation, the catch-rate model, the corpus shape) are
already in place.

**In one line:** the control plane authors governance (built), the sidecar enforces it and reports
violations (designed here; the enforcement pull is built, the evidence/console/ticketing/signing are
not), and the redteam proves enforcement works (today an approximation; a real one needs content-aware
policy first).

## 0. Implementation status (as of 2026-10-10)

This section is the honest ledger: what in this document is actually built versus what is still a
target. It is written from a direct reading of `sidecar/src` and `server/src`, not from intent. The rest
of the document describes the design; this table says how much of it exists.

**Update 2026-10-10 (refinements build):** R1 to R5 have now been implemented in the sidecar and
verified end to end (build green, sidecar offline test suite 9/9 passing, and a live run exercising
ingest -> sign -> store -> console -> ticket -> flush). The table below is updated to the post-build
state; the paragraph after it records exactly what was added and the honest remaining gaps.

**Update 2026-10-10 (gap-closure):** the three fixable gaps from the refinements build are now closed
and verified; only the SaaS layer (section 9) remains out of scope by agreement. (1) **Config signature
verification is now real end to end:** the control plane signs the bundle, endpoint-registry, and
installed-packs responses with a detached `x-acp-signature` (Ed25519 over the body, via
`Http.signConfig`/`signedObj`), and the sidecar verifies against `cp_pubkey` before applying,
**fail-closed** (verified live: unsigned config from a mock control plane was refused and last-good
kept; both server and sidecar build green). (2) **Prompt integrity:** the stored prompt is now inside
the signed canonical core, so editing the displayed text flips the record to UNVERIFIED (verified live)
while redaction still works (the full-prompt hash is signed too). (3) **Concrete ticketing adapters:** a
`ticketing_system` setting selects `generic | jira | servicenow`, each with its own create path, request
body, auth (Basic for Jira/ServiceNow, Bearer for generic), and response-id extraction.

| Refinement | Status | What is actually there |
|---|---|---|
| **R1** structured, persisted, signed violation store | **built + verified** | `violation.ky` parses each OPA decision into a typed record (prompt, policy, verdict, principal, endpoint, decision_id); `vstore.ky` is an append-only signed log with an in-memory index and a flush cursor (store-and-forward kept, history no longer dropped). Reloads from disk intact across restart. The kaidb read-model remains the optional heavier-deployment variant; this is the design's flat-file-only mode. |
| **R2** sidecar console + violations screen | **built + verified** | `console.ky` serves a self-contained (no-framework) operator console at `/console` plus JSON endpoints (`/console/violations.json`, `/console/violation/{id}`, `/console/policy.json`). Violations screen shows prompt, policy, verdict, ticket, and a per-record verified badge, with verdict/host filters; Policy and Health tabs show what the edge enforces. |
| **R3** sidecar raises/tracks tickets via HTTP client | **built + verified** | `ticketing.ky` raises tickets over `web.client.Http` off the hot path in a background loop, with an idempotency key (`id-sig`), verified against a mock ticketing server (deny -> `TKT-1001` written back onto the record). Tracking of ticket status is wired; concrete-system mapping (Jira/ServiceNow) is the remaining thin adapter. |
| **R4** tamper-proof signed records (Ed25519 + hash chain) | **built + verified** | Records are Ed25519-signed over JCS-canonical bytes (reusing `varman-core` `sign`/`canonical`, so the control plane verifies with identical code) and chained via `prev_sig`. Tamper detection proven: editing a signed field on disk flips the record to UNVERIFIED after reload while untouched records stay verified. The signature commits to `prompt_sha` (the full-prompt hash), not the stored preview, so redaction and integrity coexist. |
| **R5** pull endpoints/packs/policies -> store -> Envoy + OPA | **mostly built** | Bundle + endpoint pull and OPA/Envoy render were already present; added: installed-**packs** pull (`sync.syncPacks`), **disk persistence** of the endpoint registry and packs (last-good), and **render-from-store on boot** so a cold start with the control plane down still arms Envoy. Remaining: signature **verification** of pulled config is stubbed (the `cp_pubkey` setting exists; the control plane does not sign config yet), and the kaidb-backed config store is the optional variant. |
| **Section 9, SaaS** (tenancy, billing, signup, landing/pricing) | **~5% (greenfield, unchanged)** | Not part of this refinements build. `tenant_id` columns + Entra scaffolding only; no organisations/plans/subscriptions/billing/signup/pricing. |

### Earlier ledger (pre-build, retained for reference)

| Refinement | Status | What is actually there |
|---|---|---|
| **R1** structured, persisted, signed violation store | **~10% (foundation only)** | The durable flat-file queue (`queue.ky`) exists and `normalize` splits the posted body into verbatim record substrings. That is the crash-safe capture path the design keeps as the fallback. There is no structured record, no prompt/policy/ticket columns, no kaidb projection, and no local history (confirmed rows are dropped on flush). |
| **R2** sidecar as Kyte web app + violations console | **~25% (web app yes, console no)** | The sidecar runs on `app.run(port)` with the background loops started from `App.onStart` (done, verified). But there is no `wwwroot`, no `.kyx`, and no console handlers. It serves only the machine JSON contract: `/healthz`, `/policy/bundle`, `/policy/rego`, `/ai-endpoints`, `/violations`, `/logs`. No Violations/Policy/Health screens. |
| **R3** sidecar raises/tracks tickets via HTTP client | **~5% at the edge** | The sidecar has `web.client.Http` but uses it only to poll the control plane; it has no ticketing client. Ticketing does exist, but centrally on the **server** (the Ticketing feature: rules, `ListTickets`, `JiraCallback`, `TicketCallback`), not at the edge. So R3 as written (the sidecar raising tickets) is a genuine architectural change, not just wiring. |
| **R4** tamper-proof signed records (Ed25519 + hash chain) | **~20% (primitive proven, wrong layer)** | Real Ed25519 signing over JCS-canonical bytes is live **on the server** for GRC records (`Grc/Shared/grcsign.ky`, `sign.signHex` + `canonical`, mirroring acp), and Evidence/Assurance/Decisions sign too. The **sidecar signs nothing** (its `envoy.signature` is only a change-detection string). Violation records are unsigned and there is no hash chain anywhere. The crypto is ready to port; the violation path has none of it. |
| **R5** pull endpoints/packs/policies → sidecar store → Envoy + OPA | **~60% (the most built)** | The sidecar pulls the OPA bundle (`/v1/bundles/{name}`) and the endpoint registry (`/ai-endpoints`), caches the bundle to disk as last-good, renders Envoy config and mints per-host certs, and serves the bundle to the opa-envoy-plugin. The control plane exposes both routes. **Missing:** policy *packs* as a distinct pull, persistence in a **sidecar DB** (today it is flat-file plus in-memory, not kaidb/structured), and **signature verification** of pulled configuration. This loop predates this document; it is the sidecar's original job. |
| **Section 9, SaaS** (tenancy, billing, signup, landing/pricing) | **~5% (greenfield)** | `tenant_id` columns exist across the schema (row-level, inherited from the acp port) and Entra identity scaffolding exists (`EntraWhoami` / `EntraOnboard` / `EntraBindings`). But there are **no** organisations / plans / subscriptions / invoices / Stripe / billing tables, no self-serve signup, no entitlement enforcement, and no public landing or pricing pages (`wwwroot` is only the console SPA). |

**Summary.** Roughly one of the five sidecar refinements is real today: **R5's outbound sync loop**
(pull bundle plus endpoints, render Envoy, serve OPA), minus its packs, sidecar-DB, and
verify-signature parts. R1 to R4 as written for the sidecar do not exist: the violation path is still
the original opaque store-and-forward queue that captures and forwards bytes without parsing,
persisting structure, surfacing a screen, raising tickets, or signing. The two capabilities the design
leans on do exist, but server-side (Ed25519 signing for GRC/evidence; ticketing as a central feature),
so porting them to the edge is de-risked but not done. SaaS is greenfield, exactly as section 9
predicts. The sections below are the target; this table is the starting line.

## 1. Where we are today

The sidecar already runs on the framework reactor (`app.run(port)` with the background poll and flush
loops started from `App.onStart`). Its inbound contract is `POST /violations` and `POST /logs`, served
by `IngestHandler`. Today that handler does the minimum the store-and-forward contract demands: it
normalises the posted body, appends each record to a durable **flat-file queue** (`queue.ky`, a
length-prefixed append file), acknowledges immediately, and a background `flushLoop` ships batches to
the control plane and drops the rows the control plane confirms.

That is correct for "never lose a violation", but it has three limits that the refinements address:

- The queue is **opaque**. A record is just bytes (whatever OPA's decision log posted). The sidecar
  cannot answer "show me the last fifty denials for host X" without parsing the whole file, and it
  throws records away once the control plane confirms them, so there is no local history.
- The queue is **write-only from the operator's point of view**. There is no screen; you cannot see
  what the edge is blocking without going to the central console.
- The record is **unsigned**. Nothing stops a record being edited on disk between capture and flush,
  which is exactly the property an audit trail must not have.

## 2. Refinement R1: a structured, persisted violation store

### 2.1 The record

Every violation captured at the edge becomes a structured record, not an opaque blob. The fields we
need, at minimum:

| Field | Source | Notes |
|---|---|---|
| `id` | sidecar | monotonic local id, also the signing subject |
| `captured_at` | sidecar | wall-clock at ingest |
| `tenant` | `x-acp-tenant` header | which customer this edge serves |
| `endpoint_host` / `endpoint_port` | OPA decision input | the governed AI endpoint the call was headed to |
| `principal` | OPA decision input | who/what made the call (agent or user identity) |
| `prompt` | OPA decision input | **the request content that was judged** (the prompt or payload) |
| `verdict` | OPA decision | deny / step_up / shadow (allow is not a violation) |
| `policy_id` / `policy_name` | OPA decision | **which policy/rule matched** |
| `rule_rego_path` | OPA decision | the exact Rego path that fired, for traceability |
| `decision_id` | OPA decision log | correlates to OPA's own log line |
| `ticket_number` | ticketing (R3) | filled in once a ticket is raised; null until then |
| `ticket_status` | ticketing (R3) | open / acknowledged / closed, refreshed on sync |
| `signature` | signer (R4) | Ed25519 signature over the canonical record |
| `flush_state` | sidecar | pending / confirmed-by-cp |

The three fields the brief calls out explicitly, `prompt`, the violated `policy`, and the
`ticket_number`, are all first-class columns here, not buried in a JSON blob.

The `prompt` field needs a deliberate privacy decision, because it is request content and may carry
sensitive data. The record stores it, but the design should allow a per-tenant mode that stores a
**hash plus a redacted preview** instead of the full prompt, with the full text kept only long enough
to raise the ticket. This is written up as a configuration flag (`prompt_retention: full | redacted`)
rather than hard-coded, so a customer's data-handling posture drives it.

### 2.2 Storage choice: kaidb vs the flat file

We have `kyte-kaidb`, our own database with a driver. The question is whether the sidecar should hold
these records in kaidb or keep the flat file and add structure on top.

Honest tradeoff:

- **kaidb** gives us real queries (filter by host, verdict, time range; the console screen in R2 wants
  exactly this), indexes, and MVCC reads while the flush loop writes. The cost is that kaidb is a
  **server process with a wire protocol**, not an in-process embedded library, so the sidecar
  deployment grows a second container (a local kaidb instance) and a connection string. For a sidecar
  that is meant to be a small, self-contained edge agent, that is a real operational weight.
- **The flat file, upgraded** keeps the single-binary sidecar but means we hand-roll indexing and
  querying, which is how technical debt starts.

Recommended path: **keep the durable append file as the write-ahead, crash-safe capture path (its
"durable before ack" property is the thing we must not lose), and project each record into kaidb as
the queryable store.** The append file stays the source of truth for the store-and-forward contract;
kaidb is the read model the console and the ticketing logic query. Where a deployment cannot afford
the extra kaidb container (a minimal edge), the sidecar runs in flat-file-only mode and the console
screen degrades to "recent records, no rich filter". This matches NovaDB/kaidb's own scoping decision
(it is good as a bounded control-plane store, which is exactly this shape of data) without pretending
the sidecar must always carry a database.

This is a "maybe kaidb" per the brief: the design supports it and recommends it where the deployment
can carry it, but it is not mandatory and the durability contract does not depend on it.

## 3. Refinement R2: the sidecar as a Kyte web app with its own console

The sidecar already serves HTTP on the reactor. R2 says: lean into that and give it the same shape as
the Varman server console, a Kyte hypermedia app (KYX + Datastar) served from the sidecar itself.

Scope is deliberately small. The sidecar console is an **operator's edge view**, not a second copy of
the central console. Screens:

- **Violations** (the headline screen the brief asks for): a table of captured violations, newest
  first, with the columns that matter at the edge, time, host, principal, verdict, the policy that
  fired, a prompt preview, ticket number and ticket status, and the signature-verified badge (R4). It
  supports filtering by verdict and host and a time window (served by the kaidb read model from R1).
  Clicking a row opens the full record: the complete prompt (subject to the retention mode), the full
  Rego path, the raw OPA decision id, and the signature with a "verify" action that re-checks it.
- **Policy** (read-only): the currently cached bundle revision, when it was last synced, and the
  last-good fallback state. This already exists as `/healthz` and `/policy/rego`; the screen just makes
  it legible.
- **Health** (read-only): revision, control-plane reachability, queue depth, flush lag. Again this is
  `healthJson()` rendered as a page.

Build pattern is the one already proven for the server console (documented in the console CRUD pattern
note): a Datastar shell in `wwwroot`, nav fetches an SSE fragment, first-party `/console/*` handlers on
the sidecar serve the fragments. The violations screen is read-mostly; the only mutation from the UI is
"raise a ticket for this violation now" and "re-verify signature", both of which post to first-party
handlers. Because the sidecar is an internal, operator-facing surface it is bound to loopback or the
operator's network, not public ingress; it must not be exposed on the same route as the data-plane
proxy.

The existing data-plane endpoints (`/healthz`, `/policy/bundle`, `/policy/rego`, `/ai-endpoints`,
`/violations`, `/logs`) are unchanged. The console routes are additive and first-party.

## 4. Refinement R3: the sidecar raises and tracks tickets directly

When a violation is captured with a verdict that warrants it (deny, and optionally step_up per policy),
the sidecar raises a ticket in the external ticketing system and records the ticket number on the
violation record (the `ticket_number` / `ticket_status` fields from R1).

It does this with the Kyte web framework's HTTP client, `web.client.Http`, the same synchronous client
the sidecar already uses in `sync.ky` to poll the control plane. So there is no new dependency; we are
using a facility the sidecar already has.

Design:

- A small **ticketing client module** in the sidecar wraps `web.client.Http` and speaks the target
  system's REST API (the system is configurable: the Rust side already integrates ticketing, so the
  field names and the "create issue" / "get status" shape are ported from there). It carries its own
  auth (an API token from settings) independent of the control-plane bearer.
- **Raising** is triggered off the capture path but not inline with the ack: the ingest handler stays
  fast (durable-write then ack), and a background step (either the existing flush loop or a dedicated
  ticket loop) picks up violations whose `ticket_number` is still null, creates the ticket, and writes
  the returned number back onto the record. This keeps ticket-system latency and outages off the data
  path; a ticketing outage means tickets are raised late, never that a violation is lost.
- **Tracking**: a periodic poll (same loop) refreshes `ticket_status` for open tickets, so the
  Violations screen shows whether each one is still open, acknowledged, or closed.
- **Idempotency**: the create call carries a stable idempotency key derived from the violation `id`
  (and the signature), so a retry after a crash between "ticket created" and "number written back" does
  not open a duplicate ticket.

Configuration lives in `settings.ky` alongside the existing control-plane settings: ticketing base
URL, API token, project/queue id, and which verdicts auto-raise.

## 5. Refinement R4: tamper-proof, signed records

The Rust implementation's trust surface includes a **signed evidence ledger**: records are
cryptographically signed so that a stored record cannot be altered after the fact without detection.
We carry that property across using Kyte's own crypto: **Ed25519** is already ported into the standard
library (`crypto/ecc/ed25519.ky`, RFC 8032 verified), so this needs no new primitive.

Design:

- **Canonical form.** Each violation record is serialised to a canonical byte string (fixed field
  order, canonical JSON or a length-prefixed encoding; the Rust ledger's canonicalisation is the
  reference so the two remain differentially testable). The signature covers every field **except**
  the signature itself and the mutable ticket fields. Ticket number and status change after capture, so
  they are kept in a second, separately signed envelope, or excluded from the signed core with their
  own audit entries; the captured facts (prompt, policy, verdict, time) are immutable and signed once.
- **Signing key.** The sidecar holds a signing key (Ed25519 private key) provisioned at deploy time.
  The corresponding public key is published to the control plane so the central side, and the console,
  can verify any record the edge produced. This mirrors the Rust model where the signer's identity is
  verifiable centrally.
- **Chaining (tamper-evidence for the whole log, not just each row).** Beyond signing each record, each
  record includes the hash of the previous record's signature, forming a hash chain (a lightweight
  ledger). That upgrades the property from "you cannot edit a record" to "you cannot delete or reorder
  records" either, because a gap breaks the chain. This is the ledger property the Rust side provides
  and is cheap to add once records are signed.
- **Verification.** The console's Violations screen shows a verified badge per record and offers a
  re-verify action (R2). Verification re-canonicalises the record, checks the Ed25519 signature against
  the published public key, and checks the chain link to the previous record. A failure is surfaced
  loudly, a tampered or missing record is an incident, not a warning.
- **Boundary.** Signing happens at capture, inside the sidecar, before the record is written to the
  durable store and before it is flushed. So the signed artefact is what persists and what travels; the
  flat-file queue and the kaidb read model both hold the signed form. The control plane verifies on
  receipt and rejects anything that does not verify (fail-closed, consistent with the rest of the
  system).

Not asm-accelerated and not needed to be: violation volume at a single edge is low, and Ed25519 signing
is already fast enough for this path.

## 6. Refinement R5: provisioning sync (endpoints, packs, policies) into the edge

R1 to R4 are the inbound path. R5 is the outbound path: how the sidecar learns **what to enforce**. The
AI endpoints, the policy packs, and the policies all originate in the **control-plane database**; the
sidecar pulls them, persists them in its **own store**, and renders them into the two stock-tool
configs on the data plane: Envoy (for the endpoints) and the OPA bundle that the **opa-envoy-plugin**
evaluates (for the policies).

### 6.1 What flows, and from where

Three kinds of configuration, all authored centrally and consumed at the edge:

- **AI endpoints** (`governed_endpoints` in the control-plane DB): the set of upstream AI services the
  edge governs, as host/port plus the enabled flag (and per-endpoint TLS/cert material). These drive
  **Envoy**: each endpoint becomes a cluster plus the listener routing that sends egress through the
  proxy.
- **Policy packs**: the installed, versioned bundles of controls a tenant has turned on (the
  `policy_packs` / installed-pack state in the control-plane DB). A pack is the unit a customer
  installs; it expands into concrete policies.
- **Policies**: the authored rules (the UI rule-model compiled to OPA Rego, per the migration design).
  These, together with whatever the installed packs contribute, compile into the **OPA bundle**
  (gzip tar of `policy.rego` plus `.manifest`) that the opa-envoy-plugin loads and enforces.

The control-plane DB is the single source of authorship. The sidecar never authors; it pulls and
applies.

### 6.2 The pull, and the sidecar store as local source of truth

Today the sidecar already pulls two of these over the neutral HTTP contract: it polls
`/v1/bundles/{name}` for the OPA bundle and `/ai-endpoints` for the endpoint registry, and caches them
in memory plus the flat file. R5 extends this in two ways:

- **Add policy packs to the pull**, so the edge knows which packs a tenant has installed and at what
  version, not just the already-compiled bundle. This lets the sidecar console (R2) show *what* is
  being enforced (packs and policies by name), not merely that *a* bundle is loaded.
- **Persist all three into the sidecar store** (the kaidb read model from R1, with the flat
  file/last-good bundle remaining the crash-safe fallback). The store becomes the edge's **local source
  of truth**: on boot or when the control plane is unreachable, the sidecar renders Envoy and the OPA
  bundle from the last persisted configuration, so a cold start with a down control plane still comes up
  enforcing the last-good policy. This is the provisioning counterpart to "never lose a violation": the
  edge is never left with no configuration.

Each pull is tenant-scoped by the `x-acp-tenant` header the sidecar already sends, so a sidecar only
ever receives its own tenant's endpoints, packs and policies.

### 6.3 Rendering: endpoints to Envoy, policies to the opa-envoy-plugin

From the persisted store, the sidecar generates the two stock-tool configurations. This is the step
that actually changes what the data plane does:

- **Endpoints to Envoy.** The endpoint set is rendered into Envoy config (clusters first, then the
  listener), exactly as `envoy.writeConfig` does today, but sourced from the persisted store rather than
  straight from the last HTTP response. A change in the endpoint set (an endpoint added, disabled, or
  its cert rotated) re-renders the Envoy config and signals Envoy to reload.
- **Policies to the OPA bundle.** The installed packs plus authored policies resolve to the OPA bundle
  the **opa-envoy-plugin** enforces. The bundle wire format is preserved (the migration invariant), so
  whether the bundle is compiled centrally and shipped whole, or assembled at the edge from packs and
  policies, the artefact OPA loads is byte-compatible. The sidecar serves it locally on `/policy/bundle`
  (as now) and points the plugin at that path.

Only a genuine change re-renders and reloads: the sidecar compares the newly pulled configuration
against what is persisted, and if nothing changed it does nothing (the existing `setBundle` /
`setEndpoints` "changed?" check generalised to all three kinds). This keeps Envoy and OPA stable when
the control plane is simply being polled with no edits.

### 6.4 Consistency and failure posture

- **Fail-closed and last-good.** A failed pull never clears live configuration. The edge keeps
  enforcing the last persisted endpoints and policies until a successful pull replaces them. This is the
  same posture the current bundle sync has, extended to the persisted store so it survives a restart.
- **Atomic apply.** Endpoints and policies are applied as a set, not row by row, so Envoy and OPA are
  never rendered from a half-updated configuration. A pull is persisted in full first, then rendered.
- **Versioning.** Each persisted configuration carries the control-plane revision it came from, shown in
  the sidecar console and reported on `/healthz`, so an operator can see exactly which revision of
  endpoints and which pack/policy versions the edge is currently enforcing, and whether it is behind the
  control plane.
- **Signing (ties to R4).** The pulled configuration can be signed by the control plane and verified by
  the sidecar before it is applied, so the edge refuses to enforce a tampered or unauthenticated bundle.
  This makes the outbound path tamper-evident the same way R4 makes the inbound path tamper-evident.

### 6.5 Where this lands in the sidecar console

The R2 console gains a **Policy / provisioning** view fed by this persisted configuration: the governed
endpoints the edge is enforcing (and their Envoy state), the installed packs and their versions, the
authored policies in the current bundle, the control-plane revision, and when each was last synced. This
turns "a bundle is loaded" into "here is exactly what this edge enforces and where it came from".

## 7. How the pieces fit together

There are two flows: the outbound provisioning flow (R5) that arms the edge, and the inbound capture
flow (R1 to R4) that records what the armed edge blocks.

**Provisioning (outbound), on boot and on every poll tick:**

1. The sidecar pulls the **AI endpoints**, **policy packs** and **policies** for its tenant from the
   **control plane** (R5), verifying the signature on the pulled configuration (R4) before trusting it.
2. It **persists** them into its own store (kaidb read model plus the last-good fallback), recording the
   control-plane revision. If the control plane is down, it keeps the last persisted configuration.
3. If the configuration changed, it **renders** the endpoints into **Envoy** config and the packs plus
   policies into the **OPA bundle**, and signals a reload. The opa-envoy-plugin now enforces the new
   policy; Envoy routes egress through the new endpoint set.

**Capture (inbound), per governed call:**

4. A governed AI call hits **Envoy**; Envoy consults **OPA** (external authorization, via the
   opa-envoy-plugin) with the request as input.
5. OPA returns a verdict and writes a **decision-log** entry. For a non-allow verdict, the decision log
   is posted to the sidecar's `POST /violations`.
6. `IngestHandler` parses the decision into a **structured record** (R1), fills prompt / policy /
   verdict / principal / endpoint from the decision input, **signs it and links it into the hash chain**
   (R4), writes it to the **durable append file** (unchanged durability contract), projects it into
   **kaidb** (R1 read model), and acks.
7. A background step raises a **ticket** via `web.client.Http` (R3) and writes the ticket number back
   onto the record; a periodic poll refreshes ticket status.
8. The existing **flush loop** ships signed records to the control plane, which **verifies the
   signature and chain** before accepting, and confirms; confirmed rows are dropped from the append
   file but remain in the kaidb history.
9. An operator opens the sidecar **console** (R2) and sees both: what the edge is enforcing (endpoints,
   packs, policies, revision) and every violation it has captured, with prompt, policy, ticket, and
   signature-verified state.

## 8. Suggested phasing

These are ordered so each phase is independently testable and nothing regresses the durability
contract.

- **P1, structured record + signing.** Define the record and canonical form, add Ed25519 signing and
  the hash chain, keep writing to the flat file (now signed). Verifier on the control-plane side.
  Differential test the canonical form against the Rust ledger.
- **P2, kaidb read model.** Project records into kaidb; add the degrade-to-flat-file mode. No console
  yet; drive queries from tests.
- **P3, provisioning sync (R5).** Extend the pull to policy packs; persist endpoints / packs / policies
  into the store; render Envoy and the OPA bundle from the persisted store with the "changed?" guard and
  last-good fallback; verify the signature on pulled configuration. Differential test the rendered Envoy
  config and OPA bundle against the Rust sidecar's output.
- **P4, sidecar console.** The Violations / Policy-provisioning / Health screens over the kaidb read
  model, using the server console's Datastar pattern. Loopback-bound.
- **P5, ticketing.** The `web.client.Http` ticketing client, the background raise/track step,
  idempotency keys, settings. Wire `ticket_number` / `ticket_status` into the record and the screen.

## 9. SaaS product shape

This section is a different axis from R1 to R5. Those refine the enforcement path inside one deployment.
This one is about turning Varman into a commercial, self-serve, multi-tenant service running on **Azure
Container Apps**, with a public front door and billing. It is largely greenfield: the ported `acp`
schema is the governance core (the thing customers pay for), but it is wrapped today in a
**single-tenant shell with no commercial layer at all**.

### 8.1 What becomes relevant that was not before

Judged purely as an internal control plane, the landing page and the login form were close to dead
weight. As a SaaS they invert into the most important surfaces:

- **Marketing site**: a public landing page that states what Varman is (proxy your AI egress, get
  control-mapped evidence), who it is for, and why. A features page and a pricing page. This is the top
  of the funnel and is public, unauthenticated, cacheable.
- **Pricing and plans**: named tiers (for example Starter, Team, Enterprise) with the limits and
  features each includes: number of governed endpoints, seats, which compliance frameworks, evidence
  retention, whether the content firewall and drift monitoring are unlocked.
- **Self-serve registration**: choose a plan, create an organisation, verify email, pay (or start a
  trial), and land in an onboarding flow. The decorative dev-mode login becomes a real authentication
  and signup system.
- **Session and tenant auth**: a multi-tenant service needs real sessions with revocation and strict
  per-tenant isolation. The `entra_tenant_map` and `revoked_sessions` tables, dormant in the
  single-tenant build, become load-bearing (whether via Entra or an own-auth plus billing-linked
  accounts model).

### 8.2 The commercial and tenancy layer (new schema)

The `acp` schema has no notion of a paying account, a plan, a subscription, a seat, or usage. These are
new and must be added. None of them touch the governance tables' meaning; they wrap them.

- **Tenancy.** An `organisations` table is the paying account. Every governance table
  (governed endpoints, decisions, evidence, policies, tickets, and so on) gains a `tenant_id` column so
  one customer's data is isolated from another's. This per-tenant partitioning is the **single largest
  piece of work** in the SaaS track, because the ported schema was written single-tenant and the
  isolation has to be enforced in every repository query, not just declared. Postgres row-level
  security is the backstop so a missed `WHERE tenant_id = ?` cannot leak across tenants.
- **Identity and membership.** `members` (users belonging to an organisation, with roles), invite flow,
  and the mapping from an authenticated identity to its organisation and role.
- **Plans and subscriptions.** `plans` (the catalogue, versioned), `subscriptions` (organisation to
  plan, status, current period, trial state), and the entitlement set each plan grants.
- **Billing.** A payment-provider integration (Stripe is the assumed first target), a
  `billing_customer_id` on the organisation, `invoices` / `payment_state`, and webhook handling for
  subscription lifecycle events (payment failed, subscription cancelled, plan changed).
- **Usage metering.** `usage_meters` recording whatever we bill on: governed requests, active
  endpoints, seats in use. This feeds both plan-limit enforcement and usage-based billing. The violation
  records from R1 and the decision volume are natural metering sources.

### 8.3 Entitlement enforcement

Having plans in a table is not enough; the application must enforce them. A plan defines limits
(Starter caps governed endpoints at N, only Enterprise unlocks all frameworks and the content
firewall), and the console and the machine APIs must gate on the organisation's current entitlement:
the "add endpoint" action refuses past the cap with a clear upgrade prompt, framework toggles beyond
the plan are disabled, and over-limit usage either blocks or meters into overage per the plan. This
entitlement check is a small shared service consulted by every mutating handler, not logic scattered
per screen.

### 8.4 How it wraps the governance core without changing it

The design keeps the governance core (the ported `acp` engine, the verdict semantics, the evidence
ledger, the sidecar refinements R1 to R5) untouched. The SaaS layer sits around it:

- **Public tier** (marketing, pricing, signup) is a separate, unauthenticated surface. It never touches
  governance data.
- **Tenant context** is resolved once per request from the authenticated session and threaded into
  every repository call as `tenant_id`. The governance logic does not know it is multi-tenant; it just
  operates on the rows its tenant filter returns.
- **Metering and entitlement** are cross-cutting middleware: meter on the way out, check entitlement on
  the way in. Neither changes a verdict.
- **The sidecar** is per-tenant at the edge: its `x-acp-tenant` header (already present) ties every
  violation it captures and every signed record it produces to one organisation, so the R1 to R4 work
  is already tenant-aware by construction.

### 8.5 What stays irrelevant even under the SaaS lens

The SaaS reframing does not resurrect everything. These remain dead or deferred and can be dropped or
shelved regardless:

- `control_leader` (bespoke HA leader election): Container Apps scales by replicas behind its own
  ingress; we do not hand-roll leader election. Dead.
- `control_crosswalk`, `seeds`, `report_snapshots`, `firewall_rules`: zero-reference dead tables.
- The duplicate `endpoints` table (live code uses `governed_endpoints`).
- The content firewall and drift / lineage monitoring (`firewall_config`, `drift_counts`,
  `lineage_edges`): genuine roadmap, not launch-blocking. Fine to gate behind a higher plan tier and
  ship later; they should not block an MVP and should not appear as live console nav until built.

### 8.6 Azure Container Apps shape

- The **server** (console plus machine APIs) is one container app with external ingress; the public
  marketing and signup tier can be the same app serving unauthenticated routes, or a separate static
  front end, depending on how much the landing page diverges from the app.
- **Postgres** is a managed instance (Azure Database for PostgreSQL), holding the governance schema plus
  the new tenancy and billing tables, with row-level security on.
- The **sidecar** is deployed per customer edge (often in the customer's own environment), not centrally;
  it reaches the control plane over the neutral HTTP contract it already uses.
- Scaling is by Container Apps replicas. This is exactly why `control_leader` is unnecessary: the
  platform owns horizontal scale and ingress, and the server is designed single-reactor-per-instance,
  scaled by instances.

### 8.7 Suggested phasing for the SaaS track

Separate from the R1 to R5 phasing; can run in parallel since it touches different code.

- **S1, tenancy spine.** Add `organisations`, `members`, and `tenant_id` across the governance tables;
  enforce the tenant filter in every repository and turn on row-level security. This is the big one and
  everything else depends on it.
- **S2, auth and signup.** Real authentication, organisation creation at signup, invite flow, sessions
  with revocation.
- **S3, plans and entitlement.** `plans`, `subscriptions`, the entitlement service, and gating in the
  console and APIs (limits visible and enforced, upgrade prompts).
- **S4, billing.** Stripe integration, `invoices` / payment state, webhook lifecycle handling, trial
  and dunning flows.
- **S5, marketing and metering.** The public landing and pricing pages, usage metering feeding billing
  and limit enforcement, onboarding polish.

## 10. Roadmap beyond the refinements: content-aware policy

R1 to R5 and the SaaS layer make the machine complete and trustworthy. They do not, on their own, make
it say much. Today the plane governs **which endpoints** a call may reach and **who** may make it: OPA
judges the routing-level facts (host, port, principal, tenant) that Envoy hands it. The signed
violation record even has a `prompt` field, but nothing in the enforcement path actually inspects that
prompt to reach a verdict. This section is the roadmap item that closes that gap, because it is where
the product's real differentiation lives.

**What it is.** Content-aware policy is the ability to make a verdict on **what is in the request and
response bodies**, not just the connection metadata: the prompt text, the tool-call arguments, the
model's response. It is what lets a policy catch prompt-injection, data exfiltration, PII or secret
leakage in a prompt, unsafe tool invocation, or a disallowed topic, rather than only "this agent may
not talk to that endpoint". It is the difference between "we proxy and log your AI traffic against
controls" and "we catch the bad thing in the prompt".

**Why it is the moat.** Most of the market is dashboards and questionnaires. Proxied egress that blocks
is already a real control (the refinements deliver that). Content-aware enforcement is the capability
that is genuinely hard to build and genuinely valuable, and it is the natural destination of everything
the refinements put in place: the bundle pipeline (R5) ships the policies, the edge (R1 to R4) captures
and signs the evidence, and this layer gives the policies something substantive to decide on.

**Where it sits in the architecture.** The current data path (Envoy → OPA via the opa-envoy-plugin) is
authorization over request attributes. Body inspection needs a step that can see and act on the payload:

- an **Envoy external-processing (ext_proc) filter** or a body-tap that streams the request/response
  bodies to an inspector before the call is allowed to proceed, so a verdict can block, redact, or
  step-up based on content; and
- an **inspector** that runs the content checks. This is exactly the **content firewall** track parked
  as roadmap in the implementation status (`firewall_config` / `firewall_rules` in the schema, no
  feature today). Content-aware policy is that track, made real and wired into the verdict.

Checks range from cheap and deterministic (regex/pattern/entropy for secrets, PII detectors, denylists)
to expensive and probabilistic (a classifier or an LLM-as-judge call for injection or topic). The
design should treat the inspector as a pipeline of checks with a cost/latency budget, not a single
model call on the hot path.

**How it ties to the refinements.**

- **R5 (provisioning).** Content rules become part of what the control plane authors and the sidecar
  pulls and renders, alongside the OPA bundle. The still-empty Policy-versions screen is the authoring
  pipeline that compiles UI-authored content rules into the enforced artefact; this is the work that
  fills it.
- **R1 and R4 (evidence).** A content verdict produces exactly the signed, control-mapped violation
  record the refinements already define, now with the matched content rule and a redacted snippet of
  the offending text. The `prompt_retention: full | redacted` flag from R1 becomes load-bearing here,
  because content inspection is precisely where sensitive payloads are handled.
- **R2 (console).** The sidecar and server consoles gain the content-rule authoring and the
  content-violation views.

**The hard parts, stated honestly.**

- **Latency on the hot path.** Inspecting bodies, especially with a classifier or judge model, adds
  real latency to every governed call. This needs streaming, inline-vs-async modes (block only on cheap
  checks, shadow the expensive ones), and a per-policy budget.
- **Privacy.** The inspector sees raw prompts and responses. Where inspection runs (in the customer's
  own environment at the edge, never shipping raw content centrally) and what is retained are
  first-order design and trust decisions, not afterthoughts.
- **Accuracy and the verdict model.** Probabilistic checks produce false positives and negatives;
  fail-closed on a flaky classifier is a product problem. The four-way verdict (deny / step_up / shadow
  / allow) is the right escape valve here (shadow-mode a new content rule before it blocks), but it has
  to be deliberately applied.
- **It is a program, not a refinement.** Unlike R1 to R5 this is not a bounded sidecar change; it is a
  new subsystem (filter + inspector + content-rule authoring + model/detector integrations) and should
  be scoped and staged as its own track once the refinements land.

**Suggested first slice.** Ship the cheap, deterministic, inline checks first (secret/PII/denylist
patterns over request bodies via an ext_proc tap), producing signed content-violation records through
the R1 to R4 path, authored and provisioned through R5. That proves the whole content path end to end
with bounded latency and no model dependency, and is a sellable capability on its own. The probabilistic
layer (injection and topic classifiers, LLM-as-judge) is a second slice on top.

## 11. Open questions

- **Prompt retention default.** Full prompt vs hash-plus-redacted-preview as the default, and whether
  that is a product-tier or a per-tenant setting. Leans to redacted-by-default for a SaaS posture.
- **kaidb as a sidecar dependency.** Whether every edge deployment can carry a local kaidb container,
  or whether flat-file-only is the common case and kaidb is an opt-in for heavier edges.
- **Key provisioning and rotation.** How the sidecar's Ed25519 signing key is provisioned at deploy and
  rotated, and how the control plane tracks the set of valid edge public keys over a rotation.
- **Ticket system target.** Which ticketing system is first (the Rust integration's target), and
  whether the client abstracts over more than one.
- **Auth strategy for SaaS.** Own auth with billing-linked accounts, Entra/enterprise SSO, or both
  (own auth for self-serve tiers, SSO for Enterprise). Decides how much of `entra_tenant_map` is reused.
- **Billing model.** Flat per-tier, per-seat, usage-based (per governed request or per endpoint), or a
  hybrid with overage. This drives what `usage_meters` must record and how fine-grained metering is.
- **Marketing site coupling.** Whether the public landing and pricing pages live inside the server app
  or as a separate static front end, and how tightly they share styling with the console.
- **Tenant data residency.** Whether Enterprise customers need region-pinned data or a dedicated
  instance, which affects whether one multi-tenant Postgres is sufficient or per-tenant isolation must
  go further than row-level security.
- **Content inspection placement.** Whether body inspection (section 10) runs only at the customer-edge
  sidecar (raw content never leaves their environment) or can optionally run centrally, and how that
  choice is surfaced as a trust/plan decision.
- **Inline vs async content checks.** Which content checks are allowed to block on the hot path versus
  run in shadow, and what per-policy latency budget is acceptable before a call proceeds.
- **Classifier/judge dependency.** Whether the probabilistic content layer calls an external model, a
  self-hosted one, or is pluggable per tenant, given the latency, cost, and data-handling implications.
