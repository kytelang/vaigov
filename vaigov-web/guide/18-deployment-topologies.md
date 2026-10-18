# 18. Deployment topologies

This chapter answers one practical question: what runs where. It is deliberately simple. There is one
recommended topology for most customers, and a self-hosted alternative for buyers who cannot use a
hosted control plane.

## The recommended topology: managed control plane, workstation agents

Run the **control plane and the LLM gateway as a managed service on Azure**, and install the **agent on
each workstation**. Customers do not stand up servers; they install one lightweight agent per machine
and point it at the hosted control plane.

- **We host the control plane (Azure).** Identity, policy, approvals, evidence, GRC, conformance and
  the browser console all live in the managed service. Policy is authored and deployed centrally; every
  agent fetches its policy, firewall config and reporting endpoints from it over `--control-plane`.
- **The customer installs the agent per workstation.** `acp-agent` governs the machine: `mcp` for local
  MCP tool servers, `firewall` for direct model and API traffic, and `guard` to refuse any call that
  tries to skip ACP. The agent is thin: it holds almost no state, because policy and config come from
  the control plane.
- **The gateway is part of the managed service.** Direct model API calls route through `acp-gateway`,
  which holds the upstream key so a caller cannot reach the model off-ACP, and where token and cost
  (FinOps) telemetry is collected.
- **The store is Postgres.** The hosted control plane runs on PostgreSQL (Azure Database for PostgreSQL
  Flexible Server), which is what lets it run multiple replicas and gives point-in-time recovery and
  failover. Self-hosted single-node installs may use SQLite instead. See [chapter 16](16-setup.md#the-control-plane-database).

This keeps operations simple: no servers for the customer to run, central policy and evidence, and
enforcement where the work actually happens.

## Where each piece runs

| Workload | Example | Put the agent… | Why (what makes it unavoidable) |
| --- | --- | --- | --- |
| Developer machines: coding assistants, desktop AI apps, local MCP tools | Cursor or Claude Code calling a local `mcp-server-filesystem` over stdio, while an app hits `api.anthropic.com` directly | **Workstation** (`acp-agent mcp` + `firewall`, with `guard`) | Only place that can see a local stdio tool call and direct egress. Pair with `guard` and MDM-forced egress so it cannot be skipped |
| Server-hosted agents, CI jobs, backend runners, containerised agents | A CrewAI agent in a Kubernetes pod calling an internal `payments.charge` tool; a nightly GitHub Actions agent | **Central** (co-located with the gateway) | The work already runs server-side, so the enforcement point rides along in the same runtime. Simpler ops, no fleet to manage |
| Model / LLM API calls (any origin) | Any workload calling `api.openai.com`, Azure OpenAI or Bedrock, from a laptop or a pod | **Always central, the gateway** (`acp-gateway`) | The gateway holds the upstream key and brokers the call, so no caller can reach the model off-ACP. Also where FinOps telemetry lives |
| Cross-boundary calls (agent to a second proxy or a partner control plane) | A governed call leaving one trust zone and arriving at another enforcement point | **Both ends**: agent mints, receiver verifies | A signed `x-acp-identity` header (`acp egress-identity`), pinned on the receiver with `--identity-pubkey`, so attribution is cryptographic, not header-trust |

**Rule of thumb:** the gateway is always central; the agent follows the workload; anything a user can run
or call locally must be governed locally, because a central point cannot see a stdio tool call or a
direct API request that never reaches it.

## Why the agent is on the workstation

Enforcement only counts if it cannot be routed around. A local MCP tool server is governed only because
`acp-agent mcp stdio` owns the child's stdio on that machine, and a direct call to `api.openai.com` is
caught only if a forward proxy on that machine intercepts it. A hosted control plane sees neither. So for
developer and desktop workloads the agent has to be on the workstation, and its guarantee is only as
strong as your ability to force traffic through it:

- **Close the bypass.** Run the `guard` sidecar in front of tool servers so a call that skips ACP is
  refused, and use MDM or egress firewall rules to force machine traffic through the agent.
- **Manage the fleet.** Push install and updates through MDM. The agent is thin, so there is little to
  manage on the endpoint beyond enrolment and the optional ACP certificate authority for TLS
  interception.
- **Prove it is enforcing.** `acp verify-enforcement` and the coverage and posture checks confirm a
  workstation agent is actually enforcing, not disabled.

If you cannot mandate MDM or egress control on a machine (for example a contractor's own laptop), the
guarantee downgrades from hard enforcement to cooperative, and you should say so to the buyer rather than
imply otherwise.

## Self-hosted and air-gapped (the alternative)

Some buyers cannot send governance data to a hosted service: sovereign, defence, air-gapped or strictly
regulated environments. The same binaries run fully on-premises. The customer hosts `acp-server` (and
optionally `acp-gateway`) themselves, and the agents point at that private control-plane URL instead of
the managed one. Everything else in this chapter is identical; only the location of the control plane
changes. Use the [setup runbook](16-setup.md) for the self-hosted install.

## What we operate versus what the customer operates

| Responsibility | Managed (recommended) | Self-hosted |
| --- | --- | --- |
| Control plane, console, gateway | We host on Azure | Customer hosts |
| Policy authoring and deployment | Customer, in the hosted console | Customer, in their console |
| Workstation agents | Customer installs and manages (MDM) | Customer installs and manages (MDM) |
| Evidence storage and retention | Managed service | Customer's storage |
| Upgrades of the control plane | We roll out | Customer rolls out |

The split is the same shape as an endpoint-security product: a managed console plus customer-managed
endpoint agents. Billing follows the enrolled agent identities (per seat), independent of where the
control plane is hosted, so the self-hosted option is priced the same way as the managed one.
