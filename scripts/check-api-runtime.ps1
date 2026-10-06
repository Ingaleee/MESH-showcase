$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$taskContainers = @('mesh-showcase-api-hardening-ready', 'mesh-showcase-api-hardening-outage')
$taskCreated = @()
New-Item -ItemType Directory -Path 'docs/evidence/backend-hardening' -Force | Out-Null

function Invoke-MeshRuntimeDocker {
  param([string[]]$Arguments)
  $taskResult = & docker @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Docker runtime step failed: $($Arguments[0])" }
  return $taskResult
}

foreach ($taskName in $taskContainers) {
  $taskExisting = Invoke-MeshRuntimeDocker -Arguments @('ps', '-a', '--filter', "name=^/$taskName`$", '--format', '{{.ID}}')
  if ($taskExisting) { throw "$taskName already exists; finish the earlier check first." }
}

$taskKeyBase = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$taskSecrets = @{
  MESH_METRICS_TOKEN = [guid]::NewGuid().ToString('N')
  MESH_GATEWAY_SECRET = [guid]::NewGuid().ToString('N')
  MESH_WEBHOOK_SECRET = [guid]::NewGuid().ToString('N')
}
try {
  for ($taskIndex = 0; $taskIndex -lt $taskContainers.Length; $taskIndex++) {
    $taskName = $taskContainers[$taskIndex]
    $taskPort = 3212 + $taskIndex
    $taskDatabasePort = if ($taskIndex -eq 0) { 5432 } else { 65432 }
    $taskArguments = @(
      'run', '-d', '--name', $taskName, '--label', 'mesh.purpose=hardening-verification',
      '--network', 'mesh-showcase_default', '--read-only', '--cap-drop', 'ALL',
      '--security-opt', 'no-new-privileges',
      '--tmpfs', '/app/tmp:rw,noexec,nosuid,size=64m,mode=1777',
      '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m,mode=1777',
      '-p', "127.0.0.1:${taskPort}:3000",
      '-e', "DATABASE_URL=postgres://mesh:mesh_development@db:$taskDatabasePort/mesh_development",
      '-e', 'QUEUE_DATABASE_URL=postgres://mesh:mesh_development@db:5432/mesh_queue',
      '-e', "SECRET_KEY_BASE=$taskKeyBase",
      '-e', 'MESH_PUBLIC_ORIGIN=https://mesh.example.test',
      '-e', 'MESH_PAYOUTS_ENABLED=false',
      '-e', 'BUNDLE_USER_HOME=/app/tmp/bundle',
      '-e', 'OTEL_TRACES_EXPORTER=none'
    )
    foreach ($taskSecret in $taskSecrets.GetEnumerator()) { $taskArguments += @('-e', "$($taskSecret.Key)=$($taskSecret.Value)") }
    Invoke-MeshRuntimeDocker -Arguments ($taskArguments + 'mesh-showcase-api:hardening-verification') | Out-Null
    $taskCreated += $taskName
    $taskUid = Invoke-MeshRuntimeDocker -Arguments @('exec', $taskName, 'id', '-u')
    if ([int]$taskUid -eq 0) { throw 'Production API must not run as root.' }
  }
  & node scripts/check-api-readiness.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Production API readiness check failed.' }
  $taskRuntime = foreach ($taskName in $taskCreated) {
    $taskInspection = Invoke-MeshRuntimeDocker -Arguments @('inspect', $taskName, '--format', '{{json .HostConfig}}') | ConvertFrom-Json
    [ordered]@{
      name = $taskName
      uid = [int](Invoke-MeshRuntimeDocker -Arguments @('exec', $taskName, 'id', '-u'))
      readonly_root = $taskInspection.ReadonlyRootfs
      cap_drop = $taskInspection.CapDrop
      security_options = $taskInspection.SecurityOpt
    }
  }
  [ordered]@{
    checked_at = [DateTimeOffset]::UtcNow.ToString('o')
    image = (Invoke-MeshRuntimeDocker -Arguments @('image', 'inspect', 'mesh-showcase-api:hardening-verification', '--format', '{{.Id}}')).Trim()
    containers = @($taskRuntime)
    scope = 'Read-only readiness and public feed smoke checks. Uploaded storage needs a separate writable volume in an actual deployment.'
  } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath 'docs/evidence/backend-hardening/production-runtime.json'
} catch {
  $taskFailure = $_
  try {
    $ErrorActionPreference = 'Continue'
    foreach ($taskName in $taskCreated) {
      & docker logs --tail 35 $taskName 2>&1 | Set-Content -Encoding UTF8 -LiteralPath ".cache/$taskName.log"
    }
  } finally {
    $ErrorActionPreference = 'Stop'
  }
  throw $taskFailure
} finally {
  foreach ($taskName in $taskCreated) { Invoke-MeshRuntimeDocker -Arguments @('rm', '-f', $taskName) | Out-Null }
}
