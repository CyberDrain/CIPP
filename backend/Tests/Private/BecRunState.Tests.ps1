BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Set-CIPPBecRunState.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunState.ps1')

    # The table service rejects any string property over 64 KiB (32768 UTF-16 characters).
    # The in-memory table below enforces that limit so a regression fails the same way production does.
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Add-CIPPAzDataTableEntity {
        param($TableName, $Entity, [switch]$Force)
        foreach ($Row in @($Entity)) {
            if ($script:FailHead -and $Row.RowKey -notlike '*~*') { throw 'simulated head write failure' }
            foreach ($Value in $Row.Values) {
                if ($Value -is [string] -and $Value.Length -gt 32768) {
                    throw 'The property value exceeds the maximum allowed size (64KB).'
                }
            }
            foreach ($Old in @($script:Rows | Where-Object { $_.PartitionKey -eq $Row.PartitionKey -and $_.RowKey -eq $Row.RowKey })) {
                $null = $script:Rows.Remove($Old)
            }
            $script:Rows.Add($Row)
        }
    }
    function Get-CIPPAzDataTableEntity {
        [CmdletBinding()]
        param($TableName, $Filter, $Property, $First)
        if ($script:TableReadError) { Write-Error 'table read failed'; return }
        $PartitionKey = [regex]::Match($Filter, "PartitionKey eq '([^']*)'").Groups[1].Value
        $Rows = @($script:Rows | Where-Object { $_.PartitionKey -eq $PartitionKey })
        # Azure Table Storage compares RowKey ordinally; PowerShell's -ge/-lt are culture-aware.
        foreach ($Clause in @(
                @{ Pattern = "RowKey eq '([^']*)'"; Test = { param($Row, $Value) $Row.RowKey -eq $Value } }
                @{ Pattern = "RowKey ge '([^']*)'"; Test = { param($Row, $Value) [System.StringComparer]::Ordinal.Compare($Row.RowKey, $Value) -ge 0 } }
                @{ Pattern = "RowKey lt '([^']*)'"; Test = { param($Row, $Value) [System.StringComparer]::Ordinal.Compare($Row.RowKey, $Value) -lt 0 } }
            )) {
            $Match = [regex]::Match($Filter, $Clause.Pattern)
            if ($Match.Success) {
                $Value = $Match.Groups[1].Value
                $Rows = @($Rows | Where-Object { & $Clause.Test $_ $Value })
            }
        }
        return $Rows
    }
    function Remove-CIPPAzDataTableEntity {
        param($TableName, $Entity, [switch]$Force)
        foreach ($Row in @($Entity)) {
            foreach ($Old in @($script:Rows | Where-Object { $_.PartitionKey -eq $Row.PartitionKey -and $_.RowKey -eq $Row.RowKey })) {
                $null = $script:Rows.Remove($Old)
            }
        }
    }
}

Describe 'BEC run state chunking' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        $script:FailHead = $false
        $script:TableReadError = $false
    }

    It 'writes a small section as one row' {
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '01-AuditLog' -Values @{ AuditLogEnabled = $true }
        $script:Rows.Count | Should -Be 1
        $script:Rows[0].RowKey | Should -Be '01-AuditLog'
        $script:Rows[0].ContainsKey('ChunkCount') | Should -BeFalse
    }

    It 'splits a value the table service cannot hold and reads it back unchanged' {
        $Payload = 'x' * 100000
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @($Payload) }
        $script:Rows.Count | Should -BeGreaterThan 1
        ($script:Rows | ForEach-Object { $_.Data.Length } | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 32768
        (Get-CIPPBecRunState -CaseId 'BEC-1').MailRecords[0] | Should -Be $Payload
    }

    It 'round-trips a multi-megabyte value over many part rows' {
        $Payload = 'abcde' * 400000
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @($Payload) }
        $script:Rows.Count | Should -BeGreaterThan 50
        (Get-CIPPBecRunState -CaseId 'BEC-1').MailRecords[0] | Should -Be $Payload
    }

    It 'keeps the newest value and ignores the superseded generation' {
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @('x' * 100000) }
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @('y' * 100000) }
        (Get-CIPPBecRunState -CaseId 'BEC-1').MailRecords[0] | Should -Be ('y' * 100000)
        # The old parts stay readable for a reader already following the old head; -Clear removes them.
        $script:Rows.Count | Should -BeGreaterThan 1
        Set-CIPPBecRunState -CaseId 'BEC-1' -Clear
        $script:Rows.Count | Should -Be 0
    }

    It 'leaves the previous value in place when the head write fails' {
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @('x' * 100000) }
        $script:FailHead = $true
        { Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @('y' * 100000) } } | Should -Throw '*simulated*'
        $script:FailHead = $false
        (Get-CIPPBecRunState -CaseId 'BEC-1').MailRecords[0] | Should -Be ('x' * 100000)
    }

    It 'never splits a surrogate pair at a chunk boundary' {
        $Emoji = [char]::ConvertFromUtf32(0x1F600)
        foreach ($Pad in 23990..24010) {
            $Value = ('a' * $Pad) + $Emoji + 'b'
            $CaseId = "BEC-$Pad"
            Set-CIPPBecRunState -CaseId $CaseId -Section '11-Activity' -Values @{ MailRecords = @($Value) }
            (Get-CIPPBecRunState -CaseId $CaseId).MailRecords[0] | Should -Be $Value
        }
    }

    It 'reads a section written before chunking existed' {
        $script:Rows.Add(@{
                PartitionKey = 'BEC-1'
                RowKey       = '01-AuditLog'
                Data         = '{"AuditLogEnabled":true}'
            })
        (Get-CIPPBecRunState -CaseId 'BEC-1').AuditLogEnabled | Should -BeTrue
    }

    It 'projects only the named values but still merges Completeness' {
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '01-AuditLog' -Values @{ AuditLogEnabled = $true; PermissionsLog = @('p1') }
        $State = Get-CIPPBecRunState -CaseId 'BEC-1' -Name 'AuditLogEnabled'
        $State.AuditLogEnabled | Should -BeTrue
        $State.ContainsKey('PermissionsLog') | Should -BeFalse
        $State.Completeness -is [System.Collections.IDictionary] | Should -BeTrue
    }

    It 'refuses to return a section whose parts are missing' {
        Set-CIPPBecRunState -CaseId 'BEC-1' -Section '11-Activity' -Values @{ MailRecords = @('x' * 100000) }
        $Part = $script:Rows | Where-Object { $_.RowKey -like '11-Activity~*' } | Select-Object -First 1
        $null = $script:Rows.Remove($Part)
        { Get-CIPPBecRunState -CaseId 'BEC-1' } | Should -Throw '*incomplete*'
    }

    It 'surfaces a non-terminating table read error instead of returning empty state' {
        $script:TableReadError = $true
        { Get-CIPPBecRunState -CaseId 'BEC-1' } | Should -Throw '*table read failed*'
    }
}
