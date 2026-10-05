import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const packsRoot = "apps/api/packs";
const apis = JSON.parse(await readFile("contracts/module-apis.json", "utf8"));
const packs = Object.keys(apis);
const namespace = (name) => name[0].toUpperCase() + name.slice(1);
const failures = [];
async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  return (
    await Promise.all(
      entries.map((entry) =>
        entry.isDirectory()
          ? walk(path.join(directory, entry.name))
          : path.join(directory, entry.name),
      ),
    )
  ).flat();
}
for (const owner of packs) {
  const dependencies = await readFile(path.join(packsRoot, owner, "package.yml"), "utf8");
  for (const file of (await walk(path.join(packsRoot, owner))).filter((item) =>
    item.endsWith(".rb"),
  )) {
    const source = await readFile(file, "utf8");
    for (const target of packs.filter((item) => item !== owner)) {
      const references = [
        ...source.matchAll(new RegExp(`\\b${namespace(target)}::([A-Z][A-Za-z0-9_]*)`, "g")),
      ];
      for (const [, constant] of references) {
        if (!dependencies.includes(`packs/${target}`))
          failures.push(`${file}: undeclared dependency on ${target}`);
        if (!apis[target].includes("*") && !apis[target].includes(constant))
          failures.push(`${file}: ${namespace(target)}::${constant} is private`);
      }
    }
  }
}
if (failures.length) throw new Error(failures.join("\n"));
console.log(
  "Module API check passed. String associations are checked too; dynamic constant lookup still requires review.",
);
