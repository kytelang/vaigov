--
-- PostgreSQL database dump
--

\restrict coFBKUR2v4D0McBwCYz4PwdldbdmnnGS97vSDYeg3jrmrfHyNblMfKZ15FyJKQs

-- Dumped from database version 18.4 (Homebrew)
-- Dumped by pg_dump version 18.4 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: act_countries; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.act_countries (
    act_slug character varying(255) NOT NULL,
    country_code character varying(8) NOT NULL,
    applicability text DEFAULT 'statutory'::text NOT NULL
);


ALTER TABLE public.act_countries OWNER TO kamlesh;

--
-- Name: acts; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.acts (
    act_id character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    label text NOT NULL,
    version text DEFAULT ''::text NOT NULL,
    framework_type text DEFAULT ''::text NOT NULL,
    jurisdiction text DEFAULT ''::text NOT NULL,
    effective_date text DEFAULT ''::text NOT NULL,
    record_keeping_reference text DEFAULT ''::text NOT NULL,
    source text DEFAULT ''::text NOT NULL,
    is_builtin integer DEFAULT 0 NOT NULL,
    tenant_id character varying(255) DEFAULT 'system'::character varying NOT NULL,
    created_ms bigint NOT NULL,
    updated_ms bigint NOT NULL
);


ALTER TABLE public.acts OWNER TO kamlesh;

