import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";

await mkdir(".cache/tla", { recursive: true });
let jar;
try {
  jar = await readFile(".cache/tla/tla2tools.jar");
} catch {
  const response = await fetch(
    "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar",
  );
  if (!response.ok) throw new Error(`TLC download failed: ${response.status}`);
  jar = Buffer.from(await response.arrayBuffer());
  await writeFile(".cache/tla/tla2tools.jar", jar);
}
if (createHash("sha1").update(jar).digest("hex") !== "bee4a54f3ee3d4afc347c3240ec2d9e93b075104")
  throw new Error("TLC checksum mismatch.");
const result = spawnSync(
  "docker",
  [
    "run",
    "--rm",
    "--memory=384m",
    "-v",
    `${process.cwd()}:/workspace`,
    "-w",
    "/workspace/specs",
    "eclipse-temurin:21-jre-alpine@sha256:51ab5e3302e7141ce665ca3ea85e8b5cd648eafbc3c0c90dd79d6537684e4555",
    "java",
    "-Xmx256m",
    "-XX:+UseParallelGC",
    "-cp",
    "/workspace/.cache/tla/tla2tools.jar",
    "tlc2.TLC",
    "-workers",
    "1",
    "-metadir",
    "/workspace/.cache/tla/states",
    "PayoutRecovery",
  ],
  { encoding: "utf8", maxBuffer: 2 ** 22 },
);
const evidence = process.env.MESH_EVIDENCE_DIR ?? "docs/evidence";
await mkdir(evidence, { recursive: true });
await writeFile(path.join(evidence, "tlc.txt"), result.stdout + result.stderr);
console.log(result.stdout);
if (result.status !== 0) throw new Error(result.stderr || "TLC failed.");
