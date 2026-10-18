# Varman Pilot Readiness Plan

Audience: design-partner engineering and security teams evaluating a first pilot of Varman, the on-prem Agent Control Plane (Kyte implementation).

This document is deliberately candid about what is ready and what is not. A pilot should start from an accurate picture, not a sales picture.

## 1. Objective and shape of the pilot

The goal of the first pilot is narrow and provable: run Varman in **shadow mode** alongside one or two governed AI endpoints, for one team, measured against one compliance framework, and at the end hand the customer an **independently verifiable audit evidence pack** covering a defined number of decisions.

Shape:

- **Mode:** shadow first. Varman records decisions and downgrades any would-be block to "shadow", so it never blocks live traffic during the pilot. Enforcement is a later, opt-in phase.
- **Scope:** 1 to 2 governed endpoints (for example, one agent tool-call path or one model-serving route), one owning team, one target framework (for example, EU AI Act or NIST AI RMF).
- **Window:** 4 to 8 weeks.
- **Concrete success metric:** produce an evidence pack for N decisions (suggested N = 500 to 5,000 depending on traffic) that the customer's own security reviewer can verify using only the public key, with the Merkle inclusion and consistency proofs checking out and no trust in the Varman store required.

If that evidence pack verifies on the customer's own machine, the pilot has demonstrated the core value: tamper-evident, independently auditable governance of agent traffic, running entirely inside the customer's environment.

## 2. Engineering readiness checklist

Honest status as of this plan. Items marked TODO or IN PROGRESS are prerequisites that must close (or be explicitly waived by the customer) before the corresponding phase.

| # | Item | Why it matters for a pilot | Status |
|---|------|----------------------------|--------|
| 1 | Trust core: Ed25519 signing, SHA-256, RFC 6962 Merkle ledger (inclusion + consistency), JCS canonical bytes | This is the core deliverable; evidence packs verify independently with the public key alone. 70/70 library unit tests pass. | DONE |
| 2 | Content firewall signs and hash-chains violation records (Ed25519, prevSig chain) | Edge-local, tamper-evident violation records. | DONE |
| 3 | OBSERVE / SHADOW mode (record and downgrade blocks) | The pilot runs in shadow; this must work and is tested behaviour. | DONE |
| 4 | Fail-closed-to-last-good in the sidecar when control plane is unreachable | Safety guarantee for the data plane. | DONE |
| 5 | Policy compiled to Rego (OPA) plus in-process manifest engine (deny > step_up > shadow > allow, fail-closed-to-deny on error) | Policy authoring and enforcement path. | DONE |
| 6 | Compliance catalogue: 265 controls, 12 frameworks, article citations and crosswalks | Framework reporting during and after the pilot. | DONE |
| 7 | Schema migrations auto-apply from the binary (`server --migrate`) | Clean install and upgrade in the customer VPC without manual SQL. Verified: applies 10 migrations, idempotent. | DONE |
| 8 | Durable approvals store (Postgres-backed) | Approvals survive restart. Verified: register -> kill -> restart -> still pending. | DONE |
| 9 | One green end-to-end (cf-local-test.sh) | Full author -> enforce -> sign -> verify loop passes (11/11). | DONE |
| 10 | Server-side automated tests | Security-critical capability gates covered by e2e integration checks (unauth/under-privileged -> 403). Broader offline unit tests need an app.run harness (PG handlers cannot run under the standalone test driver). | PARTIAL |
| 11 | Entra / OIDC JWKS signature verification | id_token RS256 signature verified against the fetched tenant JWKS, fail-closed, before any claim is trusted. Verify + JWK-set parse tested hermetically; live Microsoft fetch exercised at cutover. | DONE |
| 12 | Deploy packaging and SBOM | Customer needs a clean, inventoried artefact to run in their VPC. | TODO |
| 13 | Backup and restore procedure (Postgres + ledger) | Operability and evidence durability. | TODO |
| 14 | Observability: structured logs and health/metrics endpoints | Pilot operability and incident triage. | TODO (partial logging exists) |
| 15 | Kill-switch runbook (scoped disable) | Required rollback control. | TODO (document + test) |

The library and enforcement core are the strongest part. The gaps are in operational hardening (migrations, durability, packaging, tests, JWKS verify). None of these block a **shadow-mode** pilot that starts with a controlled, hands-on deployment, but items 7, 8, 9, 11 and 15 should close before any **enforce** phase.

## 3. Deployment model for the pilot

Everything runs inside the customer's own environment. Varman is on-prem / in-VPC by design.

