# 19. Operator walkthrough: from zero to a signed compliance report

This chapter is a task-oriented walkthrough of the console for someone who governs AI systems. It goes
end to end: register a system, assess it against a regulation, attach evidence, generate a signed
report, then set the enforcement policy and firewall. Every screen writes to the control-plane
database, so what you see is what is stored.

Open the console at the control plane's address (for a local run, `http://127.0.0.1:8787`). The left
sidebar is grouped: **Governance**, **Identity**, **Policy**, **Compliance**, **Emergency**, **Health**.

## 1. The catalogue you assess against

Go to **Compliance, Acts & controls**. This is the regulatory catalogue, served from the `acts` and
`conformance_checklist` tables. The left pane lists the acts (EU AI Act, ISO 42001, NIST AI RMF, and
more), each with its version and control count. Select one to read its controls on the right: the
reference, the obligation, the roles it binds, and how each is assessed. You do not edit the built-in
catalogue; you assess your systems against it.

## 2. Register the teams and agents that act

Under **Identity**:

- **Teams** registers an application or team. This is the owner of the agents.
- **Agents** registers an agent under a team. Registration issues a one-time virtual key (shown once).
  A caller presents that key so the enforcement points know which agent is acting (chapter 8).

An agent must belong to a real team; the database enforces it.

## 3. Register the AI system you are governing

Under **Compliance, AI systems**, add the system you want to govern: its name, purpose, owner, risk
tier, sector and the jurisdictions it operates in. The AI system is the hub of governance: roles,
Statements of Applicability, evidence and governance records all attach to it.

Open the system to reach its workspace.

## 4. Declare roles and run the assessment (the Statement of Applicability)

In the system workspace:

1. **Roles.** Add the role your organisation plays for this system in each market, for example
   `provider` in the EU. The role and jurisdiction drive which controls apply.
2. **Statement of Applicability.** Pick a framework. The worksheet lists that act's controls, and marks
   each as applicable or not based on the system's role and risk tier. For each applicable control set a
   status (planned, implemented, partial, gap, not-applicable) and a justification, then save. Each row
   is stored in `soa_entries`, linked to the exact control in `conformance_checklist`.

If you want a fast start, use **Apply pack** to seed the applicable controls for the framework, then
refine.

## 5. Attach evidence

For a control that is implemented, attach evidence: a title, the owner, and a validity date. Evidence
is stored against the system and its control, with a freshness date so a report can tell current
evidence from stale. Stale or missing evidence shows up in the report rather than being assumed.

## 6. Generate the signed compliance report

Still in the system workspace (or under **Governance, Reports**), generate the framework report. It
grades every applicable control from the SoA and the evidence, states the conformity of each, lists the
not-applicable controls with the reason, and pins the framework version. The report is signed, so an
auditor can verify it with the public key alone. You can download it, and take a point-in-time snapshot
for the record.

## 7. Governance records: risk, impact, model cards, datasets

Under **Compliance, Governance** you record the rest of the lifecycle against a system:

- **New risk** enters a risk with likelihood and impact; the score and severity band form the residual-
  risk matrix shown in the workspace.
- **New assessment** records a conformity assessment or a fundamental-rights impact assessment (FRIA).
- **New model card** documents a model and links it to its use case and risk.
- **New dataset** records a dataset's provenance and lifecycle (source, licence, consent basis,
  retention, deletion or unlearning status).

Click any record to open its detail: all its fields, assignment and due date, links to other records,
and a comment thread.

## 8. Set the enforcement policy

Under **Policy**:

- **Deploy YAML** deploys a signed policy. Each deploy is a new version.
- **History** shows every version with its author and note, which one is active and which is the
  baseline, and lets you roll back to an earlier version or pin a new baseline. Policy is stored in the
  `artifacts` and `artifact_versions` tables and served signed to the enforcement points.
- **Author** drafts a rule from a plain-English description.

## 9. Configure the content firewall and agent config

- **Content firewall** sets what the firewall inspects and blocks (secrets, denied topics, toxicity, an
  optional external scanner). Each save is a new signed version, listed under Config version history.
- **Agent config** sets the per-group tool and MCP guard configuration, also versioned per group.

## 10. Operate and prove it

- **Governance, Approvals** resolves step-up holds. **Oversight** and **Violations** show what the
  enforcement points are doing. **Evidence** and **Integrity** let you verify the tamper-evident ledger.
- **Emergency, Kill-switch** engages a signed, scoped break-glass stop.
- **Health, Monitors** shows classifier drift, and **Integrity** verifies the signed evidence.

That is the whole loop: assess against the catalogue, evidence it, report it, enforce it, and prove it,
with every step stored and signed.
