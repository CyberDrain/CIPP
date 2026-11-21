BeforeDiscovery {
    $script:Operations = @(
        @{ Verb = 'Set'; Noun = 'Object'; Params = @{ Key = 'a/b.json.gz'; Body = [byte[]](1, 2, 3); ContentType = 'application/gzip'; Metadata = @{ Area = 'Intune' } } }
        @{ Verb = 'Get'; Noun = 'Object'; Params = @{ Key = 'a/b.json.gz'; VersionId = 'v1' } }
        @{ Verb = 'Get'; Noun = 'ObjectList'; Params = @{ Prefix = 'a/' } }
        @{ Verb = 'Get'; Noun = 'ObjectVersionList'; Params = @{ Prefix = 'a/' } }
        @{ Verb = 'Receive'; Noun = 'ObjectStream'; Params = @{ Key = 'a/b'; VersionId = 'v1'; OutStream = [System.IO.MemoryStream]::new() } }
        @{ Verb = 'Remove'; Noun = 'Object'; Params = @{ Key = 'a/b.json.gz' } }
        @{ Verb = 'Remove'; Noun = 'Object'; Params = @{ Key = 'a/b.json.gz'; VersionId = 'v1' } }
        @{ Verb = 'Get'; Noun = 'RetentionRule'; Params = @{ RuleName = 'cipp-p' } }
        @{ Verb = 'Set'; Noun = 'RetentionRule'; Params = @{ RuleName = 'cipp-p'; Prefix = 'p/'; Days = 90 } }
        @{ Verb = 'Set'; Noun = 'RetentionRule'; Params = @{ RuleName = 'cipp-p'; Prefix = 'p/'; Days = 90; Mode = 'Versioned' } }
        @{ Verb = 'Remove'; Noun = 'RetentionRule'; Params = @{ RuleName = 'cipp-p' } }
        @{ Verb = 'Get'; Noun = 'Versioning'; Params = @{} }
    )
}

BeforeAll {
    $Operations = @(
        @{ Verb = 'Set'; Noun = 'Object' }, @{ Verb = 'Get'; Noun = 'Object' }, @{ Verb = 'Get'; Noun = 'ObjectList' }, @{ Verb = 'Remove'; Noun = 'Object' }
        @{ Verb = 'Get'; Noun = 'ObjectVersionList' }, @{ Verb = 'Receive'; Noun = 'ObjectStream' }
        @{ Verb = 'Get'; Noun = 'RetentionRule' }, @{ Verb = 'Set'; Noun = 'RetentionRule' }, @{ Verb = 'Remove'; Noun = 'RetentionRule' }, @{ Verb = 'Get'; Noun = 'Versioning' }
    )
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    foreach ($Operation in $Operations) {
        foreach ($Provider in 'Azure', 'S3') {
            $Name = "$($Operation.Verb)-CIPPCloudBackup$Provider$($Operation.Noun)"
            $null = New-Item -Path "function:script:$Name" -Value { param($Destination, $Key, $Body, $ContentType, $Metadata, $Prefix, $RuleName, $Days, $Mode, $VersionId, $OutStream) } -Force
        }
        . (Join-Path $Folder "$($Operation.Verb)-CIPPCloudBackup$($Operation.Noun).ps1")
    }

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CIPPSecret { param($Name) }
    . (Join-Path $Folder 'Get-CIPPCloudBackupDestination.ps1')
}

Describe 'Cloud backup provider dispatch' {
    It '<Verb>-CIPPCloudBackup<Noun> routes <Provider> destinations to the <Provider> function with the same parameters' -ForEach @(
        foreach ($Operation in $Operations) {
            @{ Verb = $Operation.Verb; Noun = $Operation.Noun; Params = $Operation.Params; Provider = 'AzureBlob'; Target = 'Azure'; Other = 'S3' }
            @{ Verb = $Operation.Verb; Noun = $Operation.Noun; Params = $Operation.Params; Provider = 'S3'; Target = 'S3'; Other = 'Azure' }
        }
    ) {
        $Target = "$Verb-CIPPCloudBackup$Target$Noun"
        $OtherName = "$Verb-CIPPCloudBackup$Other$Noun"
        Mock $Target { 'routed' }
        Mock $OtherName { 'wrong' }
        $Destination = [pscustomobject]@{ Provider = $Provider }
        & "$Verb-CIPPCloudBackup$Noun" -Destination $Destination @Params | Should -Be 'routed'
        Should -Invoke $OtherName -Times 0 -Exactly
        Should -Invoke $Target -Times 1 -Exactly -ParameterFilter {
            $Ok = $Destination.Provider -eq $Provider
            foreach ($Name in $Params.Keys) {
                $Bound = Get-Variable -Name $Name -ValueOnly
                if ("$Bound" -ne "$($Params[$Name])") { $Ok = $false }
            }
            $Ok
        }
    }

    It 'throws ArgumentException for an unknown provider' {
        { Get-CIPPCloudBackupVersioning -Destination ([pscustomobject]@{ Provider = 'Dropbox' }) } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Get-CIPPCloudBackupDestination' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{
                PartitionKey = 'CloudBackupDestination'; RowKey = '11111111-1111-1111-1111-111111111111'; Name = 'Azure'; Provider = 'AzureBlob'
                StorageAccount = 'acct'; Container = 'backups'; ForcePathStyle = 'false'
                LastTest = '{"Write":true,"Read":true,"Delete":true,"Lifecycle":false,"Versioning":"Enabled","Passed":false,"Errors":["Lifecycle: denied"]}'
                LastTestedAt = '2026-11-20T10:00:00Z'
            }
        }
        Mock Get-CIPPSecret { 'the-secret' }
    }

    It 'returns the row fields with LastTest parsed and no secret by default' {
        $Destination = Get-CIPPCloudBackupDestination
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' -and $Filter -eq "PartitionKey eq 'CloudBackupDestination'" }
        $Destination.Id | Should -Be '11111111-1111-1111-1111-111111111111'
        $Destination.StorageAccount | Should -Be 'acct'
        $Destination.ForcePathStyle | Should -BeFalse
        $Destination.LastTest.Lifecycle | Should -BeFalse
        $Destination.LastTest.Errors | Should -Be @('Lifecycle: denied')
        $Destination.PSObject.Properties['Secret'] | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPSecret -Times 0 -Exactly
    }

    It 'reads one destination and its secret' {
        $Destination = Get-CIPPCloudBackupDestination -Id '11111111-1111-1111-1111-111111111111' -IncludeSecret
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 'CloudBackupDestination' and RowKey eq '11111111-1111-1111-1111-111111111111'" }
        Should -Invoke Get-CIPPSecret -ParameterFilter { $Name -eq 'CloudBackupDest-11111111-1111-1111-1111-111111111111' }
        $Destination.Secret | Should -Be 'the-secret'
    }

    It 'rejects an id that is not a guid' {
        { Get-CIPPCloudBackupDestination -Id "x' or RowKey ne '" } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}
