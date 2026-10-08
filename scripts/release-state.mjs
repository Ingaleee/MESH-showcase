import { open, rename, mkdir, readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import path from "node:path";

export async function atomicJSON(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = file + "." + randomUUID() + ".tmp";
  const handle = await open(temporary, "wx", 0o600);
  try {
    await handle.writeFile(JSON.stringify(value, null, 2) + "\n");
    await handle.sync();
  } finally {
    await handle.close();
  }
  await rename(temporary, file);
  if (process.platform !== "win32") {
    const directory = await open(path.dirname(file), "r");
    try {
      await directory.sync();
    } finally {
      await directory.close();
    }
  }
}

export async function optionalJSON(file) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

// The caller holds the OS lock throughout this function and all child processes.
export async function recoverRelease(state, apply, validate) {
  const journalFile = path.join(state, "journal.json");
  const journal = await optionalJSON(journalFile);
  if (!journal) return null;
  if (
    !["applying", "verified", "rolling_back", "committed", "recovered", "rejected"].includes(
      journal.phase,
    )
  )
    throw new Error("Unknown release journal phase; refuse automatic recovery.");
  if (["committed", "recovered", "rejected"].includes(journal.phase)) return null;
  const target = validate(journal.baseline ?? journal.target);
  const smoke = await apply(target, !journal.baseline);
  await atomicJSON(path.join(state, "current.json"), target);
  const recovery = {
    ...journal,
    phase: "recovered",
    recovered_at: new Date().toISOString(),
    recovered_to_baseline: Boolean(journal.baseline),
    recovery_smoke: smoke,
  };
  await atomicJSON(journalFile, recovery);
  return recovery;
}
