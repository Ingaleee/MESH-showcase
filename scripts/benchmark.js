import http from "k6/http";
import { check } from "k6";

export const options = {
  scenarios: {
    discovery: {
      executor: "constant-arrival-rate",
      rate: 20,
      timeUnit: "1s",
      duration: "30s",
      preAllocatedVUs: 20,
      maxVUs: 20,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"],
    checks: ["rate>0.99"],
    dropped_iterations: ["count==0"],
  },
};

const paths = [
  "/api/v1/projects?limit=12",
  "/api/v1/projects?category=%D0%A2%D0%B5%D0%BA%D1%81%D1%82%D1%8B&limit=12",
  "/api/v1/creators?q=UX",
];

export function setup() {
  for (const path of paths) {
    const response = http.get(`${__ENV.MESH_BASE_URL || "http://edge"}${path}`, {
      headers: { Host: __ENV.MESH_REQUEST_HOST || "localhost" },
    });
    if (response.status !== 200) throw new Error(`Warmup failed: ${response.status}`);
  }
}

export default function () {
  const response = http.get(
    `${__ENV.MESH_BASE_URL || "http://edge"}${paths[__ITER % paths.length]}`,
    { headers: { Host: __ENV.MESH_REQUEST_HOST || "localhost" } },
  );
  check(response, {
    "HTTP 200 with data": (result) => result.status === 200 && Array.isArray(result.json("data")),
  });
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify({ metrics: data.metrics }, null, 2),
    "/workspace/docs/evidence/k6.json": JSON.stringify(data, null, 2),
  };
}
