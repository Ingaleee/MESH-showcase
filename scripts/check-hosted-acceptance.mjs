import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
const root = path.resolve(process.argv[2] ?? "docs/evidence/acceptance-oct08/hosted");
const loaded = {};
for (const kind of ["ci", "release", "ubuntu", "kubernetes"]) {
  const directory = path.join(root, kind);
  const manifest = JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8"));
  assert.equal(manifest.schema_version, 1);
  assert.equal(manifest.kind, kind);
  assert.equal(manifest.workflow_run.conclusion, "success");
  assert.match(manifest.workflow_run.head_sha, /^[a-f0-9]{40}$/);
  const files = {};
  for (const entry of manifest.reports) {
    assert.equal(path.basename(entry.file), entry.file, "Evidence paths must be simple filenames.");
    const raw = await readFile(path.join(directory, entry.file));
    assert.equal(createHash("sha256").update(raw).digest("hex"), entry.sha256, entry.file);
    files[entry.file] = entry.file.endsWith(".json") ? JSON.parse(raw) : raw.toString();
  }
  loaded[kind] = { manifest, files };
}
const { ci, release, ubuntu, kubernetes } = loaded;
const revision = release.files["release.json"].revision;
assert.equal(ci.manifest.workflow_run.head_sha, revision);
assert.equal(ci.files["context.json"].revision, revision);
assert.equal(String(ci.files["context.json"].run_id), String(ci.manifest.workflow_run.id));
for (const name of ["rspec.json", "rspec-native.json"]) {
  const s = ci.files[name].summary;
  assert.ok(s.example_count > 0);
  assert.equal(s.failure_count + s.pending_count + s.errors_outside_of_examples_count, 0);
}
assert.equal(
  ci.files["rspec.json"].summary.example_count,
  ci.files["rspec-native.json"].summary.example_count,
);
const stats = ci.files["playwright.json"].stats;
assert.ok(stats.expected > 0);
assert.equal(stats.unexpected + stats.flaky + stats.skipped, 0);
assert.equal(ci.files["worker-incident-summary.json"].success, true);
assert.equal(ci.files["telemetry-retention.json"].historic_scrape_preserved, true);
assert.equal(ci.files["telemetry-retention.json"].silence_preserved, true);
assert.equal(ci.files["telemetry-retention.json"].receipt_history_preserved, true);
assert.deepEqual(ci.files["gitleaks.json"], []);
assert.deepEqual(ci.files["gitleaks-history.json"], []);
const recovery = ci.files["publishing-continuity.json"];
assert.equal(
  recovery.partner_publish_requests_before_recovery,
  recovery.partner_publish_requests_after_recovery,
);
for (const name of [
  "private_http_artifact_verified",
  "restored_pending_reconciled",
  "remote_identity_unchanged",
  "replay_preserved_active",
  "wrong_key_denied",
  "ciphertext_corruption_denied",
])
  assert.equal(recovery[name], true, name);
assert.ok(recovery.private_objects_verified > 0);
const security = release.files["image-security.json"];
assert.equal(security.success, true);
for (const [name, image] of Object.entries(release.files["release.json"].images)) {
  assert.equal(security.images[name].image, image);
  assert.equal(security.images[name].findings, 0);
  assert.equal(security.images[name].scan_exit_code, 0);
}
for (const name of ["api", "web", "postgres", "clamav"]) {
  const rows = ubuntu.files["attestation-" + name + ".json"];
  const expectedDigest = release.files["release.json"].images[name].split("@sha256:")[1];
  assert.ok(
    rows.some((row) => {
      const verified = row.verificationResult;
      const certificate = verified.signature.certificate;
      return (
        certificate.sourceRepositoryDigest === revision &&
        certificate.sourceRepositoryURI === "https://github.com/Ingaleee/MESH-showcase" &&
        certificate.runnerEnvironment === "github-hosted" &&
        certificate.buildSignerURI ===
          "https://github.com/Ingaleee/MESH-showcase/.github/workflows/image.yml@refs/heads/main" &&
        verified.statement.subject.some((subject) => subject.digest.sha256 === expectedDigest)
      );
    }),
    "Verified provenance identity mismatch: " + name,
  );
}
const runtime = ubuntu.files["runtime-and-rollback.json"];
assert.equal(runtime.success, true);
assert.deepEqual(runtime.release, release.files["release.json"].images);
assert.deepEqual(runtime.data_before, runtime.data_after);
assert.equal(runtime.previous_images_restored, true);
assert.equal(runtime.migration_reverted, false);
assert.ok(
  Object.values(ubuntu.files["business-probe.json"].denied).every((value) => value === true),
);
assert.match(ubuntu.files["ansible-second.log"], /changed=0 .*unreachable=0 .*failed=0/);
assert.equal(ubuntu.files["schema-compatibility.json"].target, revision);
assert.equal(ubuntu.files["schema-compatibility.json"].target_restored, true);
assert.equal(ubuntu.files["crash-recovery.json"].phases.length, 3);
assert.ok(
  ubuntu.files["crash-recovery.json"].phases.every(
    (p) => p.killed_signal === "SIGKILL" && p.recovered,
  ),
);
const load = ubuntu.files["tls-read-profile.json"];
assert.equal(load.errors, 0);
assert.equal(load.rejected_arrivals, 0);
assert.ok(load.p95_ms <= load.config.maximum_read_p95_ms);
const history = kubernetes.files["helm-history.json"];
assert.ok(
  history.some(
    (entry) => entry.status === "failed" && /not ready|deadline exceeded/.test(entry.description),
  ),
);
assert.equal(history.at(-1).status, "deployed");
assert.ok(history.at(-1).rollback_revision > 0);
const kube = kubernetes.files["summary.json"];
assert.equal(kube.release_revision, revision);
assert.deepEqual(kube.images, release.files["release.json"].images);
for (const name of [
  "terraform_drift_detected_and_repaired",
  "migration_completed_before_application",
  "positive_api_and_db",
  "untrusted_ingress_denied",
  "unapproved_egress_denied_with_positive_control",
  "worker_50_once_only_effects",
  "database_outage_ready_503_live_200",
  "outage_preserved_api_uids_and_restarts",
  "alpine_rollout",
  "broken_upgrade_rejected",
  "registry_digest_restored",
])
  assert.equal(kube[name], true, name);
console.log(
  JSON.stringify(
    {
      revision,
      ruby_examples: ci.files["rspec.json"].summary.example_count,
      browser_passed: stats.expected,
      release_images: Object.keys(security.images).length,
      workflows: Object.fromEntries(
        Object.entries(loaded).map(([kind, value]) => [kind, value.manifest.workflow_run.html_url]),
      ),
      scope:
        "These four hosted workflows and recorded reports; not blanket acceptance of Q01–Q14 or production reliability.",
    },
    null,
    2,
  ),
);
