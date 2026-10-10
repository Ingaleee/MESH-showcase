import { spawn } from "node:child_process";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import path from "node:path";
import assert from "node:assert/strict";
const root = process.cwd();
assert.ok(root.endsWith("MESH-showcase"), "Run only from the independent showcase checkout.");
await access("SHOWCASE.md");
const evidence = ".cache/interview-demo/" + new Date().toISOString().replaceAll(":", "-");
await mkdir(evidence, { recursive: true });
const stages = [];
async function run(name, program, args, extra = {}) {
  console.log("\n" + name);
  const start = Date.now();
  let stdout = "",
    stderr = "";
  const child = spawn(program, args, {
    cwd: root,
    windowsHide: true,
    env: { ...process.env, ...extra },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (data) => {
    stdout += data;
    process.stdout.write(data);
  });
  child.stderr.on("data", (data) => {
    stderr += data;
    process.stderr.write(data);
  });
  const status = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code));
  });
  stages.push({ name, exit_code: status, elapsed_seconds: (Date.now() - start) / 1000 });
  await writeFile(path.join(evidence, "stages.json"), JSON.stringify(stages, null, 2) + "\n");
  if (status !== 0) throw new Error(name + " failed; stages are saved at " + evidence);
  return stdout;
}
try {
  await access(".env");
} catch {
  const env = {
    SECRET_KEY_BASE: randomBytes(48).toString("hex"),
    MESH_GATEWAY_SECRET: randomBytes(48).toString("hex"),
    MESH_WEBHOOK_SECRET: randomBytes(48).toString("hex"),
    MESH_METRICS_TOKEN: randomBytes(48).toString("hex"),
    MESH_PAYOUTS_ENABLED: "true",
    MESH_SCAN_FILES: "true",
    MESH_WEB_PORT: "3200",
    MESH_API_PORT: "3201",
    MESH_GATEWAY_PORT: "3202",
  };
  await writeFile(
    ".env",
    Object.entries(env)
      .map(([key, value]) => key + "=" + value)
      .join("\n") + "\n",
    { flag: "wx", mode: 0o600 },
  );
}
const node = process.execPath;
await run("Docker readiness", "docker", ["info", "--format", "{{.OSType}}/{{.Architecture}}"]);
await run("Preserve and prepare partner credentials", node, ["scripts/prepare-publishing.mjs"]);
const config = await readFile(".env", "utf8");
assert.ok(
  !/^COMPOSE_PROJECT_NAME=(?!mesh-showcase$)/m.test(config),
  "Only the mesh-showcase project is permitted.",
);
assert.ok(
  !process.env.COMPOSE_PROJECT_NAME || process.env.COMPOSE_PROJECT_NAME === "mesh-showcase",
);
assert.ok(
  !process.env.COMPOSE_FILE && !process.env.COMPOSE_ENV_FILES,
  "Demo uses the verified local compose.yaml and .env.",
);
const npmProgram = process.platform === "win32" ? node : "npm";
const npmPrefix =
  process.platform === "win32"
    ? [path.join(path.dirname(node), "node_modules", "npm", "bin", "npm-cli.js")]
    : [];
