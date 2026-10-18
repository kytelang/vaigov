# 4. The LLM gateway

`acp-gateway` governs **direct model API calls**. It is a reverse proxy in front of a model provider
(OpenAI, Anthropic, Bedrock, Gemini and the like) that applies the same policy engine, obligations
and evidence as the tool-call path, and, crucially, **holds the upstream API key itself**. Callers
send requests to the gateway without a key; the gateway authorises, then adds the key and forwards.
This is credential brokering: even a leaked client cannot reach the model off-ACP.

::: tip Enforcement model in varman
In the Kyte varman build, runtime enforcement runs through an **Envoy `ext_authz` sidecar** that calls
the content-firewall check, plus a **signed OPA / Rego policy bundle** served from the control plane to
an OPA sidecar, rather than a single standalone gateway binary. The served bundle now **honours the
configured default verdict** (it no longer fails open) and carries each rule's control tags and the
`step_up` approver group. Content-firewall inspection is on the request path only (see
[chapter 10](10-content-firewall.md)). Read the gateway flags and FinOps material below as the parity
design for the dedicated model-gateway surface.
:::

## Configure in the console, launch on the box

The gateway is an enforcement point you launch on a machine. Everything it governs is authored in the console: the policy on the **Policy** page, the model endpoints and their dispositions on the **AI Endpoints** page, and the content firewall on the **Content firewall** page. The one thing you run on the box is the gateway launch command below. Author and deploy the policy from the console, then launch the gateway against that policy file; the gateway holds the upstream model key and brokers every call, so nothing reaches a model off-ACP.

## Running it

```sh
acp-gateway \
  --addr 0.0.0.0:8799 \
  --policy policy.yaml \
  --upstream https://api.anthropic.com \
  --content-firewall
```

Point your application's model base-URL at the gateway. It streams responses through (server-sent
events pass straight back), applies a load-shed semaphore, and records every decision before
forwarding.

## Model classes

The gateway classifies each request's model into a class (`frontier`, `standard`, `embeddings`,
`image-gen`, ...) using a name taxonomy, and the policy governs by class. So a rule like "the
unattributed principal may not call a frontier model" holds across providers without naming every
model:

```yaml
  - id: no-anon-frontier
    when: { resource: frontier, principal: unattributed }
    verdict: deny
```

## Budgets

Token and cost budgets are an obligation on an allow. Under a single instance they are in-process;
across replicas, point the gateway at Postgres so replicas share one budget and a failover keeps the
limit correct:

```sh
acp-gateway --addr 0.0.0.0:8799 --policy policy.yaml \
  --upstream https://api.anthropic.com \
  --budget-pg "host=pg user=acp password=... dbname=acp" \
  --content-firewall
```

## FinOps: token and cost telemetry

Budgets cap spend before a call runs. FinOps telemetry records what was actually spent after it runs, so a platform team can see token consumption and estimated cost by model. The gateway reads the token usage block on each model response (OpenAI `prompt_tokens` and `completion_tokens`, Anthropic `input_tokens` and `output_tokens`) and folds it into running counters. On a buffered streaming response it reads the usage from the trailing chunk. On a plain streaming relay with no response gate active there is nothing to parse, so those calls are not counted.

Give the gateway a price table to turn tokens into money. Each `--price` flag maps a model to its input and output price per 1000 tokens, in whatever currency you price in (the metric label reads USD):

```bash
acp-gateway --upstream https://api.openai.com \
  --price gpt-4o:0.005:0.015 \
  --price gpt-4o-mini:0.00015:0.0006
```

Two surfaces expose the result:

- `GET /metrics` (Prometheus) gains `acp_gateway_prompt_tokens_total`, `acp_gateway_completion_tokens_total`, `acp_gateway_tokens_total` and `acp_gateway_cost_usd_total`, plus a per-model breakdown as `acp_gateway_model_tokens_total{model="..."}` and `acp_gateway_model_cost_usd_total{model="..."}`.
- `GET /usage` returns the same data as JSON for the console: totals plus a `by_model` array of `{model, calls, prompt_tokens, completion_tokens, total_tokens, cost_usd}`, and a `priced` flag that is false when no price table is set.

With no price table the gateway still counts tokens; only the cost estimate stays at zero.

## Content firewall on the prompt path

`--content-firewall` scans the prompt, and `--content-ml <model.json>` adds the trained injection
classifier. Detection is enforced on both the gateway (prompt) and the proxy (tool arguments); see
[chapter 10](10-content-firewall.md). If a content scan is configured and errors, the gateway blocks
(fail-closed), because forwarding an unscanned prompt when scanning was required would be unsafe.

## Identity

Add `--entra-tenant` and `--entra-audience`
to resolve the human principal per request from a bearer token; requests without a valid token
degrade to `unattributed`, which your policy can then treat as it likes. See [chapter 8](08-identity.md).

## Fleet reporting and break-glass

The gateway reports to the control plane the same way the proxy does. With `--report-url <control-plane>`
and `--report-token <token>` it posts a heartbeat every ten seconds and a governance event on each
non-allow decision, so the console liveness, alerts and violation views cover model calls too, and
`--proxy-id <id>` sets the name it reports under. It also honours the emergency kill-switch: point
`--break-glass-file` at the signed grant (and pin it with `--break-glass-key`) and an engaged
`lockdown_all` denies matching model calls at the gateway. See [chapter 11](11-containment.md) and
[chapter 14](14-operations.md).

## Flags

| Flag | Effect |
| --- | --- |
| `--addr <host:port>` | listen address |
| `--policy <file>` | the policy to enforce |
| `--upstream <base-url>` | the model provider to broker to |
| `--budget-pg <dsn>` | shared token/cost budgets via Postgres |
| `--content-firewall` | enable the signature content firewall on prompts |
| `--content-ml <model.json>` | also load the trained ML classifier |
| `--content-scan <url>` | send each prompt/response to an external scanner hook ([chapter 10](10-content-firewall.md)); the gateway fails closed if it errors |
| `--upstream-key <key>` | the brokered upstream model key the gateway holds, so a caller cannot reach the model off-ACP |
| `--price <model>:<in>:<out>` | FinOps price per 1000 tokens for a model (input:output); repeatable, feeds `/usage` and the cost metrics |
| `--groundedness-threshold <f>` | block a response whose claims are not grounded in its context below this score |
| `--block-secrets` / `--block-toxicity` / `--deny-topic <t>` | content-firewall toggles on the prompt/response |
| `--entra-tenant`, `--entra-audience` | Entra identity for the human principal |
| `--report-url <server>` | report a heartbeat and non-allow events to the control plane |
| `--report-token <tok>` | the shared token the control-plane reporting routes require (`ACP_REPORT_TOKEN`) |
| `--proxy-id <id>` | the identifier this gateway reports under |
| `--break-glass-file <file>` | honour a signed break-glass grant (lockdown, disable-enforce, bypass) |
| `--break-glass-key <hex>` | pin the break-glass public key so a tampered or unsigned grant is rejected |

Evidence at-rest encryption and HSM signing are configured by the same environment variables as the
proxy ([chapter 9](09-evidence.md)).
