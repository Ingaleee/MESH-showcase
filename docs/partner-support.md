# Partner integration and support guide

This is an English guide to the MESH static-package Publishing lab. It demonstrates external-studio support; it is not a claim of a production BGaming integration or a casino game certification system. Uploaded code is never executed.

## Before onboarding

An administrator approves an exact partner origin and credential reference. Production transport must use HTTPS with certificate and hostname verification. HTTP is an explicit allowance for the isolated simulator. Configure a generated printable credential of 32–256 bytes; empty values, control characters and oversized values fail closed. No credential is accepted from a candidate manifest or returned in diagnostics.

The partner must expose contract version 1 with publish, lookup and signed_callbacks capabilities. GET /contract verifies compatibility. A successful local validation binds package bytes, manifest, contract version, policy, approved origins, credential, trust root and environment generation. Rotation changes the fingerprint: request fresh validation for a new release. Reconciliation of an existing uncertain operation retains its original identity and does not require republishing under a new validation.

## Package contract

Supply a manifest-v1 JSON and a ZIP: at most 2 MB compressed and expanded, 16 regular relative files, including index.html. Every declared file has its byte size and SHA-256. The archive inventory must match exactly; traversal, duplicate entries, links, undeclared files and mismatched bytes are rejected. Validation also requires a real clean scanner result and a compatible partner contract.

The report provides stable error codes, expected and observed values, and a suggested fix. Fix the package and upload a new candidate. Do not edit the immutable stored bytes or use the same upload idempotency key for different content. The lab's 3-second archive inspection budget and 2 MB artifact ceiling are deliberate limits, not a general large-game distribution solution.

## Operation identity and ambiguous outcomes

POST /deployments carries the original operation_id, partner_id, candidate_id, exact artifact_sha256, contract_version and package. The simulator durably stores an operation before returning its observation. GET /deployments/{operation_id} is the reconciliation contract.

A timeout, disconnected connection, authentication rejection or absent lookup does not establish that an operation never committed. MESH retains unknown and uses lookup on the same ID. A 404 is not permission to manufacture another operation. If the partner cannot provide an authoritative outcome, preserve the uncertainty and escalate with that ID and digest. Do not manually change database state to confirmed.

A current lease prevents a competing worker. Expired leases switch to lookup. A stale worker cannot overwrite a newer claim or a confirmed result. The monotonic sequence prevents a delayed callback from moving the active release backwards.

## Credential rotation procedure

1. Generate the replacement outside the repository and deliver it through the approved secret channel.
2. Update the partner and the MESH processes that issue HTTP requests and receive callbacks. The lab uses an atomic simulator process restart; it does not demonstrate a production zero-downtime keyring.
3. Expect a temporary authentication failure while the two sides disagree. Deployment stays unknown; PARTNER_AUTH_REJECTED points to restoring the credential, not another POST.
4. Resume lookup for the original operation. Verify its identity, digest and sequence before confirmation.
5. Request a new validation before another publication under the changed fingerprint.

Callbacks are HMAC-SHA256 over timestamp + "." + event_id + "." + exact JSON bytes. Send X-Callback-Timestamp, X-Event-ID and X-Callback-Signature. Timestamp tolerance is 300 seconds. Event IDs are UUIDs: identical authenticated repeats are deduplicated, different content under the same ID is rejected. Old-key signatures are rejected immediately; there is no grace-key mechanism. Plan partner clock synchronization and callback retries accordingly.

## Operator diagnostic

Use the existing authenticated Ruby CLI: mesh-publish diagnose OPERATION_ID. The browser's diagnostic includes the same local read and an English support update.

| action_code | Safe operator action |
| --- | --- |
| await_dispatch | Process the existing pending operation |
| await_lease | Let its current lease finish; do not compete |
| lookup_only | Query the same remote operation, including after 404 |
| restore_configuration | Restore approved credential/trust, then resume the same operation |
| revalidate | Validate exact bytes under the new configuration |
| inspect_failure | Inspect a closed failure before requesting another release |
| inspect_confirmed | Review recorded confirmation/history |

current_inputs_match is null if the fingerprint cannot be obtained. It is distinct from false. configuration_error exposes only a stable code. A missing credential must not hide the local state, operation ID or recorded confirmation. The report does not contact the partner, mutate state, download files or certify current remote health. Confirmation is historical; remote_state_queried is always false. The EN text is a factual template for an operator to review, not an automatically sent message.

Share the operation ID, correlation ID, digest, observed time, local state, stable error and next safe action through an approved support channel. Do not include a bearer token, cookie, callback signature, full environment or arbitrary application logs.

## Reproduce the acceptance exercise

Run npm run demo:partner-support from MESH-showcase after preparing the full local system, scanner and test database. This creates a disposable non-root Node/SQLite peer on the showcase network and a dedicated synthetic operator in mesh_test. It does not restart the existing partner or the product MESH. The private peer volume survives its process rotations and is removed at the end after checking its ownership label.

The four phases cover remote commit before timeout; rejected old credential and successful new credential; stale validation, expired leases and stale result/failure fencing; old and replayed new HMAC callbacks; missing local secret; unreachable peer; and an absent lookup. The final assertion requires one remote POST and one stored result. The real callback endpoint runs in-process through Rack on a separate executor thread; this exercise does not claim callback network transport coverage. The existing Publishing demo covers real network-delivered signed callbacks.

Only sanitized reports are retained. Generated credentials are held in memory and are not written to the repository or the report. CI runs the exercise alongside the full Ruby/native/browser suite. [Readiness against the vacancy](vacancy-readiness.md) and [existing reliability acceptance](reliability-acceptance-oct09.md) define the wider proof and limits.

The owned candidate/release catalog remains readable during credential or trust unavailability. Validation exposes null input compatibility and a stable configuration error; new validation/publication commands remain blocked. The UI distinguishes unavailable configuration from changed inputs.
