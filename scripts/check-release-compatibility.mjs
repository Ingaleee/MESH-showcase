import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE);
const baseline = ".cache/downloaded-baseline/release.json";
const target = ".cache/downloaded-release/release.json";
function deploy(file) {
  const r = spawnSync("bash", ["scripts/release.sh", "deploy", file], {
    encoding: "utf8",
    timeout: 420000,
  });
  if (r.status !== 0) throw Error(r.stderr.slice(-1000));
}
const dc = [
  "compose",
  "--env-file",
  path.join(state, "runtime.env"),
  "-f",
  "infra/deploy/compose.yaml",
  "-p",
  "mesh-showcase-release",
];
const probe = await readFile("apps/api/script/deployment_probe.rb", "utf8");
function business() {
  const r = spawnSync(
    "docker",
    [...dc, "exec", "-T", "-e", "MESH_DEPLOYMENT_PROBE=true", "api", "bundle", "exec", "ruby", "-"],
    {
      input: probe.replace(
        'require_relative "../config/environment"',
        'require "./config/environment"',
      ),
      encoding: "utf8",
      timeout: 90000,
    },
  );
  if (r.status !== 0) throw Error(r.stderr.slice(-1000));
  return JSON.parse(r.stdout.slice(r.stdout.lastIndexOf('{\n  "checked_at"')));
}
deploy(baseline);
const first = business();
deploy(target);
const newRuntime = business();
// Images revert, while all expand migrations and tables remain in place.
const rollback = spawnSync("bash", ["scripts/release.sh", "rollback"], {
  encoding: "utf8",
  timeout: 420000,
});
assert.equal(rollback.status, 0, rollback.stderr.slice(-1000));
const oldOnNewSchema = business();
deploy(target);
const report = {
  checked_at: new Date().toISOString(),
  baseline: JSON.parse(await readFile(baseline)).revision,
  target: JSON.parse(await readFile(target)).revision,
  first,
  new_runtime: newRuntime,
  previous_runtime_on_new_schema: oldOnNewSchema,
  target_restored: true,
  automatic_schema_downgrade: false,
  scope:
    "Actual marketplace/private file workflow before upgrade, after upgrade, and previous image against expanded schema. Publishing job payload compatibility requires its separate regression scenarios.",
};
await writeFile(
  path.join(process.env.MESH_EVIDENCE_DIR, "schema-compatibility.json"),
  JSON.stringify(report, null, 2) + "\n",
);
console.log("Release A -> B -> A on expanded schema -> B passed real business and file checks.");
