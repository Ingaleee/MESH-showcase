import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";

assert.ok(process.cwd().endsWith("MESH-showcase"));
await access("SHOWCASE.md");
const directory = process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/publishing-release";
await mkdir(directory, { recursive: true });
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment");
const manifest = JSON.parse(await readFile(path.join(state, "current.json"), "utf8"));
assert.equal(manifest.schema_version, 2);
assert.equal(manifest.project, "mesh-showcase-release");
const compose = [
  "compose",
  "--env-file",
  path.join(state, "runtime.env"),
  "-f",
  "infra/deploy/compose.yaml",
  "-p",
  manifest.project,
];
function run(program, args, input, allowFailure = false) {
  const result = spawnSync(program, args, {
    input,
    encoding: "utf8",
    windowsHide: true,
    timeout: 420000,
    maxBuffer: 2 ** 24,
    env: { ...process.env, MESH_EVIDENCE_DIR: directory },
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && !allowFailure)
    throw new Error(program + " failed: " + result.stderr.slice(-1200));
  return result;
}
const ruby = (code) =>
  run("docker", [...compose, "exec", "-T", "api", "bundle", "exec", "rails", "runner", code]);
function extract(output, field) {
  const marker = '{\n  "' + field + '":';
  const index = output.lastIndexOf(marker);
  assert.ok(index >= 0, "Expected structured report.");
  return JSON.parse(output.slice(index));
}
const smoke = extract(run(process.execPath, ["scripts/release.mjs", "smoke"]).stdout, "origin");
const probeSource = (await readFile("apps/api/script/deployment_probe.rb", "utf8")).replace(
  'require_relative "../config/environment"',
  'require "./config/environment"',
);
const probe = extract(
  run(
    "docker",
    [
      ...compose,
      "exec",
      "-T",
      "-e",
      "MESH_DEPLOYMENT_PROBE=true",
      "api",
      "bundle",
      "exec",
      "ruby",
      "-",
    ],
    probeSource,
  ).stdout,
  "checked_at",
);
await writeFile(path.join(directory, "business-probe.json"), JSON.stringify(probe, null, 2) + "\n");
const snapshot = () =>
  extract(
    ruby(`
  blobs=ActiveStorage::Blob.order(:id).map { |b| [b.id, Digest::SHA256.hexdigest(b.download)] }
  puts JSON.pretty_generate({
    schema_version: 1,
    submissions: Engagements::Submission.count,
    blobs: ActiveStorage::Blob.count,
    journals: Finance::LedgerTransaction.where(status: "posted").count,
    file_inventory_sha256: Digest::SHA256.hexdigest(JSON.generate(blobs))
  })
`).stdout,
    "schema_version",
  );
const before = snapshot();
const baseTag = "mesh-showcase-rollback-base:" + manifest.images.web.slice(-16);
run("docker", ["tag", manifest.images.web, baseTag]);
assert.equal(
  run("docker", ["image", "inspect", baseTag, "--format", "{{.Id}}"]).stdout.trim(),
  run("docker", ["image", "inspect", manifest.images.web, "--format", "{{.Id}}"]).stdout.trim(),
);
run(
  "docker",
  ["build", "-t", "mesh-showcase-web:exit42", "-f", "-", "."],
  "FROM " + baseTag + '\nENTRYPOINT []\nCMD ["node", "-e", "process.exit(42)"]\n',
);
const badImage = run("docker", [
  "image",
  "inspect",
  "mesh-showcase-web:exit42",
  "--format",
  "{{.Id}}",
]).stdout.trim();
assert.match(badImage, /^sha256:[a-f0-9]{64}$/);
const bad = {
  ...manifest,
  revision: null,
  source_tree_sha256: null,
  working_tree_dirty: true,
  synthetic_fault: "local frontend exit 42",
  images: { ...manifest.images, web: badImage },
};
const file = path.join(state, "publishing-exit42.json");
await writeFile(file, JSON.stringify(bad, null, 2) + "\n");
const rejected =
  process.platform === "linux"
    ? run("bash", ["scripts/release.sh", "deploy", file], undefined, true)
    : run(process.execPath, ["scripts/release.mjs", "deploy", file], undefined, true);
assert.notEqual(rejected.status, 0, "Fault injection unexpectedly succeeded.");
const afterSmoke = extract(
  run(process.execPath, ["scripts/release.mjs", "smoke"]).stdout,
  "origin",
);
const restored = JSON.parse(await readFile(path.join(state, "current.json"), "utf8"));
assert.deepEqual(restored.images, manifest.images);
const after = snapshot();
assert.deepEqual(after, before, "Durable records or private bytes changed during image rollback.");
const report = {
  checked_at: new Date().toISOString(),
  success: true,
  environment: manifest.project,
  release: manifest.images,
  smoke,
  business_probe: probe,
  rejected_exit: rejected.status,
  previous_images_restored: true,
  data_before: before,
  data_after: after,
  migration_reverted: false,
  restored_smoke: afterSmoke,
  scope:
    "Actual loopback HTTPS v2 inventory, restricted runtime, real private file scan and local exit-42 rollback. Host/run context is recorded separately; this loopback stand does not prove physical high availability.",
};
await writeFile(
  path.join(directory, "runtime-and-rollback.json"),
  JSON.stringify(report, null, 2) + "\n",
);
console.log(
  JSON.stringify(
    {
      success: true,
      rejected_exit: rejected.status,
      data_preserved: true,
      report: directory + "/runtime-and-rollback.json",
    },
    null,
    2,
  ),
);
