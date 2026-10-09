import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

await readFile("SHOWCASE.md");
assert.equal(path.basename(process.cwd()), "MESH-showcase");
const suffix = randomUUID();
const peer = "mesh-support-" + suffix;
const volume = peer + "-data";
const oldToken = randomBytes(48).toString("hex");
const newToken = randomBytes(48).toString("hex");
const directory = path.resolve(process.env.MESH_EVIDENCE_DIR ?? ".cache/partner-support");
const report = {
  schema_version: 1,
  checked_at: new Date().toISOString(),
  phases: {},
  scope:
    "Disposable independent Node/SQLite peer on the showcase network; real authenticated HTTP, real ClamAV and Rails use cases on mesh_test. Callback HMAC/replay uses the real Rails Rack endpoint in-process. Lease expiry is controlled clock injection, not a claim of SIGKILL coverage. No external studio, main MESH or existing partner volume is changed.",
};
let activePhase = "setup";
let containerCreated = false;
let volumeCreated = false;
function command(args, { token, input, timeout = 30_000 } = {}) {
  const run = spawnSync("docker", args, {
    encoding: "utf8",
    windowsHide: true,
    timeout,
    maxBuffer: 2 ** 22,
    input,
    env: token ? { ...process.env, MESH_PARTNER_TOKEN_SHOWCASE: token } : process.env,
  });
  if (run.error || run.status !== 0) {
    const error = new Error("Support drill Docker command failed in " + activePhase);
    error.cause = run.error?.code ?? "exit-" + run.status;
    process.stderr.write(
      (run.stderr ?? "")
        .replaceAll(oldToken, "[REDACTED]")
        .replaceAll(newToken, "[REDACTED]")
        .slice(-8000),
    );
    // Do not persist general process output: Ruby/Docker logs are not a support export.
    throw error;
  }
  return run.stdout;
}
const config = JSON.parse(
  command(["compose", "--profile", "publishing", "config", "--format", "json"]),
);
assert.match(config.name, /^mesh-showcase(?:-[a-z0-9-]+)?$/);
report.project = config.name;
const api = command(["compose", "ps", "-q", "api"]).trim();
assert.match(api, /^[a-f0-9]{12,64}$/);
const inspection = JSON.parse(command(["inspect", api]))[0];
assert.equal(inspection.Config.Labels["com.docker.compose.project"], config.name);
const network = Object.keys(inspection.NetworkSettings.Networks).find(
  (name) => name === config.name + "_default",
);
assert.ok(network, "API must belong to its isolated default network.");
const image = config.services.partner.image;
assert.equal(typeof image, "string");
report.runtime = {
  api_image: inspection.Image,
  peer_image: JSON.parse(command(["image", "inspect", image]))[0].Id,
};
function git(args) {
  const run = spawnSync("git", args, { encoding: "utf8", windowsHide: true });
  assert.ok(!run.error && run.status === 0, "Cannot identify support source revision.");
  return run.stdout.trim();
}
report.revision = git(["rev-parse", "HEAD"]);
assert.match(report.revision, /^[a-f0-9]{40}$/);
report.dirty_source = Boolean(git(["status", "--porcelain"]));
report.source_hashes = {};
for (const file of [
  "apps/api/script/partner_support_drill.rb",
  "apps/api/packs/publishing/app/services/publishing/deployment_diagnostic.rb",
  "apps/partner/src/server.ts",
  "apps/api/packs/publishing/app/services/publishing/settings.rb",
  "apps/api/packs/publishing/app/domain/publishing/domain/deployment_rules.rb",
  "apps/api/packs/publishing/app/services/publishing/apply_observation.rb",
  "apps/api/packs/publishing/app/infrastructure/publishing/infrastructure/deployment_partner.rb",
  "scripts/run-partner-support-drill.mjs",
]) {
  report.source_hashes[file] = createHash("sha256")
    .update(await readFile(file))
    .digest("hex");
}
async function start(token) {
  command(
    [
      "run",
      "-d",
      "--name",
      peer,
      "--network",
      network,
      "--label",
      "mesh.support=" + suffix,
      "--env",
      "MESH_PARTNER_TOKEN_SHOWCASE",
      "--env",
      "MESH_PUBLISHING_FAILPOINTS=true",
      "--env",
      "MESH_PARTNER_CALLBACK_ORIGIN=http://127.0.0.1:9",
      "--volume",
      volume + ":/data",
      "--read-only",
      "--tmpfs",
      "/tmp:uid=1000,gid=1000,mode=1777",
      "--cap-drop",
      "ALL",
      "--security-opt",
      "no-new-privileges:true",
      "--memory",
      "128m",
      "--pids-limit",
      "64",
      image,
    ],
    { token },
  );
  containerCreated = true;
  const deadline = Date.now() + 30_000;
  for (;;) {
    const probe = spawnSync(
      "docker",
      [
        "exec",
        peer,
        "node",
        "-e",
        "fetch('http://127.0.0.1:3216/health',{signal:AbortSignal.timeout(2000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))",
      ],
      { encoding: "utf8", windowsHide: true, timeout: 5_000 },
    );
    if (!probe.error && probe.status === 0) break;
    assert.ok(Date.now() < deadline, "Disposable peer readiness expired.");
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}
function removePeer() {
  if (!containerCreated) return;
  const row = JSON.parse(command(["inspect", peer]))[0];
  assert.equal(row.Config.Labels["mesh.support"], suffix, "Refuse to remove another container.");
  command(["rm", "-f", peer]);
  containerCreated = false;
}
function phase(name, token, extra = {}) {
  activePhase = name;
  const output = command(
    [
      "compose",
      "exec",
      "-T",
      "-e",
      "RAILS_ENV=test",
      "api",
      "bundle",
      "exec",
      "rails",
      "runner",
      "script/partner_support_drill.rb",
    ],
    {
      input: JSON.stringify({ phase: name, origin: "http://" + peer + ":3216", token, ...extra }),
      timeout: 180_000,
    },
  );
  const marker = "MESH_SUPPORT_REPORT=";
  const line = output.split("\n").find((value) => value.startsWith(marker));
  assert.ok(line, "Missing support phase report.");
  const result = JSON.parse(line.slice(marker.length));
  assert.equal(result.success, true);
  assert.equal(result.phase, name);
  report.phases[name] = result;
  return result;
}
try {
  command(["volume", "create", "--label", "mesh.support=" + suffix, volume]);
  volumeCreated = true;
  await start(oldToken);
  const first = phase("prepare", oldToken);
  removePeer();
  await start(newToken);
  const rotated = phase("rotated", newToken, {
    operation_id: first.operation_id,
    old_token: oldToken,
  });
  removePeer();
  phase("unavailable", newToken, { uncertain_operation_id: rotated.uncertain_operation_id });
  await start(newToken);
  const absent = phase("absent", newToken, {
    uncertain_operation_id: rotated.uncertain_operation_id,
  });
  assert.equal(absent.remote_posts, 1);
  assert.equal(absent.remote_effects, 1);
  report.success = true;
} catch (error) {
  report.success = false;
  report.failure = { phase: activePhase, error_class: error.name, message: error.message };
  process.exitCode = 1;
} finally {
  try {
    removePeer();
    if (volumeCreated) {
      const row = JSON.parse(command(["volume", "inspect", volume]))[0];
      assert.equal(row.Labels["mesh.support"], suffix, "Refuse to remove another volume.");
      command(["volume", "rm", volume]);
      volumeCreated = false;
    }
    report.disposable_resources_removed = true;
  } catch (error) {
    report.success = false;
    report.disposable_resources_removed = false;
    report.cleanup_error = error.name;
    process.exitCode = 1;
  }
  await mkdir(directory, { recursive: true });
  const serialized = JSON.stringify(report, null, 2) + "\n";
  assert.ok(
    !serialized.includes(oldToken) && !serialized.includes(newToken),
    "Refuse a credential-bearing report.",
  );
  await writeFile(path.join(directory, "partner-support.json"), serialized);
  console.log(
    JSON.stringify(
      {
        success: report.success,
        phases: Object.keys(report.phases),
        failure: report.failure,
        disposable_resources_removed: report.disposable_resources_removed,
        report: path.join(directory, "partner-support.json"),
      },
      null,
      2,
    ),
  );
}
