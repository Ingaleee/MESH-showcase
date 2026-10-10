import { readFile, appendFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
await readFile("SHOWCASE.md");
const file = process.argv[2] ?? ".env";
if (![".env", ".env.ci", ".cache/deployment/secrets.env"].includes(file))
  throw new Error("Choose an isolated showcase environment file.");
let contents = await readFile(file, "utf8");
const config = {
  MESH_METRICS_TOKEN: randomBytes(48).toString("hex"),
  MESH_PUBLISHING_ENABLED: "true",
  MESH_PARTNER_ORIGINS: "http://partner:3216",
  MESH_PARTNER_HTTP_ORIGINS: "http://partner:3216",
  MESH_PARTNER_TOKEN_SHOWCASE: randomBytes(48).toString("hex"),
  MESH_PUBLISHING_FAILPOINTS: "true",
};
const missing = Object.entries(config).filter(
  ([key]) => !new RegExp("^" + key + "=", "m").test(contents),
);
if (missing.length)
  await appendFile(file, "\n" + missing.map(([key, value]) => key + "=" + value).join("\n") + "\n");
console.log("Isolated publishing configuration prepared; existing credentials preserved.");
