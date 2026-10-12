import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile, cp, rm } from "node:fs/promises";
import path from "node:path";
import { performance } from "node:perf_hooks";
import { randomBytes } from "node:crypto";

const base = path.resolve(".cache/build-cache");
const evidence = path.resolve("docs/evidence/build-cache");
await mkdir(base, { recursive: true });
await mkdir(evidence, { recursive: true });
const context = await mkdtemp(path.join(base, "context-"));
const run = randomBytes(6).toString("hex");
const report = {
  checked_at: new Date().toISOString(),
  run,
  scope:
    "One local web-image BuildKit cache experiment. Cold means --no-cache instructions with the base already present; no registry cold-start, repeat-sample distribution or API-image cache claim. Lockfile edit changes metadata only, not dependency versions.",
  runs: [],
};
try {
  const listing = spawnSync(
    "git",
    ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
    {
      encoding: "utf8",
    },
  );
  if (listing.status !== 0) throw new Error("Cannot inventory the publishable build inputs.");
  for (const file of [...new Set(listing.stdout.split("\0").filter(Boolean))]) {
    if (
      ![
        "package.json",
        "package-lock.json",
        ".dockerignore",
        "infra/Dockerfile.web",
        "apps/partner/package.json",
      ].includes(file) &&
      !file.startsWith("apps/web/") &&
      !file.startsWith("contracts/")
    )
      continue;
    const source = path.resolve(file);
    if (!source.startsWith(process.cwd() + path.sep)) throw new Error("Path outside source tree.");
    const target = path.join(context, file);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(source, target);
  }
  async function build(name, noCache = false) {
    console.log(`Build-cache experiment: ${name}`);
    const tag = `mesh-showcase-cache:${run}-${name}`;
    const args = [
      "build",
      "--progress=plain",
      ...(noCache ? ["--no-cache"] : []),
      "-f",
      path.join(context, "infra/Dockerfile.web"),
      "-t",
      tag,
      context,
    ];
    const start = performance.now();
    const child = spawn("docker", args, { windowsHide: true });
    let log = "";
    child.stdout.on("data", (data) => {
      log += data;
    });
    child.stderr.on("data", (data) => {
      log += data;
    });
    const code = await new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("close", resolve);
    });
    await writeFile(path.join(evidence, `${name}.log`), log);
    assert.equal(code, 0, `Build failed: ${name}`);
    const lines = log.split("\n");
    function cached(command) {
      const definition = lines.find((line) => line.includes(command) && /^#\d+ /.test(line));
      assert.ok(definition, `Missing build step: ${command}`);
      const id = /^#\d+/.exec(definition)[0];
      return lines.some((line) => line.startsWith(id + " CACHED"));
    }
    const image = spawnSync("docker", ["image", "inspect", tag], { encoding: "utf8" });
    assert.equal(image.status, 0);
    const rows = JSON.parse(image.stdout);
    const result = {
      name,
      elapsed_seconds: Number(((performance.now() - start) / 1000).toFixed(3)),
      npm_ci_cached: cached("RUN npm ci"),
      app_build_cached: cached("RUN npm run build"),
      runtime_packages_cached: cached("RUN apt-get update"),
      image: rows[0].Id,
      image_size_bytes: rows[0].Size,
    };
    report.runs.push(result);
    console.log(JSON.stringify(result));
  }
  await build("cold", true);
  await build("repeat");
  const source = path.join(context, "apps/web/src/app/page.tsx");
  await writeFile(source, (await readFile(source, "utf8")) + "\n// Isolated source cache probe.\n");
  await build("source");
  const lock = path.join(context, "package-lock.json");
  const data = JSON.parse(await readFile(lock, "utf8"));
  data.meshCacheProbe = run;
  await writeFile(lock, JSON.stringify(data, null, 2) + "\n");
  await build("lockfile");
  const [cold, repeat, changed, lockfile] = report.runs;
  assert.equal(cold.npm_ci_cached, false);
  assert.equal(cold.app_build_cached, false);
  assert.equal(repeat.npm_ci_cached, true);
  assert.equal(repeat.app_build_cached, true);
  assert.equal(changed.npm_ci_cached, true);
  assert.equal(changed.app_build_cached, false);
  assert.equal(lockfile.npm_ci_cached, false);
  assert.equal(lockfile.app_build_cached, false);
  assert.ok([repeat, changed, lockfile].every((row) => row.runtime_packages_cached));
  report.success = true;
} catch (error) {
  report.success = false;
  report.failure = error.message;
  throw error;
} finally {
  await writeFile(path.join(evidence, "summary.json"), JSON.stringify(report, null, 2) + "\n");
  const target = path.resolve(context);
  if (!target.startsWith(base + path.sep) || path.dirname(target) !== base)
    throw new Error("Refusing cleanup outside the isolated cache context.");
  await rm(target, { recursive: true, force: true });
}
