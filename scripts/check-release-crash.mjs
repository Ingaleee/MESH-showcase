import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment");
const manifest = JSON.parse(await readFile(path.join(state, "current.json"), "utf8"));
const phases = [];
function run(args, fault) {
  return spawnSync("bash", ["scripts/release.sh", ...args], {
    encoding: "utf8",
    timeout: 420000,
    env: { ...process.env, MESH_RELEASE_FAILPOINT: fault ?? "" },
  });
}
for (const phase of ["runtime", "verified", "current"]) {
  const started = Date.now();
  const killed = run(["deploy", path.join(state, "current.json")], phase);
  assert.equal(killed.signal, "SIGKILL", "Fault must kill the actual deployment process.");
  const interrupted = JSON.parse(await readFile(path.join(state, "journal.json"), "utf8"));
  assert.ok(["applying", "verified"].includes(interrupted.phase));
  const recovered = run(["deploy", path.join(state, "current.json")]);
  assert.equal(recovered.status, 0, recovered.stderr.slice(-1000));
  assert.equal(JSON.parse(await readFile(path.join(state, "journal.json"))).phase, "committed");
  assert.deepEqual(
    JSON.parse(await readFile(path.join(state, "current.json"))).images,
    manifest.images,
  );
  phases.push({
    phase,
    killed_signal: killed.signal,
    recovered: true,
    elapsed_ms: Date.now() - started,
  });
}
await writeFile(
  path.join(process.env.MESH_EVIDENCE_DIR, "crash-recovery.json"),
  JSON.stringify(
    { checked_at: new Date().toISOString(), phases, schema_downgraded: false },
    null,
    2,
  ) + "\n",
);
console.log("Three actual SIGKILL interruptions recovered and committed.");
