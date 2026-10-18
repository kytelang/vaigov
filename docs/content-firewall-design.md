# Varman content firewall: design

This document designs the **content firewall**: the layer that makes a verdict on *what is in the
request and response bodies* of a governed AI call, not just the connection metadata. It is written to
be built in **Kyte**, as a component of the existing sidecar, and it is the realisation of the roadmap
item in `design-refinements.md` section 10.

It follows the stance agreed in that section and in discussion: inspect at the **TLS-terminating
proxy** (never raw packets), **deterministic / regex rules first** (no ML on the hot path),
**edge-local** (raw prompts never leave the customer's environment), **model-pluggable** and
**latency-budgeted** for the later probabilistic layer, and **marketed honestly** (deterministic checks
are an enforcement guarantee; probabilistic checks are advisory until a customer promotes them).

Everything here builds on the shipped refinements: the signed violation store (R1), the operator
console (R2), ticketing (R3), Ed25519 signing and chaining (R4), and the pull-and-render provisioning
loop (R5). The content firewall authors nothing new on the trust surface; it produces the same signed,
control-mapped violation records the rest of the system already understands.

## Contents

1. [Where it fits (and why not packet interception)](#1-where-it-fits-and-why-not-packet-interception)
2. [Request path](#2-request-path)
3. [The rule model](#3-the-rule-model)
4. [The deterministic engine](#4-the-deterministic-engine)
5. [The ext_authz check handler](#5-the-ext_authz-check-handler)
6. [Envoy wiring](#6-envoy-wiring)
7. [Provisioning rules (R5)](#7-provisioning-rules-r5)
8. [Verdict and evidence (R1 + R4)](#8-verdict-and-evidence-r1--r4)
9. [Verdict semantics and the shadow escape valve](#9-verdict-semantics-and-the-shadow-escape-valve)
10. [Latency and the fast/slow split](#10-latency-and-the-fastslow-split)
11. [Privacy](#11-privacy)
12. [Response-body inspection](#12-response-body-inspection)
13. [Redaction and mutation (the ext_proc track)](#13-redaction-and-mutation-the-ext_proc-track)
14. [Redteam, made real](#14-redteam-made-real)
15. [Configuration surface](#15-configuration-surface)
16. [Phasing](#16-phasing)
17. [Testing](#17-testing)
18. [Honest limits and open questions](#18-honest-limits-and-open-questions)

## 1. Where it fits (and why not packet interception)

AI endpoints are HTTPS. A packet interceptor sees TLS-encrypted bytes; you cannot regex a prompt out of
an encrypted packet. The only place the body is plaintext is where TLS is terminated, and that place
already exists in Varman: the sidecar's **Envoy** bump proxy terminates TLS to each governed endpoint
(it mints a per-host leaf cert under the Varman CA, see `sidecar/src/envoy.ky`). So the content firewall
hooks in at the proxy, one layer above packets.

The crucial observation: the Envoy bump chain **already forwards the request body to an external
authorization service**. The current `ext_authz` filter calls OPA over gRPC with
`with_request_body: { max_request_bytes: 65536 }`. The content firewall is therefore not new plumbing,
it is a **second `ext_authz` filter in the same chain** that calls a small Kyte service with the same
request body. We use the **HTTP variant** of `ext_authz` (`http_service`, not `grpc_service`), so the
inspector is a plain Kyte HTTP handler. No gRPC server is required, which matters because Kyte has
HTTP/1.1 and HTTP/2 but not a gRPC server; `ext_authz` HTTP needs neither.

The inspector is **co-located in the sidecar process**. It reuses the sidecar's signed store (R1), its
signing key (R4), and its rule provisioning (R5) directly, with no cross-process hop: a content verdict
becomes a signed record in the same local store the console reads. A separate-process deployment is
possible (the contract is just HTTP) but co-location is the default and the simplest.

## 2. Request path

```
client / app
   │  HTTPS to api.openai.com (routed through the sidecar's Envoy)
   ▼
Envoy bump chain (terminates TLS with the host leaf cert)
   ├─ ext_authz #1  → OPA (routing-level verdict: who/where, as today)
   ├─ ext_authz #2  → Kyte content inspector  POST /cf/check   ◄── NEW
   │                     reads the request body (the prompt)
   │                     runs the deterministic rule engine
   │                     allow → 200 ; block → 403 (+ records a signed violation)
   └─ router → upstream AI endpoint (only if both allowed)
```

Deny-over-allow falls out of Envoy's filter ordering: if either `ext_authz` returns a non-2xx, the
request is blocked before it reaches the router, so the call never leaves the edge. The content
inspector runs after OPA so it only inspects calls that passed routing policy (cheaper, and it never
sees traffic to ungoverned endpoints).

## 3. The rule model

A content rule is data, authored centrally and provisioned to the edge. The Kyte type (proposed
`sidecar/src/cf/rule.ky`):

```kyte
//! A content-firewall rule: a deterministic check over request/response text.

/// What the rule looks for.
///   "regex"    - the `pattern` is a regular expression (text.regex)
///   "substr"   - case-insensitive substring match on `pattern`
///   "secret"   - built-in secret/high-entropy detectors (pattern selects which)
///   "pii"      - built-in PII detectors (pattern selects: email|ssn|card|phone)
///   "size"     - body length exceeds `threshold`
pub struct ContentRule {
    pub id: string,              // stable id (also used in evidence)
    pub name: string,            // human name, shown in the console
    pub kind: string,            // regex | substr | secret | pii | size
    pub pattern: string,         // the regex / substring / detector selector
    pub threshold: int,          // for kind="size"
    pub target: string,          // "request" | "response" | "both"
    pub action: string,          // "block" | "shadow" | "step_up"
    pub severity: string,        // "low" | "medium" | "high" | "critical"
    pub controlIds: List<string>,// mapped governance controls (for evidence)

    init(id: string, name: string, kind: string, pattern: string) {
        self.id = id; self.name = name; self.kind = kind; self.pattern = pattern;
        self.threshold = 0; self.target = "request"; self.action = "block";
        self.severity = "medium"; self.controlIds = List<string>();
    }
}
```

A rule's `action` is how it maps to the four-way verdict: `block` → deny, `step_up` → step_up,
`shadow` → record-but-allow. Severity and `controlIds` travel into the evidence record so a violation is
control-mapped the moment it is caught.

Rules are grouped into a signed **rule set** pulled from the control plane (section 7). The deterministic
set is first-party and owned; the probabilistic set (classifiers) is pluggable (section 10).

## 4. The deterministic engine

The engine compiles each rule once and evaluates request/response text against the active set. It uses
Kyte's `text.regex` (`compile`/`test`/`exec`) for `regex` rules and `string` for the rest. Proposed
`sidecar/src/cf/engine.ky`:

```kyte
import text.regex;
import string;
import list;

/// The outcome of evaluating text against the rule set.
pub class ContentVerdict {
    pub decision: string,     // "allow" | "deny" | "step_up" | "shadow"
    pub ruleId: string,       // the rule that fired ("" if allow)
    pub ruleName: string,
    pub severity: string,
    pub matchIndex: int,      // offset of the match, for a redacted snippet
    pub controlIds: list.List<string>,

    init() {
        self.decision = "allow"; self.ruleId = ""; self.ruleName = "";
        self.severity = ""; self.matchIndex = -1; self.controlIds = list.List<string>();
    }
}

/// A compiled rule: the rule plus its prepared regex (when kind="regex").
pub class Compiled {
    pub rule: ContentRule,
    pub rx: regex.Regex | undefined,
    init(rule: ContentRule) { self.rule = rule; self.rx = undefined; }
}

/// Compiles a rule set once (called when provisioning installs a new set).
pub fn compileAll(rules: list.List<ContentRule>): list.List<Compiled> {
    let out = list.List<Compiled>();
    let i = 0;
    while (i < rules.size()) {
        let r = rules.get(i) ?? ContentRule("", "", "substr", "");
        let c = Compiled(r);
        if (string.eql(r.kind, "regex")) { c.rx = regex.compile(r.pattern); }
        out.push(c);
        i = i + 1;
    }
    return out;
}

/// Does a single compiled rule match `text`? Deterministic, side-effect free.
fn ruleMatches(c: Compiled, text: string): bool {
    let r = c.rule;
    if (string.eql(r.kind, "regex")) {
        let rx = c.rx ?? regex.compile("$a"); // never-match fallback
        return rx.test(text);
    }
    if (string.eql(r.kind, "substr")) {
        return string.contains(string.toLowerCase(text), string.toLowerCase(r.pattern));
    }
    if (string.eql(r.kind, "size")) {
        return text.length > r.threshold;
    }
    if (string.eql(r.kind, "pii") || string.eql(r.kind, "secret")) {
        return detect(r.pattern, text); // built-in detectors, section below
    }
    return false;
}

/// Evaluates `text` against the compiled set. First non-shadow match that would
/// BLOCK wins (deny-over-step_up-over-shadow-over-allow); shadow matches are
/// recorded but do not change an otherwise-allow decision. Returns the verdict.
pub fn evaluate(set: list.List<Compiled>, text: string): ContentVerdict {
    let v = ContentVerdict();
    let i = 0;
    while (i < set.size()) {
        let c = set.get(i) ?? Compiled(ContentRule("", "", "substr", ""));
        if (ruleMatches(c, text)) {
            let act = c.rule.action;
            // deny beats step_up beats shadow; keep the strongest seen.
            if (string.eql(act, "block")) { return fill(v, "deny", c); }
            if (string.eql(act, "step_up") && !string.eql(v.decision, "deny")) { v = fill(v, "step_up", c); }
            if (string.eql(act, "shadow") && string.eql(v.decision, "allow")) { v = fill(v, "shadow", c); }
        }
        i = i + 1;
    }
    return v;
}

fn fill(v: ContentVerdict, decision: string, c: Compiled): ContentVerdict {
    v.decision = decision; v.ruleId = c.rule.id; v.ruleName = c.rule.name;
    v.severity = c.rule.severity; v.controlIds = c.rule.controlIds;
    return v;
}
```

The built-in `detect(selector, text)` covers the checks that are tedious to express as a single regex:
credit-card (Luhn), SSN, email, phone, and high-entropy secret-like tokens (Shannon entropy over a
sliding window plus known key prefixes such as `sk-`, `AKIA`, `ghp_`). These are deterministic and
explainable, which is exactly the property a blocking control needs.

## 5. The ext_authz check handler

Envoy's `ext_authz` HTTP service receives an HTTP request mirroring the original call (method, path,
headers, and the body when `with_request_body` is set). The handler reads the body (the prompt),
evaluates it, and answers 200 (allow) or 403 (deny). On a non-allow verdict it records a signed
violation through the R1 path. Proposed `sidecar/src/cf/check.ky`:

```kyte
import state;
import violation;
import cf.engine;
import web.routing;
import web.response;
import web.status;
import string;

/// POST /cf/check  (Envoy ext_authz HTTP). 200 = allow, 403 = deny.
pub struct CheckHandler impl RouteHandler {
    pub st: state.SidecarState,
    init(st: state.SidecarState) { self.st = st; }

    async fn serve(self: CheckHandler, ctx: routing.Context): response.Response {
        let body = ctx.request.body;                 // the prompt / payload
        let verdict = engine.evaluate(self.st.cfSet, body);

        if (string.eql(verdict.decision, "allow")) {
            return response.Response(Status.Ok, "");  // 200 -> Envoy forwards upstream
        }

        // Non-allow: record a signed violation (R1 + R4), reusing the same store
        // and record type as the inbound relay path.
        let v = violation.Violation();
        v.tenant = self.st.cfg.tenant;
        v.endpointHost = ctx.request.getHeader("x-forwarded-host") ?? "";
        v.principal = ctx.request.getHeader("x-acp-principal") ?? "";
        v.prompt = violation.promptForMode(body, self.st.cfg.prompt_redact);
        v.promptSha = canonicalSha(body);
        v.verdict = verdict.decision;                 // deny | step_up | shadow
        v.policyId = verdict.ruleId;
        v.policyName = verdict.ruleName;
        v.ruleRegoPath = "content-firewall";
        v.capturedMs = state.nowMs();
        let _stored = self.st.recordViolation(v);     // signs + appends to vstore

        // shadow -> allow the call through but keep the signed record (trial mode).
        if (string.eql(verdict.decision, "shadow")) {
            return response.Response(Status.Ok, "");
        }
        // deny / step_up -> block. A step_up could instead return 401 to trigger
        // an interactive re-auth flow; v1 treats both as a block.
        let r = response.Response(Status.Forbidden, "blocked by content policy: " + verdict.ruleName);
        r.headers.set("x-acp-content-verdict", verdict.decision);
        return r;
    }
}
```

The handler is registered on the sidecar app and the inspector set lives on `SidecarState` as
`cfSet: list.List<engine.Compiled>` (compiled once when provisioning installs a new rule set, section 7).
It writes through the **same** `recordViolation` → `vstore` → signed-record path the inbound relay uses,
so content violations appear in the console with a verified badge, raise tickets (R3), and flush to the
control plane (R4 verify) exactly like any other violation. No new evidence path.

## 6. Envoy wiring

Two small additions to `sidecar/src/envoy.ky`:

- A `content` cluster pointing at the inspector (the sidecar's own listen address), HTTP/1.1.
- A second `ext_authz` HTTP filter in each bump chain, before the router and after the OPA filter:

```
- name: envoy.filters.http.ext_authz
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
    transport_api_version: V3
    with_request_body: { max_request_bytes: 65536, allow_partial_message: true }
    http_service:
      server_uri: { uri: http://127.0.0.1:8899, cluster: content, timeout: 2s }
      path_prefix: "/cf/check"
      authorization_request:
        allowed_headers: { patterns: [ { exact: "content-type" }, { prefix: "x-acp-" } ] }
      authorization_response:
        allowed_upstream_headers: { patterns: [ { prefix: "x-acp-" } ] }
```

The OPA filter stays exactly as-is. The ordering (OPA then content) is deliberate; it can be flipped if
content inspection should run even when routing policy would allow. The `max_request_bytes` matches the
existing OPA cap (64KB); larger bodies use `allow_partial_message: true` so the inspector sees the first
64KB rather than failing (a documented limit, section 18).

## 7. Provisioning rules (R5)

Content rules are authored in the control plane and reach the edge through the **existing R5 loop**, with
nothing new in the transport:

- The control plane serves the active content rule set for a tenant at a signed endpoint (for example
  `GET /content-rules`), signed with the trust key exactly like the bundle, endpoints, and packs
  (`Http.signConfig`).
- The sidecar pulls it in `sync.syncContentRules(st)` alongside the bundle/endpoints/packs pull,
  **verifies the signature** against `cp_pubkey` (fail-closed, kept last-good on failure, the same
  `verifyPulled` path), persists it to disk as last-good, and on change **recompiles** the set into
  `st.cfSet` via `engine.compileAll`.
- On boot the sidecar loads the last-good rule set from disk and compiles it before accepting traffic,
  so a cold start with the control plane down still enforces the last-known content policy.

So the content firewall inherits R5's whole posture: tenant-scoped, signed, fail-closed, last-good. The
authoring UI is the piece the still-empty "Policy versions" screen becomes: a rule editor in the control
plane that compiles UI-authored rules into the signed set the edge pulls.

### 7.1 Authoring lives in the control plane, not the edge

Content rules are **authored in the control plane and never at the edge.** This is forced by the
architecture, not a preference:

- **Single source of authorship.** Acts, packs, policies, and endpoints are all authored centrally and
  provisioned to the edge via R5; content rules are the same kind of object and belong in the same place.
- **Signing depends on it.** The control plane signs the rule set and the sidecar *verifies* it against
  `cp_pubkey`, fail-closed. If the edge could author its own enforcement policy, there would be no
  trustworthy signer, and a customer-side edge could rewrite the policy that governs it, which defeats
  central governance.
- **Many edges, one tenant.** A tenant can run many sidecars; a rule authored once provisions to all of
  them consistently. Per-edge authoring would mean N places to keep in sync.
- **Audit and versioning.** Rule changes are governance events that belong in the central audit trail and
  version history.

So the split is the same clean rule as the rest of Varman, **control plane authors; sidecar enforces and
reports**:

**Control plane, the authoring screen (new `ContentRules` feature):**
- list / create / edit / delete / enable / disable content rules for the tenant;
- fields per rule: name, kind (regex | substr | secret | pii | size), pattern/threshold, target
  (request | response | both), action (block | shadow | step_up), severity, mapped `controlIds`;
- a **"test rule"** box that runs the rule against sample text server-side (reusing the engine's match
  logic) so an author sees what it would catch before publishing;
- **publish** → compile and **sign** the active set (`Http.signConfig`) → serve at `GET /content-rules`;
- version history and rollback (this is what fills the empty "Policy versions" screen).

**Sidecar, read-only (already R2):** the console's Policy tab shows *what this edge is enforcing*, the
active rule set by name and version, which rules are firing, and the content violations captured, each
with a verified badge. There are **no add/edit forms at the edge**; the only edge-side actions remain
operational (re-verify a record, raise a ticket now).

### 7.2 Control-plane `ContentRules` feature layout (build scope)

Following the server's VSA shape (one handler per `<UseCase>/handler.ky`, `routes.ky` registers only,
the Endpoints console is the reference), the feature is:

```
server/src/Features/ContentRules/
  routes.ky                       # registers the routes below (view before {id})
  Shared/
    ContentRuleRepository.ky      # PG CRUD over a content_rules table, tenant-scoped
    ContentRuleRow.ky             # Dto: id, name, kind, pattern, threshold, target,
                                  #      action, severity, controls_json, enabled, updated_ms
  ListRules/handler.ky            # GET  /content-rules/all        -> JSON list (console)
  ActiveSet/handler.ky            # GET  /content-rules           -> SIGNED active set (the edge pulls this)
  CreateRule/handler.ky           # POST /content-rules            (requireCap EditFirewall)
  UpdateRule/handler.ky           # POST /content-rules/{id}
  DeleteRule/handler.ky           # POST /content-rules/{id}/delete
  ToggleRule/handler.ky           # POST /content-rules/{id}/toggle
  TestRule/handler.ky             # POST /content-rules/test       -> {matched, rule, snippet}
  RulesView/handler.ky            # GET  /content-rules/view       -> Datastar fragment (console screen)
  RulesConsole/handler.ky         # POST /console/content-rules/{save,delete,toggle} (first-party BFF)
  views/contentrules.kyx          # the authoring screen (add/edit modal, table, test box)
```

Notes that keep it consistent with what already ships:

- **`ActiveSet` is the only machine endpoint the edge consumes**, and it is **signed** with
  `Http.signConfig` (R5 + R4), so the sidecar verifies it with `cp_pubkey` exactly like the bundle,
  endpoints, and packs. The `*View`/`*Console`/`List` endpoints are console-facing.
- The machine mutation endpoints keep `requireCap(EditFirewall)` (the capability the red-team run already
  uses); the first-party `/console/content-rules/*` BFF handlers follow the trusted-console pattern (no
  bearer) used by the rest of the console.
- The authoring screen reuses the proven Datastar CRUD pattern (shell-level signal bag, add/edit modal,
  per-row edit/delete/toggle, server-rendered fragment), the same shape as the Endpoints and Policy
  screens.
- A `content_rules` table is added to the schema (tenant-scoped, like `governed_endpoints`); this is new
  schema the port did not carry, authored here rather than inherited from acp.
- **`TestRule` shares the exact match logic with the sidecar engine.** To avoid two implementations
  drifting, the deterministic matchers (`regex`/`substr`/`size`/`pii`/`secret`) should live in a small
  shared module usable by both the server (for test + optional server-side preview) and the sidecar
  engine, or be differentially tested against the same corpus so they cannot disagree.

## 8. Verdict and evidence (R1 + R4)

A content verdict produces exactly the signed `Violation` record defined in R1, with:

- `prompt` = the offending text under the retention mode (preview when redacting), and `prompt_sha` the
  full-text hash, both inside the signed canonical core (so the displayed text is tamper-evident, per the
  gap-closure fix);
- `policyId` / `policyName` = the content rule that fired;
- `ruleRegoPath` = `"content-firewall"` to distinguish content from routing decisions;
- `verdict` = deny / step_up / shadow.

Because it is the same record type, it is Ed25519-signed and hash-chained (R4), shown in the console with
a verified badge (R2), eligible for a ticket (R3), and verified by the control plane on flush. The
control mapping comes for free from the rule's `controlIds`.

## 9. Verdict semantics and the shadow escape valve

The content firewall uses the same four-way verdict as the rest of Varman, and the precedence is the same
(deny over step_up over shadow over allow). The important one is **shadow**: a shadow rule records a
signed violation but lets the call through. This is the safe way to introduce a new rule, especially a
probabilistic one: run it in shadow, watch what it would have blocked in the console, and promote it to
`block` only once its false-positive rate is acceptable. Blocking a customer's legitimate traffic is the
fastest way to get pulled out of the egress path, so new rules default to shadow.

## 10. Latency and the fast/slow split

Every governed call now waits on inspection, so latency is a first-class constraint.

- **Deterministic checks are inline.** Regex, substring, size, PII, and secret detectors over a 64KB body
  are microseconds; they run synchronously in the `ext_authz` call and can block. This is phase one and
  it needs no model.
- **Probabilistic checks are not inline by default.** Prompt-injection, jailbreak, and topic classifiers,
  or an LLM-as-judge, add real latency and are non-deterministic. They run in **shadow mode** and/or
  **out of band**: the inline path makes the deterministic decision immediately, and the probabilistic
  verdict is recorded asynchronously (and can be promoted to inline-blocking per rule once trusted, with
  a per-rule latency budget). The classifier backend is **pluggable** (a configured model service URL),
  because the compute cannot run in-process (Kyte's wasm runtime cannot lower async, so a classifier is a
  network call, not embedded code), and because enterprises will want to bring their own or keep it in
  their environment.

The honest framing carries into the product: deterministic checks are an enforcement guarantee;
probabilistic checks are advisory until promoted.

## 11. Privacy

The inspector sees raw prompts, the most sensitive data in the system. The design keeps this local:

- Inspection runs at the **customer-edge sidecar**; raw prompt text never leaves the customer's
  environment. Only the signed verdict and a **redacted snippet** (governed by `prompt_retention`) flow to
  the control plane.
- The probabilistic backend, if used, is either self-hosted or the customer's own model endpoint; a rule
  set can forbid sending content to any third-party classifier.
- "Your prompts never leave your network, and you still get control-mapped, tamper-evident evidence" is
  both the privacy posture and the strongest part of the pitch.

## 12. Response-body inspection

Request inspection catches what the user/agent sends; response inspection catches what the model returns
(leaked secrets, disallowed content, exfiltration in the completion). Envoy `ext_authz` is request-path
only, so response inspection needs either a response-path filter or the ext_proc track (section 13). The
rule model already carries `target: request | response | both`; response inspection is a phase-two filter
that streams the response body to the same engine and records a violation (and can block the response)
the same way. Streaming completions (SSE/chunked) make this harder and are called out in section 18.

## 13. Redaction and mutation (the ext_proc track)

`ext_authz` can allow or block, but it cannot *rewrite* the body. Redaction (strip the secret, forward
the sanitised prompt) and response rewriting need Envoy **`ext_proc`**, which is gRPC-streaming. Kyte has
HTTP/2 framing but not a gRPC server today, so `ext_proc` is a later track with a prerequisite: either a
minimal gRPC-over-HTTP/2 server in Kyte (bounded: `ext_proc` is a single bidirectional stream with a
small protobuf), or an Envoy **Lua** filter that calls the Kyte inspector and applies the mutation Envoy
side. Until then, the firewall's power is allow/block/flag, which is the right v1 scope.

## 14. Redteam, made real

Today's redteam (`Assurance/RedteamRun`) scores a built-in corpus with an in-process keyword check; it
does not exercise the live path. Once the content firewall exists, the redteam becomes real: it sends
attack prompts **through the live Envoy → content-inspector path** at the configured endpoints and
confirms the configured rules actually catch them, producing the signed attestation it already produces,
now backed by live enforcement. The honest metric a customer wants ("catch rate on my traffic, through
the live path, against my enabled rules") becomes measurable. The content firewall and a real redteam
advance together, which is why section 10 of the refinements doc lists redteam as blocked on this.

## 15. Configuration surface

Additions to the sidecar settings (`settings.ky`), all with safe defaults:

```
content_firewall: true            # master on/off
cf_check_path: "/cf/check"        # ext_authz HTTP path
cf_max_body: 65536                # bytes inspected (matches Envoy cap)
cf_rules_cache: "varman-sidecar-content-rules.json"   # last-good on disk
cf_default_action: "shadow"       # action for a newly pulled rule with none set
cf_classifier_url: ""             # probabilistic backend; "" = deterministic only
cf_classifier_inline: false       # whether the classifier may block inline
```

`cp_pubkey` (already present) gates signature verification of the pulled rule set; `prompt_retention`
(already present) governs how much of the offending prompt the evidence record keeps.

## 16. Phasing

Each phase is independently shippable and testable, and none regresses the enforcement already in place.

- **F1, deterministic inline (the floor).** Rule model, engine (regex/substr/size/PII/secret), the
  `/cf/check` ext_authz HTTP handler, Envoy second-filter wiring, request-path only, block/shadow, signed
  records through R1-R4, rules provisioned + signed via R5. This is a real, demonstrable, no-ML content
  firewall and a sellable capability on its own.
- **F2, response-path inspection.** A response-path filter feeding the same engine with `target=response`
  rules; block or flag model outputs.
- **F3, probabilistic (shadow-first).** A pluggable classifier/judge backend, run in shadow by default,
  promotable per rule to inline with a latency budget. Injection/jailbreak/topic rules.
- **F4, redaction and mutation.** The ext_proc (gRPC) or Lua track for sanitising bodies in place.

F1 is the near-term build. F2-F4 are sequenced after it and each carries its own prerequisites
(response filter, model backend, gRPC/Lua).

## 17. Testing

- **Engine unit tests (offline):** a corpus of malicious and benign payloads per rule kind; assert the
  verdict and that benign traffic is not blocked (false-positive guard). This mirrors the sidecar's
  existing offline gate.
- **Handler tests (offline):** feed `/cf/check` synthetic ext_authz bodies, assert 200 vs 403 and that a
  signed violation is recorded and verifies.
- **Differential vs the deterministic reference:** the same corpus the redteam uses, run through the
  engine directly and through the live Envoy path, must agree.
- **Latency budget test:** assert inline deterministic evaluation of a 64KB body stays within a set
  microsecond budget.

## 18. Honest limits and open questions

- **Body-size cap.** Inspection sees the first 64KB (the Envoy `ext_authz` body cap). A prompt larger than
  that is inspected only up to the cap; the design should log when a body is truncated so coverage is
  never silently partial. Raising the cap trades memory and latency.
- **Streaming.** Chunked/SSE requests and responses do not present a single body to `ext_authz`;
  full streaming inspection needs the ext_proc track (F4).
- **Regex cost.** A pathological rule regex can be slow; the engine should bound per-rule evaluation time
  and the control plane should lint authored patterns.
- **Probabilistic accuracy.** False positives/negatives are inherent; shadow-first and per-rule promotion
  are the mitigations, not a cure. Never market the probabilistic layer as a guarantee.
- **ext_proc prerequisite.** Redaction/mutation and full streaming need a gRPC server in Kyte or a Lua
  bridge; scope that as its own piece before promising redaction.
- **Open:** request-vs-response rule precedence when both fire; whether `step_up` drives a real
  interactive re-auth or is treated as a block in v1 (currently a block); where the probabilistic backend
  runs (edge-local vs customer model vs forbidden) as a per-tenant/plan decision.
