# 12. Discovery, enrolment and GRC

Governing what you know about is only half the job. This chapter covers finding the AI you do not yet
govern, bringing it under policy, and producing the compliance artifacts an auditor asks for. The GRC
model is anchored on the AI system: you register a system once, declare who you are for it in each
market, work its controls per framework, attach evidence, and generate a signed report that is aware of
your jurisdiction.

## Discovering shadow AI

`acp discover` classifies ungoverned model-API and MCP endpoints by provider, from an egress log or
an endpoint list, against a table of known AI hosts and MCP path hints.

```sh
acp discover egress.log          # list shadow-AI endpoints and their providers
```

It produces a worklist and marks scopes it did not cover, so a partial scan does not masquerade as
complete.

## Enrolling endpoints

Register discovered endpoints from the console's **AI Endpoints** page, or the control-plane API,
which records a **signed disposition** per endpoint (the latest wins) in the control-plane database:

```sh
curl -X POST http://<host>:8787/endpoints/register \
  -d '{"endpoint":"claude.ai","disposition":"govern","reason":"sanctioned"}'
# disposition is govern (route through ACP), block (quarantine), or accept-risk (time-boxed)
curl http://<host>:8787/endpoints            # the current dispositions
```

Each disposition is Ed25519-signed, so it is tamper-evident evidence of an operator's decision. The
governed set feeds the coverage report and the [interceptor's rules](05-intercept.md) via
`acp intercept from-enrollment`.

## The GRC model: everything hangs off the AI system

Older versions of Varman kept governance as a flat list of signed records. That could not answer the
question an auditor actually asks: "for this AI system, what is its compliance posture against the
regulation that applies in my jurisdiction, with the evidence, as a signed report I accept." The model
is now anchored on a first-class **AI system**, and every other object hangs off it.

::: warning Implementation status (varman today)
The per-system model below (system registry, roles, SoA, evidence, crosswalk, report) is implemented and
graded from the operator-asserted SoA and evidence rows. Two honest caveats apply. First, the catalogue
is **not exhaustive**: `varman-core` ships 264 controls across the 12 frameworks, and the flagship
catalogues (EU AI Act, NIST AI RMF, ISO/IEC 42001) are representative subsets, not the full official
sets. Second, the parts of a report that would cite **runtime decision evidence** depend on the durable,
tamper-evident store, which is not instantiated on the live path yet (`--migrate` does not apply the DDL
and the decision ledger is not populated at runtime, see [chapter 9](09-evidence.md)). So the
per-system SoA report is real, but the generic cross-framework report and any "cited from the ledger"
claim are a working design rather than a populated path today.
:::

The moving parts:

- a versioned **control catalogue** (12 frameworks; 264 controls shipped today, 494 the parity target),
- an **AI system** registry (the use-case anchor),
- **roles per system** that drive which controls apply,
- a persisted **Statement of Applicability** (SoA) per system and framework,
- **evidence** as first-class records with freshness,
- the **control crosswalk** (author once, satisfy many frameworks),
- **conformity states** per control with a rollup,
- an **immutable change-history** plus signed, as-at report snapshots.

### The control catalogue

The catalogue is versioned as data, not hand-written code, and ships inside the binary read-only. It
covers twelve frameworks: EU AI Act, NIST AI RMF, ISO/IEC 42001, ISO/IEC 27001, SOC 2, GDPR, India DPDP
2023, UK AI principles, Colorado AI Act, NYC LL144, Canada AIDA and ISO/IEC 23894. The shipped catalogue
totals 264 controls today (494 is the parity target); the flagship frameworks are representative subsets
rather than the complete official control sets, so treat a framework's coverage as partial where the
[conformance reference](/guide/conformance/) marks it so.

Each control is not just an id and a title. It carries a hierarchy path (for example Chapter III,
Section 2, Article 14), a normative reference (`Art. 14`, `A.8.2`, `CC6.1`, `GOVERN 1.1`), an
obligation type (govern, document, technical, process, transparency, oversight, record-keeping,
prohibition), the roles it binds (provider, deployer, importer, distributor, controller, processor), an
applicability predicate (for example `risk_tier in [high]`, `role=deployer`, `asset_type=gpai`), an
evidence type (attestation, artefact, test, ledger), a crosswalk to equivalent controls in other
frameworks, and a citation to the official source. Each framework also declares its **type**
(`statutory_conformity`, `principles_based`, `standard` or `sectoral`), which is what makes a UK report
read differently from an EU one. See "Jurisdiction-aware reporting" below.

### Registering an AI system

The AI system is the hub. Register it once with: id, name, purpose, owner, lifecycle state (intake,
development, staging, production, retired), risk tier, sector and the set of jurisdictions it operates
in (for example `["uk","eu"]`).

```sh
curl -X POST http://<host>:8787/systems \
  -d '{"name":"hiring-screener","purpose":"rank CVs","owner":"hr-lead",
       "risk_tier":"high","sector":"employment","jurisdictions":["uk","eu"]}'
curl http://<host>:8787/systems            # the registry
```

In the console, open **Governance**, **AI Systems** and click **+ Register system**.

### Declaring roles per system

The same system is governed differently depending on what your organisation is for it in a given
market. Declare a role (provider, deployer, importer or distributor) per jurisdiction:

```sh
curl -X POST http://<host>:8787/systems/<id>/roles \
  -d '{"role":"deployer","jurisdiction":"uk"}'
```

Roles feed the applicability predicate on each control, so a UK deployer and an EU provider of the same
system see different applicable control sets and therefore report differently. This is not a display
filter: it drives which obligations bind you.

### The Statement of Applicability

For each system and framework, Varman persists a Statement of Applicability: one row per control saying
whether it is **applicable** or not, a **justification** (the reason it is excluded, or the note on how
it is met), and a **status** (planned, in progress, implemented). The framework report is graded
directly from the SoA, so the SoA is the working surface, not a report artefact.

```sh
curl http://<host>:8787/systems/<id>/soa/eu-ai-act          # read the SoA for a framework
curl -X POST http://<host>:8787/systems/<id>/soa/eu-ai-act \
  -d '{"control_id":"art-14","applicable":true,"status":"implemented",
       "justification":"human reviewer signs every rejection"}'
```

In the console, open the system, pick a framework tab, and work down the control list. The applicable
set is seeded from the control catalogue's predicates against the system's profile and roles; you can
override any row with an explicit applicable-or-not and a justification.

### Evidence with freshness

Evidence is a first-class record bound to a system, framework and control. Each piece carries a title,
a source, an owner, a produced timestamp, an artefact reference and, crucially, a **valid_until**
freshness date.

```sh
curl -X POST http://<host>:8787/systems/<id>/evidence \
  -d '{"framework":"eu-ai-act","control_id":"art-12","title":"audit-log config",
       "source":"ledger","owner":"carol","valid_until_ms":1790000000000}'
```

Freshness gates the grade. A control the SoA marks implemented but which has no fresh evidence (none
attached, or every piece expired) does not count as conformant: it drops to **partial**, with the
reason "claimed implemented but no fresh evidence". A signed report is then honest about its own
currency rather than presenting stale paperwork as live proof.

### The control crosswalk: author once, satisfy many

Every control declares a crosswalk to equivalent controls in other frameworks, and the report resolver
walks that graph symmetrically. Evidence attached to one control automatically satisfies the mapped
controls in every other framework. Attach EU AI Act Art. 12 (record-keeping) evidence once and it also
satisfies GDPR Art. 30 (records of processing); the GDPR report shows that control conformant with the
reason "satisfied via crosswalk: eu-ai-act:art-12". You assess and collect once, and report against
whichever regulations apply.

### Conformity states and the rollup

Each control in a report resolves to one conformity state: **conformant**, **partial**,
**non-conformant**, **not-applicable** or **not-assessed**. The logic, in order: a control the SoA
excludes is not-applicable; one that is applicable, marked implemented and backed by fresh evidence is
conformant; one implemented but without fresh evidence is partial; one satisfied via a crosswalk edge is
conformant; anything else falls back to its SoA status or, with no SoA row at all, not-assessed. The
report carries a **conformity rollup**: totals for applicable, not-applicable, conformant, partial,
non-conformant and not-assessed, so the posture is one glance.

### Immutable change-history and as-at reporting

Every governance change to a system (created, roles declared, SoA updated, evidence added) appends an
immutable event to the change-history (`grc_audit`): who did what to which entity, when. This is the
audit trail an assessor relies on, and it is append-only.

```sh
curl http://<host>:8787/systems/<id>/audit          # the change history, newest first
```

Because history is preserved, a report can be rendered **as at** any past date. Pass `as_at` (epoch
milliseconds) and the resolver filters evidence and SoA rows to only those that existed by that instant,
so you can reproduce the conformance posture as it stood on the day of an incident or a prior audit,
not just today.

```sh
curl "http://<host>:8787/systems/<id>/report/eu-ai-act?as_at=1780000000000"
```

Reports are also stored as immutable, signed snapshots, so a point-in-time rendering is pinned and
reproducible.

## Jurisdiction-aware reporting

The report is `(system) x (framework) -> graded, signed, versioned`. It branches on the framework's
type, because the regimes are genuinely different in shape:

- **EU AI Act** is `statutory_conformity`: enumerated Annex obligations, pass or fail, the Art. 9 to 15
  controls with status and evidence, data governance, human oversight, accuracy and robustness,
  post-market monitoring, and a conformity declaration (the Annex IV technical documentation shape).
- **UK AI principles** is `principles_based`: there is no single UK AI statute, so the report is a
  principle-by-principle narrative (safety and robustness, transparency and explainability, fairness,
  accountability and governance, contestability and redress) with the same evidence bound under each
  principle, plus the relevant sector-regulator expectations. It is attestation-style, not a pass/fail
  checklist.

An organisation operating in both markets registers one system, declares an EU provider role and a UK
deployer role, works one SoA, and generates both reports off the same crosswalked evidence.

## The console flow, end to end

1. **Register the system.** Governance, AI Systems, **+ Register system**. Give it a name, purpose,
   owner, risk tier, sector and jurisdictions.
2. **Declare roles.** On the system, add a role per jurisdiction (provider, deployer, importer,
   distributor). This sets which controls bind you in each market.
3. **Work the SoA per framework.** Open a framework tab. For each control, confirm it is applicable (or
   exclude it with a justification) and move its status towards implemented as your team closes it.
4. **Attach evidence.** Bind each piece of proof to its control with an owner and a valid_until date.
   The crosswalk carries it to mapped controls in other frameworks automatically.
5. **Generate and download the report.** The framework report is graded live from the SoA and evidence,
   with the conformity rollup and any freshness or crosswalk reasons per control. Download it as a signed
   JSON-LD pack (`@type: acp:ComplianceReport`, `conformsTo` the framework, verifiable offline with
   `acp verify-pack` and the public key alone) or as CSV for the controls table. Reporting is
   jurisdiction-aware: the UK principles-based narrative and the EU statutory Annex IV report come from
   the same object graph.

> API: `GET/POST /systems`, `GET /systems/:id`, `POST /systems/:id/roles`,
> `GET/POST /systems/:id/soa/:framework`, `GET/POST /systems/:id/evidence`,
> `GET /systems/:id/audit`, `GET /systems/:id/report/:framework?as_at=<ms>`, and the signed pack and CSV
> at `GET /report/framework/:name/pack` and `GET /report/framework/:name/csv`. Day to day, use the
> console; the API is for schedulers and CI.

## Automated risk tiering

Classifying a system by hand is the slow step. Varman can propose the risk tier for you before an agent
goes live, from what the agent actually is and what it can do. `POST /agents/:id/auto-assess` reads the
agent's business `domain` and its registered `tools` (both from the agent's registration metadata, and
either may be overridden in the request body), derives an EU AI Act screening from those signals, and
runs the same tiering engine as the operator-answered questionnaire.

