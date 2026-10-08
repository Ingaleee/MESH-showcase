import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const state = path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment");
const manifest = JSON.parse(await readFile(path.join(state, "current.json"), "utf8"));
const phases = [];
const recoveryFile = path.join(state, "crash-recovery-target.json");
await writeFile(recoveryFile, JSON.stringify(manifest, null, 2) + "\n");
const candidateFile = ".cache/downloaded-baseline/release.json";
const candidate = JSON.parse(await readFile(candidateFile, "utf8"));
assert.notEqual(
  candidate.images.api,
  manifest.images.api,
  "Crash drill requires two distinct attested releases.",
);
function run(args, fault) {
  return spawnSync("bash", ["scripts/release.sh", ...args], {
    encoding: "utf8",
    timeout: 420000,
    env: { ...process.env, MESH_RELEASE_FAILPOINT: fault ?? "" },
  });
}
for (const phase of [
  "intent",
  "runtime",
  "migrated",
  "services",
  "smoke",
  "verified",
  "previous",
  "current",
]) {
  const started = Date.now();
  const killed = run(["deploy", candidateFile], phase);
  assert.equal(killed.signal, "SIGKILL", "Fault must kill the actual deployment process.");
  const interrupted = JSON.parse(await readFile(path.join(state, "journal.json"), "utf8"));
  assert.ok(["applying", "verified"].includes(interrupted.phase));
  assert.deepEqual(interrupted.baseline.images, manifest.images);
  assert.deepEqual(interrupted.target.images, candidate.images);
  if (phase === "intent") {
    const recoveryKilled = run(["deploy", recoveryFile], "recovery-runtime");
    assert.equal(recoveryKilled.signal, "SIGKILL");
    assert.equal(
      JSON.parse(await readFile(path.join(state, "journal.json"))).phase,
      interrupted.phase,
    );
  }
  const recovered = run(["deploy", recoveryFile]);
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
    interrupted_target_revision: candidate.revision,
    recovered_baseline_revision: manifest.revision,
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
// The dedicated hosted VM is the only supported environment for this actual engine outage.
assert.equal(
  process.env.GITHUB_ACTIONS,
  "true",
  "Engine fault must run on the isolated hosted runner.",
);
assert.equal(run(["deploy", recoveryFile], "intent").signal, "SIGKILL");
const journalBefore = await readFile(path.join(state, "journal.json"), "utf8");
const currentBefore = await readFile(path.join(state, "current.json"), "utf8");
try {
  const stopped = spawnSync("sudo", ["systemctl", "stop", "docker.socket", "docker.service"], {
    encoding: "utf8",
    timeout: 60000,
  });
  assert.equal(stopped.status, 0, stopped.stderr);
  const failed = run(["deploy", recoveryFile]);
  assert.notEqual(failed.status, 0);
  assert.equal(await readFile(path.join(state, "journal.json"), "utf8"), journalBefore);
  assert.equal(await readFile(path.join(state, "current.json"), "utf8"), currentBefore);
} finally {
  const started = spawnSync("sudo", ["systemctl", "start", "docker"], {
    encoding: "utf8",
    timeout: 60000,
  });
  assert.equal(started.status, 0, started.stderr);
}
assert.equal(run(["deploy", recoveryFile]).status, 0);
const goodJournal = await readFile(path.join(state, "journal.json"), "utf8");
try {
  await writeFile(path.join(state, "journal.json"), "{truncated");
  const denied = run(["deploy", recoveryFile]);
  assert.notEqual(denied.status, 0);
  assert.equal(await readFile(path.join(state, "current.json"), "utf8"), currentBefore);
} finally {
  await writeFile(path.join(state, "journal.json"), goodJournal);
}
await writeFile(
  path.join(process.env.MESH_EVIDENCE_DIR, "crash-recovery.json"),
  JSON.stringify(
    {
      checked_at: new Date().toISOString(),
      phases,
      recovery_sigkill: true,
      unavailable_engine_preserved_state: true,
      subsequent_recovery: true,
      corrupt_journal_denied: true,
      schema_downgraded: false,
      scope:
        "Actual Linux process death and Docker service outage on an ephemeral hosted VM; no kernel power-loss/HA claim.",
    },
    null,
    2,
  ) + "\n",
);
console.log(
  "Eight commit boundaries, recovery SIGKILL, unavailable engine and corrupt journal verified.",
);
