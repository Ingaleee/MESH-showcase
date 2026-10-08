import { spawnSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const manifest = JSON.parse(await readFile(".cache/downloaded-release/release.json", "utf8"));
const namespace = "mesh-showcase";
const context = "k3d-mesh-acceptance";
const evidence = ".cache/kubernetes-evidence";
await mkdir(evidence, { recursive: true });
function run(program, args, input, allowFailure = false) {
  const result = spawnSync(program, args, {
    input,
    encoding: "utf8",
    timeout: 360000,
    maxBuffer: 2 ** 23,
  });
  appendFileSync(
    path.join(evidence, "commands.jsonl"),
    JSON.stringify({
      checked_at: new Date().toISOString(),
      program,
      args: args.map((value) => value.replace(/[a-f0-9]{96}/g, "[REDACTED]")),
      exit_code: result.status,
      spawn_error: result.error?.code ?? null,
    }) + "\n",
  );
  if (result.error || (result.status !== 0 && !allowFailure))
    throw (
      result.error ??
      Error(
        program + " failed: " + result.stderr.replace(/[a-f0-9]{96}/g, "[REDACTED]").slice(-1500),
      )
    );
  return result;
}
const kube = (args, input) =>
  run("kubectl", ["--context", context, "-n", namespace, ...args], input).stdout;
const apply = (object) => kube(["apply", "-f", "-"], JSON.stringify(object));
const secret = () => randomBytes(48).toString("hex");
const ownerPassword = secret(),
  runtimePassword = secret();
const common = {
  SECRET_KEY_BASE: secret(),
  MESH_GATEWAY_SECRET: secret(),
  MESH_WEBHOOK_SECRET: secret(),
  MESH_METRICS_TOKEN: secret(),
  DATABASE_URL: "postgres://mesh_runtime:" + runtimePassword + "@db:5432/mesh_kubernetes",
  QUEUE_DATABASE_URL:
    "postgres://mesh_runtime:" + runtimePassword + "@db:5432/mesh_kubernetes_queue",
};
run("k3d", [
  "cluster",
  "create",
  "mesh-acceptance",
  "--image",
  "rancher/k3s:v1.35.5-k3s1",
  "--wait",
  "--timeout",
  "120s",
  "--k3s-arg",
  "--disable=traefik@server:0",
]);
const kubeconfig = path.resolve(".cache/kubernetes-acceptance-config");
await writeFile(kubeconfig, run("k3d", ["kubeconfig", "get", "mesh-acceptance"]).stdout, {
  mode: 0o600,
});
const tf = ["-chdir=infra/terraform/namespace"];
run("terraform", [...tf, "init", "-input=false"]);
const variables = ["-var=kube_context=" + context, "-var=kubeconfig_path=" + kubeconfig];
run("terraform", [...tf, "apply", "-auto-approve", ...variables]);
kube(["label", "namespace", namespace, "mesh.showcase/managed-by=drift", "--overwrite"]);
const drift = run(
  "terraform",
  [...tf, "plan", "-detailed-exitcode", ...variables],
  undefined,
  true,
);
assert.equal(drift.status, 2);
run("terraform", [...tf, "apply", "-auto-approve", ...variables]);
assert.equal(run("terraform", [...tf, "plan", "-detailed-exitcode", ...variables]).status, 0);
apply({
  apiVersion: "v1",
  kind: "Secret",
  metadata: { name: "registry" },
  type: "kubernetes.io/dockerconfigjson",
  data: {
    ".dockerconfigjson": Buffer.from(
      await readFile(path.join(process.env.HOME, ".docker/config.json")),
    ).toString("base64"),
  },
});
apply({ apiVersion: "v1", kind: "Secret", metadata: { name: "mesh-runtime" }, stringData: common });
apply({
  apiVersion: "v1",
  kind: "Secret",
  metadata: { name: "mesh-migration" },
  stringData: {
    ...common,
    DATABASE_URL: common.DATABASE_URL.replace(
      "mesh_runtime:" + runtimePassword,
      "mesh_owner:" + ownerPassword,
    ),
    QUEUE_DATABASE_URL: common.QUEUE_DATABASE_URL.replace(
      "mesh_runtime:" + runtimePassword,
      "mesh_owner:" + ownerPassword,
    ),
  },
});
for (const name of ["mesh-files", "mesh-database"])
  apply({
    apiVersion: "v1",
    kind: "PersistentVolumeClaim",
    metadata: { name },
    spec: { accessModes: ["ReadWriteOnce"], resources: { requests: { storage: "1Gi" } } },
  });
const restricted = {
  runAsNonRoot: true,
  runAsUser: 10001,
  runAsGroup: 10001,
  fsGroup: 10001,
  seccompProfile: { type: "RuntimeDefault" },
};
const security = { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } };
apply({
  apiVersion: "apps/v1",
  kind: "Deployment",
  metadata: { name: "db" },
  spec: {
    replicas: 1,
    selector: { matchLabels: { component: "db" } },
    template: {
      metadata: { labels: { component: "db", "mesh.showcase/dependency": "true" } },
      spec: {
        automountServiceAccountToken: false,
        imagePullSecrets: [{ name: "registry" }],
        securityContext: { ...restricted, runAsUser: 70, runAsGroup: 70, fsGroup: 70 },
        containers: [
          {
            name: "db",
            image: manifest.images.postgres,
            securityContext: security,
            env: [
              { name: "POSTGRES_USER", value: "mesh_owner" },
              { name: "POSTGRES_PASSWORD", value: ownerPassword },
              { name: "POSTGRES_DB", value: "mesh_kubernetes" },
            ],
            resources: {
              requests: { cpu: "100m", memory: "128Mi" },
              limits: { cpu: "1", memory: "384Mi" },
            },
            readinessProbe: {
              exec: { command: ["pg_isready", "-U", "mesh_owner", "-d", "mesh_kubernetes"] },
              periodSeconds: 3,
            },
            volumeMounts: [{ name: "database", mountPath: "/var/lib/postgresql" }],
          },
        ],
        volumes: [{ name: "database", persistentVolumeClaim: { claimName: "mesh-database" } }],
      },
    },
  },
});
apply({
  apiVersion: "v1",
  kind: "Service",
  metadata: { name: "db" },
  spec: { selector: { component: "db" }, ports: [{ port: 5432, targetPort: 5432 }] },
});
kube(["rollout", "status", "deployment/db", "--timeout=180s"]);
kube(
  [
    "exec",
    "-i",
    "deployment/db",
    "--",
    "psql",
    "-U",
    "mesh_owner",
    "-d",
    "mesh_kubernetes",
    "-v",
    "ON_ERROR_STOP=1",
  ],
  "CREATE ROLE mesh_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD '" +
    runtimePassword +
    "';\nCREATE DATABASE mesh_kubernetes_queue OWNER mesh_owner;\n",
);
const args = [
  "--kube-context",
  context,
  "--namespace",
  namespace,
  "--set-string",
  "images.api=" + manifest.images.api,
  "--set-string",
  "images.web=" + manifest.images.web,
  "--set",
  "files.existingClaim=mesh-files",
  "--set",
  "imagePullSecrets[0].name=registry",
];
const preflight = run("helm", [
  "template",
  "mesh",
  "infra/helm/mesh",
  ...args,
  "--set",
  "migration.enabled=true",
  "--show-only",
  "templates/configmap.yaml",
  "--show-only",
  "templates/migration.yaml",
]).stdout;
kube(["apply", "-f", "-"], preflight);
kube(["wait", "--for=condition=complete", "job/mesh-migration-1", "--timeout=300s"]);
kube([
  "annotate",
  "configmap/mesh-runtime",
  "meta.helm.sh/release-name=mesh",
  "meta.helm.sh/release-namespace=" + namespace,
  "--overwrite",
]);
kube(["label", "configmap/mesh-runtime", "app.kubernetes.io/managed-by=Helm", "--overwrite"]);
for (const db of ["mesh_kubernetes", "mesh_kubernetes_queue"])
  kube(
    [
      "exec",
      "-i",
      "deployment/db",
      "--",
      "psql",
      "-U",
      "mesh_owner",
      "-d",
      db,
      "-v",
      "ON_ERROR_STOP=1",
    ],
    "GRANT CONNECT ON DATABASE " +
      db +
      " TO mesh_runtime; GRANT USAGE ON SCHEMA public TO mesh_runtime; REVOKE CREATE ON SCHEMA public FROM PUBLIC,mesh_runtime; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO mesh_runtime; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO mesh_runtime;",
  );