The derivation is a case-insensitive substring match over the domain label and each tool binding. A
`hiring` domain or a `resume.parse` tool raises the employment-or-education flag, `credit.score` or
`loan.underwrite` raises access-to-essential-services, `biometric` or `facial` raises biometric
identification, and so on. The tier that comes out is one of `unacceptable`, `high`, `limited` or
`minimal`, along with the reasons and the obligation checklist that the tier pulls from the control
library (a high-risk tier pulls the full EU AI Act high-risk set, Articles 9 to 15).

The result is filed as a signed `assessment` GRC record, pre-filled with the proposed tier, the reasons,
the checklist and an `auto` block recording the source agent, domain, tools and the matched signals. It
is deliberately conservative: auto-tiering can only propose a tier, never silently approve one. The
record opens in the `draft` stage, and an operator still reviews and advances it. This satisfies the
pre-deployment risk classification expected by EU AI Act Article 9. The route needs the `EditGrc`
capability.

> API: `POST /agents/:id/auto-assess` with an optional `{domain, tools}` body. It returns
> `{ok, id, agent, tier, controls, signals}`, where `id` is the new assessment record.

## The risk register and risk matrix

Alongside conformity, Varman keeps a lightweight, evidence-linked risk register. The full GRC lifecycle
still belongs to a dedicated GRC platform, but ACP holds enough of a register that a risk can point at
the real ledger decisions and controls that bear on it. Each risk item carries a title, an owner, a
likelihood and an impact (each `low`, `medium` or `high`, the `Level` enum), a treatment (`mitigate`,
`accept`, `transfer` or `avoid`, the `Treatment` enum) and a status (`open`, `mitigating`, `accepted` or
`closed`, the `RiskStatus` enum). It may also link to the controls and ledger decisions that mitigate it.