await run("Locked host dependencies", npmProgram, [
  ...npmPrefix,
  "ci",
  "--ignore-scripts",
  "--registry=https://registry.npmjs.org",
]);
await run("Build Ruby development environment", "docker", [
  "compose",
  "-f",
  "compose.yaml",
  "--profile",
  "files",
  "build",
  "api",
  "db",
  "scanner",
]);
await run("Start isolated PostgreSQL and real scanner", "docker", [
  "compose",
  "-f",
  "compose.yaml",
  "--profile",
  "files",
  "up",
  "-d",
  "db",
  "scanner",
]);
await run("Install locked Ruby dependencies", "docker", [
  "compose",
  "run",
  "--rm",
  "api",
  "bundle",
  "install",
  "--jobs",
  "4",
]);
await run("Apply showcase migrations", "docker", [
  "compose",
  "run",
  "--rm",
  "api",
  "bin/rails",
  "db:prepare",
]);
await run("Prepare repeatable synthetic accounts and projects", "docker", [
  "compose",
  "run",
  "--rm",
  "api",
  "bin/rails",
  "db:seed",
]);
await run("Build independent partner", "docker", [
  "compose",
  "--profile",
  "publishing",
  "build",
  "partner",
]);
await run("Build production frontend", "docker", [
  "build",
  "-f",
  "infra/Dockerfile.web",
  "-t",
  "mesh-showcase-web:demo",
  ".",
]);
const image = (
  await run("Record immutable preview image", "docker", [
    "image",
    "inspect",
    "mesh-showcase-web:demo",
    "--format",
    "{{.Id}}",
  ])
).trim();
assert.match(image, /^sha256:[a-f0-9]{64}$/);
const runtime = { MESH_PREVIEW_WEB_IMAGE: image, MESH_INTERVIEW_DEMO: "true" };
await run(
  "Start bounded preview and ordinary workers",
  "docker",
  [
    "compose",
    "-f",
    "compose.yaml",
    "-f",
    "infra/preview/compose.yaml",
    "--profile",
    "publishing",
    "--profile",
    "files",
    "up",
    "-d",
    "--no-build",
    "api",
    "gateway",
    "worker",
    "dispatcher",
    "partner",
    "web",
    "edge",
  ],
  runtime,
);
const deadline = Date.now() + 90000;
while (true) {
  try {
    const response = await fetch("http://localhost:3200/ready", {
      signal: AbortSignal.timeout(5000),
    });
    if (response.ok) break;
  } catch {}
  if (Date.now() >= deadline) throw new Error("Showcase readiness did not recover.");
  await new Promise((resolve) => setTimeout(resolve, 1000));
}
await run("Real scanner readiness", "docker", [
  "compose",
  "exec",
  "-T",
  "api",
  "bundle",
  "exec",
  "rails",
  "runner",
  'deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+180; loop do; begin; raise "scanner result" unless Talent::FileScanner.scan("MESH readiness probe")==:clean; break; rescue Talent::FileScanner::Unavailable; raise "scanner unavailable" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline; sleep 2; end; end',
]);
await run("Provision real telemetry", node, ["scripts/prepare-telemetry.mjs"]);
await run("Start dashboard and authenticated internal alerts", "docker", [
  "compose",
  "--env-file",
  ".cache/telemetry/runtime.env",
  "-f",
  "infra/telemetry/compose.yaml",
  "up",
  "-d",
  "--build",
]);
await run(
  "Partner validation, uncertain outcome, lookup and rollback",
  node,
  ["scripts/run-publishing-demo.mjs"],
  { MESH_EVIDENCE_DIR: evidence },
);
await run(
  "Market workflow and Publishing browser checks",
  node,
  ["node_modules/@playwright/test/cli.js", "test", "marketplace.spec.ts", "publishing.spec.ts"],
  { MESH_EVIDENCE_DIR: evidence, MESH_DEMO_MARKETPLACE_ONLY: "true" },
);
console.log(
  "\nReady: http://localhost:3200/publishing\nDashboard: http://localhost:32092/d/mesh-reliability\nIncident: node scripts/run-showcase-incident.mjs\nEvidence: " +
    evidence,
);
await writeFile(
  path.join(evidence, "summary.json"),
  JSON.stringify(
    {
      success: true,
      checked_at: new Date().toISOString(),
      environment: "mesh-showcase local preview",
      frontend_image: image,
      stages,
      mutates_synthetic_data_only: true,
      resets_or_deletes_data: false,
      scope:
        "Repeatable local preparation and actual browser/partner flows. Image security release authorization, external GitHub runs and cluster exercises are separate.",
    },
    null,
    2,
  ) + "\n",
);
