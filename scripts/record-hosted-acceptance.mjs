import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const [kind, runFile, artifactDirectory, releaseFile] = process.argv.slice(2);
assert.ok(["ci", "release", "ubuntu", "kubernetes"].includes(kind));
const run = JSON.parse((await readFile(runFile, "utf8")).replace(/^\uFEFF/, ""));
assert.equal(run.conclusion, "success", "Only completed successful runs can be accepted.");
assert.equal(run.status, "completed");
assert.match(run.head_sha, /^[a-f0-9]{40}$/);
assert.equal(run.html_url, "https://github.com/Ingaleee/MESH-showcase/actions/runs/" + run.id);
const files = {
  ci: [
    ".cache/ci-evidence/context.json",
    ".cache/ci-evidence/rspec.json",
    ".cache/ci-evidence/rspec-native.json",
    ".cache/ci-evidence/playwright.json",
    ".cache/ci-evidence/publishing-demo/summary.json",
    ".cache/ci-evidence/publishing-continuity.json",
    ".cache/ci-evidence/telemetry-retention.json",
    ".cache/ci-evidence/worker-incident/summary.json",
    ".cache/ci-evidence/gitleaks.json",
    ".cache/ci-evidence/gitleaks-history.json",
  ],
  release: ["image-security.json"],
  ubuntu: [
    "business-probe.json",
    "runtime-and-rollback.json",
    "schema-compatibility.json",
    "crash-recovery.json",
    "tls-read-profile.json",
    "ansible-first.log",
    "ansible-second.log",
    "attestation-api.json",
    "attestation-web.json",
    "attestation-postgres.json",
    "attestation-clamav.json",
  ],
  kubernetes: ["summary.json", "helm-history.json", "commands.jsonl"],
}[kind];
const directory = path.resolve("docs/evidence/acceptance-oct08/hosted", kind);
await mkdir(directory, { recursive: true });
const reports = [];
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
function sanitize(value) {
  if (Array.isArray(value)) return value.map(sanitize);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => !["backup_key_path", "encrypted_backup_path"].includes(key))
      .map(([key, item]) => [key, sanitize(item)]),
  );
}
for (const file of files) {
  const raw = await readFile(path.join(artifactDirectory, file));
  const name = file.replace(/^\.cache\/ci-evidence\//, "").replaceAll("/", "-");
  const published = file.endsWith(".json")
    ? Buffer.from(JSON.stringify(sanitize(JSON.parse(raw)), null, 2) + "\n")
    : raw;
  await writeFile(path.join(directory, name), published);
  reports.push({ file: name, sha256: hash(published), original_sha256: hash(raw) });
}
if (kind === "release") {
  assert.ok(releaseFile, "Release manifest from the same workflow run is required.");
  const raw = await readFile(releaseFile);
  const manifest = JSON.parse(raw);
  assert.equal(manifest.revision, run.head_sha);
  assert.equal(manifest.working_tree_dirty, false);
  await writeFile(path.join(directory, "release.json"), raw);
  reports.push({ file: "release.json", sha256: hash(raw), original_sha256: hash(raw) });
}
const result = {
  schema_version: 1,
  kind,
  recorded_at: new Date().toISOString(),
  workflow_run: run,
  reports,
  policy:
    "Successful workflow plus report assertions; hashes preserve downloaded reports, not an independent signature.",
};
await writeFile(path.join(directory, "manifest.json"), JSON.stringify(result, null, 2) + "\n");
console.log("Recorded " + kind + " from workflow " + run.id);
