import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile, rm } from "node:fs/promises";
import path from "node:path";

const reportDir = path.resolve(process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/showcase-final");
const cache = path.resolve(".cache/trivy");
await mkdir(reportDir, { recursive: true });
await mkdir(cache, { recursive: true });
const manifest = JSON.parse(
  await readFile(process.argv[2] ?? ".cache/deployment/current.json", "utf8"),
);
const scanner =
  "aquasec/trivy@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa";
const report = {
  checked_at: new Date().toISOString(),
  scanner,
  policy: "Report HIGH/CRITICAL including unfixed; reject any finding.",
  images: {},
};
let failed = false;
const allowed = new Set([
  "api",
  "web",
  "partner",
  "postgres",
  "caddy",
  "clamav",
  "prometheus",
  "grafana",
  "alertmanager",
]);
if (!manifest.images?.api || !manifest.images?.web)
  throw new Error("API and web images are required.");
for (const name of Object.keys(manifest.images)) {
  if (!allowed.has(name)) throw new Error("Unrecognized runtime image role.");
  const image = manifest.images?.[name];
  if (
    !/^(sha256:[a-f0-9]{64}|ghcr\.io\/[a-z0-9_.\/-]+@sha256:[a-f0-9]{64}|docker\.io\/library\/caddy@sha256:[a-f0-9]{64})$/.test(
      image ?? "",
    )
  )
    throw new Error("Only immutable release image references can be scanned.");
  const outputFile = path.join(reportDir, `trivy-${name}.json`);
  await rm(outputFile, { force: true });
  const result = spawnSync(
    "docker",
    [
      "run",
      "--rm",
      "--memory=768m",
      "--cpus=1",
      "--mount",
      "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly",
      "--mount",
      `type=bind,source=${cache},target=/root/.cache/trivy`,
      "--mount",
      `type=bind,source=${reportDir},target=/evidence`,
      scanner,
      "image",
      "--scanners",
      "vuln",
      "--quiet",
      "--parallel",
      "1",
      "--timeout",
      "10m",
      "--severity",
      "HIGH,CRITICAL",
      "--exit-code",
      "1",
      "--format",
      "json",
      "--output",
      `/evidence/trivy-${name}.json`,
      image,
    ],
    { stdio: "inherit" },
  );
  if (result.error) throw result.error;
  let rows;
  try {
    rows = JSON.parse(await readFile(outputFile, "utf8"));
  } catch {
    failed = true;
    report.images[name] = {
      image,
      scan_exit_code: result.status,
      findings: null,
      scan_error: "Scanner did not produce a valid report.",
    };
    continue;
  }
  const findings = (rows.Results ?? []).flatMap((row) => row.Vulnerabilities ?? []);
  report.images[name] = {
    image,
    scan_exit_code: result.status,
    findings: findings.length,
    fixable: findings.filter((row) => row.FixedVersion).length,
  };
  failed ||= result.status !== 0;
}
report.success = !failed;
report.scope =
  "Known OS/library vulnerabilities in each explicitly listed immutable runtime image; applicability decisions and signed provenance are separate.";
await writeFile(
  path.join(reportDir, "image-security.json"),
  JSON.stringify(report, null, 2) + "\n",
);
if (failed) throw new Error("Image vulnerability gate failed; review the saved findings.");
console.log("All listed immutable runtime images passed the HIGH/CRITICAL vulnerability gate.");