- **Control plane** (`server/`): the Kyte web server with the Datastar hypermedia console. Runs in the customer VPC. Postgres-backed.
- **Data plane** (`sidecar/`): an Envoy `ext_authz` handler plus the content firewall, deployed next to the governed endpoint. Enforces at the edge and fails closed to last-good config if the control plane is unreachable.
- **Postgres:** hosted by the customer. Varman does not require a managed or vendor-hosted database.
- **Signing keys:** held by the customer. The Ed25519 signing seed is customer-held configuration. It never leaves their environment, and Varman (the vendor) never receives it.
- **Prompt data:** content inspection is edge-local in the sidecar. Raw prompts never leave the customer environment.

Net effect: the vendor does not see prompts, does not hold keys, and does not host the data. This is the deployment property the security packet in `docs/security/` documents in detail.

## 4. Pilot phases

### Phase A: Shadow
- **Entry criteria:** checklist items 1 to 6 DONE; sidecar deployed next to the governed endpoint; control plane reachable; keys generated and held by the customer; a target framework chosen.
- **Activity:** all traffic to the governed endpoint is observed. Decisions are recorded and signed. Any would-be block is downgraded to shadow. No traffic is blocked.
- **Exit criteria:** a steady stream of signed decision records is being produced; the customer can see decisions in the console; at least one framework report renders from runtime coverage.

### Phase B: Narrow enforce (optional, opt-in)
- **Entry criteria:** Phase A exit met; checklist items 7, 8, 9, 11, 15 closed; the customer explicitly opts in to enforcement on a named, narrow rule set; kill-switch runbook tested in a dry run.
- **Activity:** a small, agreed set of rules moves from shadow to real enforcement (deny or step_up) on the scoped endpoint only. Everything else stays in shadow.
- **Exit criteria:** enforcement behaves as specified; no unintended blocks outside the agreed rules; kill-switch demonstrated live.

### Phase C: Evidence-pack delivery
- **Entry criteria:** N decisions accumulated (from Phase A and/or B).
- **Activity:** export an evidence pack for the N decisions. The customer's security reviewer verifies it independently, using the public key only, checking Merkle inclusion and consistency proofs.
- **Exit criteria:** the pack verifies on the customer's own machine with no trust in the Varman store. This is the pilot's headline success metric.

## 5. Rollback, kill-switch, and the "it must never break your AI" guarantee

Three layers protect the customer's live AI traffic:

1. **Shadow mode.** During Phase A (and for everything not explicitly promoted in Phase B), Varman records and downgrades blocks to shadow. It cannot block traffic in this state. This is tested behaviour.
2. **Fail-closed to last-good.** If the control plane becomes unreachable, the sidecar does not fail open to "no governance" and does not hard-stop on a missing control plane. It continues on the last-good configuration it already holds. ("Fail closed" here means it keeps enforcing the known-good policy rather than dropping governance; in shadow that known-good policy still does not block.)
3. **Scoped kill-switch.** A single, documented control disables enforcement for the governed endpoint and returns it to pure shadow (or to pass-through), scoped to the pilot endpoint only, without touching anything else. The runbook for this (checklist item 15) is a hard prerequisite for Phase B.

The combined guarantee: in the shadow phase Varman physically cannot block the customer's AI, and in the enforce phase the customer holds a tested, one-step switch back to shadow.

## 6. Roles, timeline, and what we need from the customer

### Roles
- **Varman engineer (us):** deployment support, policy authoring help, evidence-pack export, verification walkthrough.
- **Customer endpoint owner:** provides and operates the governed endpoint.
- **Customer platform / SRE:** hosts Postgres, runs the control plane and sidecar in the VPC.
- **Customer security reviewer:** independently verifies the evidence pack and signs off on the security packet.

### What we need from the customer
- One, at most two, AI endpoints to govern (an agent tool-call path or a model-serving route).
- A representative test corpus of prompts / tool-calls for the shadow phase.
- A named security reviewer who will run the independent verification.
- An Entra tenant for SSO (note: JWKS signature verification is still TODO in the Kyte port; see the questionnaire).
- A Postgres instance they host.

### Indicative 8-week timeline

| Week | Focus |
|------|-------|
| 1 | Environment access, deploy control plane + sidecar in VPC, customer generates and holds signing keys, Postgres stood up. |
| 2 | Wire sidecar to the governed endpoint, confirm shadow mode, first signed decisions visible in console. |
| 3 | Author policy for the target framework, confirm framework report renders, tune rules in shadow. |
| 4 | Steady-state shadow run, accumulate decisions, mid-pilot review with the security reviewer. |
| 5 | Close enforce prerequisites (migrations, durable approvals, green e2e, JWKS, kill-switch runbook); dry-run the kill-switch. |
| 6 | Optional Phase B: promote a narrow rule set to enforce on the scoped endpoint; validate no unintended blocks. |
| 7 | Reach N decisions; export the evidence pack; reviewer runs independent verification. |
| 8 | Verification sign-off, framework report walkthrough, expand / hold decision, written readout. |