The score is the residual-risk matrix in code: it is likelihood times impact, on a scale of 1 to 9, and
the severity band is derived from that score. A score of 1 or 2 is `low`, 3 or 4 is `medium`, 6 is
`high` and 9 is `critical`. This is the matrix reviewers look for under EU AI Act Article 9 and NIST AI
RMF: a defensible, repeatable rating rather than a subjective label.

Create a risk item with `POST /grc/risk`. The body carries `subject`, `title`, `likelihood`, `impact`,
`treatment` and `owner`; the server computes the score and band from `RiskItem` and stores them in the
signed record body, returning `{ok, id, score, band}`. A missing or malformed `likelihood` or `impact`
is rejected with a clear error. A risk can also be created through the generic `POST /grc` with
`kind: "risk"`.

The register as a whole is signable. The signed view (`RiskRegisterView`) sorts items by score and
carries the heatmap counts the console shows: the number of `open` items, the number of `high` band
items and the number of `critical` band items. The snapshot is signed with the tenant key and verifies
offline, so a point-in-time risk posture can be exported as tamper-evident evidence.

> API: `POST /grc/risk` (or `POST /grc` with `kind: "risk"`). Levels are `low|medium|high`; treatments
> are `mitigate|accept|transfer|avoid`; statuses are `open|mitigating|accepted|closed`.

