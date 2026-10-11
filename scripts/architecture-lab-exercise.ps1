# Sourced by architecture-lab.ps1, which owns environment and cleanup.
Invoke-LabDocker -Arguments @('build', '-f', 'infra/Dockerfile.api', '-t', 'mesh-showcase-api:architecture-lab', '.')
Invoke-LabDocker -Arguments @(
  'run', '-d', '--name', "$($taskLab.prefix)-api", '--label', "mesh.lab=$($taskLab.id)",
  '--network', 'mesh-showcase_default', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
  '--tmpfs', '/tmp', '--tmpfs', '/app/tmp:uid=10001,gid=10001', '-p', '127.0.0.1:3214:3000',
  '-v', "$($taskLab.volume):/app/storage:ro", '-e', 'RAILS_ENV=production',
  '-e', "DATABASE_URL=postgres://mesh:mesh_development@db:5432/$($taskLab.database)",
  '-e', "QUEUE_DATABASE_URL=postgres://mesh:mesh_development@db:5432/$($taskLab.database)_queue",
  '-e', "SECRET_KEY_BASE=$($taskLab.secret)", '-e', "MESH_METRICS_TOKEN=$($taskLab.metrics)",
  '-e', "MESH_GATEWAY_SECRET=$($taskLab.gateway)", '-e', "MESH_WEBHOOK_SECRET=$($taskLab.webhook)",
  '-e', 'MESH_PUBLIC_ORIGIN=https://mesh.example.test', '-e', 'MESH_PAYOUTS_ENABLED=false',
  '-e', 'OTEL_TRACES_EXPORTER=none', 'mesh-showcase-api:architecture-lab'
)
$taskDirectory = Join-Path $PWD ".cache/architecture-lab/$($taskLab.id)"
@"
global:
  scrape_interval: 1s
  evaluation_interval: 1s
rule_files: [/etc/prometheus/lab-alerts.yml]
scrape_configs:
  - job_name: architecture-lab
    metrics_path: /internal/metrics
    authorization:
      type: Bearer
      credentials: $($taskLab.metrics)
    static_configs:
      - targets: ['$($taskLab.prefix)-api:3000']
"@ | Set-Content -Encoding UTF8 (Join-Path $taskDirectory 'prometheus.yml')
@'
groups:
  - name: architecture-lab
    rules:
      - alert: LabQueueWait
        expr: mesh_queue_oldest_ready_seconds > 2
        for: 3s
      - alert: LabPoisonEvent
        expr: mesh_outbox_failed > 0
        for: 3s
'@ | Set-Content -Encoding UTF8 (Join-Path $taskDirectory 'lab-alerts.yml')
Invoke-LabDocker -Arguments @('run', '-d', '--name', "$($taskLab.prefix)-prometheus", '--label', "mesh.lab=$($taskLab.id)",
  '--network', 'mesh-showcase_default', '-p', '127.0.0.1:3215:9090', '-v', "${taskDirectory}:/etc/prometheus:ro",
  'prom/prometheus:v3.15.0', '--config.file=/etc/prometheus/prometheus.yml', '--storage.tsdb.path=/prometheus')
& node scripts/architecture-lab-observe.mjs boot
if ($LASTEXITCODE -ne 0) { throw 'Lab production API/Prometheus boot failed.' }
$image = & docker image inspect mesh-showcase-api:architecture-lab --format '{{.Id}}'
$cpus = & docker info --format '{{.NCPU}}'
$memory = & docker info --format '{{.MemTotal}}'
[ordered]@{ checkedAt = [DateTimeOffset]::UtcNow.ToString('o'); apiImage = $image; dockerCpus = [int]$cpus; dockerMemoryBytes = [long]$memory;
  api = 'production Ruby/Rails, non-root, read-only root'; database = 'isolated logical PostgreSQL DB on shared local server';
  rate = 20; durationSeconds = 120; cache = 'warm'; scope = 'Direct Docker HTTP; no TLS, frontend/SSR or capacity claim.'
} | ConvertTo-Json | Set-Content -Encoding UTF8 docs/evidence/showcase-architecture-lab/environment.json
$fixtures = Get-Content (Join-Path $taskDirectory 'fixtures.json') -Raw | ConvertFrom-Json
Invoke-LabDocker -Arguments @('run', '--rm', '--user', '0', '--network', 'mesh-showcase_default',
  '-e', "MESH_BASE_URL=http://$($taskLab.prefix)-api:3000", '-v', "${PWD}:/workspace",
  '-e', "MESH_LAB_DEEP_CURSOR=$($fixtures.deep_cursor)",
  'grafana/k6@sha256:5221b620a4f874faff6e32ba597aa667c058391fe4898b1c6f6377f062c6cdec',
  'run', '--quiet', '/workspace/scripts/architecture-lab-load.js')
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('burst')
& node scripts/architecture-lab-observe.mjs backlog
if ($LASTEXITCODE -ne 0) { throw 'Backlog alert did not fire.' }
Start-LabWorker
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('drain')
& node scripts/architecture-lab-observe.mjs drained
if ($LASTEXITCODE -ne 0) { throw 'Backlog alert did not resolve.' }
# Stop the competing producer so the event deterministically reaches the failed queue connection.
Invoke-LabDocker -Arguments @('stop', '-t', '35', "$($taskLab.prefix)-dispatcher")
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('outage')
Invoke-LabDocker -Arguments @('start', "$($taskLab.prefix)-dispatcher")
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('recover-outage')
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('poison')
& node scripts/architecture-lab-observe.mjs poison
if ($LASTEXITCODE -ne 0) { throw 'Poison alert did not fire.' }
& node scripts/architecture-lab-observe.mjs timeline
if ($LASTEXITCODE -ne 0) { throw 'Prometheus queue timeline failed.' }
Invoke-LabDocker -Arguments @('stop', '-t', '35', "$($taskLab.prefix)-worker", "$($taskLab.prefix)-dispatcher", "$($taskLab.prefix)-api")
Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('backup-lease')
$env:MESH_LAB_QUIESCED = 'true'
try {
  # Invoke-LabRuby explicitly passes this guard into the helper container.
  $restoreTimer = [Diagnostics.Stopwatch]::StartNew()
  Invoke-LabRuby -Script 'architecture_lab_backup.rb'
  Invoke-LabRuby -Script 'architecture_lab_verify_restore.rb' -Restore
  Start-LabWorker -Restore
  Invoke-LabRuby -Script 'architecture_lab_queue.rb' -ScriptArgs @('recover') -Restore
  $restoreTimer.Stop()
  @{ checkedAt = [DateTimeOffset]::UtcNow.ToString('o'); localRecoverySeconds = $restoreTimer.Elapsed.TotalSeconds;
    scope = 'Includes backup, DB/file restore, authentication checks, worker boot and recovery of a lost queue claim. Single local run, not a production RTO/RPO promise.'
  } | ConvertTo-Json | Set-Content -Encoding UTF8 docs/evidence/showcase-architecture-lab/recovery-time.json
} finally { Remove-Item Env:MESH_LAB_QUIESCED }
& node scripts/check-architecture-evidence.mjs
if ($LASTEXITCODE -ne 0) { throw 'Architecture evidence does not agree.' }
Write-Host 'Architecture lab passed: SQL, sustained HTTP reads, queue failures and DB + file recovery.'
