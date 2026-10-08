import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
await readFile("SHOWCASE.md");
const directory = path.resolve(process.argv[2] ?? ".cache/acceptance-evidence");
const destination = path.resolve(process.argv[3] ?? "docs/evidence/acceptance-oct08");
const source = [
  ["publishing-history-before.json", "Historical page before order index", "sql_ruby_read"],
  ["publishing-history-benchmark.json", "50k page after order index", "sql_ruby_read"],
  [
    "telemetry-retention.json",
    "Historical sample, silences and receipt restart",
    "same_host_restart",
  ],
  [
    "publishing-continuity.json",
    "Primary, queue and private bytes restore",
    "same_host_quiescent_restore",
  ],
  [
    "worker-incident/summary.json",
    "Worker outage, delivered firing/resolved and replay",
    "same_host_incident",
  ],
];
const records = [];
for (const [file, claim, scope] of source) {
  const bytes = await readFile(path.join(directory, file));
  const report = JSON.parse(bytes);
  if (!report.checked_at && !report.timestamp)
    throw Error("Report lacks an execution timestamp: " + file);
  // Operator recovery locations are local configuration, not publishable evidence.
  delete report.backup_key_path;
  delete report.encrypted_backup_path;
  const relative = file.replaceAll("/", "-");
  const sanitized = JSON.stringify(report, null, 2) + "\n";
  await mkdir(destination, { recursive: true });
  await writeFile(path.join(destination, relative), sanitized);
  records.push({
    file: relative,
    claim,
    scope,
    checked_at: report.checked_at ?? report.timestamp,
    sha256: createHash("sha256").update(sanitized).digest("hex"),
  });
}
const git = (args) => {
  const r = spawnSync("git", args, { encoding: "utf8" });
  if (r.status !== 0) throw Error("Git context unavailable");
  return r.stdout.trim();
};
const record = {
  schema_version: 1,
  recorded_at: new Date().toISOString(),
  recorded_revision: git(["rev-parse", "HEAD"]),
  working_tree_dirty: Boolean(git(["status", "--porcelain"])),
  records,
  limitations: [
    "Local exercises share the physical host.",
    "SQL read measurements do not define HTTP capacity.",
    "Encrypted backup key custody and whole-VM/offsite restoration require separate acceptance.",
    "The manifest hashes detect report changes; they are not a signature or independent review.",
  ],
};
await writeFile(path.join(destination, "manifest.json"), JSON.stringify(record, null, 2) + "\n");
console.log("Sanitized evidence manifest recorded: " + destination);
