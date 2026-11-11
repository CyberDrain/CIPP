BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-PrivateStatic([type]$Type, [string]$Name) {
        $Type.GetField($Name, [System.Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
    }
}

Describe 'CIPPSharp static holders' {
    It 'does not remember report image names that do not ship' {
        foreach ($i in 1..1000) {
            [CIPP.Reporting.ReportComponents]::DecodeImage("/reportImages/missing$i.png", $true) | Should -BeNullOrEmpty
        }
        (Get-PrivateStatic ([CIPP.Reporting.ReportComponents]) 'ReportImageCache').Count | Should -BeLessOrEqual 20
    }
}
