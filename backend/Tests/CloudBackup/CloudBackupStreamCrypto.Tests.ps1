BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    function Get-CIPPCloudBackupKey { param($KeyId) }
    foreach ($Name in 'Read-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStreamBlock') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $script:KeyId = [guid]::NewGuid().ToString()
    $script:Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)

    function New-Plain {
        param([int]$Length)
        $Bytes = [byte[]]::new($Length)
        for ($i = 0; $i -lt $Length; $i++) { $Bytes[$i] = [byte](($i * 31 + 7) % 251) }
        , $Bytes
    }

    function Protect-Bytes {
        param([byte[]]$Bytes, [int]$ChunkSize = 64)
        $Out = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Bytes)) -OutputStream $Out -KeyId $KeyId -Key $Key -ChunkSize $ChunkSize
        , $Out.ToArray()
    }

    function Unprotect-Bytes {
        param([byte[]]$Bytes)
        $Out = [System.IO.MemoryStream]::new()
        $null = Unprotect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Bytes)) -OutputStream $Out
        , $Out.ToArray()
    }

    function Get-Frame {
        param([byte[]]$Bytes, [int]$Index, [int]$ChunkSize = 64)
        $Start = 100 + $Index * ($ChunkSize + 16)
        , [byte[]]$Bytes[$Start..($Start + $ChunkSize + 15)]
    }
}

