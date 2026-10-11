#requires -Version 7.0
param(
  [ValidateSet('All', 'Prepare', 'Seed', 'Measure', 'Exercise', 'Cleanup')][string]$Step = 'All'
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$taskStateFile = Join-Path $PWD '.cache/architecture-lab/run.json'

function Invoke-LabDocker {
  param([string[]]$Arguments)
  & docker @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Lab Docker step failed: $($Arguments[0])" }
}

function Invoke-LabRuby {
  param([string]$Script, [string[]]$ScriptArgs = @(), [switch]$Restore)
  $database = $script:taskLab.database
  $volume = $script:taskLab.volume
  if ($Restore) { $database += '_restore'; $volume = $script:taskLab.restore_volume }
  Invoke-LabDocker -Arguments (@(
    'compose', 'run', '--rm', '--no-deps', '-T',
    '-e', "DATABASE_URL=postgres://mesh:mesh_development@db:5432/$database",
    '-e', "QUEUE_DATABASE_URL=postgres://mesh:mesh_development@db:5432/${database}_queue",
    '-e', "MESH_LAB_DATABASE=$database", '-e', 'MESH_PAYOUTS_ENABLED=false', '-e', 'MESH_SCAN_FILES=true',
    '-e', "SECRET_KEY_BASE=$($script:taskLab.secret)",
    '-e', "MESH_LAB_STATE=$($script:taskLab.state_path)", '-e', "MESH_LAB_BACKUP=$($script:taskLab.backup_path)",
    '-e', "MESH_LAB_QUIESCED=$env:MESH_LAB_QUIESCED",
    '-v', "${volume}:/workspace/apps/api/storage", '-v', "$($script:taskLab.restore_volume):/lab-restored-storage",
    'api', 'bundle', 'exec', 'ruby', "script/$Script"
  ) + $ScriptArgs)
}

function Start-LabWorker {
  param([switch]$Restore)
  $database = $script:taskLab.database
  $volume = $script:taskLab.volume
  $prefix = $script:taskLab.prefix
  if ($Restore) { $database += '_restore'; $volume = $script:taskLab.restore_volume; $prefix += '-restore' }
  foreach ($service in @('worker', 'dispatcher')) {
    $command = if ($service -eq 'worker') { 'bin/jobs' } else { 'script/dispatcher.rb' }
    Invoke-LabDocker -Arguments @(
      'compose', 'run', '-d', '--no-deps', '--name', "$prefix-$service", '--label', "mesh.lab=$($script:taskLab.id)",
      '-e', "DATABASE_URL=postgres://mesh:mesh_development@db:5432/$database",
      '-e', "QUEUE_DATABASE_URL=postgres://mesh:mesh_development@db:5432/${database}_queue",
      '-e', 'MESH_PAYOUTS_ENABLED=false', '-e', 'MESH_SCAN_FILES=true',
      '-v', "${volume}:/workspace/apps/api/storage", $service, 'bundle', 'exec', 'ruby', $command
    )
  }
}

function Remove-LabResources {
  $id = $script:taskLab.id
  if ($id -notmatch '^[a-f0-9]{12}$' -or $script:taskLab.database -ne "mesh_lab_$id" -or
      $script:taskLab.prefix -ne "mesh-showcase-architecture-$id" -or $script:taskLab.volume -ne "mesh-showcase-architecture-files-$id" -or
      $script:taskLab.restore_volume -ne "mesh-showcase-architecture-restore-files-$id") { throw 'Invalid cleanup target.' }
  $containers = & docker ps -aq --filter "label=mesh.lab=$($script:taskLab.id)"
  foreach ($container in $containers) {
    $name = & docker inspect $container --format '{{.Name}}'
    if ($name -notmatch "^/mesh-showcase-architecture-$id-(api|prometheus|worker|dispatcher|restore-worker|restore-dispatcher)$") {
      throw 'Refusing to remove an unrelated container.'
    }
    Invoke-LabDocker -Arguments @('rm', '-f', '-v', $container)
  }
  Invoke-LabRuby -Script 'architecture_lab_admin.rb' -ScriptArgs @('drop')
  foreach ($volume in @($script:taskLab.volume, $script:taskLab.restore_volume)) {
    $label = & docker volume inspect $volume --format '{{index .Labels "mesh.lab"}}'
    if ($label -ne $script:taskLab.id) { throw 'Refusing to remove an unrelated volume.' }
    Invoke-LabDocker -Arguments @('volume', 'rm', $volume)
  }
  $script:taskLab.status = 'cleaned'
  $script:taskLab | ConvertTo-Json | Set-Content -Encoding UTF8 $taskStateFile
}

if ($Step -in @('All', 'Prepare')) {
  if (Test-Path $taskStateFile) {
    $previous = Get-Content $taskStateFile -Raw | ConvertFrom-Json
    if ($previous.status -ne 'cleaned') { throw 'A previous lab is active; use Cleanup or finish its stages.' }
  }
  $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
  $taskDirectory = Join-Path $PWD ".cache/architecture-lab/$id"
  New-Item -ItemType Directory -Force $taskDirectory | Out-Null
  New-Item -ItemType Directory -Force 'docs/evidence/showcase-architecture-lab' | Out-Null
  $script:taskLab = [ordered]@{
    id = $id; status = 'active'; database = "mesh_lab_$id"; prefix = "mesh-showcase-architecture-$id"
    volume = "mesh-showcase-architecture-files-$id"; restore_volume = "mesh-showcase-architecture-restore-files-$id"
    state_path = "/workspace/.cache/architecture-lab/$id/fixtures.json"
    backup_path = "/workspace/.cache/architecture-lab/$id/backup"
    secret = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    metrics = [guid]::NewGuid().ToString('N'); gateway = [guid]::NewGuid().ToString('N'); webhook = [guid]::NewGuid().ToString('N')
  }
  $script:taskLab | ConvertTo-Json | Set-Content -Encoding UTF8 $taskStateFile
} else {
  $script:taskLab = Get-Content $taskStateFile -Raw | ConvertFrom-Json -AsHashtable
  if ($script:taskLab.status -ne 'active') { throw 'There is no active lab.' }
}

try {
  if ($Step -in @('All', 'Prepare')) {
    foreach ($volume in @($taskLab.volume, $taskLab.restore_volume)) {
      Invoke-LabDocker -Arguments @('volume', 'create', '--label', "mesh.lab=$id", $volume)
    }
    Invoke-LabRuby -Script 'architecture_lab_admin.rb' -ScriptArgs @('create')
  }
  if ($Step -in @('All', 'Prepare', 'Seed')) {
    Invoke-LabRuby -Script 'architecture_lab_data.rb'
    Invoke-LabRuby -Script 'architecture_lab_queries.rb' -ScriptArgs @('before')
  }
  if ($Step -in @('All', 'Measure')) {
    Invoke-LabRuby -Script 'architecture_lab_indexes.rb'
    Invoke-LabRuby -Script 'architecture_lab_queries.rb' -ScriptArgs @('after')
  }
  if ($Step -in @('All', 'Exercise')) {
    # Runtime, queue, load and restore phases are kept in the companion script.
    . (Join-Path $PSScriptRoot 'architecture-lab-exercise.ps1')
  }
  if ($Step -eq 'Cleanup') { Remove-LabResources }
} finally {
  if ($Step -eq 'All') { Remove-LabResources }
}
