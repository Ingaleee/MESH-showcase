import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";

await import("./check-architecture-evidence.mjs");

const artifacts = [
  "rspec.json",
  "playwright.json",
  "brakeman.json",
  "bundler-audit.json",
  "npm-audit.json",
  "money-mutations.json",
  "production-csp.json",
  "restore-drill.json",
  "observability.json",
  "k6.json",
  "benchmark-environment.json",
  "architecture-lab/summary.json",
  "architecture-lab/verification.json",
  "architecture-lab/cleanup.json",
];
const contents = await Promise.all(
  artifacts.map(async (name) => [name, await readFile(`docs/evidence/${name}`)]),
);
const reports = Object.fromEntries(
  contents.map(([name, content]) => [
    name,
    JSON.parse(content.toString("utf8").replace(/^\uFEFF/, "")),
  ]),
);
const backend = reports["rspec.json"].summary;
assert.ok(backend.example_count > 0);
assert.equal(backend.failure_count, 0);
assert.equal(backend.pending_count, 0);
assert.equal(backend.errors_outside_of_examples_count, 0);
const browser = reports["playwright.json"].stats;
assert.ok(browser.expected > 0);
assert.equal(browser.unexpected + browser.skipped + browser.flaky, 0);
assert.equal(reports["brakeman.json"].scan_info.security_warnings, 0);
assert.equal(reports["bundler-audit.json"].results.length, 0);
assert.equal(reports["npm-audit.json"].metadata.vulnerabilities.total, 0);
const mutations = reports["money-mutations.json"];
assert.equal(mutations.length, 4);
assert.equal(mutations.find((result) => result.variant === "baseline").passes, true);
assert.ok(
  mutations.filter((result) => result.variant !== "baseline").every((result) => !result.passes),
);
const csp = reports["production-csp.json"];
assert.equal(csp.production, true);
assert.equal(csp.unsafe_eval, false);
assert.equal(csp.distinct_nonce_per_response, true);
assert.equal(csp.browser_hydration_and_keyboard_verified, true);
assert.equal(csp.csp_violations.length + csp.javascript_errors.length, 0);
const restore = reports["restore-drill.json"];
assert.equal(restore.restored_state_after, "confirmed");
assert.equal(restore.provider_post_attempts, 1);
assert.equal(restore.recovered_journals, 1);
assert.equal(restore.recovered_by_reconciliation_before_duplicate_replay, true);
assert.equal(restore.restored_trigger_verified, true);
assert.equal(restore.payouts_disabled_during_recovery, true);
assert.equal(reports["observability.json"].prometheus_target.health, "up");
assert.ok(reports["observability.json"].recent_span_count > 0);
const metrics = reports["k6.json"].metrics;
for (const name of ["http_req_duration", "http_req_failed", "checks", "dropped_iterations"]) {
  assert.ok(Object.values(metrics[name].thresholds).every((threshold) => threshold.ok));
}
assert.equal(reports["benchmark-environment.json"].exit_code, 0);
assert.equal(reports["architecture-lab/verification.json"].rspec.failure_count, 0);
assert.equal(
  reports["architecture-lab/verification.json"].rspec.example_count,
  backend.example_count,
);
const cleanup = reports["architecture-lab/cleanup.json"];
assert.equal(cleanup.status, "cleaned");
assert.equal(
  cleanup.containersRemaining + cleanup.volumesRemaining + cleanup.databasesRemaining,
  0,
);
const model = await readFile("docs/evidence/tlc.txt", "utf8");
assert.ok(model.includes("Model checking completed. No error has been found."));

const ignored = new Set([
  "node_modules",
  ".next",
  ".cache",
  ".git",
  ".bundle",
  "tmp",
  "log",
  "storage",
]);
async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const groups = await Promise.all(
    entries.map(async (entry) => {
      const filename = path.join(directory, entry.name);
      if (entry.isDirectory() && !ignored.has(entry.name)) return sourceFiles(filename);
      return entry.isFile() && entry.name !== "master.key" ? [filename] : [];
    }),
  );
  return groups.flat();
}
const groups = await Promise.all(
  [
    "apps/api",
    "apps/gateway",
    "apps/web",
    "contracts",
    "infra",
    "scripts",
    "specs",
    "tests",
    ".github",
  ].map(sourceFiles),
);
const files = [
  ...groups.flat(),
  "package.json",
  "package-lock.json",
  "compose.yaml",
  ".editorconfig",
  ".prettierrc.json",
].sort();
const sourceHash = createHash("sha256");
for (const filename of files) {
  sourceHash.update(filename.replaceAll(path.sep, "/") + "\0");
  sourceHash.update(
    createHash("sha256")
      .update(await readFile(filename))
      .digest(),
  );
}
const manifest = {
  generated_at: new Date().toISOString(),
  source_snapshot_sha256: sourceHash.digest("hex"),
  source_file_count: files.length,
  backend_examples: backend.example_count,
  browser_tests: browser.expected,
  benchmark_iterations: metrics.iterations.values.count,
  benchmark_p95_ms: metrics.http_req_duration.values["p(95)"],
  architecture_lab_requests: reports["architecture-lab/summary.json"].httpRequests,
  architecture_lab_p95_ms: reports["architecture-lab/summary.json"].httpP95Ms,
  artifacts: Object.fromEntries(
    [...contents, ["tlc.txt", Buffer.from(model)]].map(([name, content]) => [
      name,
      createHash("sha256").update(content).digest("hex"),
    ]),
  ),
  scope:
    "Local evidence snapshot with current Ruby reliability experiments. Earlier browser/frontend, financial drill and small-data benchmark have their own scopes/dates; not a signed CI attestation or a production SLA.",
};
await writeFile("docs/evidence/manifest.json", JSON.stringify(manifest, null, 2) + "\n");
console.log(
  `Evidence agrees: ${backend.example_count} backend examples, ${browser.expected} browser tests.`,
);
