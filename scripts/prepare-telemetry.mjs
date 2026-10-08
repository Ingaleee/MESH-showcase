import { readFile, writeFile, mkdir, appendFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import path from "node:path";
await readFile("SHOWCASE.md");
const env = await readFile(process.env.COMPOSE_ENV_FILES ?? ".env", "utf8");
const token =
  /^MESH_METRICS_TOKEN=(.+)$/m.exec(env)?.[1] ??
  (() => {
    throw new Error("Prepare isolated credentials before telemetry.");
  })();
const directory = path.resolve(".cache/telemetry");
await mkdir(directory, { recursive: true });
const file = path.join(directory, "runtime.env");
try {
  await writeFile(
    file,
    "MESH_TELEMETRY_CONFIG=" +
      directory.replaceAll("\\", "/") +
      "\nMESH_GRAFANA_ADMIN_PASSWORD=" +
      randomBytes(40).toString("hex") +
      "\n",
    { flag: "wx", mode: 0o600 },
  );
} catch (error) {
  if (error.code !== "EEXIST") throw error;
}
let runtime = await readFile(file, "utf8");
if (!/^MESH_ALERT_TOKEN=/m.test(runtime)) {
  await appendFile(file, "MESH_ALERT_TOKEN=" + randomBytes(48).toString("hex") + "\n");
  runtime = await readFile(file, "utf8");
}
const alertToken = /^MESH_ALERT_TOKEN=(.+)$/m.exec(runtime)?.[1];
await writeFile(
  path.join(directory, "prometheus.yml"),
  `global:
  scrape_interval: 5s
  evaluation_interval: 5s
rule_files: [/etc/prometheus/alerts.yml]
alerting:
  alertmanagers:
    - static_configs:
        - targets: [alertmanager:9093]
scrape_configs:
  - job_name: mesh-api
    metrics_path: /internal/metrics
    scrape_timeout: 4s
    authorization:
      credentials: ${token}
    static_configs:
      - targets: [api:3000]
`,
);
await writeFile(
  path.join(directory, "alertmanager.yml"),
  `route:
  receiver: local-drill
  group_by: [alertname]
  group_wait: 1s
  group_interval: 5s
  repeat_interval: 5m
receivers:
  - name: local-drill
    webhook_configs:
      - url: http://receiver:8080/alerts
        send_resolved: true
        http_config:
          authorization:
            credentials: ${alertToken}
`,
);
console.log(
  "Local read-only dashboard and authenticated alert configuration prepared; credentials preserved.",
);
