# 20. Configuration guide: policy, firewall and enforcement

Chapter 19 walked the governance flow (register a system, assess it, report). This chapter is the other
half: how you configure what the system actually enforces, and the order to do it in. Everything here is
edited in the console and stored, versioned and signed, in the control-plane database.

## What you configure, and where

| You configure | On the screen | Stored as |
| --- | --- | --- |
| The authorization policy (who may do what) | Policy | a `policy` artifact, versioned |
| The content firewall (what text to inspect and block) | Content firewall | a `firewall_config` artifact, versioned |
| Interception rules (which traffic the forward proxy inspects) | Content firewall (rules) | firewall rules |
| Per-group agent settings (tool and MCP guard) | Agent config | an `agent_config` artifact per group, versioned |

Each save is a new signed version you can roll back to (see the History tab on the Policy and Content
firewall screens).

## Step 1: configure the authorization policy

The policy is one signed document. A rule matches on the trusted facts of a request (the tool, the agent,
the human principal, the resource and operation, and argument values) and returns a verdict.

Open **Policy, Deploy YAML** and write rules. A minimal policy:

```yaml
version: 1
# Start permissive so you can observe first; move to deny once coverage is proven.
default: allow
rules:
  # Never allow destructive database operations in production.
  - id: no-prod-delete
    when:
      tool: "db.*"
      env: { eq: "prod" }
      arg: { operation: { in: ["delete", "drop", "truncate"] } }
    verdict: deny

  # A large payment needs a human, with separation of duty.
  - id: payments-need-approval
    when: { tool: "payments.charge", arg: { amount_cents: { gt: 50000 } } }
    verdict: step_up
    approvers: ["finance"]

  # Reads are allowed, but PII is masked on the way out.
  - id: mask-pii-on-reads
    when: { tool: "db.*", arg: { operation: { eq: "read" } } }
    verdict: allow
    obligations: [{ kind: redact, fields: ["ssn", "card"] }]
```

The four verdicts are `allow`, `deny`, `step_up` (hold for a human), and `shadow` (record but do not
block). Obligations ride on an allow: `redact`, `rate_limit` (a token or cost budget), `confirm` and
`disclose`. The engine is default-deny with deny-overrides once you set `default: deny`.

**Observe before you enforce.** Set `enforcement_mode: observe` at the top and deploy. Blocking verdicts
are then recorded but not enforced, so you can watch what the policy would do on the Violations and
Evidence screens before switching to `enforce`.

**Deploy and iterate.** Click **Deploy**. That signs the policy and creates version 1. Change it and
deploy again for version 2. The **History** tab lists every version with its author and note, shows which
is active and which is the baseline, and lets you roll back or pin a new baseline. You can also draft a
rule from plain English on the **Author** tab.

Rules of thumb for getting to default-deny safely: start with `default: allow` and `enforcement_mode:
observe`, run real traffic, watch the would-block list, add explicit `allow` rules for what should pass,
then switch to `default: deny` and `enforce`.

## Step 2: configure the content firewall

The firewall answers a different question from the policy: "does this text carry a threat, and which
traffic do I inspect?". Open **Content firewall**:

- **Config**: turn on the firewall, and toggle what it blocks: secrets and PII, toxicity, and a list of
  denied topics. Optionally point it at an external scanner URL, and choose whether to fail closed if that
  scanner errors. Each save is a new version (see Config version history).
- **Interception rules**: these decide which traffic the forward proxy intercepts and how. A rule matches
  on host, SNI, path or port, and carries an action: `inspect-prompt`, `govern-tool-call`, `dlp-only`,
  `block` or `pass`. For example, intercept `api.openai.com` to inspect prompts, and `pass` an internal
  analytics host you do not want to touch.

The firewall runs on both directions: it screens the prompt on the way in and the response on the way out
(for injected instructions in a fetched document, secrets or PII leaking out, and system-prompt leaks).

## Step 3: configure per-group agent settings

Open **Agent config**. Pick a directory group (from your IdP) and set the tool and MCP guard configuration
for agents that act for that group. This is how you differ configuration by team without writing a policy
rule per agent. Like the others, each save is a signed, versioned artifact for that group.

## Step 4: make the configuration take effect (connect an enforcement point)

Configuration on the control plane does nothing until an enforcement point fetches and applies it. Start
one and point it at the control plane:

```sh
# govern a local MCP tool server
acp-agent mcp stdio --control-plane http://<control-plane-host>:8787 -- your-mcp-server --its --args

# or govern arbitrary HTTP/model traffic as a forward proxy (with the content firewall)
acp-agent firewall --control-plane http://<control-plane-host>:8787

# or govern direct model API calls through the brokered gateway
acp-gateway --upstream https://api.openai.com --policy <deployed-policy>
```

The agent fetches the signed policy, the firewall config and the interception rules from the control
plane, and from then on every governed action is authorised, screened and appended to the signed evidence
ledger. Now the Approvals, Oversight, Evidence and Violations screens fill with real activity.

## The recommended order

1. **Deploy a starter policy** in `default: allow` + `enforcement_mode: observe` (Step 1).
2. **Register a team and an agent** (Identity) so calls are attributed.
3. **Connect an enforcement point** (Step 4) and run real traffic.
4. **Configure the firewall** and interception rules for the providers you use (Step 2).
5. **Tighten the policy**: read the would-block list on Violations, add allow rules, then switch to
   `default: deny` and `enforce`.
6. **Govern the systems**: register each AI system and run its Statement of Applicability (chapter 19).

That is the whole configure-and-use loop: set the policy and firewall, connect an enforcement point,
observe, tighten, and govern.
