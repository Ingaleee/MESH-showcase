import { spawnSync } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
await readFile("SHOWCASE.md");
const directory = "docs/evidence/publishing-kubernetes";
await mkdir(directory, { recursive: true });
const binary = path.resolve(".cache/tools/kubectl/kubectl.exe");
const prefix = [
  "--kubeconfig",
  path.resolve(".cache/kubernetes/config"),
  "--context",
  "k3d-mesh-showcase",
  "-n",
  "mesh-showcase",
];
function kubectl(args, input) {
  const result = spawnSync(binary, [...prefix, ...args], {
    input,
    encoding: "utf8",
    timeout: 60000,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) throw result.error ?? new Error(result.stderr);
  return result.stdout;
}
const values = JSON.parse(await readFile(".cache/kubernetes/values.json", "utf8"));
const apiIP = JSON.parse(kubectl(["get", "service", "mesh-api", "-o", "json"])).spec.clusterIP;
const partner = spawnSync(
  "docker",
  [
    "inspect",
    "mesh-showcase-partner-1",
    "--format",
    '{{(index .NetworkSettings.Networks "mesh-showcase_default").IPAddress}}',
  ],
  { encoding: "utf8", windowsHide: true },
);
assert.equal(partner.status, 0);
const partnerIP = partner.stdout.trim();
const dbIP = values.networkPolicy.externalDependencies[0].cidr.split("/")[0];
const result = {
  checked_at: new Date().toISOString(),
  context: "k3d-mesh-showcase",
  real_cni: true,
  api_ip: apiIP,
  partner_ip: partnerIP,
  db_ip: dbIP,
  probes: [],
};
async function probe(name, labels, code) {
  kubectl(["delete", "pod", name, "--ignore-not-found=true", "--wait=true"]);
  const pod = {
    apiVersion: "v1",
    kind: "Pod",
    metadata: { name, labels },
    spec: {
      restartPolicy: "Never",
      automountServiceAccountToken: false,
      securityContext: {
        runAsNonRoot: true,
        runAsUser: 10001,
        runAsGroup: 10001,
        seccompProfile: { type: "RuntimeDefault" },
      },
      containers: [
        {
          name: "probe",
          image: values.images.api,
          imagePullPolicy: "IfNotPresent",
          command: ["ruby", "-e", "sleep 180"],
          securityContext: {
            allowPrivilegeEscalation: false,
            readOnlyRootFilesystem: true,
            capabilities: { drop: ["ALL"] },
          },
          resources: {
            requests: { cpu: "50m", memory: "32Mi" },
            limits: { cpu: "1", memory: "128Mi" },
          },
        },
      ],
    },
  };
  kubectl(["apply", "-f", "-"], JSON.stringify(pod));
  const deadline = Date.now() + 30000;
  while (true) {
    const state = JSON.parse(kubectl(["get", "pod", name, "-o", "json"])).status.phase;
    if (state === "Running") break;
    if (state === "Failed") throw new Error("Probe container failed to start.");
    if (Date.now() > deadline) throw new Error("Network probe timed out: " + name);
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  const log = JSON.parse(
    kubectl([
      "exec",
      name,
      "--",
      "ruby",
      "-rnet/http",
      "-rsocket",
      "-rtimeout",
      "-rjson",
      "-e",
      code,
    ]).trim(),
  );
  result.probes.push({ name, ...log });
  kubectl(["delete", "pod", name, "--wait=true"]);
  return log;
}
const http = (ip, port, route) =>
  'Timeout.timeout(4) { Net::HTTP.new("' + ip + '",' + port + ',nil).get("' + route + '").code }';
const yes = await probe(
  "mesh-network-approved",
  { app: "mesh" },
  'deadline=Time.now+20; loop do; begin; raise "API unavailable" unless ' +
    http(apiIP, 3000, "/up") +
    ' == "200"; break; rescue Errno::ECONNREFUSED,Timeout::Error; raise if Time.now>deadline; sleep 0.5; end; end; Timeout.timeout(4) { socket=TCPSocket.new("' +
    dbIP +
    '",5432); socket.close }; puts JSON.generate(api_http:200,database_tcp:"connected")',
);
assert.equal(yes.api_http, 200);
await probe(
  "mesh-network-untrusted",
  {},
  'raise "Partner control unavailable" unless ' +
    http(partnerIP, 3216, "/health") +
    ' == "200"; begin; ' +
    http(apiIP, 3000, "/up") +
    '; raise "Ingress policy failed"; rescue Timeout::Error,Errno::EHOSTUNREACH,Errno::ETIMEDOUT,Errno::ECONNREFUSED; puts JSON.generate(api_ingress:"denied",partner_positive_control:200); end',
);
await probe(
  "mesh-network-egress",
  { app: "mesh" },
  "begin; " +
    http(partnerIP, 3216, "/health") +
    '; raise "Egress policy failed"; rescue Timeout::Error,Errno::EHOSTUNREACH,Errno::ETIMEDOUT,Errno::ECONNREFUSED; puts JSON.generate(partner_egress:"denied"); end',
);
result.success = true;
result.scope =
  "Actual pod-to-service ingress and pod-to-private-Docker-network egress enforced by K3s network-policy controller, with positive HTTP and DB controls. Port-forward is not used as policy evidence. One local node is not physical HA.";
await writeFile(directory + "/networkpolicy.json", JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify(result, null, 2));
