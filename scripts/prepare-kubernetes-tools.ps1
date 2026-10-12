$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path -LiteralPath SHOWCASE.md) -or (Split-Path $PWD -Leaf) -ne 'MESH-showcase') { throw 'Independent showcase checkout required.' }
$taskDirectory = Join-Path $PWD '.cache/tools/kubectl'
New-Item -ItemType Directory -Force -Path $taskDirectory | Out-Null
$taskVersion = 'v1.35.5'
$taskUrl = "https://dl.k8s.io/release/$taskVersion/bin/windows/amd64/kubectl.exe"
$taskFile = Join-Path $taskDirectory 'kubectl.exe'
Invoke-WebRequest $taskUrl -OutFile $taskFile
$taskChecksum = (Invoke-RestMethod "$taskUrl.sha256").Trim()
if ($taskChecksum -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash $taskFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskChecksum) { throw 'kubectl checksum verification failed.' }
& $taskFile version --client --output=json
if ($LASTEXITCODE -ne 0) { throw 'kubectl readiness failed.' }
