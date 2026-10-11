import http from "k6/http";
import exec from "k6/execution";
import { check } from "k6";

const routes = [
  ["feed", "/api/v1/projects?limit=12"],
  [
    "deep_feed",
    `/api/v1/projects?limit=12&cursor=${encodeURIComponent(__ENV.MESH_LAB_DEEP_CURSOR)}`,
  ],
  ["category", "/api/v1/projects?category=%D0%94%D0%B8%D0%B7%D0%B0%D0%B9%D0%BD&limit=12"],
  ["project_search", "/api/v1/projects?q=RareNeedle&limit=12"],
  ["creator_search", "/api/v1/creators?q=RareNeedle"],
];
export const options = {
  scenarios: {
    discovery: {
      executor: "constant-arrival-rate",
      rate: 20,
      timeUnit: "1s",
      duration: "120s",
      preAllocatedVUs: 20,
      maxVUs: 20,
    },
  },
  thresholds: {
    http_req_failed: ["rate==0"],
    checks: ["rate==1"],
    dropped_iterations: ["count==0"],
    ...Object.fromEntries(
      routes.map(([name]) => [`http_req_duration{route:${name}}`, ["p(95)<500"]]),
    ),
  },
};
const get = ([name, path]) =>
  http.get(`${__ENV.MESH_BASE_URL}${path}`, {
    headers: { Host: "mesh.example.test" },
    tags: { route: name },
  });
export function setup() {
  for (const route of routes) {
    if (get(route).status !== 200) throw new Error(`Warmup failed: ${route[0]}`);
  }
}
export default function () {
  const response = get(routes[exec.scenario.iterationInTest % routes.length]);
  check(response, {
    "HTTP 200 with data": (value) => value.status === 200 && Array.isArray(value.json("data")),
  });
}
export function handleSummary(data) {
  return {
    "/workspace/docs/evidence/showcase-architecture-lab/load.json": JSON.stringify(data, null, 2),
    stdout: JSON.stringify({ metrics: data.metrics }, null, 2),
  };
}
