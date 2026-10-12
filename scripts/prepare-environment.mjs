import { randomBytes } from "node:crypto";
import { mkdir, writeFile, access } from "node:fs/promises";
import path from "node:path";

const mode = process.argv[2];
if (!["ci", "deployment"].includes(mode)) throw new Error("Use ci or deployment.");
await access("SHOWCASE.md");
const destination = path.resolve(
  process.argv[3] ??
    (mode === "ci"
      ? ".env.ci"
      : path.join(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment", "secrets.env")),
);
const allowed =
  mode === "ci"
    ? path.resolve(".env.ci")
    : path.resolve(process.env.MESH_DEPLOYMENT_STATE ?? ".cache/deployment", "secrets.env");
if (destination !== allowed) throw new Error("Unexpected environment target.");
const secret = () => randomBytes(48).toString("hex");
const common = {
  SECRET_KEY_BASE: secret(),
  MESH_GATEWAY_SECRET: secret(),
  MESH_WEBHOOK_SECRET: secret(),
  MESH_METRICS_TOKEN: secret(),
};
const values =
  mode === "ci"
    ? {
        ...common,
        COMPOSE_PROJECT_NAME: `mesh-showcase-ci-${process.env.GITHUB_RUN_ID ?? "local"}`,
        MESH_SESSION_COOKIE: "_mesh_showcase_ci_session",
        MESH_WEB_PORT: "3300",
        MESH_API_PORT: "3301",
        MESH_GATEWAY_PORT: "3302",
        MESH_PARTNER_PORT: "3303",
        MESH_PAYOUTS_ENABLED: "true",
        MESH_SCAN_FILES: "true",
      }
    : {
        ...common,
        POSTGRES_PASSWORD: secret(),
        RUNTIME_DATABASE_PASSWORD: secret(),
        MESH_PUBLIC_ORIGIN: "https://localhost:3243",
        MESH_HTTPS_PORT: "3243",
        MESH_PAYOUTS_ENABLED: "false",
        MESH_SCAN_FILES: "true",
      };
if (!/^[a-z0-9-]+$/.test(values.COMPOSE_PROJECT_NAME ?? "deployment"))
  throw new Error("Invalid project name.");
await mkdir(path.dirname(destination), { recursive: true });
await writeFile(
  destination,
  Object.entries(values)
    .map(([key, value]) => `${key}=${value}`)
    .join("\n") + "\n",
  { flag: "wx", mode: 0o600 },
);
console.log(`Created ${path.relative(process.cwd(), destination)} with fresh local secrets.`);
