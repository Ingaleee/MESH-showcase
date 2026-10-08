# Publishing integration laboratory

Scope: showcase only; one Rails Publishing pack, one independent TypeScript partner simulator, immutable ZIP artifacts in private disk storage, Ruby CLI and an operator UI. The partner is a trusted test process; arbitrary uploaded code is never executed by Rails or the simulator.

The candidate includes a ZIP digest, manifest digest, contract version and partner binding. Validation adds the policy/configuration fingerprint. Publishing rechecks this fingerprint and the bytes; changing an input invalidates the gate. A release has a durable operation UUID, preserved across uncertainty and retries. After a lost POST response only lookup is automatic. Missing remote state remains unknown for operator triage; it never authorizes an unbounded POST retry.

Validation and release intents live in primary PostgreSQL. The ordinary dispatcher enqueues bounded batches; enqueue failure and a dead worker recover through deadlines/leases. Token fencing prevents an expired attempt from committing. Network, scanner and ZIP validation run outside transactions. Queue jobs are at least once; the durable source and guarded terminal transition prevent duplicate local effects.

Signed callbacks carry event UUID, timestamp and operation/artifact identity. Deduplication rejects reuse with different content. A partner sequence orders active releases so an older callback cannot replace a newer active version. Rollback creates a new attempt for a previously validated artifact; it preserves history.

Only appointed operators manage integrations. Endpoints must match administrator-configured exact origins; redirects, environment proxies and arbitrary credential references are forbidden. Plain HTTP is accepted only for an explicitly configured isolated simulator origin. TLS validates hostname and CA. ZIP entries are read in memory within compressed/uncompressed/entry/time budgets; no extraction to host paths. Antivirus supports this boundary but does not certify safety.

Tradeoffs: local disk/SQLite simulator demonstrate one host, not HA; filesystem writes are not atomic with a DB transaction; bounded orphan blobs require retention cleanup. Primary metric aggregates cost an extra SQL write per successful notification/validation; HTTP histograms are process local. No live studio, gaming certification, real stake or payment is implied.

The repository and hosted verification/release now exist. See execution-status.md for actual run IDs and their source revisions. Hosted deployment uses exact release source and verified signed registry digests; the disposable environment and Linux crash-recovery choice are recorded in 003-hosted-acceptance.md.
