-- SaaS billing + usage metering (docs/relevance-saas.md §4). Varman-owned tables.
CREATE TABLE IF NOT EXISTS subscriptions (
  tenant_id text PRIMARY KEY,
  plan_slug text NOT NULL DEFAULT 'free',
  status text NOT NULL DEFAULT 'active',
  stripe_customer_id text NOT NULL DEFAULT '',
  stripe_subscription_id text NOT NULL DEFAULT '',
  current_period_end_ms bigint NOT NULL DEFAULT 0,
  created_ms bigint NOT NULL DEFAULT 0,
  updated_ms bigint NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS usage_counters (
  tenant_id text NOT NULL,
  period text NOT NULL,
  decisions_count bigint NOT NULL DEFAULT 0,
  updated_ms bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (tenant_id, period)
);