run("helm", [
  "upgrade",
  "--install",
  "mesh",
  "infra/helm/mesh",
  ...args,
  "--set",
  "networkPolicy.enabled=true",
  "--wait",
  "--timeout",
  "300s",
]);
const initial = JSON.parse(
  kube(["get", "pods", "-l", "app=mesh,component=api", "-o", "json"]),
).items;
const apiIP = JSON.parse(kube(["get", "service", "mesh-api", "-o", "json"])).spec.clusterIP;
const dbIP = JSON.parse(kube(["get", "service", "db", "-o", "json"])).spec.clusterIP;
for (const [name, labels] of [
  ["approved", { app: "mesh" }],
  ["untrusted", {}],
]) {
  apply({
    apiVersion: "v1",
    kind: "Pod",
    metadata: { name, labels },
    spec: {
      automountServiceAccountToken: false,
      imagePullSecrets: [{ name: "registry" }],
      securityContext: restricted,
      containers: [
        {
          name: "probe",
          image: manifest.images.api,
          command: ["ruby", "-e", "sleep 3600"],
          securityContext: security,
        },
      ],
    },
  });
  kube(["wait", "--for=condition=Ready", "pod/" + name, "--timeout=120s"]);
}
const ruby = (pod, code) =>
  kube(["exec", pod, "--", "ruby", "-rnet/http", "-rtimeout", "-rsocket", "-e", code]).trim();
