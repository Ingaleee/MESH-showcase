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

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: enforce_publishing_active_binding(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_publishing_active_binding() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.active_deployment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.active_deployment_id
      AND d.partner_id = NEW.id AND d.state = 'confirmed' AND d.remote_sequence = NEW.active_sequence
  ) THEN RAISE EXCEPTION 'active deployment must belong to this partner and sequence'; END IF;
  RETURN NEW;
END $$;


--
-- Name: enforce_publishing_rollback_basis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_publishing_rollback_basis() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.kind = 'rollback' AND NOT EXISTS (
    SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.rollback_of_id
      AND d.partner_id = NEW.partner_id AND d.candidate_id = NEW.candidate_id AND d.state = 'confirmed'
  ) THEN RAISE EXCEPTION 'rollback requires a confirmed deployment of the same partner and candidate'; END IF;
  RETURN NEW;
END $$;


--
-- Name: guard_reclaimed_publishing_attachment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_reclaimed_publishing_attachment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE upload_state text;
BEGIN
  SELECT state INTO upload_state FROM publishing_upload_intents
    WHERE artifact_blob_id = NEW.blob_id FOR UPDATE;
  IF upload_state = 'discarded' THEN
    RAISE EXCEPTION 'a reclaimed publishing blob cannot acquire references';
  END IF;
  RETURN NEW;
END $$;


--
-- Name: guard_reclaimed_publishing_candidate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_reclaimed_publishing_candidate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE upload_state text;
BEGIN
  SELECT state INTO upload_state FROM publishing_upload_intents
    WHERE artifact_blob_id = NEW.artifact_blob_id FOR UPDATE;
  IF upload_state = 'discarded' THEN
    RAISE EXCEPTION 'a reclaimed publishing blob cannot acquire references';
  END IF;
  RETURN NEW;
END $$;


--
-- Name: mesh_check_ledger_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mesh_check_ledger_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE target_id uuid; entry_count integer;
BEGIN
  IF TG_TABLE_NAME = 'finance_ledger_transactions' THEN
    target_id := NEW.id;
  ELSE
    target_id := COALESCE(NEW.ledger_transaction_id, OLD.ledger_transaction_id);
  END IF;
  IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id = target_id AND status = 'posted') THEN
    SELECT COUNT(*) INTO entry_count FROM finance_ledger_entries WHERE ledger_transaction_id = target_id;
    IF entry_count < 2 OR EXISTS (
      SELECT currency FROM finance_ledger_entries WHERE ledger_transaction_id = target_id
      GROUP BY currency HAVING SUM(CASE direction WHEN 'debit' THEN amount_minor ELSE -amount_minor END) <> 0
    ) THEN RAISE EXCEPTION 'unbalanced ledger transaction %', target_id; END IF;
  END IF;
  RETURN NULL;
END $$;


--
-- Name: mesh_protect_agreement_terms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mesh_protect_agreement_terms() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.terms IS DISTINCT FROM OLD.terms
    OR NEW.client_id <> OLD.client_id OR NEW.creator_id <> OLD.creator_id
    OR NEW.source_award_id <> OLD.source_award_id THEN
    RAISE EXCEPTION 'agreed terms and parties are immutable';
  END IF;
  RETURN NEW;
END $$;


--
-- Name: mesh_protect_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mesh_protect_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'historical record is immutable'; END $$;


--
-- Name: mesh_protect_posted_ledger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mesh_protect_posted_ledger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME = 'finance_ledger_transactions' THEN
    IF OLD.status = 'posted' THEN RAISE EXCEPTION 'posted ledger transaction is immutable'; END IF;
  ELSIF TG_OP = 'INSERT' THEN
    IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id = NEW.ledger_transaction_id AND status = 'posted') THEN
      RAISE EXCEPTION 'posted ledger entries are immutable';
    END IF;
    RETURN NEW;
  ELSE
    IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id IN (OLD.ledger_transaction_id, NEW.ledger_transaction_id) AND status = 'posted') THEN
      RAISE EXCEPTION 'posted ledger entries are immutable';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;


