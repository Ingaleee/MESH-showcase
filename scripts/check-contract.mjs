import { readFile, mkdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";

const root = process.cwd();
const output = path.join(root, ".cache", "contract-generated.d.ts");
await mkdir(path.dirname(output), { recursive: true });
const result = spawnSync(
  process.execPath,
  ["node_modules/openapi-typescript/bin/cli.js", "contracts/openapi.json", "-o", output],
  { stdio: "inherit" },
);
if (result.status !== 0) process.exit(result.status ?? 1);
const normalize = (value) => value.replaceAll("\r\n", "\n");
const actual = normalize(await readFile("apps/web/src/lib/api-schema.d.ts", "utf8"));
const expected = normalize(await readFile(output, "utf8"));
if (actual !== expected)
  throw new Error("Generated types have drifted. Run npm run contract:generate.");
const contract = JSON.parse(await readFile("contracts/openapi.json", "utf8"));
const operations = Object.values(contract.paths).flatMap((item) => Object.values(item));
const ids = operations.map((item) => item.operationId);
if (new Set(ids).size !== ids.length) throw new Error("Duplicate OpenAPI operationId.");
console.log(`OpenAPI and generated types agree: ${ids.length} operations.`);