const http = "Timeout.timeout(4) { Net::HTTP.new('" + apiIP + "',3000,nil).get('/up').code }";
assert.equal(ruby("approved", "puts " + http), "200");
assert.equal(
  ruby(
    "approved",
    "Timeout.timeout(4) { TCPSocket.new('" + dbIP + "',5432).close }; puts 'connected'",
  ),
  "connected",
);
assert.equal(
  ruby(
    "untrusted",
    "begin; " +
      http +
      "; puts 'LEAK'; rescue Timeout::Error,Errno::ETIMEDOUT,Errno::EHOSTUNREACH,Errno::ECONNREFUSED; puts 'denied'; end",
  ),
  "denied",
);
// A CNI may reject rather than silently drop. Re-check the same healthy target
// through the authorized path so an unavailable service cannot masquerade as policy.
assert.equal(ruby("approved", "puts " + http), "200");
apply({
  apiVersion: "v1",
  kind: "Pod",
  metadata: { name: "sink" },
  spec: {
    automountServiceAccountToken: false,
    imagePullSecrets: [{ name: "registry" }],
    securityContext: restricted,
    containers: [
      {
        name: "sink",
        image: manifest.images.web,
        securityContext: security,
        command: [
          "node",
          "-e",
          "require('node:http').createServer((q,r)=>r.end('ok')).listen(8080,'0.0.0.0')",
        ],
      },
    ],
  },
});
kube(["wait", "--for=condition=Ready", "pod/sink", "--timeout=120s"]);
const sinkIP = JSON.parse(kube(["get", "pod", "sink", "-o", "json"])).status.podIP;
const sinkHTTP = "Timeout.timeout(4) { Net::HTTP.new('" + sinkIP + "',8080,nil).get('/').code }";
assert.equal(ruby("untrusted", "puts " + sinkHTTP), "200");
assert.equal(
  ruby(
    "approved",
    "begin; " +
      sinkHTTP +
      "; puts 'LEAK'; rescue Timeout::Error,Errno::ETIMEDOUT,Errno::EHOSTUNREACH,Errno::ECONNREFUSED; puts 'denied'; end",
  ),
  "denied",
);
assert.equal(ruby("untrusted", "puts " + sinkHTTP), "200");
const correlation = randomUUID();
const probe = await readFile("apps/api/script/kubernetes_probe.rb", "utf8");
const queueProbe = (phase) => {
  const output = kube(
    [
      "exec",
      "-i",
      "deployment/mesh-api",
      "--",
      "env",
      "MESH_KUBERNETES_PROBE=true",
      "ruby",
      "-",
      phase,
      correlation,
    ],
    'require "./config/environment"\n' + probe,
  );
  return JSON.parse(
    output
      .split("\n")
      .find((row) => row.startsWith("MESH_KUBERNETES_REPORT="))
      .slice("MESH_KUBERNETES_REPORT=".length),
  );
};
kube(["scale", "deployment/mesh-worker", "--replicas=0"]);
kube(["wait", "--for=delete", "pod", "-l", "app=mesh,component=worker", "--timeout=90s"]);
const burst = queueProbe("burst");
assert.equal(burst.events, 50);
kube(["scale", "deployment/mesh-worker", "--replicas=1"]);
kube(["rollout", "status", "deployment/mesh-worker", "--timeout=180s"]);
const drain = queueProbe("drain");
assert.deepEqual(drain.effects_per_event, [1]);
kube(["scale", "deployment/db", "--replicas=0"]);
kube(["wait", "--for=delete", "pod", "-l", "component=db", "--timeout=90s"]);
const apiPod = initial[0].metadata.name;
assert.equal(ruby(apiPod, "puts Net::HTTP.new('127.0.0.1',3000,nil).get('/ready').code"), "503");
assert.equal(ruby(apiPod, "puts Net::HTTP.new('127.0.0.1',3000,nil).get('/up').code"), "200");
kube(["scale", "deployment/db", "--replicas=1"]);
kube(["rollout", "status", "deployment/db", "--timeout=180s"]);
kube(["rollout", "status", "deployment/mesh-api", "--timeout=180s"]);
const afterOutage = JSON.parse(
  kube(["get", "pods", "-l", "app=mesh,component=api", "-o", "json"]),
).items;
assert.deepEqual(
  afterOutage.map((p) => p.metadata.uid).sort(),
  initial.map((p) => p.metadata.uid).sort(),
);
assert.deepEqual(
  afterOutage.map((p) => p.status.containerStatuses[0].restartCount).sort(),
  initial.map((p) => p.status.containerStatuses[0].restartCount).sort(),
);
kube(["delete", "pod", "approved", "untrusted", "sink"]);
kube(["rollout", "restart", "deployment/mesh-api"]);
kube(["rollout", "status", "deployment/mesh-api", "--timeout=180s"]);
const failed = run(
  "helm",
  [
    "upgrade",
    "mesh",
    "infra/helm/mesh",
    ...args,
    "--set",
    "networkPolicy.enabled=true",
    "--set-string",
    "images.api=ghcr.io/ingaleee/mesh-showcase-api@sha256:" + "0".repeat(64),
    "--rollback-on-failure",
    "--wait",
    "--timeout",
    "45s",
  ],
  undefined,
  true,
);
assert.notEqual(failed.status, 0);
const restored = JSON.parse(kube(["get", "deployment", "mesh-api", "-o", "json"]));
assert.equal(restored.spec.template.spec.containers[0].image, manifest.images.api);
await writeFile(
  path.join(evidence, "helm-history.json"),
  run("helm", ["history", "mesh", "-n", namespace, "-o", "json"]).stdout,
);
await writeFile(
  path.join(evidence, "runtime.json"),
  kube(["get", "pods", "-l", "app=mesh", "-o", "json"]),
);
await writeFile(
  path.join(evidence, "summary.json"),
  JSON.stringify(
    {
      checked_at: new Date().toISOString(),
      release_revision: manifest.revision,
      images: manifest.images,
      terraform_drift_detected_and_repaired: true,
      migration_completed_before_application: true,
      positive_api_and_db: true,
      untrusted_ingress_denied: true,
      unapproved_egress_denied_with_positive_control: true,
      worker_50_once_only_effects: true,
      database_outage_ready_503_live_200: true,
      outage_preserved_api_uids_and_restarts: true,
      alpine_rollout: true,
      broken_upgrade_rejected: true,
      registry_digest_restored: true,
      scope:
        "One K3s node in an ephemeral hosted Ubuntu VM. No physical HA, offsite recovery or Publishing partner/scanner workload in this cluster.",
    },
    null,
    2,
  ) + "\n",
);
console.log(
  "Current digest rollout, Terraform drift, CNI ingress, queue and DB recovery, Helm rollback passed.",
);