--
-- Name: mesh_protect_work_file(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mesh_protect_work_file() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.submission_id IS NOT NULL AND (TG_OP = 'DELETE' OR
    NEW.submission_id IS DISTINCT FROM OLD.submission_id OR
    NEW.engagement_id IS DISTINCT FROM OLD.engagement_id OR
    NEW.creator_id IS DISTINCT FROM OLD.creator_id OR NEW.sha256 IS DISTINCT FROM OLD.sha256) THEN
    RAISE EXCEPTION 'submitted file association is immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;


--
-- Name: protect_publishing_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_publishing_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'publishing history cannot be deleted'; END IF;
  IF TG_TABLE_NAME = 'publishing_partners' THEN
    IF ROW(NEW.owner_id, NEW.name, NEW.origin, NEW.credential_ref, NEW.contract_version)
      IS DISTINCT FROM ROW(OLD.owner_id, OLD.name, OLD.origin, OLD.credential_ref, OLD.contract_version)
      OR NEW.active_sequence < OLD.active_sequence THEN
      RAISE EXCEPTION 'partner binding and monotonic sequence are protected';
    END IF;
    IF NEW.active_deployment_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.active_deployment_id
        AND d.partner_id = NEW.id AND d.state = 'confirmed' AND d.remote_sequence = NEW.active_sequence
    ) THEN RAISE EXCEPTION 'active deployment must belong to this partner and sequence'; END IF;
  END IF;
  IF TG_TABLE_NAME = 'publishing_candidates'  OR TG_TABLE_NAME = 'publishing_callback_receipts' THEN
    RAISE EXCEPTION 'publishing inputs and receipts are immutable';
  END IF;
  IF TG_TABLE_NAME = 'publishing_validations' THEN
    IF ROW(NEW.candidate_id, NEW.policy_version, NEW.input_fingerprint, NEW.created_at)
      IS DISTINCT FROM ROW(OLD.candidate_id, OLD.policy_version, OLD.input_fingerprint, OLD.created_at)
      OR OLD.state IN ('passed','rejected','failed') THEN
      RAISE EXCEPTION 'validation provenance and terminal result are immutable';
    END IF;
  END IF;
  IF TG_TABLE_NAME = 'publishing_deployments' THEN
    IF ROW(NEW.partner_id, NEW.candidate_id, NEW.validation_id, NEW.rollback_of_id, NEW.kind, NEW.scenario, NEW.correlation_id, NEW.created_at)
      IS DISTINCT FROM ROW(OLD.partner_id, OLD.candidate_id, OLD.validation_id, OLD.rollback_of_id, OLD.kind, OLD.scenario, OLD.correlation_id, OLD.created_at)
      OR OLD.state IN ('confirmed','failed') THEN
      RAISE EXCEPTION 'deployment provenance and terminal result are immutable';
    END IF;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: validate_publishing_release_basis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_publishing_release_basis() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM publishing_validations v WHERE v.id = NEW.validation_id
    AND v.candidate_id = NEW.candidate_id AND v.state = 'passed') THEN
    RAISE EXCEPTION 'release requires a passed validation of this candidate';
  END IF;
  RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: engagements_acceptances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements_acceptances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    submission_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: engagements_engagements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements_engagements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    source_award_id uuid NOT NULL,
    client_id uuid NOT NULL,
    creator_id uuid NOT NULL,
    terms jsonb NOT NULL,
    state character varying DEFAULT 'agreed'::character varying NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    started_at timestamp(6) without time zone,
    CONSTRAINT engagement_distinct_parties CHECK ((client_id <> creator_id)),
    CONSTRAINT engagement_state CHECK (((state)::text = ANY (ARRAY[('agreed'::character varying)::text, ('in_progress'::character varying)::text, ('submitted'::character varying)::text, ('accepted'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: engagements_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements_feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    submission_id uuid,
    actor_id uuid NOT NULL,
    kind character varying DEFAULT 'comment'::character varying NOT NULL,
    content text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT work_feedback_kind CHECK (((kind)::text = ANY (ARRAY[('comment'::character varying)::text, ('changes_requested'::character varying)::text])))
);


--
-- Name: engagements_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements_submissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    version integer NOT NULL,
    content text NOT NULL,
    sha256 character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    title character varying DEFAULT ''::character varying NOT NULL,
    ready_for_acceptance boolean DEFAULT true NOT NULL,
    files_manifest jsonb DEFAULT '[]'::jsonb NOT NULL,
    manifest_sha256 character varying,
    manifest_format character varying DEFAULT 'canonical-json-v1'::character varying NOT NULL
);


--
-- Name: engagements_work_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements_work_files (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    creator_id uuid NOT NULL,
    submission_id uuid,
    sha256 character varying NOT NULL,
    state character varying DEFAULT 'quarantined'::character varying NOT NULL,
    scan_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scan_token uuid,
    scan_lease_until timestamp(6) without time zone,
    scan_retry_at timestamp(6) without time zone,
    scan_attempts integer DEFAULT 0 NOT NULL,
    CONSTRAINT work_file_state CHECK (((state)::text = ANY (ARRAY[('quarantined'::character varying)::text, ('available'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: finance_ledger_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ledger_transaction_id uuid NOT NULL,
    account_key character varying NOT NULL,
    currency character varying NOT NULL,
    direction character varying NOT NULL,
    amount_minor bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_entry_valid CHECK (((amount_minor > 0) AND ((direction)::text = ANY (ARRAY[('debit'::character varying)::text, ('credit'::character varying)::text]))))
);


--
-- Name: finance_ledger_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_ledger_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    operation_key character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    description text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_transaction_status CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('posted'::character varying)::text])))
);


--
-- Name: finance_payment_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_payment_operations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    settlement_id uuid NOT NULL,
    kind character varying NOT NULL,
    state character varying DEFAULT 'requested'::character varying NOT NULL,
    amount_minor bigint NOT NULL,
    currency character varying NOT NULL,
    scenario character varying DEFAULT 'normal'::character varying NOT NULL,
    external_id character varying,
    last_error text,
    attempts integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp(6) without time zone,
    lease_until timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    reconciled_at timestamp(6) without time zone,
    CONSTRAINT payment_money_valid CHECK (((amount_minor > 0) AND ((currency)::text = ANY (ARRAY[('RUB'::character varying)::text, ('USD'::character varying)::text, ('EUR'::character varying)::text, ('JPY'::character varying)::text])))),
    CONSTRAINT payment_operation_state CHECK ((((kind)::text = ANY (ARRAY[('fund'::character varying)::text, ('payout'::character varying)::text])) AND ((state)::text = ANY (ARRAY[('requested'::character varying)::text, ('dispatching'::character varying)::text, ('unknown'::character varying)::text, ('confirmed'::character varying)::text, ('failed'::character varying)::text])))),
    CONSTRAINT payment_sandbox_scenario CHECK (((scenario)::text = ANY (ARRAY[('normal'::character varying)::text, ('timeout_after_success'::character varying)::text, ('decline'::character varying)::text])))
);


--
-- Name: finance_reconciliation_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_reconciliation_exceptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_operation_id uuid NOT NULL,
    code character varying NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: finance_settlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_settlements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    currency character varying NOT NULL,
    funded boolean DEFAULT false NOT NULL,
    hold boolean DEFAULT false NOT NULL,
    hold_reason text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT settlement_amount_positive CHECK ((amount_minor > 0))
);


--
-- Name: finance_webhook_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_webhook_receipts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_event_id character varying NOT NULL,
    payload jsonb NOT NULL,
    processed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    next_enqueue_at timestamp(6) without time zone
);


--
-- Name: identity_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    display_name character varying NOT NULL,
    password_digest character varying NOT NULL,
    persona character varying DEFAULT 'client'::character varying NOT NULL,
    operator boolean DEFAULT false NOT NULL,
    session_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT account_persona CHECK (((persona)::text = ANY (ARRAY[('client'::character varying)::text, ('creator'::character varying)::text]))),
    CONSTRAINT normalized_email CHECK (((email)::text = lower((email)::text)))
);


--
-- Name: marketplace_awards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplace_awards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    proposal_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: marketplace_brief_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplace_brief_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    version integer NOT NULL,
    terms jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: marketplace_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplace_projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    title character varying NOT NULL,
    category character varying NOT NULL,
    description text NOT NULL,
    budget_minor bigint NOT NULL,
    currency character varying DEFAULT 'RUB'::character varying NOT NULL,
    deadline date NOT NULL,
    state character varying DEFAULT 'open'::character varying NOT NULL,
    brief_version integer DEFAULT 1 NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    expected_result text DEFAULT ''::text NOT NULL,
    deliverables text[] DEFAULT '{}'::text[] NOT NULL,
    requirements text[] DEFAULT '{}'::text[] NOT NULL,
    skills text[] DEFAULT '{}'::text[] NOT NULL,
    reference_urls text[] DEFAULT '{}'::text[] NOT NULL,
    accepting_proposals boolean DEFAULT true NOT NULL,
    CONSTRAINT project_budget_positive CHECK (((budget_minor > 0) AND (budget_minor <= '100000000000'::bigint))),
    CONSTRAINT project_state CHECK (((state)::text = ANY (ARRAY[('open'::character varying)::text, ('awarded'::character varying)::text, ('closed'::character varying)::text])))
);


