BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    function Get-CIPPSecret { param($Name) }
    function Set-CIPPSecret { param($Name, $Value) }
    . (Join-Path $Folder 'New-CIPPCloudBackupKey.ps1')
    . (Join-Path $Folder 'Get-CIPPCloudBackupKey.ps1')
    . (Join-Path $Folder 'Protect-CIPPCloudBackupData.ps1')
    . (Join-Path $Folder 'Unprotect-CIPPCloudBackupData.ps1')

    $script:KeyId = [guid]::NewGuid().ToString()
    $script:Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $script:Plain = [System.Text.Encoding]::UTF8.GetBytes('{"Area":"ConditionalAccess","Sections":{}}' * 50)
}

Describe 'New-CIPPCloudBackupKey' {
    It 'stores 32 random bytes under its CloudBackupKey name and returns the id' {
        Mock Set-CIPPSecret { $script:Stored = @{ Name = $Name; Value = $Value } }
        $Id = New-CIPPCloudBackupKey
        [guid]::Parse($Id) | Should -Not -BeNullOrEmpty
        $Stored.Name | Should -Be "CloudBackupKey-$Id"
        [System.Convert]::FromBase64String($Stored.Value).Length | Should -Be 32
    }
}

Describe 'Get-CIPPCloudBackupKey' {
    It 'returns the stored key bytes' {
        Mock Get-CIPPSecret { [System.Convert]::ToBase64String($script:Key) }
        $Result = Get-CIPPCloudBackupKey -KeyId $KeyId
        $Result.GetType() | Should -Be ([byte[]])
        [System.Convert]::ToBase64String($Result) | Should -Be ([System.Convert]::ToBase64String($Key))
        Should -Invoke Get-CIPPSecret -ParameterFilter { $Name -eq "CloudBackupKey-$KeyId" }
    }

    It 'throws ItemNotFoundException for an unknown key' {
        Mock Get-CIPPSecret { $null }
        { Get-CIPPCloudBackupKey -KeyId $KeyId } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }
}

Describe 'Protect and Unprotect-CIPPCloudBackupData' {
    BeforeEach {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
    }

    It 'writes the documented header and round-trips the data' {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        $Encrypted.Length | Should -Be ($Plain.Length + 112)
        [System.Text.Encoding]::ASCII.GetString($Encrypted, 0, 8) | Should -Be 'CIPPENC1'
        [guid]::new([byte[]]$Encrypted[8..23]).ToString() | Should -Be $KeyId

        $Decrypted = Unprotect-CIPPCloudBackupData -Bytes $Encrypted
        [System.Convert]::ToBase64String($Decrypted) | Should -Be ([System.Convert]::ToBase64String($Plain))
        Should -Invoke Get-CIPPCloudBackupKey -Times 1 -ParameterFilter { $KeyId -eq $script:KeyId }
    }

    It 'uses a fresh data key and nonce for every object' {
        $First = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        $Second = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        [System.Convert]::ToBase64String($First) | Should -Not -Be ([System.Convert]::ToBase64String($Second))
    }

    It 'round-trips empty data' {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes ([byte[]]::new(0)) -KeyId $KeyId -Key $Key
        $Encrypted.Length | Should -Be 112
        (Unprotect-CIPPCloudBackupData -Bytes $Encrypted).Length | Should -Be 0
    }

    It 'rejects tampering with <Name>' -TestCases @(
        @{ Name = 'the ciphertext'; Offset = 150 }
        @{ Name = 'the data tag'; Offset = 100 }
        @{ Name = 'the wrapped key'; Offset = 40 }
        @{ Name = 'the wrap tag'; Offset = 70 }
        @{ Name = 'the data nonce'; Offset = 90 }
    ) {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        $Encrypted[$Offset] = $Encrypted[$Offset] -bxor 0x01
        { Unprotect-CIPPCloudBackupData -Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
    }

    It 'rejects a header whose key id was swapped to another valid key' {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        $OtherId = [guid]::NewGuid()
        [System.Array]::Copy($OtherId.ToByteArray(), 0, $Encrypted, 8, 16)
        { Unprotect-CIPPCloudBackupData -Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
        Should -Invoke Get-CIPPCloudBackupKey -ParameterFilter { $KeyId -eq $OtherId.ToString() }
    }

    It 'fails with the wrong key' {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        Mock Get-CIPPCloudBackupKey { , [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32) }
        { Unprotect-CIPPCloudBackupData -Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
    }

    It 'fails when the key id is unknown' {
        $Encrypted = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key $Key
        Mock Get-CIPPCloudBackupKey { throw [System.Management.Automation.ItemNotFoundException]::new('Encryption key was not found.') }
        { Unprotect-CIPPCloudBackupData -Bytes $Encrypted } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'rejects data that is not in the format' {
        { Unprotect-CIPPCloudBackupData -Bytes ([byte[]]::new(200)) } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'rejects a key that is not 32 bytes' {
        { Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $KeyId -Key ([byte[]]::new(16)) } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}
