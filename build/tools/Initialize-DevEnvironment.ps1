Write-Host 'Initializing development environment...' -ForegroundColor Green
# Backend root - the old CIPP-API repo now lives under backend\ in the monorepo
$CippRoot = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.FullName 'backend'
Write-Host "CIPP backend root: $CippRoot" -ForegroundColor Green
$env:CIPPRootPath = $CippRoot

$SettingsPath = Join-Path $PSScriptRoot 'local.settings.json'
try {
    # -Raw + -ErrorAction Stop: without both, a missing file is a non-terminating error that
    # this catch never sees, leaving every setting below unset and failing much later with an
    # opaque 'Connection string parsing error' from AzBobbyTables.
    $CIPPSettings = Get-Content $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Failed to read '$SettingsPath'. Ensure the file exists and is valid JSON. Error: $($_.Exception.Message)"
}

# NonLocalHostAzurite is what flips the backend into dev mode when AzureWebJobsStorage is a full
# Azurite connection string rather than the literal 'UseDevelopmentStorage=true' - without it
# Get-CIPPAuthentication reaches for Key Vault instead of the DevSecrets table.
$ValidKeys = @('AzureWebJobsStorage', 'NonLocalHostAzurite')
foreach ($Key in $CIPPSettings.PSObject.Properties.Name) {
    if ($ValidKeys -contains $Key) {
        [Environment]::SetEnvironmentVariable($Key, $CIPPSettings.$Key, [System.EnvironmentVariableTarget]::Process)
    }
}

if ([string]::IsNullOrWhiteSpace($env:AzureWebJobsStorage)) {
    throw "'$SettingsPath' did not provide a value for AzureWebJobsStorage. Add the Azurite connection string before re-running."
}

# Verify the cipp docker stack is already running by checking that Azurite answers.
# Probe with a real TCP connect rather than Get-NetTCPConnection: Docker Desktop's WSL2 backend
# proxies published ports without creating a Windows-visible listening socket, so the listener
# tables are empty even for ports that work fine (5196 included).
Write-Host 'Checking Azurite...' -ForegroundColor DarkGray
$ConnectionParts = @{}
foreach ($Pair in ($env:AzureWebJobsStorage -split ';')) {
    if ($Pair -match '^\s*([^=]+?)\s*=\s*(.+)$') { $ConnectionParts[$Matches[1]] = $Matches[2] }
}
$RequiredEndpoints = @(
    @{ Service = 'Blob'; Key = 'BlobEndpoint'; DefaultPort = 10000 }
    @{ Service = 'Queue'; Key = 'QueueEndpoint'; DefaultPort = 10001 }
    @{ Service = 'Table'; Key = 'TableEndpoint'; DefaultPort = 10002 }
)
$Unreachable = @()
foreach ($Endpoint in $RequiredEndpoints) {
    # Fall back to the emulator defaults when the connection string is 'UseDevelopmentStorage=true'
    $TargetHost = '127.0.0.1'
    $TargetPort = $Endpoint.DefaultPort
    $Uri = $ConnectionParts[$Endpoint.Key] -as [uri]
    if ($Uri -and $Uri.Host) {
        $TargetHost = $Uri.Host
        if ($Uri.Port -gt 0) { $TargetPort = $Uri.Port }
    }

    $Client = [System.Net.Sockets.TcpClient]::new()
    try {
        $Connected = $Client.ConnectAsync($TargetHost, $TargetPort).Wait(3000) -and $Client.Connected
    } catch {
        $Connected = $false
    } finally {
        $Client.Dispose()
    }

    if ($Connected) {
        Write-Host ('  {0} ({1}:{2}): reachable' -f $Endpoint.Service, $TargetHost, $TargetPort) -ForegroundColor DarkGray
    } else {
        $Unreachable += '  - {0} ({1}:{2})' -f $Endpoint.Service, $TargetHost, $TargetPort
    }
}
if ($Unreachable.Count -gt 0) {
    throw "Azurite is not reachable on all required endpoints:`n$($Unreachable -join "`n")`n`nStart the windows local dev script first (build\tools\Start-Cipp-Dev-Windows-docker.ps1), then re-run this script."
}
Write-Host '  Azurite is reachable on all required endpoints.' -ForegroundColor Green

$CIPPSharpDllPath = Join-Path $CippRoot 'Shared\CIPPSharp\bin\CIPPSharp.dll'
if ((Test-Path $CIPPSharpDllPath) -and !('CIPP.CIPPRestClient' -as [type])) {
    [Reflection.Assembly]::LoadFile($CIPPSharpDllPath) | Out-Null
}

# Remove previously loaded modules to force reloading if new code changes were made
$LoadedModules = Get-Module | Select-Object -ExpandProperty Name
switch ($LoadedModules) {
    'CIPPCore' { Remove-Module CIPPCore -Force }
    'CippExtensions' { Remove-Module CippExtensions -Force }
}

Import-Module ( Join-Path $CippRoot 'Modules\AzBobbyTables' )
Import-Module ( Join-Path $CippRoot 'Modules\DNSHealth' )
Import-Module ( Join-Path $CippRoot 'Modules\CIPPCore' )
Import-Module ( Join-Path $CippRoot 'Modules\CippExtensions' )
# This is a comment
$Auth = Get-CIPPAuthentication
if ($Auth) {
    Write-Host 'Development environment initialized successfully!' -ForegroundColor Green
} else {
    Write-Host 'Failed to initialize development environment. Please check the error messages above.' -ForegroundColor Red
}
