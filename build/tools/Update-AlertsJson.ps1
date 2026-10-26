<#
.SYNOPSIS
Copies alerts.json from the CIPP frontend to the backend Config folder.

.DESCRIPTION
The frontend alert catalog (frontend/src/data/alerts.json) is the copy you edit. The scheduler reads
backend/Config/alerts.json for each alert's minimumRunInterval, because the container ships only the
built frontend. Run this after editing the frontend copy; backend/Tests/Static/AlertsJsonSync.Tests.ps1
fails while the two differ.

.EXAMPLE
Update-AlertsJson.ps1
#>

$Source = Join-Path $PSScriptRoot '..\..\frontend\src\data\alerts.json'
$Destination = Join-Path $PSScriptRoot '..\..\backend\Config\alerts.json'

if (-not (Test-Path $Source)) {
    Write-Host "Source file not found: $Source" -ForegroundColor Red
    return
}
if ((Test-Path $Destination) -and (Get-FileHash $Source).Hash -eq (Get-FileHash $Destination).Hash) {
    Write-Host 'No changes detected (SHA256 match). Destination not overwritten.' -ForegroundColor Yellow
    return
}
Copy-Item -Path $Source -Destination $Destination -Force
Write-Host "Copied $Source to $Destination." -ForegroundColor Green
