$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path -LiteralPath '.env')) {
  $showcaseEnvironment = Get-Content -LiteralPath '.env.example' -Raw -Encoding UTF8
  foreach ($showcaseSecretName in @('SECRET_KEY_BASE', 'MESH_GATEWAY_SECRET', 'MESH_WEBHOOK_SECRET')) {
    $showcaseSecretValue = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $showcaseEnvironment = $showcaseEnvironment.Replace("$showcaseSecretName=", "$showcaseSecretName=$showcaseSecretValue")
  }
  [IO.File]::WriteAllText((Join-Path $PWD '.env'), $showcaseEnvironment, [Text.UTF8Encoding]::new($false))
}
& node scripts/prepare-publishing.mjs
if ($LASTEXITCODE -ne 0) { throw 'Showcase credentials preparation failed.' }
function Invoke-MeshCommand {
  param([string[]]$Arguments)
  & docker @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Docker step failed: $($Arguments -join ' ')" }
}

Invoke-MeshCommand -Arguments @('compose', '--profile', 'files', 'build', 'api', 'db', 'scanner')
Invoke-MeshCommand -Arguments @('compose', '--profile', 'files', 'up', '-d', 'db', 'scanner')
Invoke-MeshCommand -Arguments @('compose', 'run', '--rm', 'api', 'bundle', 'install', '--jobs', '4')
Invoke-MeshCommand -Arguments @('compose', 'run', '--rm', '--no-deps', 'web', 'npm', 'ci', '--ignore-scripts')
Invoke-MeshCommand -Arguments @('compose', 'run', '--rm', 'api', 'bin/rails', 'db:prepare')
Invoke-MeshCommand -Arguments @('compose', 'run', '--rm', 'api', 'bin/rails', 'db:seed')
Invoke-MeshCommand -Arguments @('compose', '--profile', 'files', 'up', '-d', 'api', 'gateway', 'worker', 'dispatcher', 'web', 'edge')
Write-Host 'MESH: http://localhost:3200'