## Fundamental-rights and impact assessments (FRIA)

A fundamental-rights impact assessment is a first-class governance record. `fria` is one of the GRC
record kinds (alongside `assessment`, `conformity`, `risk`, `model-card`, `use-case`, `attestation`,
`aibom` and `incident`), so a completed FRIA lives in the same signed, verify-on-read store as every
other record. This is the EU AI Act Article 27 fundamental-rights impact assessment that binds
deployers, and it doubles as the AI system impact assessment expected by ISO 42001 A.6. The control
catalogue models Article 27 as a deployer-only obligation, so it applies to a deployer and not to a
pure provider.

Create one with `POST /grc` and `kind: "fria"`, giving a `subject` (the system), a `title`, a `status`
and a `body` (the assessment content, stored as a string). The record is signed with the tenant key and
re-verified on every read, so its "signed" state is checked, not asserted.

For the assessment content itself, `GET /grc/templates` serves the material the console renders: the EU
AI Act risk-screening questionnaire (the nine trigger questions, from prohibited practice through to
content generation) plus one conformity-checklist template per framework in the catalogue, each listing
every control with its id, reference, title and obligation type. `POST /grc/assess` runs the screening
engine over answers to that questionnaire and persists a signed `assessment` record whose body carries
the computed tier, the reasons and a control checklist (each obligation with a `done` flag). The raw
answers, the assignee, the due date and the stage are stored as workflow metadata, separate from the
signed document. All three routes need the `EditGrc` capability.

> API: `POST /grc` (any kind, including `fria`), `POST /grc/assess` (screening to a signed assessment)
> and `GET /grc/templates` (the questionnaire and per-framework checklists).

