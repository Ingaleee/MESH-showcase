$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$containerName = 'mesh-showcase-api-benchmark'
$k6Image = 'grafana/k6@sha256:5221b620a4f874faff6e32ba597aa667c058391fe4898b1c6f6377f062c6cdec'

function Invoke-MeshDocker {
  param([string[]]$Arguments)
  & docker @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Docker step failed: $($Arguments[0])" }
}

$existing = & docker ps -a --filter "name=^/$containerName`$" --format '{{.ID}}'
if ($existing) { throw "$containerName already exists; finish that benchmark first." }
Invoke-MeshDocker -Arguments @('build', '-f', 'infra/Dockerfile.api', '-t', 'mesh-showcase-api:verification', '.')
$created = $false
try {
  $taskKeyBase = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
  $taskMetricsToken = [guid]::NewGuid().ToString('N')
  $taskGatewaySecret = [guid]::NewGuid().ToString('N')
  $taskWebhookSecret = [guid]::NewGuid().ToString('N')
  Invoke-MeshDocker -Arguments @(
    'run', '-d', '--name', $containerName, '--label', 'mesh.purpose=verification',
    '--network', 'mesh-showcase_default', '-e', 'RAILS_ENV=production',
    '-e', 'DATABASE_URL=postgres://mesh:mesh_development@db:5432/mesh_development',
    '-e', 'QUEUE_DATABASE_URL=postgres://mesh:mesh_development@db:5432/mesh_queue',
    '-e', "SECRET_KEY_BASE=$taskKeyBase",
    '-e', 'MESH_PUBLIC_ORIGIN=https://mesh.example.test',
    '-e', "MESH_METRICS_TOKEN=$taskMetricsToken",
    '-e', "MESH_GATEWAY_SECRET=$taskGatewaySecret",
    '-e', "MESH_WEBHOOK_SECRET=$taskWebhookSecret",
    '-e', 'OTEL_TRACES_EXPORTER=none', 'mesh-showcase-api:verification'
  )
  $created = $true
  $ready = $false
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & docker exec $containerName curl -fs --max-time 4 http://localhost:3000/ready 1>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) { throw 'Production API did not become ready.' }

  $imageId = (& docker image inspect mesh-showcase-api:verification --format '{{.Id}}').Trim()
  $cpus = & docker info --format '{{.NCPU}}'
  $memory = & docker info --format '{{.MemTotal}}'
  $dataset = & docker compose exec -T db psql -U mesh -d mesh_development -At -c 'SELECT json_build_object(''projects'',(SELECT count(*) FROM marketplace_projects),''profiles'',(SELECT count(*) FROM talent_profiles),''proposals'',(SELECT count(*) FROM marketplace_proposals))'
  $started = [DateTimeOffset]::UtcNow.ToString('o')
  try {
    $ErrorActionPreference = 'Continue'
    & docker run --rm --user 0 --network mesh-showcase_default -e MESH_BASE_URL=http://mesh-showcase-api-benchmark:3000 -e MESH_REQUEST_HOST=mesh.example.test -v "${PWD}:/workspace" $k6Image run --quiet /workspace/scripts/benchmark.js *> docs/evidence/k6-run.txt
    $benchmarkExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = 'Stop'
  }
  [ordered]@{
    timestamp = $started
    api_image = $imageId
    k6_image = $k6Image
    rails_env = 'production'
    puma_threads = 3
    otel_exporter = 'none'
    docker_cpus = [int]$cpus
    docker_memory_bytes = [long]$memory
    dataset = ($dataset | ConvertFrom-Json)
    warmup = 'One request per endpoint before a 30-second, 20 req/s scenario.'
    route = 'Direct API inside mesh-showcase_default; no TLS, Caddy or frontend cost.'
    exit_code = $benchmarkExit
  } | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 docs/evidence/benchmark-environment.json
  if ($benchmarkExit -ne 0) { throw 'Benchmark thresholds failed; see docs/evidence/k6.json.' }
  Write-Host 'Benchmark passed; results: docs/evidence/k6.json'
} finally {
  if ($created) { & docker rm -f $containerName }
}
