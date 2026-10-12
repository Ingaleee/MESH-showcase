import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile, access } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
await access("SHOWCASE.md");
assert.ok(process.cwd().endsWith("MESH-showcase"));
const directory = ".cache/kubernetes";
await mkdir(directory, { recursive: true });
function docker(args, input) {
  const result = spawnSync("docker", args, {
    input,
    encoding: "utf8",
    windowsHide: true,
    timeout: 60000,
  });
  if (result.error || result.status !== 0)
    throw (
      result.error ??
      new Error(
        "Isolated database preparation failed: " +
          result.stderr.replace(/[a-f0-9]{96}/g, "[REDACTED]"),
      )
    );
  return result.stdout;
}
const address = docker([
  "inspect",
  "mesh-showcase-db-1",
  "--format",
  '{{(index .NetworkSettings.Networks "mesh-showcase_default").IPAddress}}',
]).trim();
assert.match(address, /^172\.25\.\d{1,3}\.\d{1,3}$/);
const file = path.join(directory, "runtime.env");
let existing;
try {
  existing = await readFile(file, "utf8");
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
const password = existing
  ? /^DATABASE_URL=postgres:\/\/mesh_showcase_kubernetes_runtime:([a-f0-9]+)@/m.exec(existing)?.[1]
  : randomBytes(48).toString("hex");
assert.ok(password);
const secret = existing
  ? /^SECRET_KEY_BASE=(.+)$/m.exec(existing)?.[1]
  : randomBytes(48).toString("hex");
const common = {
  HOME: "/tmp",
  MESH_METRICS_TOKEN: existing
    ? /^MESH_METRICS_TOKEN=(.+)$/m.exec(existing)?.[1]
    : randomBytes(48).toString("hex"),
  MESH_GATEWAY_SECRET:
    (existing && /^MESH_GATEWAY_SECRET=(.+)$/m.exec(existing)?.[1]) ||
    randomBytes(48).toString("hex"),
  MESH_WEBHOOK_SECRET:
    (existing && /^MESH_WEBHOOK_SECRET=(.+)$/m.exec(existing)?.[1]) ||
    randomBytes(48).toString("hex"),
  SECRET_KEY_BASE: secret,
  RAILS_ENV: "production",
  RAILS_LOG_TO_STDOUT: "1",
  BOOTSNAP_CACHE_DIR: "/tmp/bootsnap",
  MESH_PUBLIC_ORIGIN: "https://mesh.example.test",
  MESH_PAYOUTS_ENABLED: "false",
  MESH_PUBLISHING_ENABLED: "false",
};
const urls = (user, pass) => ({
  DATABASE_URL: "postgres://" + user + ":" + pass + "@" + address + ":5432/mesh_kubernetes",
  QUEUE_DATABASE_URL:
    "postgres://" + user + ":" + pass + "@" + address + ":5432/mesh_kubernetes_queue",
});
const save = async (name, values) =>
  writeFile(
    path.join(directory, name),
    Object.entries(values)
      .map(([key, value]) => key + "=" + value)
      .join("\n") + "\n",
    { mode: 0o600 },
  );
await save("runtime.env", {
  ...common,
  ...urls("mesh_showcase_kubernetes_runtime", password),
  MESH_METRICS_TOKEN: existing
    ? /^MESH_METRICS_TOKEN=(.+)$/m.exec(existing)?.[1]
    : randomBytes(48).toString("hex"),
});
await save("migration.env", { ...common, ...urls("mesh", "mesh_development") });
const sql = `DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='mesh_showcase_kubernetes_runtime') THEN
  CREATE ROLE mesh_showcase_kubernetes_runtime LOGIN PASSWORD '${password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
 END IF;
END $$;
SELECT 'CREATE DATABASE mesh_kubernetes OWNER mesh' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='mesh_kubernetes')\\gexec
SELECT 'CREATE DATABASE mesh_kubernetes_queue OWNER mesh' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='mesh_kubernetes_queue')\\gexec
`;
docker(
  [
    "compose",
    "exec",
    "-T",
    "db",
    "psql",
    "-X",
    "-v",
    "ON_ERROR_STOP=1",
    "-U",
    "mesh",
    "-d",
    "postgres",
  ],
  sql,
);
await writeFile(
  path.join(directory, "terraform.tfvars.json"),
  JSON.stringify(
    {
      kubeconfig_path: path.resolve(directory, "config").replaceAll("\\", "/"),
      kube_context: "k3d-mesh-showcase",
      namespace: "mesh-showcase",
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({
    environment: "mesh-showcase local k3d",
    databases: ["mesh_kubernetes", "mesh_kubernetes_queue"],
    role: "mesh_showcase_kubernetes_runtime",
    database_address: address,
    secrets_printed: false,
  }),
);
