import { readFile, writeFile, mkdir } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import path from "node:path";
await readFile("SHOWCASE.md");
const directory = path.resolve(".cache/incident");
await mkdir(directory, { recursive: true, mode: 0o700 });
const deployment = await readFile(".cache/deployment/secrets.env", "utf8");
const token = /^MESH_METRICS_TOKEN=([a-f0-9]+)$/m.exec(deployment)?.[1];
if (!token) throw new Error("Deployment metrics token missing.");
const alertToken = randomBytes(48).toString("hex");
await writeFile(
  path.join(directory, "prometheus.yml"),
  `global:
  scrape_interval: 1s
  evaluation_interval: 1s
rule_files: [/etc/prometheus/alerts.yml]
alerting:
  alertmanagers:
    - static_configs:
        - targets: [alertmanager:9093]
scrape_configs:
  - job_name: showcase
    metrics_path: /internal/metrics
    authorization:
      credentials: ${token}
    static_configs:
      - targets: [api:3000]
`,
  { mode: 0o644 },
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
  { mode: 0o644 },
);
await writeFile(
  path.join(directory, "runtime.env"),
  `MESH_SRE_CONFIG=${directory.replaceAll("\\", "/")}\nMESH_ALERT_TOKEN=${alertToken}\n`,
  { mode: 0o600 },
);
console.log("Generated isolated SRE configuration; credentials were not printed.");
