# Start CIPP local dev environment for windows.
#
# Runs docker compose up which starts:
#   1. Azurite (local Azure Storage emulator)
#   2. Craft API container (mounts ./backend for PS modules)
#   3. Next.js frontend started in ps directly since bind mounts are really slow in Docker for Windows
#
# Prerequisites:
#   - Docker Desktop running
#   - Ports 3000, 5196, 10000-10002 free
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

$RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$frontendPath = Join-Path -Path $RepoRoot -ChildPath 'frontend'
$dockerpath = Join-Path -Path $RepoRoot -ChildPath 'build'
$frontendCommand = 'try { yarn install --network-timeout 500000; yarn run dev } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$frontendEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($frontendCommand))
$dockerCommand = 'try { ./tools/build-dev-modules.ps1; docker compose -f docker-compose-no-frontend.yml up --pull always --watch } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$dockerEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dockerCommand))
$watcherCommand = 'try { ./tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$watcherEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watcherCommand))
docker volume create cipp-ng_azurite-data
wt --title CIPP-Docker -d $dockerpath pwsh -EncodedCommand $dockerEncoded`; new-tab --title 'CIPP Modules' -d $dockerpath pwsh -EncodedCommand $watcherEncoded`; new-tab --title 'CIPP Frontend' -d $frontendPath pwsh -EncodedCommand $frontendEncoded

Write-Host "`n  API + Frontend: http://localhost:5196" -ForegroundColor Green
