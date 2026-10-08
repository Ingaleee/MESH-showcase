import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
await readFile("SHOWCASE.md");
function dc(args) {
  const result = spawnSync("docker", ["compose", ...args], { stdio: "inherit", timeout: 420000 });
  if (result.error || result.status !== 0)
    throw result.error ?? Error("Continuity command failed.");
}
dc(["stop", "api", "worker", "dispatcher"]);
try {
  dc(["run", "--rm", "api", "bin/rails", "db:prepare"]);
  dc([
    "run",
    "--rm",
    "-e",
    "MESH_RECOVERY_QUIESCED=true",
    "-e",
    "MESH_EVIDENCE_DIR=/workspace/" +
      (process.env.MESH_EVIDENCE_DIR ?? ".cache/acceptance-evidence"),
    "api",
    "bundle",
    "exec",
    "ruby",
    "script/publishing_continuity.rb",
  ]);
} finally {
  dc(["up", "-d", "api", "worker", "dispatcher"]);
}