## Model fairness evaluation

Varman does not train or host a model, but it records how a model behaves across protected groups so the
result becomes signed evidence. `POST /models/:id/fairness` takes a set of labelled rows, each with a
`group`, the model's `predicted_positive` prediction and the `actual_positive` ground-truth label, and
computes the standard fairness metrics. Because the predictions and labels come from the caller, the
same inputs always produce the same metrics.

The report gives per-group metrics (the group name, its count, the selection rate as `positive_rate`,
the `true_positive_rate` and the `accuracy`) and two cross-group gaps: the `demographic_parity_gap` (the
largest selection-rate difference between groups) and the `equal_opportunity_gap` (the largest
true-positive-rate difference), plus an `overall_accuracy`. These are the fairness measures NIST AI RMF
MEASURE asks for. The report is stored as a signed `attestation` GRC record linked to the model, so a
fairness result sits with the model card as durable, verifiable evidence. The route needs the `EditGrc`
capability.

> API: `POST /models/:id/fairness` with `{rows: [{group, predicted_positive, actual_positive}, ...]}`.
> It returns `{ok, id, report}`, where `report` holds the per-group metrics and the parity and
> equal-opportunity gaps.

### Tracking fairness over time

A single fairness run is a point measurement. To treat fairness as continuous, pass a `threshold` on the worst parity gap and read the run history.

> API: `POST /models/:id/fairness` accepts an optional `threshold`. The response adds `max_gap` (the larger of the demographic-parity and equal-opportunity gaps), the `threshold` and `passed`. A run that breaches the threshold is stored with status `failed` rather than `tested`.

> API: `GET /models/:id/fairness/history` (capability `Export`) returns the runs for a model, oldest first, each with its gaps, accuracy and `max_gap`, plus a `drifted` flag. `drifted` is true when the latest run's worst gap rose by more than the tolerance (0.05) over the previous run, so a model whose fairness is decaying across evaluations shows up without reading each run by hand.

## Dataset provenance and lifecycle

EU AI Act Article 10 and ISO/IEC 42001 control A.8 ask you to govern the data an AI system is built on, not just its runtime calls: where a dataset came from, on what basis it may be used, and what happens when someone asks for their data to be removed. `POST /grc/dataset` records that as a signed governance record, linked to a system.

> API: `POST /grc/dataset` (capability `EditGrc`). Body: `{subject, title?, source?, licence?, consent_basis?, collection_date?, retention?, records?, pii?, status?, system_id?, notes?}`.

The record keeps the provenance fields (`source`, `licence` or copyright marker, `consent_basis`, `collection_date`, `retention`, the `records` count and a `pii` flag) and a lifecycle `status`, one of `active`, `retention`, `deletion-requested`, `deleted` or `unlearned`. The response returns `governance_complete`, which is true only when `source`, `licence` and `consent_basis` are all present, so an incomplete provenance record reads as incomplete rather than passing silently.

A data deletion or unlearning request is a status transition, not a new record: `POST /grc/:id/status` with `{status: "deletion-requested"}`, and later `deleted` or `unlearned`, each re-signing the record so the history stays verifiable. Because the record is a dataset-kind GRC record linked to a system, the A.8 and Article 10 controls in the catalogue grade against it in the Statement of Applicability.

## Runtime evidence still counts

The system-anchored model documents governance; by design it does not replace the runtime record. The
intent is that when a PEP allows, denies or steps up an actual call, that becomes a leaf in the
tamper-evident decision ledger ([chapter 9](09-evidence.md)), and evidence with source `ledger` binds a
control to that machine-generated proof so a report can cite runtime facts rather than author-attested
paperwork.

::: warning Not wired at runtime today
The decision ledger is **not populated on the live varman path yet**: the append is not called and the
durable store is not instantiated (see [chapter 9](09-evidence.md)). So the "cite runtime facts" story,
the post-market and serious-incident draws, and the auditor evidence pack are a working design, not a
populated path. Today the system-anchored report is driven by the operator-asserted SoA and evidence
rows, not by live decisions.
:::

::: tip Per-regulation reference
The complete, code-aligned control list for each framework, with how Varman supports it and how evidence and reporting work, is in the [Conformance reference](/guide/conformance/).
:::
