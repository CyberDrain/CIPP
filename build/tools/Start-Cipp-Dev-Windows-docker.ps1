# Start CIPP local dev environment for windows.
#
# Runs docker compose up which starts:
#   1. Azurite (local Azure Storage emulator). Cache tables are emptied first if the
#      on-disk LokiJS file is large enough to crash Azurite's Table service.
#   2. Craft API container (mounts ./backend for PS modules)
#   3. Next.js frontend started in ps directly since bind mounts are really slow in Docker for Windows
#
# Prerequisites:
#   - Docker Desktop running
#   - Ports 3000, 5196, 10000-10002 free
#   - Node.js on PATH (or nvm-windows with the engines.node version from frontend/package.json)
#
# Access everything via http://localhost:5196

$ErrorActionPreference = 'Stop'

Write-Host "`n=== CIPP Dev Environment ===" -ForegroundColor Cyan

# Verify Windows Terminal is available
Get-Command wt -ErrorAction Stop | Out-Null

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI not found. Install Docker Desktop and ensure `docker` is on PATH.'
}

Write-Host 'Checking Docker daemon....' -ForegroundColor DarkGray
docker info --format '{{.ServerVersion}}' 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker daemon is not running. Start Docker Desktop, wait until it is ready, then re-run this script.'
}
Write-Host '  Docker is running.' -ForegroundColor Green

$RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# Azurite loads all tables as one Node string (~512 MiB cap). Trim caches first if the
# volume is already large enough to crash Table startup, and free 10000-10002 if we stop it.
docker volume create cipp-ng_azurite-data | Out-Null
try {
    & (Join-Path $PSScriptRoot 'Clear-CippAzuriteCacheIfNeeded.ps1')
} catch {
    Write-Warning "Azurite cache trim skipped; continuing startup. $($_.Exception.Message)"
}

# Free host frontend port by stopping leftover Next.js/node processes from prior runs
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue

# 3000 = Next.js on host, 5196 = Craft API, 10000-10002 = Azurite
Write-Host 'Checking required ports...' -ForegroundColor DarkGray
$requiredPorts = @(3000, 5196, 10000, 10001, 10002)
$blocked = @()
foreach ($port in $requiredPorts) {
    $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $listeners) { continue }

    $owners = foreach ($conn in $listeners) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        if ($proc) { '{0} (PID {1})' -f $proc.ProcessName, $proc.Id } else { 'PID {0}' -f $conn.OwningProcess }
    }
    $blocked += "  - ${port}: $(($owners | Select-Object -Unique) -join ', ')"
}
if ($blocked.Count -gt 0) {
    throw "Required port(s) are already in use:`n$($blocked -join "`n")`n`nStop the conflicting process/container, then re-run this script."
}
Write-Host ("  Ports free: {0}" -f ($requiredPorts -join ', ')) -ForegroundColor Green

$frontendPath = Join-Path -Path $RepoRoot -ChildPath 'frontend'
$dockerpath = Join-Path -Path $RepoRoot -ChildPath 'build'
# Prefer nvm-windows engines.node when that version is installed; otherwise use PATH Node.
$frontendCommand = @'
try {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js not found on PATH. Install Node or nvm-windows with the version from frontend/package.json engines.node.'
  }

  $engines = (Get-Content package.json -Raw | ConvertFrom-Json).engines.node
  $required = $null
  $usedNvm = $false
  if ($engines -and $engines -match '(\d+\.\d+\.\d+)') {
    $required = $Matches[1]
    $nvmHome = $env:NVM_HOME
    if (-not $nvmHome) { $nvmHome = Join-Path $env:LOCALAPPDATA 'nvm' }
    $nodeDir = Join-Path $nvmHome "v$required"
    if (Test-Path (Join-Path $nodeDir 'node.exe')) {
      # Session-local PATH pin (avoids nvm use symlink/admin side effects).
      $env:Path = "$nodeDir;$env:Path"
      $usedNvm = $true
      Write-Host "Using Node $required via nvm ($nodeDir)" -ForegroundColor Green
    } else {
      Write-Host "nvm Node $required not found; using Node from PATH." -ForegroundColor DarkYellow
    }
  }

  $active = (node -v).TrimStart('v')
  if (-not $usedNvm) {
    Write-Host "Using Node $active" -ForegroundColor Green
  }
  if ($required -and $active -ne $required) {
    Write-Warning "Active Node is $active; package.json engines.node wants $required."
  }

  yarn install --network-timeout 500000
  if ($LASTEXITCODE -ne 0) { throw "yarn install failed with exit code $LASTEXITCODE" }
  yarn run dev
} catch {
  Write-Error $_.Exception.Message
} finally {
  Read-Host 'Press Enter to exit'
}
'@
$frontendEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($frontendCommand))
# Proxyman trust (when set up via Export-ProxymanCert.ps1) is applied automatically through
# the optional CA mount in docker-compose-no-frontend.yml + build/.env, which Compose loads
# on its own — no -f overlay needed here. The frontend runs on the host in this loop, so it
# trusts Proxyman via the Windows certificate store, not a container mount.
# --pull always leaves the previous craft:dev/azurite image dangling on every update; drop them first.
$dockerCommand = "try { ./tools/build-dev-modules.ps1; docker image prune -f; docker compose -f docker-compose-no-frontend.yml up --pull always --watch } catch { Write-Error `$_.Exception.Message } finally { Read-Host 'Press Enter to exit' }"
$dockerEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dockerCommand))
$watcherCommand = 'try { ./tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$watcherEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watcherCommand))
wt --title CIPP-Docker -d $dockerpath pwsh -EncodedCommand $dockerEncoded`; new-tab --title 'CIPP Modules' -d $dockerpath pwsh -EncodedCommand $watcherEncoded`; new-tab --title 'CIPP Frontend' -d $frontendPath pwsh -EncodedCommand $frontendEncoded

Write-Host "`n  API + Frontend: http://localhost:5196" -ForegroundColor Green
