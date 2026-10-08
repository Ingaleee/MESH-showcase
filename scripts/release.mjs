import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir, rmdir, access } from "node:fs/promises";
import path from "node:path";
import { atomicJSON, optionalJSON, recoverRelease } from "./release-state.mjs";

const root = process.cwd();
await access(path.join(root, "SHOWCASE.md"));
const state = path.resolve(
  process.env.MESH_DEPLOYMENT_STATE ?? path.join(root, ".cache/deployment"),
);
await mkdir(state, { recursive: true });
const project = "mesh-showcase-release";
const tlsOptions = process.platform === "win32" ? ["--ssl-revoke-best-effort"] : [];
const compose = [
  "compose",
  "--env-file",
  path.join(state, "runtime.env"),
  "-f",
  path.join(root, "infra/deploy/compose.yaml"),
  "-p",
  project,
];
function execute(command, args, { capture = false, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio:
      process.env.MESH_RELEASE_LOCK_FD === "9"
        ? [
            capture ? "pipe" : "inherit",
            capture ? "pipe" : "inherit",
            capture ? "pipe" : "inherit",
            ...Array(6).fill("ignore"),
            9,
          ]
        : capture
          ? "pipe"
          : "inherit",
    maxBuffer: 2 ** 24,
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && !allowFailure)
    throw new Error(`${command} ${args[0]} failed (${result.status}).`);
  return capture ? result.stdout.trim() : result.status;
}
function checkpoint(phase) {
  if (process.env.MESH_RELEASE_FAILPOINT === phase) process.kill(process.pid, "SIGKILL");
}
const docker = (args, options) => execute("docker", args, options);
const dc = (args, options) => docker([...compose, ...args], options);
const imagePattern =
  /^(?:sha256:[a-f0-9]{64}|ghcr\.io\/[a-z0-9_.\/-]+@sha256:[a-f0-9]{64}|docker\.io\/library\/caddy@sha256:[a-f0-9]{64})$/;
