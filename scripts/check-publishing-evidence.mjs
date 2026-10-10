import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
await readFile("SHOWCASE.md");
assert.ok(process.cwd().endsWith("MESH-showcase"));
const files = {
  ruby: "docs/evidence/publishing-rspec-final.json",
  native: "docs/evidence/publishing-rspec-alpine.json",
  browser: "docs/evidence/publishing-current-browser/playwright.json",
  demo: "docs/evidence/publishing-repeatable-demo-final/summary.json",
  publishing: "docs/evidence/publishing-repeatable-demo-final/publishing-demo/summary.json",
  incident: "docs/evidence/publishing-incident-patched/summary.json",
  security: "docs/evidence/publishing-security-complete/image-security.json",
  release_security: "docs/evidence/publishing-release-security-current/image-security.json",
  runtime: "docs/evidence/publishing-release-current/runtime-and-rollback.json",
  rubocop: "docs/evidence/publishing-quality/rubocop.json",
  brakeman: "docs/evidence/publishing-quality/brakeman.json",
  npm: "docs/evidence/publishing-quality/npm-audit.json",
  secrets: "docs/evidence/publishing-quality/gitleaks.json",
  canary: "docs/evidence/publishing-quality/gitleaks-canary.json",
  helm: "docs/evidence/publishing-kubernetes/helm-summary.json",
  terraform: "docs/evidence/publishing-kubernetes/terraform-summary.json",
  network: "docs/evidence/publishing-kubernetes/networkpolicy.json",
  recovery: "docs/evidence/publishing-kubernetes/recovery.json",
};
const entries = await Promise.all(
  Object.entries(files).map(async ([key, file]) => {
    const bytes = await readFile(file);
    return [key, file, bytes, JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, ""))];
  }),
);
const reports = Object.fromEntries(entries.map(([key, , , report]) => [key, report]));
for (const report of [reports.ruby, reports.native]) {
  assert.equal(report.summary.example_count, 118);
  assert.equal(
    report.summary.failure_count +
      report.summary.pending_count +
      report.summary.errors_outside_of_examples_count,
    0,
  );
}
assert.equal(reports.browser.stats.expected, 13);
assert.equal(
  reports.browser.stats.unexpected + reports.browser.stats.skipped + reports.browser.stats.flaky,
  0,
);
assert.equal(reports.demo.success, true);
assert.ok(reports.demo.stages.every((row) => row.exit_code === 0));
assert.equal(reports.publishing.success, true);
assert.equal(reports.publishing.remote_publish_requests, 3);
assert.equal(reports.publishing.downloads.length, 3);
assert.equal(reports.publishing.signed_callbacks_delivered.length, 3);
assert.ok(
  reports.publishing.signed_callbacks_delivered.every(
    (row) => row.last_status === 200 && row.delivered_at,
  ),
);
assert.ok(reports.publishing.downloads.every((row) => row.private_authenticated_download));
assert.equal(reports.publishing.phases.lost_response.unknown.state, "unknown");
assert.equal(reports.publishing.phases.lost_response.recovered.state, "confirmed");
assert.equal(
  reports.publishing.local_active_after_delayed_callback.deployment_id,
  reports.publishing.phases.rollback.id,
);
assert.equal(
  reports.publishing.local_active_after_delayed_callback.sequence,
  reports.publishing.phases.rollback.remote_sequence,
);
for (const report of [reports.security, reports.release_security]) {
  assert.equal(report.success, true);
  assert.ok(
    Object.values(report.images).every((row) => row.scan_exit_code === 0 && row.findings === 0),
  );
}
assert.equal(Object.keys(reports.security.images).length, 9);
for (const [role, image] of Object.entries(reports.runtime.release))
  assert.equal(reports.release_security.images[role].image, image);
assert.equal(reports.runtime.success, true);
assert.notEqual(reports.runtime.rejected_exit, 0);
assert.equal(reports.runtime.previous_images_restored, true);
assert.deepEqual(reports.runtime.data_after, reports.runtime.data_before);
assert.equal(reports.runtime.business_probe.accepted, true);
assert.equal(reports.rubocop.summary.offense_count, 0);
assert.equal(reports.brakeman.scan_info.security_warnings, 0);
assert.equal(reports.npm.metadata.vulnerabilities.total, 0);
assert.equal(reports.secrets.length, 0);
assert.ok(
  reports.canary.some(
    (row) =>
      row.RuleID === "generic-api-key" && row.File.endsWith("backend-hardening/verification.json"),
  ),
);
const gemText = await readFile("docs/evidence/publishing-quality/bundler-audit.json", "utf8");
assert.equal(JSON.parse(gemText.trim().split(/\r?\n/).at(-1)).results.length, 0);
assert.equal(reports.incident.success, true);
assert.deepEqual(reports.incident.drained.effects_per_event, [1]);
assert.equal(reports.incident.drained.observations_added, 50);
assert.equal(reports.incident.drained.replay_observations_added, 0);
assert.equal(reports.incident.firing_receipt.status, "firing");
assert.equal(reports.incident.resolved_receipt.status, "resolved");
assert.equal(reports.helm.previous_image_restored, true);
assert.notEqual(reports.helm.rejected_release_exit, 0);
assert.equal(reports.terraform.drift_plan_exit, 2);
assert.equal(reports.terraform.repaired_plan_exit, 0);
assert.equal(reports.network.success, true);
assert.equal(reports.recovery.success, true);
assert.deepEqual(reports.recovery.worker_recovery.effects_per_event, [1]);
assert.ok(
  reports.recovery.api_after_liveness_cycles.every(
    (row) => row.ready === "False" && row.restarts === 0,
  ),
);
assert.ok(reports.recovery.api_restored.every((row) => row.ready === "True" && row.restarts === 0));
const listing = execFileSync(
  "git",
  ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
  { encoding: "utf8" },
);
const names = [
  ...new Set(listing.split("\0").filter((name) => name && !name.startsWith("docs/evidence/"))),
].sort();
const hash = createHash("sha256");
for (const name of names) hash.update(name + "\0").update(await readFile(name));
const manifest = {
  schema_version: 1,
  checked_at: new Date().toISOString(),
  environment: "Isolated MESH-showcase / Windows Docker Desktop Linux",
  git_revision: null,
  working_tree_dirty: true,
  current_source_snapshot_sha256: hash.digest("hex"),
  results: {
    ruby: reports.ruby.summary,
    native_ruby: reports.native.summary,
    browser: reports.browser.stats,
    demo: reports.demo.success,
    publishing_posts: reports.publishing.remote_publish_requests,
    actual_signed_callbacks_delivered: 3,
    strict_nine_image_gate: true,
    strict_release_inventory_gate: true,
    incident_detection_seconds: reports.incident.detection_seconds,
    runtime_rollback_data_preserved: true,
    live_kubernetes_exercises: true,
    live_terraform_drift_repaired: true,
    remote_github_runs: false,
    ansible_convergence: false,
  },
  artifacts: Object.fromEntries(
    entries.map(([, file, bytes]) => [file, createHash("sha256").update(bytes).digest("hex")]),
  ),
  scope:
    "Recorded local runs at their actual times/digests; current source fingerprint is separate from the tested historical snapshots. Not a signed CI attestation, production SLO or physical HA. Kubernetes used earlier Debian application images.",
};
await writeFile(
  "docs/evidence/publishing-implementation.json",
  JSON.stringify(manifest, null, 2) + "\n",
);
console.log(
  "Evidence agrees: 118 native Ruby, 13 browser, 3 partner POST, strict images, runtime rollback and live Kubernetes/Terraform.",
);
