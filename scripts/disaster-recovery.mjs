import { createHmac, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile, chmod } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
assert.equal(process.env.GITHUB_ACTIONS, "true");
const mode = process.argv[2];
assert.ok(["source", "target"].includes(mode));
assert.match(process.env.MESH_DR_KEY ?? "", /^[a-f0-9]{64}$/);
const root = path.resolve(".cache/disaster");
const release = JSON.parse(await readFile(".cache/downloaded-release/release.json", "utf8"));
assert.equal(release.revision, process.env.MESH_RELEASE_REVISION);
const project = "mesh-showcase-dr-" + process.env.GITHUB_RUN_ID + "-" + mode;
const derive = (name) =>
  createHmac("sha256", Buffer.from(process.env.MESH_DR_KEY, "hex"))
    .update("MESH synthetic DR " + name)
    .digest("hex");
for (const directory of ["", "transfer", "evidence", "partner-data"]) {
  await mkdir(path.join(root, directory), { recursive: true });
  await chmod(path.join(root, directory), 0o777);
}
const variables = {
  MESH_DR_PROJECT: project,
  MESH_DR_ROOT: root,
  API_IMAGE: release.images.api,
  POSTGRES_IMAGE: release.images.postgres,
  SCANNER_IMAGE: release.images.clamav,
  SECRET_KEY_BASE: derive("session"),
  MESH_METRICS_TOKEN: derive("metrics"),
  MESH_PARTNER_TOKEN_SHOWCASE: derive("partner"),
  POSTGRES_PASSWORD: randomBytes(32).toString("hex"),
  RUNTIME_DATABASE_PASSWORD: randomBytes(32).toString("hex"),
};
const envFile = path.join(root, "runtime.env");
await writeFile(
  envFile,
  Object.entries(variables)
    .map(([key, value]) => key + "=" + value)
    .join("\n") + "\n",
  { mode: 0o600 },
);
const compose = [
  "compose",
  "--env-file",
  envFile,
  "-f",
  "infra/recovery/compose.yaml",
  "-p",
  project,
];
function dc(args) {
  const result = spawnSync("docker", [...compose, ...args], { stdio: "inherit", timeout: 420000 });
  if (result.error || result.status !== 0)
    throw result.error ?? Error("Recovery command failed: " + args[0]);
}
const tool = (action) =>
  dc(["run", "--rm", "tools", "bundle", "exec", "ruby", "script/disaster_recovery.rb", action]);
try {
  dc(["build", "partner"]);
  dc(["up", "-d", "--wait", "db"]);
  // Wait while attached: compose wait can miss an already-exited short init container.
  dc([
    "up",
    "--no-deps",
    "--abort-on-container-exit",
    "--exit-code-from",
    "storage-init",
    "storage-init",
  ]);
  if (mode === "source") {
    dc(["run", "--rm", "tools", "bundle", "exec", "rails", "db:prepare"]);
    dc(["run", "--rm", "grants"]);
    dc(["up", "-d", "--wait", "partner", "scanner"]);
    dc([
      "run",
      "--rm",
      "tools",
      "bundle",
      "exec",
      "rails",
      "runner",
      'deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+180; loop do; begin; abort "Scanner result" unless Talent::FileScanner.scan("DR readiness") == :clean; break; rescue Talent::FileScanner::Unavailable; abort "Scanner readiness timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline; sleep 2; end; end',
    ]);
    tool("source");
    dc(["stop", "partner"]);
    tool("partner");
  } else {
    tool("authenticate");
    tool("import");
    dc(["run", "--rm", "grants"]);
    dc(["up", "-d", "--wait", "partner"]);
    tool("verify");
    dc(["up", "-d", "api"]);
    const began = Number(process.env.MESH_DR_STARTED_MS);
    assert.ok(Number.isFinite(began));
    let status = 0;
    for (let attempt = 0; attempt < 60; attempt++) {
      try {
        status = (await fetch("http://localhost:3251/ready")).status;
      } catch {}
      if (status === 200) break;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    assert.equal(status, 200);
    const rto = Date.now() - began;
    const restored = JSON.parse(await readFile(path.join(root, "evidence/restored.json"), "utf8"));
    restored.rto_ms = rto;
    restored.rto_target_ms = 900000;
    restored.fresh_runtime_readiness_http = status;
    restored.source_job_finished_before_target_started = true;
    await writeFile(
      path.join(root, "evidence/restored.json"),
      JSON.stringify(restored, null, 2) + "\n",
    );
    assert.ok(rto <= restored.rto_target_ms, "Declared fresh VM RTO exceeded");
  }
} finally {
  dc(["down"]);
}