--
-- Name: agents; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.agents (
    id character varying(255) NOT NULL,
    app_id character varying(255) NOT NULL,
    name text NOT NULL,
    token_sha256 text NOT NULL,
    active integer NOT NULL,
    owner text DEFAULT ''::text NOT NULL,
    metadata_json text DEFAULT '{}'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.agents OWNER TO kamlesh;

--
-- Name: ai_systems; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.ai_systems (
    id character varying(255) NOT NULL,
    name text NOT NULL,
    purpose text DEFAULT ''::text NOT NULL,
    owner text DEFAULT ''::text NOT NULL,
    lifecycle_state text DEFAULT 'development'::text NOT NULL,
    risk_tier text DEFAULT ''::text NOT NULL,
    sector text DEFAULT ''::text NOT NULL,
    asset_type text DEFAULT ''::text NOT NULL,
    jurisdictions text DEFAULT '[]'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL,
    updated_ms bigint NOT NULL
);


ALTER TABLE public.ai_systems OWNER TO kamlesh;

--
-- Name: apps; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.apps (
    id character varying(255) NOT NULL,
    name text NOT NULL,
    owner text NOT NULL,
    metadata_json text DEFAULT '{}'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.apps OWNER TO kamlesh;

--
-- Name: artifact_versions; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.artifact_versions (
    version_id character varying(255) NOT NULL,
    artifact_id character varying(255) NOT NULL,
    version_no integer NOT NULL,
    body text NOT NULL,
    author text DEFAULT ''::text NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    pubkey_hex text DEFAULT ''::text NOT NULL,
    sig_hex text DEFAULT ''::text NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.artifact_versions OWNER TO kamlesh;

--
-- Name: artifacts; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.artifacts (
    artifact_id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    scope text DEFAULT ''::text NOT NULL,
    active_version character varying(255) DEFAULT ''::character varying NOT NULL,
    baseline_version character varying(255) DEFAULT ''::character varying NOT NULL,
    updated_ms bigint NOT NULL
);


ALTER TABLE public.artifacts OWNER TO kamlesh;

--
-- Name: conformance_checklist; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.conformance_checklist (
    item_id character varying(255) NOT NULL,
    act_id character varying(255) NOT NULL,
    control_id text NOT NULL,
    ordinal integer DEFAULT 0 NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    required_evidence text DEFAULT ''::text NOT NULL,
    reference text DEFAULT ''::text NOT NULL,
    path_json text DEFAULT '[]'::text NOT NULL,
    obligation_type text DEFAULT ''::text NOT NULL,
    roles_json text DEFAULT '[]'::text NOT NULL,
    applicability text DEFAULT 'always'::text NOT NULL,
    assessment_method text DEFAULT ''::text NOT NULL,
    citation text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.conformance_checklist OWNER TO kamlesh;

--
-- Name: control_crosswalk; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.control_crosswalk (
    id character varying(255) NOT NULL,
    from_item character varying(255) NOT NULL,
    to_item character varying(255) NOT NULL,
    relation text DEFAULT 'equivalent'::text NOT NULL
);


ALTER TABLE public.control_crosswalk OWNER TO kamlesh;

--
-- Name: control_leader; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.control_leader (
    id integer NOT NULL,
    holder text NOT NULL,
    token bigint NOT NULL,
    expires_ms bigint NOT NULL
);


ALTER TABLE public.control_leader OWNER TO kamlesh;

--
-- Name: control_packs; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.control_packs (
    id character varying(255) NOT NULL,
    version text NOT NULL,
    doc_json text NOT NULL,
    pubkey_hex text NOT NULL,
    sig_hex text NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.control_packs OWNER TO kamlesh;

--
-- Name: control_state; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.control_state (
    k character varying(255) NOT NULL,
    v text NOT NULL,
    updated_ms bigint NOT NULL
);


ALTER TABLE public.control_state OWNER TO kamlesh;

--
-- Name: countries; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.countries (
    code character varying(2) NOT NULL,
    name text NOT NULL,
    region text DEFAULT 'other'::text NOT NULL
);


ALTER TABLE public.countries OWNER TO kamlesh;

--
-- Name: decisions; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.decisions (
    decision_id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    ts_ms bigint DEFAULT 0 NOT NULL,
    ts_text text DEFAULT ''::text NOT NULL,
    verdict text DEFAULT ''::text NOT NULL,
    rule_id character varying(255) DEFAULT ''::character varying NOT NULL,
    controls_json text DEFAULT '[]'::text NOT NULL,
    obligations_json text DEFAULT '[]'::text NOT NULL,
    resource text DEFAULT ''::text NOT NULL,
    operation text DEFAULT ''::text NOT NULL,
    subject text DEFAULT ''::text NOT NULL,
    bundle_revision text DEFAULT ''::text NOT NULL,
    input_json text DEFAULT '{}'::text NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.decisions OWNER TO kamlesh;

--
-- Name: drift_counts; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.drift_counts (
    class character varying(255) NOT NULL,
    hits bigint NOT NULL,
    total bigint NOT NULL,
    baseline double precision NOT NULL,
    updated_ms bigint NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.drift_counts OWNER TO kamlesh;

--
-- Name: endpoints; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.endpoints (
    endpoint character varying(255) NOT NULL,
    kind text NOT NULL,
    provider text NOT NULL,
    disposition text NOT NULL,
    operator text NOT NULL,
    reason text NOT NULL,
    decided_ms bigint NOT NULL,
    expires_ms bigint NOT NULL,
    pubkey_hex text NOT NULL,
    sig_hex text NOT NULL,
    vendor_id character varying(255),
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.endpoints OWNER TO kamlesh;

--
-- Name: entra_tenant_map; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.entra_tenant_map (
    entra_tid character varying(255) NOT NULL,
    tenant_id character varying(255) NOT NULL,
    issuer text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    connected_ms bigint NOT NULL
);


ALTER TABLE public.entra_tenant_map OWNER TO kamlesh;

--
-- Name: evidence; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.evidence (
    id character varying(255) NOT NULL,
    system_id character varying(255) NOT NULL,
    framework text NOT NULL,
    control_id text NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    source text DEFAULT ''::text NOT NULL,
    owner text DEFAULT ''::text NOT NULL,
    produced_ms bigint DEFAULT 0 NOT NULL,
    valid_until_ms bigint DEFAULT 0 NOT NULL,
    artefact_ref text DEFAULT ''::text NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL,
    checklist_item_id character varying(255)
);


ALTER TABLE public.evidence OWNER TO kamlesh;

--
-- Name: firewall_config; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.firewall_config (
    tenant_id character varying(255) NOT NULL,
    enabled integer NOT NULL,
    block_secrets integer NOT NULL,
    deny_topics text NOT NULL,
    model text NOT NULL,
    scan_url text DEFAULT ''::text NOT NULL,
    block_on_scanner_error integer DEFAULT 0 NOT NULL,
    feed_version bigint DEFAULT 0 NOT NULL,
    threat_signatures text DEFAULT '[]'::text NOT NULL,
    block_toxicity integer DEFAULT 0 NOT NULL,
    updated_ms bigint NOT NULL
);


ALTER TABLE public.firewall_config OWNER TO kamlesh;

--
-- Name: firewall_rules; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.firewall_rules (
    id character varying(255) NOT NULL,
    match_json text NOT NULL,
    classify text NOT NULL,
    action text NOT NULL,
    created_ms bigint NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.firewall_rules OWNER TO kamlesh;

--
-- Name: governed_endpoints; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.governed_endpoints (
    id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    host text NOT NULL,
    port integer DEFAULT 443 NOT NULL,
    enabled integer DEFAULT 1 NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.governed_endpoints OWNER TO kamlesh;

--
-- Name: grc_audit; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.grc_audit (
    id character varying(255) NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    action text NOT NULL,
    actor text DEFAULT ''::text NOT NULL,
    detail text DEFAULT ''::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    ts_ms bigint NOT NULL
);


ALTER TABLE public.grc_audit OWNER TO kamlesh;

--
-- Name: grc_comments; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.grc_comments (
    id character varying(255) NOT NULL,
    grc_id character varying(255) NOT NULL,
    author text NOT NULL,
    body text NOT NULL,
    created_ms bigint NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.grc_comments OWNER TO kamlesh;

--
-- Name: grc_links; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.grc_links (
    id character varying(255) NOT NULL,
    from_record character varying(255) NOT NULL,
    to_record character varying(255) NOT NULL,
    relation text DEFAULT 'ref'::text NOT NULL,
    created_ms bigint DEFAULT 0 NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.grc_links OWNER TO kamlesh;

--
-- Name: grc_records; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.grc_records (
    id character varying(255) NOT NULL,
    kind text NOT NULL,
    subject text NOT NULL,
    title text NOT NULL,
    status text NOT NULL,
    body text NOT NULL,
    operator text NOT NULL,
    created_ms bigint NOT NULL,
    pubkey_hex text NOT NULL,
    sig_hex text NOT NULL,
    linked_refs text DEFAULT '[]'::text NOT NULL,
    answers_json text DEFAULT '{}'::text NOT NULL,
    assignee text DEFAULT ''::text NOT NULL,
    due_ms bigint DEFAULT 0 NOT NULL,
    stage text DEFAULT ''::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    system_id character varying(255),
    model_id character varying(255)
);


ALTER TABLE public.grc_records OWNER TO kamlesh;

--
-- Name: ingested_evidence; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.ingested_evidence (
    decision_id character varying(255) NOT NULL,
    pep text NOT NULL,
    kind text NOT NULL,
    verdict text NOT NULL,
    record text NOT NULL,
    operator text NOT NULL,
    created_ms bigint NOT NULL,
    pubkey_hex text NOT NULL,
    sig_hex text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.ingested_evidence OWNER TO kamlesh;

--
-- Name: lineage_edges; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.lineage_edges (
    id character varying(255) NOT NULL,
    data_class text NOT NULL,
    tool text NOT NULL,
    count bigint NOT NULL,
    updated_ms bigint NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.lineage_edges OWNER TO kamlesh;

--
-- Name: models; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.models (
    id character varying(255) NOT NULL,
    name text NOT NULL,
    provider text NOT NULL,
    version text NOT NULL,
    card_json text DEFAULT '{}'::text NOT NULL,
    scan_status text DEFAULT 'unscanned'::text NOT NULL,
    aibom_json text DEFAULT ''::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL,
    vendor_id character varying(255)
);


ALTER TABLE public.models OWNER TO kamlesh;

--
-- Name: policy_rules; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.policy_rules (
    rule_id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    subject_json text DEFAULT '{}'::text NOT NULL,
    resource text DEFAULT ''::text NOT NULL,
    operation text DEFAULT ''::text NOT NULL,
    condition_json text DEFAULT '[]'::text NOT NULL,
    verdict text DEFAULT 'deny'::text NOT NULL,
    obligations_json text DEFAULT '[]'::text NOT NULL,
    enabled integer DEFAULT 1 NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    created_ms bigint NOT NULL,
    updated_ms bigint NOT NULL,
    match_json text DEFAULT ''::text NOT NULL,
    approver_group text DEFAULT ''::text NOT NULL,
    source_pack text DEFAULT ''::text NOT NULL,
    source_pack_version integer DEFAULT 0 NOT NULL,
    pack_customised integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.policy_rules OWNER TO kamlesh;

--
-- Name: principals; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.principals (
    id character varying(255) NOT NULL,
    display text DEFAULT ''::text NOT NULL,
    source text DEFAULT 'sso'::text NOT NULL,
    groups_json text DEFAULT '[]'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.principals OWNER TO kamlesh;

--
-- Name: report_snapshots; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.report_snapshots (
    id character varying(255) NOT NULL,
    framework text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    body_json text NOT NULL,
    created_ms bigint NOT NULL,
    act_id character varying(255)
);


ALTER TABLE public.report_snapshots OWNER TO kamlesh;

--
-- Name: revoked_sessions; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.revoked_sessions (
    jti character varying(255) NOT NULL,
    expires_ms bigint NOT NULL
);


ALTER TABLE public.revoked_sessions OWNER TO kamlesh;

--
-- Name: rule_controls; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.rule_controls (
    id character varying(255) NOT NULL,
    rule_id character varying(255) NOT NULL,
    item_id character varying(255) NOT NULL,
    relation text DEFAULT 'satisfies'::text NOT NULL
);


ALTER TABLE public.rule_controls OWNER TO kamlesh;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    applied_ms bigint NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO kamlesh;

--
-- Name: seeds; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.seeds (
    name character varying(255) NOT NULL,
    hash text NOT NULL,
    applied_ms bigint NOT NULL
);


ALTER TABLE public.seeds OWNER TO kamlesh;

--
-- Name: soa_entries; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.soa_entries (
    id character varying(255) NOT NULL,
    system_id character varying(255) NOT NULL,
    framework text NOT NULL,
    control_id text NOT NULL,
    applicable integer DEFAULT 1 NOT NULL,
    justification text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'planned'::text NOT NULL,
    evidence_refs text DEFAULT '[]'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    updated_ms bigint NOT NULL,
    checklist_item_id character varying(255)
);


ALTER TABLE public.soa_entries OWNER TO kamlesh;

--
-- Name: system_roles; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.system_roles (
    id character varying(255) NOT NULL,
    system_id character varying(255) NOT NULL,
    role text NOT NULL,
    jurisdiction text DEFAULT ''::text NOT NULL,
    market_date text DEFAULT ''::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.system_roles OWNER TO kamlesh;

--
-- Name: tenant_policy_packs; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.tenant_policy_packs (
    tenant_id character varying(255) NOT NULL,
    pack_slug character varying(255) NOT NULL,
    version integer NOT NULL,
    params_json text DEFAULT '{}'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    installed_ms bigint NOT NULL
);


ALTER TABLE public.tenant_policy_packs OWNER TO kamlesh;

--
-- Name: tenant_settings; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.tenant_settings (
    tenant_id character varying(255) NOT NULL,
    onboarded integer DEFAULT 0 NOT NULL,
    jurisdiction text DEFAULT ''::text NOT NULL,
    enabled_acts text DEFAULT '[]'::text NOT NULL,
    org_name text DEFAULT ''::text NOT NULL,
    updated_ms bigint DEFAULT 0 NOT NULL,
    company_address text DEFAULT ''::text NOT NULL,
    contact_name text DEFAULT ''::text NOT NULL,
    contact_email text DEFAULT ''::text NOT NULL,
    contact_phone text DEFAULT ''::text NOT NULL,
    profile_json text DEFAULT '{}'::text NOT NULL,
    address_line1 text DEFAULT ''::text NOT NULL,
    address_line2 text DEFAULT ''::text NOT NULL,
    city text DEFAULT ''::text NOT NULL,
    postcode text DEFAULT ''::text NOT NULL,
    country text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.tenant_settings OWNER TO kamlesh;

--
-- Name: ticket_rules; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.ticket_rules (
    id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    name text NOT NULL,
    enabled integer DEFAULT 1 NOT NULL,
    match_verdict text DEFAULT 'deny'::text NOT NULL,
    match_control text DEFAULT ''::text NOT NULL,
    match_resource text DEFAULT ''::text NOT NULL,
    connector text DEFAULT 'webhook'::text NOT NULL,
    target_json text DEFAULT '{}'::text NOT NULL,
    throttle_sec integer DEFAULT 3600 NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.ticket_rules OWNER TO kamlesh;

--
-- Name: tickets; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.tickets (
    id character varying(255) NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    rule_id character varying(255) DEFAULT ''::character varying NOT NULL,
    decision_id character varying(255) DEFAULT ''::character varying NOT NULL,
    dedup_key text DEFAULT ''::text NOT NULL,
    connector text DEFAULT ''::text NOT NULL,
    external_id text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    hits integer DEFAULT 1 NOT NULL,
    created_ms bigint NOT NULL,
    last_sent_ms bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.tickets OWNER TO kamlesh;

--
-- Name: vendors; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.vendors (
    id character varying(255) NOT NULL,
    name text NOT NULL,
    risk_json text DEFAULT '{}'::text NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL,
    review_due_ms bigint DEFAULT 0 NOT NULL,
    created_ms bigint NOT NULL
);


ALTER TABLE public.vendors OWNER TO kamlesh;

--
-- Name: violation_events; Type: TABLE; Schema: public; Owner: kamlesh
--

CREATE TABLE public.violation_events (
    id character varying(255) NOT NULL,
    kind text NOT NULL,
    pep text NOT NULL,
    agent text NOT NULL,
    tool text NOT NULL,
    verdict text NOT NULL,
    rule_id text NOT NULL,
    impact text NOT NULL,
    outcome text NOT NULL,
    ts_ms bigint NOT NULL,
    tenant_id character varying(255) DEFAULT 'default'::character varying NOT NULL
);


ALTER TABLE public.violation_events OWNER TO kamlesh;

--
-- Name: act_countries act_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.act_countries
    ADD CONSTRAINT act_countries_pkey PRIMARY KEY (act_slug, country_code);


--
-- Name: acts acts_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.acts
    ADD CONSTRAINT acts_pkey PRIMARY KEY (act_id);


--
-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


--
-- Name: ai_systems ai_systems_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.ai_systems
    ADD CONSTRAINT ai_systems_pkey PRIMARY KEY (id);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


--
-- Name: artifact_versions artifact_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.artifact_versions
    ADD CONSTRAINT artifact_versions_pkey PRIMARY KEY (version_id);


--
-- Name: artifacts artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.artifacts
    ADD CONSTRAINT artifacts_pkey PRIMARY KEY (artifact_id);


--
-- Name: conformance_checklist conformance_checklist_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.conformance_checklist
    ADD CONSTRAINT conformance_checklist_pkey PRIMARY KEY (item_id);


--
-- Name: control_crosswalk control_crosswalk_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_crosswalk
    ADD CONSTRAINT control_crosswalk_pkey PRIMARY KEY (id);


--
-- Name: control_leader control_leader_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_leader
    ADD CONSTRAINT control_leader_pkey PRIMARY KEY (id);


--
-- Name: control_packs control_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_packs
    ADD CONSTRAINT control_packs_pkey PRIMARY KEY (id);


--
-- Name: control_state control_state_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_state
    ADD CONSTRAINT control_state_pkey PRIMARY KEY (k);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (code);


--
-- Name: decisions decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT decisions_pkey PRIMARY KEY (decision_id);


--
-- Name: drift_counts drift_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.drift_counts
    ADD CONSTRAINT drift_counts_pkey PRIMARY KEY (class);


--
-- Name: endpoints endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.endpoints
    ADD CONSTRAINT endpoints_pkey PRIMARY KEY (endpoint);


--
-- Name: entra_tenant_map entra_tenant_map_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.entra_tenant_map
    ADD CONSTRAINT entra_tenant_map_pkey PRIMARY KEY (entra_tid);


--
-- Name: evidence evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_pkey PRIMARY KEY (id);


--
-- Name: firewall_config firewall_config_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.firewall_config
    ADD CONSTRAINT firewall_config_pkey PRIMARY KEY (tenant_id);


--
-- Name: firewall_rules firewall_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.firewall_rules
    ADD CONSTRAINT firewall_rules_pkey PRIMARY KEY (id);


--
-- Name: governed_endpoints governed_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.governed_endpoints
    ADD CONSTRAINT governed_endpoints_pkey PRIMARY KEY (id);


--
-- Name: grc_audit grc_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_audit
    ADD CONSTRAINT grc_audit_pkey PRIMARY KEY (id);


--
-- Name: grc_comments grc_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_comments
    ADD CONSTRAINT grc_comments_pkey PRIMARY KEY (id);


--
-- Name: grc_links grc_links_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_links
    ADD CONSTRAINT grc_links_pkey PRIMARY KEY (id);


--
-- Name: grc_records grc_records_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_records
    ADD CONSTRAINT grc_records_pkey PRIMARY KEY (id);


--
-- Name: ingested_evidence ingested_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.ingested_evidence
    ADD CONSTRAINT ingested_evidence_pkey PRIMARY KEY (decision_id);


--
-- Name: lineage_edges lineage_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.lineage_edges
    ADD CONSTRAINT lineage_edges_pkey PRIMARY KEY (id);


--
-- Name: models models_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.models
    ADD CONSTRAINT models_pkey PRIMARY KEY (id);


--
-- Name: policy_rules policy_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.policy_rules
    ADD CONSTRAINT policy_rules_pkey PRIMARY KEY (rule_id);


--
-- Name: principals principals_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.principals
    ADD CONSTRAINT principals_pkey PRIMARY KEY (id);


--
-- Name: report_snapshots report_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.report_snapshots
    ADD CONSTRAINT report_snapshots_pkey PRIMARY KEY (id);


--
-- Name: revoked_sessions revoked_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.revoked_sessions
    ADD CONSTRAINT revoked_sessions_pkey PRIMARY KEY (jti);


--
-- Name: rule_controls rule_controls_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.rule_controls
    ADD CONSTRAINT rule_controls_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: seeds seeds_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.seeds
    ADD CONSTRAINT seeds_pkey PRIMARY KEY (name);


--
-- Name: soa_entries soa_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.soa_entries
    ADD CONSTRAINT soa_entries_pkey PRIMARY KEY (id);


--
-- Name: system_roles system_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.system_roles
    ADD CONSTRAINT system_roles_pkey PRIMARY KEY (id);


--
-- Name: tenant_policy_packs tenant_policy_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.tenant_policy_packs
    ADD CONSTRAINT tenant_policy_packs_pkey PRIMARY KEY (tenant_id, pack_slug);


--
-- Name: tenant_settings tenant_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.tenant_settings
    ADD CONSTRAINT tenant_settings_pkey PRIMARY KEY (tenant_id);


--
-- Name: ticket_rules ticket_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.ticket_rules
    ADD CONSTRAINT ticket_rules_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: vendors vendors_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (id);


--
-- Name: violation_events violation_events_pkey; Type: CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.violation_events
    ADD CONSTRAINT violation_events_pkey PRIMARY KEY (id);


--
-- Name: idx_act_countries_country; Type: INDEX; Schema: public; Owner: kamlesh
--

CREATE INDEX idx_act_countries_country ON public.act_countries USING btree (country_code);


--
-- Name: idx_decisions_tenant_ts; Type: INDEX; Schema: public; Owner: kamlesh
--

CREATE INDEX idx_decisions_tenant_ts ON public.decisions USING btree (tenant_id, ts_ms);


--
-- Name: idx_entra_map_tenant; Type: INDEX; Schema: public; Owner: kamlesh
--

CREATE INDEX idx_entra_map_tenant ON public.entra_tenant_map USING btree (tenant_id);


--
-- Name: idx_tickets_dedup; Type: INDEX; Schema: public; Owner: kamlesh
--

CREATE INDEX idx_tickets_dedup ON public.tickets USING btree (tenant_id, dedup_key);


--
-- Name: agents agents_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: artifact_versions artifact_versions_artifact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.artifact_versions
    ADD CONSTRAINT artifact_versions_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES public.artifacts(artifact_id) ON DELETE CASCADE;


--
-- Name: conformance_checklist conformance_checklist_act_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.conformance_checklist
    ADD CONSTRAINT conformance_checklist_act_id_fkey FOREIGN KEY (act_id) REFERENCES public.acts(act_id) ON DELETE CASCADE;


--
-- Name: control_crosswalk control_crosswalk_from_item_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_crosswalk
    ADD CONSTRAINT control_crosswalk_from_item_fkey FOREIGN KEY (from_item) REFERENCES public.conformance_checklist(item_id) ON DELETE CASCADE;


--
-- Name: control_crosswalk control_crosswalk_to_item_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.control_crosswalk
    ADD CONSTRAINT control_crosswalk_to_item_fkey FOREIGN KEY (to_item) REFERENCES public.conformance_checklist(item_id) ON DELETE CASCADE;


--
-- Name: endpoints endpoints_vendor_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.endpoints
    ADD CONSTRAINT endpoints_vendor_fk FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL;


--
-- Name: evidence evidence_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_item_fk FOREIGN KEY (checklist_item_id) REFERENCES public.conformance_checklist(item_id) ON DELETE SET NULL;


--
-- Name: evidence evidence_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.ai_systems(id) ON DELETE CASCADE;


--
-- Name: grc_comments grc_comments_grc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_comments
    ADD CONSTRAINT grc_comments_grc_id_fkey FOREIGN KEY (grc_id) REFERENCES public.grc_records(id) ON DELETE CASCADE;


--
-- Name: grc_links grc_links_from_record_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_links
    ADD CONSTRAINT grc_links_from_record_fkey FOREIGN KEY (from_record) REFERENCES public.grc_records(id) ON DELETE CASCADE;


--
-- Name: grc_links grc_links_to_record_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_links
    ADD CONSTRAINT grc_links_to_record_fkey FOREIGN KEY (to_record) REFERENCES public.grc_records(id) ON DELETE CASCADE;


--
-- Name: grc_records grc_records_model_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_records
    ADD CONSTRAINT grc_records_model_fk FOREIGN KEY (model_id) REFERENCES public.models(id) ON DELETE SET NULL;


--
-- Name: grc_records grc_records_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.grc_records
    ADD CONSTRAINT grc_records_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.ai_systems(id) ON DELETE SET NULL;


--
-- Name: models models_vendor_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.models
    ADD CONSTRAINT models_vendor_fk FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL;


--
-- Name: report_snapshots report_snapshots_act_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.report_snapshots
    ADD CONSTRAINT report_snapshots_act_fk FOREIGN KEY (act_id) REFERENCES public.acts(act_id) ON DELETE CASCADE;


--
-- Name: rule_controls rule_controls_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.rule_controls
    ADD CONSTRAINT rule_controls_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.conformance_checklist(item_id) ON DELETE CASCADE;


--
-- Name: rule_controls rule_controls_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.rule_controls
    ADD CONSTRAINT rule_controls_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.policy_rules(rule_id) ON DELETE CASCADE;


--
-- Name: soa_entries soa_entries_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.soa_entries
    ADD CONSTRAINT soa_entries_item_fk FOREIGN KEY (checklist_item_id) REFERENCES public.conformance_checklist(item_id) ON DELETE CASCADE;


--
-- Name: soa_entries soa_entries_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.soa_entries
    ADD CONSTRAINT soa_entries_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.ai_systems(id) ON DELETE CASCADE;


--
-- Name: system_roles system_roles_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: kamlesh
--

ALTER TABLE ONLY public.system_roles
    ADD CONSTRAINT system_roles_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.ai_systems(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict coFBKUR2v4D0McBwCYz4PwdldbdmnnGS97vSDYeg3jrmrfHyNblMfKZ15FyJKQs