--
-- Name: marketplace_proposal_examples; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplace_proposal_examples (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    creator_id uuid NOT NULL,
    proposal_id uuid,
    state character varying DEFAULT 'quarantined'::character varying NOT NULL,
    sha256 character varying NOT NULL,
    scan_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scan_token uuid,
    scan_lease_until timestamp(6) without time zone,
    scan_retry_at timestamp(6) without time zone,
    scan_attempts integer DEFAULT 0 NOT NULL,
    CONSTRAINT proposal_example_state CHECK (((state)::text = ANY (ARRAY[('quarantined'::character varying)::text, ('available'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: marketplace_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplace_proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    creator_id uuid NOT NULL,
    brief_version integer NOT NULL,
    delivery_days integer NOT NULL,
    price_minor bigint NOT NULL,
    message text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT proposal_terms_valid CHECK (((price_minor > 0) AND (price_minor <= '100000000000'::bigint) AND ((delivery_days >= 1) AND (delivery_days <= 365))))
);


--
-- Name: notifications_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    outbox_event_id uuid NOT NULL,
    title character varying NOT NULL,
    body character varying NOT NULL,
    resource_path character varying NOT NULL,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: platform_audit_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_audit_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    action character varying NOT NULL,
    resource_type character varying NOT NULL,
    correlation_id character varying NOT NULL,
    resource_id uuid NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: platform_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    outbox_event_id uuid NOT NULL,
    consumer character varying NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    processed_at timestamp(6) without time zone,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    available_at timestamp(6) without time zone,
    claim_token uuid,
    CONSTRAINT delivery_state_valid CHECK (((state)::text = ANY (ARRAY[('pending'::character varying)::text, ('enqueued'::character varying)::text, ('processed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: platform_idempotency_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_idempotency_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid NOT NULL,
    operation character varying NOT NULL,
    key character varying NOT NULL,
    fingerprint character varying NOT NULL,
    response jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: platform_metric_totals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_metric_totals (
    name character varying NOT NULL,
    observations bigint DEFAULT 0 NOT NULL,
    total_seconds double precision DEFAULT 0.0 NOT NULL,
    buckets jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT platform_metric_nonnegative CHECK (((observations >= 0) AND (total_seconds >= (0)::double precision)))
);


--
-- Name: platform_outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_outbox_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_type character varying NOT NULL,
    aggregate_type character varying NOT NULL,
    correlation_id character varying NOT NULL,
    schema_version integer DEFAULT 1 NOT NULL,
    aggregate_id uuid NOT NULL,
    aggregate_version integer NOT NULL,
    payload jsonb NOT NULL,
    trace_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: platform_rate_limit_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_rate_limit_buckets (
    key_digest character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT rate_limit_attempts_valid CHECK ((attempts >= 0))
);


--
-- Name: publishing_callback_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_callback_receipts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    partner_id uuid NOT NULL,
    event_id uuid NOT NULL,
    deployment_id uuid NOT NULL,
    body_sha256 character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: publishing_candidates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_candidates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    partner_id uuid NOT NULL,
    artifact_blob_id bigint NOT NULL,
    artifact_sha256 character varying NOT NULL,
    manifest_sha256 character varying NOT NULL,
    manifest jsonb NOT NULL,
    correlation_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT publishing_candidate_digests CHECK ((((artifact_sha256)::text ~ '^[a-f0-9]{64}$'::text) AND ((manifest_sha256)::text ~ '^[a-f0-9]{64}$'::text)))
);


--
-- Name: publishing_deployments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_deployments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    partner_id uuid NOT NULL,
    candidate_id uuid NOT NULL,
    validation_id uuid NOT NULL,
    rollback_of_id uuid,
    kind character varying DEFAULT 'publish'::character varying NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    scenario character varying DEFAULT 'normal'::character varying NOT NULL,
    correlation_id character varying NOT NULL,
    claim_token uuid,
    lease_until timestamp(6) without time zone,
    next_enqueue_at timestamp(6) without time zone,
    attempts integer DEFAULT 0 NOT NULL,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    last_error character varying,
    remote_id character varying,
    remote_sequence bigint,
    confirmed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT publishing_confirmed_identity CHECK ((((state)::text <> 'confirmed'::text) OR ((remote_id IS NOT NULL) AND ((remote_id)::text <> ''::text) AND (remote_sequence IS NOT NULL) AND (remote_sequence > 0) AND (confirmed_at IS NOT NULL)))),
    CONSTRAINT publishing_deployment_state CHECK ((((state)::text = ANY ((ARRAY['pending'::character varying, 'dispatching'::character varying, 'unknown'::character varying, 'confirmed'::character varying, 'failed'::character varying])::text[])) AND ((kind)::text = ANY ((ARRAY['publish'::character varying, 'rollback'::character varying])::text[])) AND (attempts >= 0) AND (consecutive_failures >= 0))),
    CONSTRAINT publishing_rollback_basis CHECK ((((kind)::text = 'rollback'::text) = (rollback_of_id IS NOT NULL)))
);


--
-- Name: publishing_partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_partners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    name character varying NOT NULL,
    origin character varying NOT NULL,
    credential_ref character varying NOT NULL,
    contract_version character varying DEFAULT '1'::character varying NOT NULL,
    active_deployment_id uuid,
    active_sequence bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT publishing_active_presence CHECK ((((active_deployment_id IS NULL) AND (active_sequence = 0)) OR ((active_deployment_id IS NOT NULL) AND (active_sequence > 0)))),
    CONSTRAINT publishing_partner_sequence CHECK ((active_sequence >= 0))
);


--
-- Name: publishing_upload_intents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_upload_intents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    partner_id uuid NOT NULL,
    request_key character varying(200) NOT NULL,
    fingerprint character varying NOT NULL,
    artifact_blob_id bigint,
    state character varying DEFAULT 'reserved'::character varying NOT NULL,
    claim_token uuid,
    lease_until timestamp(6) without time zone,
    response jsonb,
    last_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT publishing_upload_completion CHECK (((((state)::text <> 'uploading'::text) OR ((claim_token IS NOT NULL) AND (lease_until IS NOT NULL) AND (artifact_blob_id IS NOT NULL))) AND (((state)::text <> 'finalized'::text) OR (response IS NOT NULL)))),
    CONSTRAINT publishing_upload_state CHECK ((((state)::text = ANY ((ARRAY['reserved'::character varying, 'uploading'::character varying, 'ready'::character varying, 'finalized'::character varying, 'discarded'::character varying])::text[])) AND ((fingerprint)::text ~ '^[a-f0-9]{64}$'::text)))
);


--
-- Name: publishing_validations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publishing_validations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    candidate_id uuid NOT NULL,
    policy_version character varying NOT NULL,
    input_fingerprint character varying NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    claim_token uuid,
    lease_until timestamp(6) without time zone,
    next_enqueue_at timestamp(6) without time zone,
    attempts integer DEFAULT 0 NOT NULL,
    report jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_error character varying,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT publishing_completed_validation CHECK ((((state)::text <> ALL ((ARRAY['passed'::character varying, 'rejected'::character varying])::text[])) OR ((completed_at IS NOT NULL) AND (report ? 'checks'::text)))),
    CONSTRAINT publishing_validation_state CHECK ((((state)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'passed'::character varying, 'rejected'::character varying, 'failed'::character varying])::text[])) AND (attempts >= 0)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: solid_cable_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cable_messages (
    id bigint NOT NULL,
    channel bytea NOT NULL,
    payload bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    channel_hash bigint NOT NULL
);


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cable_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cable_messages_id_seq OWNED BY public.solid_cable_messages.id;


--
-- Name: talent_portfolio_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.talent_portfolio_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    title character varying NOT NULL,
    state character varying DEFAULT 'quarantined'::character varying NOT NULL,
    sha256 character varying,
    scan_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scan_token uuid,
    scan_lease_until timestamp(6) without time zone,
    scan_retry_at timestamp(6) without time zone,
    scan_attempts integer DEFAULT 0 NOT NULL
);


--
-- Name: talent_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.talent_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    headline character varying NOT NULL,
    bio text DEFAULT ''::text NOT NULL,
    skills text[] DEFAULT '{}'::text[] NOT NULL,
    rate_minor integer DEFAULT 0 NOT NULL,
    currency character varying DEFAULT 'RUB'::character varying NOT NULL,
    accent character varying DEFAULT 'violet'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT profile_rate_nonnegative CHECK ((rate_minor >= 0))
);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: solid_cable_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages ALTER COLUMN id SET DEFAULT nextval('public.solid_cable_messages_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: engagements_acceptances engagements_acceptances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_acceptances
    ADD CONSTRAINT engagements_acceptances_pkey PRIMARY KEY (id);


--
-- Name: engagements_engagements engagements_engagements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_engagements
    ADD CONSTRAINT engagements_engagements_pkey PRIMARY KEY (id);


--
-- Name: engagements_feedback engagements_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_feedback
    ADD CONSTRAINT engagements_feedback_pkey PRIMARY KEY (id);


--
-- Name: engagements_submissions engagements_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_submissions
    ADD CONSTRAINT engagements_submissions_pkey PRIMARY KEY (id);


--
-- Name: engagements_work_files engagements_work_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_work_files
    ADD CONSTRAINT engagements_work_files_pkey PRIMARY KEY (id);


--
-- Name: finance_ledger_entries finance_ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_ledger_entries
    ADD CONSTRAINT finance_ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: finance_ledger_transactions finance_ledger_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_ledger_transactions
    ADD CONSTRAINT finance_ledger_transactions_pkey PRIMARY KEY (id);


--
-- Name: finance_payment_operations finance_payment_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_payment_operations
    ADD CONSTRAINT finance_payment_operations_pkey PRIMARY KEY (id);


--
-- Name: finance_reconciliation_exceptions finance_reconciliation_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_reconciliation_exceptions
    ADD CONSTRAINT finance_reconciliation_exceptions_pkey PRIMARY KEY (id);


--
-- Name: finance_settlements finance_settlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_settlements
    ADD CONSTRAINT finance_settlements_pkey PRIMARY KEY (id);


--
-- Name: finance_webhook_receipts finance_webhook_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_webhook_receipts
    ADD CONSTRAINT finance_webhook_receipts_pkey PRIMARY KEY (id);


--
-- Name: identity_accounts identity_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_accounts
    ADD CONSTRAINT identity_accounts_pkey PRIMARY KEY (id);


--
-- Name: marketplace_awards marketplace_awards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_awards
    ADD CONSTRAINT marketplace_awards_pkey PRIMARY KEY (id);


--
-- Name: marketplace_brief_versions marketplace_brief_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_brief_versions
    ADD CONSTRAINT marketplace_brief_versions_pkey PRIMARY KEY (id);


--
-- Name: marketplace_projects marketplace_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_projects
    ADD CONSTRAINT marketplace_projects_pkey PRIMARY KEY (id);


--
-- Name: marketplace_proposal_examples marketplace_proposal_examples_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposal_examples
    ADD CONSTRAINT marketplace_proposal_examples_pkey PRIMARY KEY (id);


--
-- Name: marketplace_proposals marketplace_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposals
    ADD CONSTRAINT marketplace_proposals_pkey PRIMARY KEY (id);


--
-- Name: notifications_notifications notifications_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications_notifications
    ADD CONSTRAINT notifications_notifications_pkey PRIMARY KEY (id);


--
-- Name: platform_audit_entries platform_audit_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_audit_entries
    ADD CONSTRAINT platform_audit_entries_pkey PRIMARY KEY (id);


--
-- Name: platform_deliveries platform_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_deliveries
    ADD CONSTRAINT platform_deliveries_pkey PRIMARY KEY (id);


--
-- Name: platform_idempotency_records platform_idempotency_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_idempotency_records
    ADD CONSTRAINT platform_idempotency_records_pkey PRIMARY KEY (id);


--
-- Name: platform_metric_totals platform_metric_totals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_metric_totals
    ADD CONSTRAINT platform_metric_totals_pkey PRIMARY KEY (name);


--
-- Name: platform_outbox_events platform_outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_outbox_events
    ADD CONSTRAINT platform_outbox_events_pkey PRIMARY KEY (id);


--
-- Name: platform_rate_limit_buckets platform_rate_limit_buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_rate_limit_buckets
    ADD CONSTRAINT platform_rate_limit_buckets_pkey PRIMARY KEY (key_digest);


--
-- Name: publishing_callback_receipts publishing_callback_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_callback_receipts
    ADD CONSTRAINT publishing_callback_receipts_pkey PRIMARY KEY (id);


--
-- Name: publishing_candidates publishing_candidates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_candidates
    ADD CONSTRAINT publishing_candidates_pkey PRIMARY KEY (id);


--
-- Name: publishing_deployments publishing_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT publishing_deployments_pkey PRIMARY KEY (id);


--
-- Name: publishing_partners publishing_partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_partners
    ADD CONSTRAINT publishing_partners_pkey PRIMARY KEY (id);


--
-- Name: publishing_upload_intents publishing_upload_intents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_upload_intents
    ADD CONSTRAINT publishing_upload_intents_pkey PRIMARY KEY (id);


--
-- Name: publishing_validations publishing_validations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_validations
    ADD CONSTRAINT publishing_validations_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: solid_cable_messages solid_cable_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages
    ADD CONSTRAINT solid_cable_messages_pkey PRIMARY KEY (id);


--
-- Name: talent_portfolio_items talent_portfolio_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talent_portfolio_items
    ADD CONSTRAINT talent_portfolio_items_pkey PRIMARY KEY (id);


--
-- Name: talent_profiles talent_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talent_profiles
    ADD CONSTRAINT talent_profiles_pkey PRIMARY KEY (id);


--
-- Name: engagements_work_files_scan_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX engagements_work_files_scan_due ON public.engagements_work_files USING btree (scan_retry_at, scan_lease_until) WHERE ((state)::text = 'quarantined'::text);


--
-- Name: feedback_recent_page; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX feedback_recent_page ON public.engagements_feedback USING btree (engagement_id, created_at DESC, id DESC);


--
-- Name: idempotency_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idempotency_scope ON public.platform_idempotency_records USING btree (actor_id, operation, key);


--
-- Name: identity_accounts_unique_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX identity_accounts_unique_email ON public.identity_accounts USING btree (lower((email)::text));


--
-- Name: idx_on_partner_id_created_at_id_36f00de1e8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_partner_id_created_at_id_36f00de1e8 ON public.publishing_candidates USING btree (partner_id, created_at, id);


--
-- Name: idx_on_partner_id_created_at_id_f067fb2aef; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_partner_id_created_at_id_f067fb2aef ON public.publishing_deployments USING btree (partner_id, created_at, id);


--
-- Name: idx_on_payment_operation_id_9cd0fe9f27; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_payment_operation_id_9cd0fe9f27 ON public.finance_reconciliation_exceptions USING btree (payment_operation_id);


--
-- Name: idx_on_processed_at_next_enqueue_at_997a0a058e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_processed_at_next_enqueue_at_997a0a058e ON public.finance_webhook_receipts USING btree (processed_at, next_enqueue_at);


--
-- Name: idx_on_reconciled_at_created_at_96a32f2a97; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_reconciled_at_created_at_96a32f2a97 ON public.finance_payment_operations USING btree (reconciled_at, created_at);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_engagements_acceptances_on_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_acceptances_on_engagement_id ON public.engagements_acceptances USING btree (engagement_id);


--
-- Name: index_engagements_acceptances_on_submission_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_acceptances_on_submission_id ON public.engagements_acceptances USING btree (submission_id);


--
-- Name: index_engagements_engagements_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_engagements_on_client_id ON public.engagements_engagements USING btree (client_id);


--
-- Name: index_engagements_engagements_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_engagements_on_creator_id ON public.engagements_engagements USING btree (creator_id);


--
-- Name: index_engagements_engagements_on_source_award_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_engagements_on_source_award_id ON public.engagements_engagements USING btree (source_award_id);


--
-- Name: index_engagements_feedback_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_feedback_on_actor_id ON public.engagements_feedback USING btree (actor_id);


--
-- Name: index_engagements_feedback_on_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_feedback_on_engagement_id ON public.engagements_feedback USING btree (engagement_id);


--
-- Name: index_engagements_feedback_on_submission_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_feedback_on_submission_id ON public.engagements_feedback USING btree (submission_id);


--
-- Name: index_engagements_submissions_on_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_submissions_on_engagement_id ON public.engagements_submissions USING btree (engagement_id);


--
-- Name: index_engagements_submissions_on_engagement_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_submissions_on_engagement_id_and_version ON public.engagements_submissions USING btree (engagement_id, version);


--
-- Name: index_engagements_submissions_on_id_and_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_submissions_on_id_and_engagement_id ON public.engagements_submissions USING btree (id, engagement_id);


--
-- Name: index_engagements_work_files_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_work_files_on_creator_id ON public.engagements_work_files USING btree (creator_id);


--
-- Name: index_engagements_work_files_on_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_work_files_on_engagement_id ON public.engagements_work_files USING btree (engagement_id);


--
-- Name: index_engagements_work_files_on_submission_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_work_files_on_submission_id ON public.engagements_work_files USING btree (submission_id);


--
-- Name: index_finance_ledger_entries_on_account_key_and_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_ledger_entries_on_account_key_and_currency ON public.finance_ledger_entries USING btree (account_key, currency);


--
-- Name: index_finance_ledger_entries_on_ledger_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_ledger_entries_on_ledger_transaction_id ON public.finance_ledger_entries USING btree (ledger_transaction_id);


--
-- Name: index_finance_ledger_transactions_on_operation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_ledger_transactions_on_operation_key ON public.finance_ledger_transactions USING btree (operation_key);


--
-- Name: index_finance_payment_operations_on_settlement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_payment_operations_on_settlement_id ON public.finance_payment_operations USING btree (settlement_id);


--
-- Name: index_finance_payment_operations_on_settlement_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_payment_operations_on_settlement_id_and_kind ON public.finance_payment_operations USING btree (settlement_id, kind);


--
-- Name: index_finance_payment_operations_on_state_and_next_retry_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_payment_operations_on_state_and_next_retry_at ON public.finance_payment_operations USING btree (state, next_retry_at);


--
-- Name: index_finance_settlements_on_engagement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_settlements_on_engagement_id ON public.finance_settlements USING btree (engagement_id);


--
-- Name: index_finance_webhook_receipts_on_provider_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_webhook_receipts_on_provider_event_id ON public.finance_webhook_receipts USING btree (provider_event_id);


--
-- Name: index_marketplace_awards_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketplace_awards_on_project_id ON public.marketplace_awards USING btree (project_id);


--
-- Name: index_marketplace_awards_on_proposal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketplace_awards_on_proposal_id ON public.marketplace_awards USING btree (proposal_id);


--
-- Name: index_marketplace_brief_versions_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_brief_versions_on_project_id ON public.marketplace_brief_versions USING btree (project_id);


--
-- Name: index_marketplace_brief_versions_on_project_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketplace_brief_versions_on_project_id_and_version ON public.marketplace_brief_versions USING btree (project_id, version);


--
-- Name: index_marketplace_projects_on_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_projects_on_category ON public.marketplace_projects USING btree (category);


--
-- Name: index_marketplace_projects_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_projects_on_client_id ON public.marketplace_projects USING btree (client_id);


--
-- Name: index_marketplace_proposal_examples_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_proposal_examples_on_creator_id ON public.marketplace_proposal_examples USING btree (creator_id);


--
-- Name: index_marketplace_proposal_examples_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_proposal_examples_on_project_id ON public.marketplace_proposal_examples USING btree (project_id);


--
-- Name: index_marketplace_proposal_examples_on_proposal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketplace_proposal_examples_on_proposal_id ON public.marketplace_proposal_examples USING btree (proposal_id);


--
-- Name: index_marketplace_proposals_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_proposals_on_creator_id ON public.marketplace_proposals USING btree (creator_id);


--
-- Name: index_marketplace_proposals_on_id_and_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketplace_proposals_on_id_and_project_id ON public.marketplace_proposals USING btree (id, project_id);


--
-- Name: index_marketplace_proposals_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketplace_proposals_on_project_id ON public.marketplace_proposals USING btree (project_id);


--
-- Name: index_notifications_notifications_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_notifications_on_account_id ON public.notifications_notifications USING btree (account_id);


--
-- Name: index_notifications_notifications_on_outbox_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_notifications_on_outbox_event_id ON public.notifications_notifications USING btree (outbox_event_id);


--
-- Name: index_platform_deliveries_on_outbox_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_platform_deliveries_on_outbox_event_id ON public.platform_deliveries USING btree (outbox_event_id);


--
-- Name: index_platform_deliveries_on_outbox_event_id_and_consumer; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_platform_deliveries_on_outbox_event_id_and_consumer ON public.platform_deliveries USING btree (outbox_event_id, consumer);


--
-- Name: index_platform_deliveries_on_state_and_available_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_platform_deliveries_on_state_and_available_at ON public.platform_deliveries USING btree (state, available_at);


--
-- Name: index_platform_deliveries_on_state_and_enqueued_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_platform_deliveries_on_state_and_enqueued_at ON public.platform_deliveries USING btree (state, enqueued_at);


--
-- Name: index_platform_idempotency_records_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_platform_idempotency_records_on_actor_id ON public.platform_idempotency_records USING btree (actor_id);


--
-- Name: index_platform_rate_limit_buckets_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_platform_rate_limit_buckets_on_expires_at ON public.platform_rate_limit_buckets USING btree (expires_at);


--
-- Name: index_publishing_callback_receipts_on_partner_id_and_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_callback_receipts_on_partner_id_and_event_id ON public.publishing_callback_receipts USING btree (partner_id, event_id);


--
-- Name: index_publishing_candidates_on_id_and_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_candidates_on_id_and_partner_id ON public.publishing_candidates USING btree (id, partner_id);


--
-- Name: index_publishing_deployments_on_id_and_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_deployments_on_id_and_partner_id ON public.publishing_deployments USING btree (id, partner_id);


--
-- Name: index_publishing_deployments_on_state_and_next_enqueue_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_publishing_deployments_on_state_and_next_enqueue_at ON public.publishing_deployments USING btree (state, next_enqueue_at);


--
-- Name: index_publishing_partners_on_owner_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_partners_on_owner_id_and_name ON public.publishing_partners USING btree (owner_id, name);


--
-- Name: index_publishing_upload_intents_on_artifact_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_upload_intents_on_artifact_blob_id ON public.publishing_upload_intents USING btree (artifact_blob_id) WHERE (artifact_blob_id IS NOT NULL);


--
-- Name: index_publishing_upload_intents_on_partner_id_and_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_upload_intents_on_partner_id_and_request_key ON public.publishing_upload_intents USING btree (partner_id, request_key);


--
-- Name: index_publishing_upload_intents_on_state_and_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_publishing_upload_intents_on_state_and_updated_at ON public.publishing_upload_intents USING btree (state, updated_at);


--
-- Name: index_publishing_validations_on_id_and_candidate_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_publishing_validations_on_id_and_candidate_id ON public.publishing_validations USING btree (id, candidate_id);


--
-- Name: index_publishing_validations_on_state_and_next_enqueue_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_publishing_validations_on_state_and_next_enqueue_at ON public.publishing_validations USING btree (state, next_enqueue_at);


--
-- Name: index_solid_cable_messages_on_channel_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel_hash ON public.solid_cable_messages USING btree (channel_hash);


--
-- Name: index_solid_cable_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_created_at ON public.solid_cable_messages USING btree (created_at);


--
-- Name: index_talent_portfolio_items_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_talent_portfolio_items_on_account_id ON public.talent_portfolio_items USING btree (account_id);


--
-- Name: index_talent_profiles_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_talent_profiles_on_account_id ON public.talent_profiles USING btree (account_id);


--
-- Name: marketplace_proposal_examples_scan_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX marketplace_proposal_examples_scan_due ON public.marketplace_proposal_examples USING btree (scan_retry_at, scan_lease_until) WHERE ((state)::text = 'quarantined'::text);


--
-- Name: notification_effect_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_effect_unique ON public.notifications_notifications USING btree (account_id, outbox_event_id);


--
-- Name: one_changes_request_per_submission; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_changes_request_per_submission ON public.engagements_feedback USING btree (submission_id) WHERE ((kind)::text = 'changes_requested'::text);


--
-- Name: project_description_trigram; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_description_trigram ON public.marketplace_projects USING gin (description public.gin_trgm_ops);


--
-- Name: project_feed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_feed ON public.marketplace_projects USING btree (state, created_at, id);


--
-- Name: project_title_trigram; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_title_trigram ON public.marketplace_projects USING gin (title public.gin_trgm_ops);


--
-- Name: proposal_per_brief; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX proposal_per_brief ON public.marketplace_proposals USING btree (project_id, creator_id, brief_version);


--
-- Name: proposals_days_page; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proposals_days_page ON public.marketplace_proposals USING btree (project_id, delivery_days, created_at DESC, id DESC);


--
-- Name: proposals_price_page; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proposals_price_page ON public.marketplace_proposals USING btree (project_id, price_minor, created_at DESC, id DESC);


--
-- Name: proposals_recent_page; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proposals_recent_page ON public.marketplace_proposals USING btree (project_id, created_at DESC, id DESC);


--
-- Name: publishing_candidates_history_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publishing_candidates_history_order ON public.publishing_candidates USING btree (created_at, id);


--
-- Name: publishing_deployments_history_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publishing_deployments_history_order ON public.publishing_deployments USING btree (created_at, id);


--
-- Name: publishing_latest_validation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publishing_latest_validation ON public.publishing_validations USING btree (candidate_id, created_at DESC, id DESC);


--
-- Name: publishing_one_publish_per_candidate; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX publishing_one_publish_per_candidate ON public.publishing_deployments USING btree (candidate_id) WHERE ((kind)::text = 'publish'::text);


--
-- Name: publishing_partners_history_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publishing_partners_history_order ON public.publishing_partners USING btree (owner_id, created_at, id);


--
-- Name: publishing_remote_sequence_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX publishing_remote_sequence_unique ON public.publishing_deployments USING btree (partner_id, remote_sequence) WHERE (remote_sequence IS NOT NULL);


--
-- Name: publishing_validation_inputs; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX publishing_validation_inputs ON public.publishing_validations USING btree (candidate_id, input_fingerprint);


--
-- Name: talent_portfolio_items_scan_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX talent_portfolio_items_scan_due ON public.talent_portfolio_items USING btree (scan_retry_at, scan_lease_until) WHERE ((state)::text = 'quarantined'::text);


--
-- Name: unique_reconciliation_exception; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_reconciliation_exception ON public.finance_reconciliation_exceptions USING btree (payment_operation_id, code);


--
-- Name: engagements_acceptances acceptance_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER acceptance_immutable BEFORE DELETE OR UPDATE ON public.engagements_acceptances FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_history();


--
-- Name: engagements_engagements agreement_terms_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agreement_terms_immutable BEFORE UPDATE ON public.engagements_engagements FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_agreement_terms();


--
-- Name: platform_audit_entries audit_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_immutable BEFORE DELETE OR UPDATE ON public.platform_audit_entries FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_history();


--
-- Name: marketplace_brief_versions brief_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER brief_immutable BEFORE DELETE OR UPDATE ON public.marketplace_brief_versions FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_history();


--
-- Name: engagements_feedback feedback_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER feedback_immutable BEFORE DELETE OR UPDATE ON public.engagements_feedback FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_history();


--
-- Name: finance_ledger_entries ledger_entries_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_entries_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.finance_ledger_entries FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_posted_ledger();


--
-- Name: finance_ledger_entries ledger_entry_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_entry_balance AFTER INSERT OR DELETE OR UPDATE ON public.finance_ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.mesh_check_ledger_balance();


--
-- Name: finance_ledger_transactions ledger_header_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_header_balance AFTER INSERT OR UPDATE ON public.finance_ledger_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.mesh_check_ledger_balance();


--
-- Name: finance_ledger_transactions ledger_header_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_header_immutable BEFORE DELETE OR UPDATE ON public.finance_ledger_transactions FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_posted_ledger();


--
-- Name: publishing_partners publishing_active_binding; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_active_binding BEFORE INSERT OR UPDATE ON public.publishing_partners FOR EACH ROW EXECUTE FUNCTION public.enforce_publishing_active_binding();


--
-- Name: publishing_candidates publishing_candidate_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_candidate_immutable BEFORE DELETE OR UPDATE ON public.publishing_candidates FOR EACH ROW EXECUTE FUNCTION public.protect_publishing_history();


--
-- Name: publishing_deployments publishing_deployment_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_deployment_immutable BEFORE DELETE OR UPDATE ON public.publishing_deployments FOR EACH ROW EXECUTE FUNCTION public.protect_publishing_history();


--
-- Name: publishing_partners publishing_partner_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_partner_immutable BEFORE DELETE OR UPDATE ON public.publishing_partners FOR EACH ROW EXECUTE FUNCTION public.protect_publishing_history();


--
-- Name: publishing_callback_receipts publishing_receipt_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_receipt_immutable BEFORE DELETE OR UPDATE ON public.publishing_callback_receipts FOR EACH ROW EXECUTE FUNCTION public.protect_publishing_history();


--
-- Name: active_storage_attachments publishing_reclaimed_attachment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_reclaimed_attachment BEFORE INSERT OR UPDATE ON public.active_storage_attachments FOR EACH ROW EXECUTE FUNCTION public.guard_reclaimed_publishing_attachment();


--
-- Name: publishing_candidates publishing_reclaimed_candidate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_reclaimed_candidate BEFORE INSERT OR UPDATE ON public.publishing_candidates FOR EACH ROW EXECUTE FUNCTION public.guard_reclaimed_publishing_candidate();


--
-- Name: publishing_deployments publishing_release_basis; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_release_basis BEFORE INSERT ON public.publishing_deployments FOR EACH ROW EXECUTE FUNCTION public.validate_publishing_release_basis();


--
-- Name: publishing_deployments publishing_rollback_basis; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_rollback_basis BEFORE INSERT ON public.publishing_deployments FOR EACH ROW EXECUTE FUNCTION public.enforce_publishing_rollback_basis();


--
-- Name: publishing_validations publishing_validation_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publishing_validation_immutable BEFORE DELETE OR UPDATE ON public.publishing_validations FOR EACH ROW EXECUTE FUNCTION public.protect_publishing_history();


--
-- Name: engagements_submissions submission_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER submission_immutable BEFORE DELETE OR UPDATE ON public.engagements_submissions FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_history();


--
-- Name: engagements_work_files work_file_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER work_file_immutable BEFORE DELETE OR UPDATE ON public.engagements_work_files FOR EACH ROW EXECUTE FUNCTION public.mesh_protect_work_file();


--
-- Name: engagements_acceptances acceptance_matches_engagement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_acceptances
    ADD CONSTRAINT acceptance_matches_engagement FOREIGN KEY (submission_id, engagement_id) REFERENCES public.engagements_submissions(id, engagement_id);


--
-- Name: marketplace_awards award_proposal_matches_project; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_awards
    ADD CONSTRAINT award_proposal_matches_project FOREIGN KEY (proposal_id, project_id) REFERENCES public.marketplace_proposals(id, project_id);


--
-- Name: engagements_feedback feedback_matches_engagement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_feedback
    ADD CONSTRAINT feedback_matches_engagement FOREIGN KEY (submission_id, engagement_id) REFERENCES public.engagements_submissions(id, engagement_id);


--
-- Name: engagements_work_files fk_rails_03531a6dd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_work_files
    ADD CONSTRAINT fk_rails_03531a6dd2 FOREIGN KEY (submission_id) REFERENCES public.engagements_submissions(id);


--
-- Name: marketplace_proposal_examples fk_rails_0a93aa30ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposal_examples
    ADD CONSTRAINT fk_rails_0a93aa30ea FOREIGN KEY (proposal_id) REFERENCES public.marketplace_proposals(id);


--
-- Name: finance_ledger_entries fk_rails_189d792fef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_ledger_entries
    ADD CONSTRAINT fk_rails_189d792fef FOREIGN KEY (ledger_transaction_id) REFERENCES public.finance_ledger_transactions(id);


--
-- Name: publishing_callback_receipts fk_rails_281ea990e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_callback_receipts
    ADD CONSTRAINT fk_rails_281ea990e0 FOREIGN KEY (partner_id) REFERENCES public.publishing_partners(id);


--
-- Name: notifications_notifications fk_rails_2d896865ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications_notifications
    ADD CONSTRAINT fk_rails_2d896865ce FOREIGN KEY (account_id) REFERENCES public.identity_accounts(id);


--
-- Name: publishing_deployments fk_rails_31b6fc6fbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_31b6fc6fbf FOREIGN KEY (candidate_id, partner_id) REFERENCES public.publishing_candidates(id, partner_id);


--
-- Name: talent_profiles fk_rails_39ec124ee3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talent_profiles
    ADD CONSTRAINT fk_rails_39ec124ee3 FOREIGN KEY (account_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_work_files fk_rails_3b84640d77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_work_files
    ADD CONSTRAINT fk_rails_3b84640d77 FOREIGN KEY (creator_id) REFERENCES public.identity_accounts(id);


--
-- Name: publishing_validations fk_rails_3d1847deb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_validations
    ADD CONSTRAINT fk_rails_3d1847deb6 FOREIGN KEY (candidate_id) REFERENCES public.publishing_candidates(id);


--
-- Name: publishing_partners fk_rails_505f1e3d35; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_partners
    ADD CONSTRAINT fk_rails_505f1e3d35 FOREIGN KEY (owner_id) REFERENCES public.identity_accounts(id);


--
-- Name: platform_deliveries fk_rails_5166ec5b6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_deliveries
    ADD CONSTRAINT fk_rails_5166ec5b6d FOREIGN KEY (outbox_event_id) REFERENCES public.platform_outbox_events(id);


--
-- Name: engagements_feedback fk_rails_52d0a062c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_feedback
    ADD CONSTRAINT fk_rails_52d0a062c4 FOREIGN KEY (actor_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_feedback fk_rails_576bbd9365; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_feedback
    ADD CONSTRAINT fk_rails_576bbd9365 FOREIGN KEY (engagement_id) REFERENCES public.engagements_engagements(id);


--
-- Name: notifications_notifications fk_rails_587156ea24; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications_notifications
    ADD CONSTRAINT fk_rails_587156ea24 FOREIGN KEY (outbox_event_id) REFERENCES public.platform_outbox_events(id);


--
-- Name: marketplace_proposals fk_rails_5b710645ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposals
    ADD CONSTRAINT fk_rails_5b710645ca FOREIGN KEY (project_id) REFERENCES public.marketplace_projects(id);


--
-- Name: marketplace_brief_versions fk_rails_5cfb34dd1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_brief_versions
    ADD CONSTRAINT fk_rails_5cfb34dd1d FOREIGN KEY (project_id) REFERENCES public.marketplace_projects(id);


--
-- Name: engagements_acceptances fk_rails_6e9f13caac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_acceptances
    ADD CONSTRAINT fk_rails_6e9f13caac FOREIGN KEY (submission_id) REFERENCES public.engagements_submissions(id);


--
-- Name: engagements_feedback fk_rails_71672876de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_feedback
    ADD CONSTRAINT fk_rails_71672876de FOREIGN KEY (submission_id) REFERENCES public.engagements_submissions(id);


--
-- Name: publishing_candidates fk_rails_73588ebbea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_candidates
    ADD CONSTRAINT fk_rails_73588ebbea FOREIGN KEY (artifact_blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: publishing_deployments fk_rails_746c20ee62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_746c20ee62 FOREIGN KEY (validation_id, candidate_id) REFERENCES public.publishing_validations(id, candidate_id);


--
-- Name: marketplace_awards fk_rails_78a89937e9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_awards
    ADD CONSTRAINT fk_rails_78a89937e9 FOREIGN KEY (proposal_id) REFERENCES public.marketplace_proposals(id);


--
-- Name: publishing_deployments fk_rails_7d35e99453; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_7d35e99453 FOREIGN KEY (validation_id) REFERENCES public.publishing_validations(id);


--
-- Name: publishing_upload_intents fk_rails_859d573a1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_upload_intents
    ADD CONSTRAINT fk_rails_859d573a1b FOREIGN KEY (partner_id) REFERENCES public.publishing_partners(id);


--
-- Name: engagements_engagements fk_rails_8c8df55412; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_engagements
    ADD CONSTRAINT fk_rails_8c8df55412 FOREIGN KEY (source_award_id) REFERENCES public.marketplace_awards(id);


--
-- Name: publishing_callback_receipts fk_rails_8d5a154fb4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_callback_receipts
    ADD CONSTRAINT fk_rails_8d5a154fb4 FOREIGN KEY (deployment_id, partner_id) REFERENCES public.publishing_deployments(id, partner_id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: publishing_callback_receipts fk_rails_9edfe352c2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_callback_receipts
    ADD CONSTRAINT fk_rails_9edfe352c2 FOREIGN KEY (deployment_id) REFERENCES public.publishing_deployments(id);


--
-- Name: engagements_engagements fk_rails_9f59f1a6b6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_engagements
    ADD CONSTRAINT fk_rails_9f59f1a6b6 FOREIGN KEY (client_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_work_files fk_rails_a4fd6fbd4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_work_files
    ADD CONSTRAINT fk_rails_a4fd6fbd4a FOREIGN KEY (engagement_id) REFERENCES public.engagements_engagements(id);


--
-- Name: publishing_candidates fk_rails_a53b57d4cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_candidates
    ADD CONSTRAINT fk_rails_a53b57d4cb FOREIGN KEY (partner_id) REFERENCES public.publishing_partners(id);


--
-- Name: publishing_deployments fk_rails_a6f96b2209; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_a6f96b2209 FOREIGN KEY (rollback_of_id) REFERENCES public.publishing_deployments(id);


--
-- Name: publishing_deployments fk_rails_ae97ea1b73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_ae97ea1b73 FOREIGN KEY (candidate_id) REFERENCES public.publishing_candidates(id);


--
-- Name: publishing_upload_intents fk_rails_b78ac958e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_upload_intents
    ADD CONSTRAINT fk_rails_b78ac958e4 FOREIGN KEY (artifact_blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: finance_settlements fk_rails_bbe8545def; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_settlements
    ADD CONSTRAINT fk_rails_bbe8545def FOREIGN KEY (engagement_id) REFERENCES public.engagements_engagements(id);


--
-- Name: publishing_deployments fk_rails_bea744deea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_deployments
    ADD CONSTRAINT fk_rails_bea744deea FOREIGN KEY (partner_id) REFERENCES public.publishing_partners(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: talent_portfolio_items fk_rails_c3f2fb59e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.talent_portfolio_items
    ADD CONSTRAINT fk_rails_c3f2fb59e4 FOREIGN KEY (account_id) REFERENCES public.identity_accounts(id);


--
-- Name: marketplace_proposal_examples fk_rails_c47de63fa7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposal_examples
    ADD CONSTRAINT fk_rails_c47de63fa7 FOREIGN KEY (project_id) REFERENCES public.marketplace_projects(id);


--
-- Name: finance_reconciliation_exceptions fk_rails_cb4a3ce872; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_reconciliation_exceptions
    ADD CONSTRAINT fk_rails_cb4a3ce872 FOREIGN KEY (payment_operation_id) REFERENCES public.finance_payment_operations(id);


--
-- Name: marketplace_awards fk_rails_cb832ec80c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_awards
    ADD CONSTRAINT fk_rails_cb832ec80c FOREIGN KEY (project_id) REFERENCES public.marketplace_projects(id);


--
-- Name: finance_payment_operations fk_rails_cdafd32bbe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_payment_operations
    ADD CONSTRAINT fk_rails_cdafd32bbe FOREIGN KEY (settlement_id) REFERENCES public.finance_settlements(id);


--
-- Name: marketplace_proposals fk_rails_cf7f1d1cc5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposals
    ADD CONSTRAINT fk_rails_cf7f1d1cc5 FOREIGN KEY (creator_id) REFERENCES public.identity_accounts(id);


--
-- Name: publishing_partners fk_rails_de280e19c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publishing_partners
    ADD CONSTRAINT fk_rails_de280e19c4 FOREIGN KEY (active_deployment_id) REFERENCES public.publishing_deployments(id);


--
-- Name: marketplace_proposal_examples fk_rails_e0c3e90db0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_proposal_examples
    ADD CONSTRAINT fk_rails_e0c3e90db0 FOREIGN KEY (creator_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_submissions fk_rails_e2b6628a26; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_submissions
    ADD CONSTRAINT fk_rails_e2b6628a26 FOREIGN KEY (engagement_id) REFERENCES public.engagements_engagements(id);


--
-- Name: platform_idempotency_records fk_rails_e3145bf816; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_idempotency_records
    ADD CONSTRAINT fk_rails_e3145bf816 FOREIGN KEY (actor_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_acceptances fk_rails_f414dadd0f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_acceptances
    ADD CONSTRAINT fk_rails_f414dadd0f FOREIGN KEY (engagement_id) REFERENCES public.engagements_engagements(id);


--
-- Name: marketplace_projects fk_rails_f59e5f12f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_projects
    ADD CONSTRAINT fk_rails_f59e5f12f9 FOREIGN KEY (client_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_engagements fk_rails_f81c3ca546; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_engagements
    ADD CONSTRAINT fk_rails_f81c3ca546 FOREIGN KEY (creator_id) REFERENCES public.identity_accounts(id);


--
-- Name: engagements_work_files work_file_matches_engagement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements_work_files
    ADD CONSTRAINT work_file_matches_engagement FOREIGN KEY (submission_id, engagement_id) REFERENCES public.engagements_submissions(id, engagement_id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261008190000'),
('20261008182000'),
('20261008170000'),
('20261008160000'),
('20261008150000'),
('20261008142000'),
('20261008140000'),
('20261008120000'),
('20261008060000'),
('20261008040000'),
('20261008020000'),
('20261007180000'),
('20261007160000'),
('20261007140000'),
('20261007120000'),
('20261007005000'),
('20261007004000'),
('20261007003000'),
('20261007002000'),
('20261007001356'),
('20261007000200'),
('20261007000100'),
('20261007000002');