Describe 'CIPPENC2 streaming encryption' {
    BeforeEach {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
    }

    It 'round-trips <Length> bytes with 64-byte chunks' -ForEach @(
        @{ Length = 0 }, @{ Length = 1 }, @{ Length = 63 }, @{ Length = 64 }, @{ Length = 65 }, @{ Length = 640 }, @{ Length = 1000 }
    ) {
        $Plain = New-Plain $Length
        $Encrypted = Protect-Bytes $Plain
        $Frames = [Math]::Floor($Length / 64) + 1
        $Encrypted.Length | Should -Be (100 + $Length + 16 * $Frames)
        [System.Text.Encoding]::ASCII.GetString($Encrypted, 0, 8) | Should -Be 'CIPPENC2'
        [guid]::new([byte[]]$Encrypted[8..23]).ToString() | Should -Be $KeyId
        ([int]$Encrypted[26] -shl 8) + $Encrypted[27] | Should -Be 64
        [System.Convert]::ToBase64String((Unprotect-Bytes $Encrypted)) | Should -Be ([System.Convert]::ToBase64String($Plain))
        Should -Invoke Get-CIPPCloudBackupKey -Times 1 -Exactly -ParameterFilter { $KeyId -eq $script:KeyId }
    }

    It 'round-trips with the default 4 MiB chunks and reports the byte counts' {
        $Plain = New-Plain (9MB + 3)
        $Out = [System.IO.MemoryStream]::new()
        $Written = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Plain)) -OutputStream $Out -KeyId $KeyId -Key $Key
        $Written | Should -Be (100 + $Plain.Length + 3 * 16)
        $Decrypted = [System.IO.MemoryStream]::new()
        Unprotect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Out.ToArray())) -OutputStream $Decrypted | Should -Be $Plain.Length
        [System.Convert]::ToBase64String($Decrypted.ToArray()) | Should -Be ([System.Convert]::ToBase64String($Plain))
    }

    It 'uses a fresh data key and nonce for every object' {
        $Plain = New-Plain 100
        [System.Convert]::ToBase64String((Protect-Bytes $Plain)) | Should -Not -Be ([System.Convert]::ToBase64String((Protect-Bytes $Plain)))
    }

    It 'detects truncation <Name>' -ForEach @(
        @{ Name = 'at a chunk boundary (final chunk dropped)'; Length = 640; Cut = { param($E) 100 + 10 * 80 } }
        @{ Name = 'inside a chunk'; Length = 300; Cut = { param($E) 100 + 80 + 40 } }
        @{ Name = 'inside the final chunk'; Length = 300; Cut = { param($E) $E.Length - 5 } }
        @{ Name = 'down to the header'; Length = 300; Cut = { param($E) 100 } }
        @{ Name = 'inside the header'; Length = 300; Cut = { param($E) 50 } }
    ) {
        $Encrypted = Protect-Bytes (New-Plain $Length)
        $Keep = & $Cut $Encrypted
        $Truncated = [byte[]]$Encrypted[0..($Keep - 1)]
        { Unprotect-Bytes $Truncated } | Should -Throw
    }

    It 'reports a stream that stops at a chunk boundary as incomplete' {
        $Encrypted = Protect-Bytes (New-Plain 640)
        { Unprotect-Bytes ([byte[]]$Encrypted[0..(100 + 10 * 80 - 1)]) } | Should -Throw '*incomplete*'
    }

    It 'detects reordered chunks' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        $First = Get-Frame $Encrypted 0
        $Second = Get-Frame $Encrypted 1
        [System.Array]::Copy($Second, 0, $Encrypted, 100, 80)
        [System.Array]::Copy($First, 0, $Encrypted, 180, 80)
        { Unprotect-Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
    }

    It 'detects a duplicated chunk' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        $First = Get-Frame $Encrypted 0
        $Duplicated = [byte[]]($Encrypted[0..179] + $First + $Encrypted[180..($Encrypted.Length - 1)])
        { Unprotect-Bytes $Duplicated } | Should -Throw '*changed or is damaged*'
    }

    It 'detects a chunk replaced with the same position from another object' {
        $One = Protect-Bytes (New-Plain 300)
        $Two = Protect-Bytes (New-Plain 300)
        [System.Array]::Copy((Get-Frame $Two 1), 0, $One, 180, 80)
        { Unprotect-Bytes $One } | Should -Throw '*changed or is damaged*'
    }

    It 'detects a final chunk moved forward to hide the chunks before it' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        $FinalStart = 100 + 4 * 80
        $Moved = [byte[]]($Encrypted[0..179] + $Encrypted[$FinalStart..($Encrypted.Length - 1)])
        { Unprotect-Bytes $Moved } | Should -Throw '*changed or is damaged*'
    }

    It 'detects data appended after the final chunk' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        { Unprotect-Bytes ([byte[]]($Encrypted + [byte[]](1))) } | Should -Throw '*changed or is damaged*'
    }

    It 'detects tampering with <Name>' -ForEach @(
        @{ Name = 'the chunk size'; Offset = 27 }
        @{ Name = 'the wrap nonce'; Offset = 30 }
        @{ Name = 'the wrapped key'; Offset = 50 }
        @{ Name = 'the wrap tag'; Offset = 80 }
        @{ Name = 'the base nonce'; Offset = 95 }
        @{ Name = 'the first ciphertext'; Offset = 110 }
        @{ Name = 'the first tag'; Offset = 170 }
        @{ Name = 'the last ciphertext'; Offset = 425 }
    ) {
        $Encrypted = Protect-Bytes (New-Plain 300)
        $Encrypted[$Offset] = $Encrypted[$Offset] -bxor 0x01
        { Unprotect-Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
    }

    It 'rejects a header whose key id was swapped to another valid key' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        $OtherId = [guid]::NewGuid()
        [System.Array]::Copy($OtherId.ToByteArray(), 0, $Encrypted, 8, 16)
        { Unprotect-Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
        Should -Invoke Get-CIPPCloudBackupKey -ParameterFilter { $KeyId -eq $OtherId.ToString() }
    }

    It 'fails with the wrong key' {
        $Encrypted = Protect-Bytes (New-Plain 300)
        Mock Get-CIPPCloudBackupKey { , [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32) }
        { Unprotect-Bytes $Encrypted } | Should -Throw '*changed or is damaged*'
    }

    It 'rejects CIPPENC1 data and a chunk size it would not write' {
        $Enc1 = [byte[]]::new(200)
        [System.Array]::Copy([System.Text.Encoding]::ASCII.GetBytes('CIPPENC1'), $Enc1, 8)
        { Unprotect-Bytes $Enc1 } | Should -Throw -ExceptionType ([System.ArgumentException])

        $Encrypted = Protect-Bytes (New-Plain 10)
        $Encrypted[24] = 0x7F
        { Unprotect-Bytes $Encrypted } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Get-CIPPCloudBackupKey -Times 0 -Exactly
    }

    It 'rejects a key that is not 32 bytes or an invalid key id' {
        { Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new()) -OutputStream ([System.IO.MemoryStream]::new()) -KeyId $KeyId -Key ([byte[]]::new(16)) } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new()) -OutputStream ([System.IO.MemoryStream]::new()) -KeyId 'nope' -Key $Key } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Read-CIPPCloudBackupStreamBlock' {
    It 'returns full blocks and then a short last block without encryption' {
        $Reader = @{ Stream = [System.IO.MemoryStream]::new((New-Plain 25)) }
        $Lengths = @(
            (Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 10).Length
            (Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 10).Length
            (Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 10).Length
            (Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 10).Length
        )
        $Lengths | Should -Be @(10, 10, 5, 0)
    }

    It 'returns a byte array even for a one-byte block' {
        $Block = Read-CIPPCloudBackupStreamBlock -Reader @{ Stream = [System.IO.MemoryStream]::new([byte[]](42)) } -Size 10
        $Block.GetType() | Should -Be ([byte[]])
        $Block.Length | Should -Be 1
    }

    It 'splits ciphertext across blocks of any size identically to one read' {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
        $Plain = New-Plain 500
        $Reader = @{ Stream = [System.IO.MemoryStream]::new($Plain); KeyId = $KeyId; Key = $Key; ChunkSize = 64 }
        $Out = [System.IO.MemoryStream]::new()
        do {
            $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 37
            $Out.Write($Block, 0, $Block.Length)
        } while ($Block.Length -eq 37)
        [System.Convert]::ToBase64String((Unprotect-Bytes $Out.ToArray())) | Should -Be ([System.Convert]::ToBase64String($Plain))
    }
}
