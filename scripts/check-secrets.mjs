import { spawnSync } from "node:child_process";
import { cp, mkdir, mkdtemp, rm, lstat, appendFile, readFile } from "node:fs/promises";
import path from "node:path";
import { randomBytes } from "node:crypto";

const root = process.cwd();
const base = path.join(root, ".cache/security");
await mkdir(base, { recursive: true });
const snapshot = await mkdtemp(path.join(base, "source-"));
const evidence = path.resolve(process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/showcase-final");
await mkdir(evidence, { recursive: true });
const scanner =
  "ghcr.io/gitleaks/gitleaks@sha256:cdbb7c955abce02001a9f6c9f602fb195b7fadc1e812065883f695d1eeaba854";
try {
  const listing = spawnSync(
    "git",
    ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
    { encoding: "utf8" },
  );
  if (listing.status !== 0) throw new Error("Cannot inventory publishable Git files.");
  const files = [...new Set(listing.stdout.split("\0").filter(Boolean))];
  for (const file of files) {
    const source = path.resolve(root, file);
    if (!source.startsWith(root + path.sep) || !(await lstat(source)).isFile())
      throw new Error("Refusing a path outside the source tree or a non-regular file.");
    const target = path.join(snapshot, file);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(source, target);
  }
  // A credential-shaped canary in an allowlisted report must still be detected.
  const probeFile = "docs/evidence/backend-hardening/verification.json";
  await appendFile(
    path.join(snapshot, probeFile),
    `\n"api_key": "${randomBytes(24).toString("base64url")}"\n`,
  );
  const probe = spawnSync(
    "docker",
    [
      "run",
      "--rm",
      "--memory=256m",
      "--mount",
      `type=bind,source=${snapshot},target=/source,readonly`,
      "--mount",
      `type=bind,source=${evidence},target=/evidence`,
      scanner,
      "dir",
      "--config",
      "/source/.gitleaks.toml",
      "/source",
      "--no-banner",
      "--redact=100",
      "--report-format",
      "json",
      "--report-path",
      "/evidence/gitleaks-canary.json",
    ],
    { stdio: "inherit" },
  );
  if (probe.error) throw probe.error;
  const findings = JSON.parse(await readFile(path.join(evidence, "gitleaks-canary.json"), "utf8"));
  if (
    probe.status !== 1 ||
    !findings.some((row) => row.File.endsWith(probeFile) && row.RuleID === "generic-api-key")
  )
    throw new Error("Secret scanner failed its canary check.");
  await cp(path.join(root, probeFile), path.join(snapshot, probeFile));
  const result = spawnSync(
    "docker",
    [
      "run",
      "--rm",
      "--memory=256m",
      "--mount",
      `type=bind,source=${snapshot},target=/source,readonly`,
      "--mount",
      `type=bind,source=${evidence},target=/evidence`,
      scanner,
      "dir",
      "--config",
      "/source/.gitleaks.toml",
      "/source",
      "--no-banner",
      "--redact=100",
      "--report-format",
      "json",
      "--report-path",
      "/evidence/gitleaks.json",
    ],
    { stdio: "inherit" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0)
    throw new Error("Publishable source secret scan failed; inspect the redacted report.");
  console.log(
    `Secret scan passed for ${files.length} publishable files. Ignored runtime data and Git history are outside this scope.`,
  );
} finally {
  if (!path.resolve(snapshot).startsWith(path.resolve(base) + path.sep))
    throw new Error("Refusing cleanup outside the temporary scanner directory.");
  await rm(snapshot, { recursive: true, force: true });
}
