import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

function docker(args) {
  const result = spawnSync("docker", args, { encoding: "utf8", timeout: 30000 });
  assert.equal(result.status, 0, result.stderr || "Docker command failed.");
  return result.stdout.trim();
}
const container = docker(["compose", "ps", "-q", "api"]);
assert.match(container, /^[a-f0-9]{12,64}$/);
const name = docker(["inspect", "--format", "{{.Name}}", container]);
assert.match(name, /^\/mesh-showcase(?:-ci-[0-9]+)?-api-1$/);
const command = JSON.parse(docker(["inspect", "--format", "{{json .Config.Cmd}}", container]));
assert.ok(command.includes("--pid") && command[command.indexOf("--pid") + 1] === "/dev/null");

const started = Date.now();
docker(["compose", "kill", "-s", "SIGKILL", "api"]);
docker(["compose", "start", "api"]);
const base = process.env.MESH_BASE_URL ?? "http://localhost:3200";
let ready = false;
for (let attempt = 0; attempt < 30; attempt++) {
  try {
    const response = await fetch(base + "/api/v1/session", {
      signal: AbortSignal.timeout(2000),
    });
    if (response.ok) {
      ready = true;
      break;
    }
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 1000));
}
assert.ok(ready, "API did not recover after an abrupt stop.");
const evidence = process.env.MESH_EVIDENCE_DIR ?? ".cache/acceptance-evidence";
await mkdir(evidence, { recursive: true });
const report = {
  checked_at: new Date().toISOString(),
  container: name,
  abrupt_signal: "SIGKILL",
  pidfile: "/dev/null",
  recovered: ready,
  elapsed_seconds: (Date.now() - started) / 1000,
  scope: "One development API container; databases, files and other services stay running.",
};
await writeFile(path.join(evidence, "api-restart.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report));
