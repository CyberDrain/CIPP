function Get-CIPPEnrollmentRestrictionPlatformTypes {
    <#
    .SYNOPSIS
        The Graph platform types behind one CIPP enrollment restriction platform.
    .DESCRIPTION
        Intune stores a device type restriction as one singlePlatformRestriction object per Graph
        platform type, and the portal shows objects with the same name on the same platform tab
        as one restriction. Android is the one platform made of two objects: androidForWork
        (Android Enterprise work profile) and android (Android device administrator).

        Each type maps to the prefix its settings use in CIPP's flat settings shape:
        androidForWork, ios, mac and windows use the unprefixed names, the device administrator
        half of Android uses 'deviceAdmin'. HasVersions is false for macOS, which carries no OS
        version limit.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Platform
    )

    $Map = [ordered]@{
        android = @(
            [PSCustomObject]@{ PlatformType = 'androidForWork'; Prefix = ''; HasVersions = $true; HasManufacturers = $false }
            [PSCustomObject]@{ PlatformType = 'android'; Prefix = 'deviceAdmin'; HasVersions = $true; HasManufacturers = $true }
        )
        ios     = @([PSCustomObject]@{ PlatformType = 'ios'; Prefix = ''; HasVersions = $true; HasManufacturers = $false })
        macOS   = @([PSCustomObject]@{ PlatformType = 'mac'; Prefix = ''; HasVersions = $false; HasManufacturers = $false })
        windows = @([PSCustomObject]@{ PlatformType = 'windows'; Prefix = ''; HasVersions = $true; HasManufacturers = $false })
    }

    if ([string]::IsNullOrWhiteSpace($Platform)) { return $Map }
    $Key = @($Map.Keys | Where-Object { $_ -eq $Platform }) | Select-Object -First 1
    if (-not $Key) { throw "Unsupported enrollment restriction platform '$Platform'. Use one of: $(@($Map.Keys) -join ', ')." }
    $Map[$Key]
}