function validate(manifest) {
  if (![1, 2].includes(manifest.schema_version) || manifest.project !== project)
    throw new Error("Unexpected release manifest.");
  for (const name of manifest.schema_version === 2
    ? ["api", "web", "postgres", "clamav", "caddy"]
    : ["api", "web"])
    if (!imagePattern.test(manifest.images?.[name] ?? ""))
      throw new Error("Use immutable local image IDs or GHCR digests.");
  return manifest;
}
async function json(file) {
  return JSON.parse(await readFile(file, "utf8"));
}
async function runtime(manifest) {
  const secretFile = path.join(state, "secrets.env");
  const secrets = await readFile(secretFile, "utf8");
  if (
    /^(?:API_IMAGE|WEB_IMAGE|POSTGRES_IMAGE|SCANNER_IMAGE|CADDY_IMAGE|COMPOSE_PROJECT_NAME)=/m.test(
      secrets,
    )
  )
    throw new Error("Release keys cannot be overridden in secrets.");
  await writeFile(
    path.join(state, "runtime.env"),
    secrets +
      "\n" +
      Object.entries({
        API_IMAGE: manifest.images.api,
        WEB_IMAGE: manifest.images.web,
        // Historical v1 rollback preserves the current infrastructure rather than reverting the DB engine.
        POSTGRES_IMAGE:
          manifest.images.postgres ??
          JSON.parse(
            docker(["image", "inspect", "mesh-showcase-postgres:patched"], { capture: true }),
          )[0].Id,
        SCANNER_IMAGE:
          manifest.images.clamav ??
          JSON.parse(
            docker(["image", "inspect", "mesh-showcase-scanner:patched"], { capture: true }),
          )[0].Id,
        CADDY_IMAGE:
          manifest.images.caddy ??
          "docker.io/library/caddy@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f",
        ...(manifest.schema_version === 2
          ? {
              POSTGRES_IMAGE: manifest.images.postgres,
              SCANNER_IMAGE: manifest.images.clamav,
              CADDY_IMAGE: manifest.images.caddy,
            }
          : {}),
      })
        .map(([key, value]) => key + "=" + value)
        .join("\n") +
      "\n",
    { mode: 0o600 },
  );
}
async function smoke(manifest) {
  validate(manifest);
  const secrets = await readFile(path.join(state, "secrets.env"), "utf8");
  const origin = /^MESH_PUBLIC_ORIGIN=(.+)$/m.exec(secrets)?.[1];
  if (!origin || !/^https:\/\/localhost:\d+$/.test(origin))
    throw new Error("This local smoke supports only the loopback HTTPS origin.");
  const ca = path.join(state, "root.crt");
  dc(["cp", "edge:/data/caddy/pki/authorities/local/root.crt", ca]);
  const curl = (endpoint) =>
    execute(
      "curl",
      [
        ...tlsOptions,
        "--silent",
        "--show-error",
        "--fail",
        "--cacert",
        ca,
        "--max-time",
        "15",
        origin + endpoint,
      ],
      { capture: true },
    );
  const session = JSON.parse(curl("/api/v1/session"));
  if (typeof session.csrf_token !== "string") throw new Error("Session smoke failed.");
  const homepage = curl("/");
  if (!homepage.includes("MESH")) throw new Error("Frontend smoke failed.");
  curl("/ready");
  const headers = execute(
    "curl",
    [...tlsOptions, "--silent", "--show-error", "--head", "--cacert", ca, origin + "/"],
    { capture: true },
  );
  if (!/content-security-policy:/i.test(headers) || headers.includes("'unsafe-eval'"))
    throw new Error("Production CSP smoke failed.");
  const privateStatus = execute(
    "curl",
    [
      ...tlsOptions,
      "--silent",
      "--cacert",
      ca,
      "--output",
      process.platform === "win32" ? "NUL" : "/dev/null",
      "--write-out",
      "%{http_code}",
      origin + "/internal/metrics",
    ],
    { capture: true },
  );
  if (privateStatus !== "404") throw new Error("Internal metrics leaked through edge.");
  const ids = dc(["ps", "-q"], { capture: true }).split(/\s+/).filter(Boolean);
  const containers = JSON.parse(docker(["inspect", ...ids], { capture: true }));
  const running = containers.filter((row) => row.State.Running);
  const required = ["db", "api", "web", "worker", "dispatcher", "gateway", "scanner", "edge"];
  for (const service of required)
    if (!running.some((row) => row.Config.Labels["com.docker.compose.service"] === service))
      throw new Error(`Release service is not running: ${service}`);
  for (const row of running) {
    const service = row.Config.Labels["com.docker.compose.service"];
    const expected = {
      web: manifest.images.web,
      api: manifest.images.api,
      worker: manifest.images.api,
      dispatcher: manifest.images.api,
      gateway: manifest.images.api,
      db: manifest.images.postgres,
      scanner: manifest.images.clamav,
      edge: manifest.images.caddy,
    }[service];
    if (expected && row.Config.Image !== expected)
      throw new Error(`Running image differs from release manifest: ${service}`);
    const bindings = Object.values(row.HostConfig.PortBindings ?? {})
      .flat()
      .filter(Boolean);
    if (service !== "edge" && bindings.length)
      throw new Error(`Unexpected public port: ${service}`);
    if (service === "edge" && (bindings.length !== 1 || bindings[0].HostIp !== "127.0.0.1"))
      throw new Error("Edge port is not isolated.");
    if (
      ["api", "web", "worker", "dispatcher", "gateway", "edge"].includes(service) &&
      (!row.HostConfig.ReadonlyRootfs || !row.Config.User || row.Config.User.startsWith("0"))
    )
      throw new Error(`Runtime hardening failed: ${service}`);
  }
  const privileges = dc(
    [
      "exec",
      "-T",
      "db",
      "psql",
      "-U",
      "mesh_owner",
      "-d",
      "mesh_production",
      "-Atc",
      "SELECT rolsuper, rolcreatedb, rolcreaterole, has_schema_privilege('mesh_runtime','public','CREATE') FROM pg_roles WHERE rolname='mesh_runtime'",
    ],
    { capture: true },
  );
  if (privileges !== "f|f|f|f") throw new Error("Runtime database role is too powerful.");
  return {
    origin,
    ca_trusted_by_smoke_only: true,
    session: true,
    frontend: true,
    csp: true,
    internal_metrics_blocked: true,
    database_runtime_role_restricted: true,
    containers: running.map((row) => ({
      service: row.Config.Labels["com.docker.compose.service"],
      image_id: row.Image,
      image_reference: row.Config.Image,
      user: row.Config.User,
      readonly: row.HostConfig.ReadonlyRootfs,
      memory_limit_bytes: row.HostConfig.Memory,
      stop_timeout: row.Config.StopTimeout,
    })),
  };
}
async function apply(manifest, migrate) {
  await runtime(manifest);
  checkpoint("runtime");
  dc(["up", "-d", "db", "storage-init"]);
  if (migrate) {
    dc(["run", "--rm", "migrate"]);
    dc(["run", "--rm", "grants"]);
  }
  dc([
    "up",
    "-d",
    "--wait",
    "--wait-timeout",
    "300",
    "gateway",
    "scanner",
    "api",
    "web",
    "worker",
    "dispatcher",
    "edge",
  ]);
  return smoke(manifest);
}
async function sourceHash() {
  const files = execute("git", ["ls-files", "--cached", "--others", "--exclude-standard"], {
    capture: true,
  })
    .split("\n")
    .filter((file) => file && !file.startsWith("docs/evidence/"))
    .sort();
  const hash = createHash("sha256");
  for (const file of files) hash.update(file + "\0").update(await readFile(path.join(root, file)));
  return hash.digest("hex");
}