For a 4-week pilot, collapse to Weeks 1 to 4 and 7, staying in shadow throughout and skipping Phase B.

## 7. Success criteria and the "expand" decision

The pilot is a success if:

1. The evidence pack for N decisions verifies independently, on the customer's own machine, using the public key alone, with Merkle inclusion and consistency proofs intact.
2. Shadow mode demonstrably never blocked live traffic, and (if Phase B ran) enforcement was confined to the agreed rules with a working kill-switch.
3. At least one framework report renders from real runtime decision and evidence coverage, with article citations the reviewer accepts as meaningful.
4. The security reviewer is satisfied that the vendor never saw raw prompts and never held the signing keys.

A "yes, expand" decision looks like: move from one endpoint to several, from one framework to the customer's full applicable set, from shadow to selective enforcement, and begin closing the production-hardening roadmap (HA, third-party pen test, SOC 2, independent crypto audit) as a condition of production use. A "not yet" decision should point at specific unmet criteria above, not a vague impression.

## Appendix: engineering fix plan (concrete approach per readiness item)

This appendix records the exact approach and touch points for the IN PROGRESS / TODO
items, so the work is actionable and reviewable. Each should be done as its own
change, built, and verified against a live Postgres (the dev `acp` database), not
batched, because the server currently has no automated test net.

### Item 7: schema migrations auto-apply (IN PROGRESS, highest priority)

Today `server/src/main.ky` `runMigrations()` only lints and logs, then returns 0; it
never opens a connection. `server/src/migrations.ky` declares 10 of the roughly 43
tables in `server/docs/acp-schema.sql`.

Approach:
- Apply through the stdlib runner `data.migrate.run(conn, migrations)` (it owns the
  advisory lock, the version table, and the per-step `exec`). The pool API is
  `await db.pool.acquire()` / `db.pool.release(conn)`, mirrored from
  `Features/Decisions/Shared/DecisionRepository.ky`.
- Because `acquire`/`run` are async, `--migrate` must drive one coroutine to
  completion on a reactor (the one-shot analogue of `app.run`). Use the reactor
  start hook (`app.onStart`) in a migrate-only `App`: the start task `coroStart`s the
  apply coroutine and exits the process on completion with the apply status. Verify
  by pointing `db.dsn` at a scratch database and confirming the tables and the
  `schema_migrations` version row are created, and that a second run is a no-op.
- Complete the migration set to cover every table the handlers read/write (audit the
  43-table reference schema against the live `Repository<...>` binds).

Acceptance: `server --migrate` against an empty database exits 0 and creates the full
schema; re-running is idempotent; the server then boots and serves against it.

### Item 8: durable approvals (IN PROGRESS)

`ApprovalStore` is in-memory, so holds and approvals are lost on restart.

Approach: add an `approvals` (and `approval_holds`) table to `migrations.ky`; replace
the in-memory store with a Postgres repository following the `DecisionRepository`
pattern (`acquire` / parameterised `exec` / `release`); keep the same interface so the
`Approvals` feature handlers are unchanged. Preserve the capability check
(`requireCap(Approve)`) and record the approver identity and timestamp for the
evidence trail.

Acceptance: create a hold, restart the server, approve it; the approval resolves and
is written to the signed ledger.

### Item 9: one green end-to-end (IN PROGRESS)

`scripts/cf-local-test.sh` fails because it posts rule-saves unauthenticated after the
console save endpoint began requiring `Auth.Capability.EditPolicy` and binding tenant
from the session.

Approach: give the script an authenticated path (establish a dev session via
`--dev-auth` and carry the session cookie / CSRF token on the save requests), or add a
narrow, clearly-labelled machine ingestion endpoint for rule provisioning that is
capability-gated by a bearer token rather than a browser session. Then re-run so rules
persist, the sidecar pulls a non-empty set, and the secret/injection cases are blocked
and recorded.

Acceptance: `cf-local-test.sh` passes all checks, demonstrating author -> pull ->
enforce -> sign -> verify end to end.

### Item 10: server tests (TODO)

Add a `server/tests` suite covering the security-critical glue: the capability/auth
gates (unauthenticated and under-privileged requests are refused), the OPA bundle is
signed and verifies, and a decision log ingested over the wire lands in the `decisions`
table with the right verdict and controls. Use the offline `app.dispatch(req)` pattern
(no socket) as in the web guide, plus a disposable Postgres schema for the SQL paths.

### Item 11: Entra JWKS verification (TODO)

The Kyte port parses the Entra `id_token` but does not yet verify its RS256 signature
against the tenant JWKS; it currently relies on TLS transport. Fetch and cache the
tenant JWKS, verify the token signature and the `iss` / `aud` / `exp` / `nonce` claims
before trusting identity. This is required before the enforce phase of any pilot.