const [operation, file, api, web] = process.argv.slice(2);
if (operation === "manifest") {
  if (!file || !api || !web) throw new Error("manifest FILE API_TAG WEB_TAG");
  const images = {};
  for (const [name, tag] of Object.entries({
    api,
    web,
    postgres: "mesh-showcase-postgres:patched",
    clamav: "mesh-showcase-scanner:patched",
    caddy: "caddy:2.11.7-alpine",
  }))
    images[name] = JSON.parse(docker(["image", "inspect", tag], { capture: true }))[0].Id;
  const revision =
    execute("git", ["rev-parse", "--verify", "HEAD"], { capture: true, allowFailure: true }) ||
    null;
  const manifest = validate({
    schema_version: 2,
    project,
    created_at: new Date().toISOString(),
    revision,
    source_tree_sha256: await sourceHash(),
    working_tree_dirty: Boolean(execute("git", ["status", "--porcelain"], { capture: true })),
    images,
    schema_rollback: "Never automatic; use backward-compatible migrations.",
  });
  await mkdir(path.dirname(path.resolve(file)), { recursive: true });
  await writeFile(file, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Release manifest written: ${file}`);
} else if (operation === "deploy" || operation === "rollback") {
  // Linux deployments must enter through release.sh. Windows retains its conservative directory lock.
  if (process.platform !== "win32" && process.env.MESH_RELEASE_LOCK_FD !== "9")
    throw new Error("Use bash scripts/release.sh for Linux deployment locking.");
  const lock = path.join(state, "lock");
  if (process.platform === "win32") await mkdir(lock);
  const current = path.join(state, "current.json");
  const journal = path.join(state, "journal.json");
  const report = {
    checked_at: new Date().toISOString(),
    operation,
    environment: project,
    success: false,
    migration_reverted: false,
  };
  let previous;
  try {
    report.interrupted_recovery = await recoverRelease(state, apply, validate);
    previous = await optionalJSON(current);
    if (previous) validate(previous);
    const target = validate(
      await json(operation === "rollback" ? path.join(state, "previous.json") : file),
    );
    if (operation === "deploy" && target.schema_version !== 2)
      throw new Error("New deployments require the complete v2 runtime inventory.");
    report.release = target;
    const intent = {
      phase: "applying",
      operation,
      baseline: previous,
      target,
      started_at: new Date().toISOString(),
    };
    await atomicJSON(journal, intent);
    try {
      report.smoke = await apply(target, operation === "deploy");
      await atomicJSON(journal, { ...intent, phase: "verified" });
      checkpoint("verified");
      if (previous) await atomicJSON(path.join(state, "previous.json"), previous);
      await atomicJSON(current, target);
      checkpoint("current");
      await atomicJSON(journal, { ...intent, phase: "committed" });
      report.success = true;
    } catch (error) {
      report.failure = error.message;
      await atomicJSON(journal, { ...intent, phase: "rolling_back", failure: error.message });
      if (previous) {
        report.rollback_smoke = await apply(previous, false);
        await atomicJSON(current, previous);
        report.previous_release_restored = true;
        await atomicJSON(journal, { ...intent, phase: "recovered" });
      }
      throw error;
    }
  } catch (error) {
    report.failure = error.message;
    throw error;
  } finally {
    const evidence = path.resolve(
      process.env.MESH_EVIDENCE_DIR ?? path.join(root, "docs/evidence"),
    );
    await atomicJSON(path.join(evidence, `deployment-${Date.now()}.json`), report);
    if (process.platform === "win32") await rmdir(lock);
  }
} else if (operation === "smoke") {
  console.log(
    JSON.stringify(await smoke(validate(await json(path.join(state, "current.json")))), null, 2),
  );
} else {
  throw new Error("Use manifest, deploy, rollback or smoke.");
}
