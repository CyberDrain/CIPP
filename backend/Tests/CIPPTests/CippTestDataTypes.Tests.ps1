# Guards the registry's per-test `dataTypes` against the most common drift: a test that directly
# reads a cached type it doesn't declare. This checks DIRECT data.Get/Has("X") and
# FirstByIdentityOrFirst(data,"X") literals in each test file only — it deliberately does NOT resolve
# helper calls, because helper resolution is branch-blind and over-approximates (it would flag types a
# test can only reach on a path it never takes). Helper-introduced and field-level accuracy are covered
# by the on/off projection A/B and the isolated type-recorder audit, not by this static test. An
# undeclared type is safe at runtime (it just loads whole), so this is an accuracy guard, not a
# correctness gate.

BeforeAll {
    $Backend = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $TestsDir = Join-Path $Backend 'Shared/CIPPSharp/Tests'
    $RegistryPath = Join-Path $Backend 'Modules/CIPPTests/tests.registry.json'

    $LiteralRe = [regex]'data\.(?:Get|Has)\("([A-Za-z0-9_]+)"\)'
    $FbifRe = [regex]'FirstByIdentityOrFirst\(\s*data\s*,\s*"([A-Za-z0-9_]+)"'

    $Registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json
    $Declared = @{}
    foreach ($suite in $Registry.suites) {
        foreach ($t in $suite.tests) { $Declared[$t.id] = @($t.dataTypes) }
    }

    $script:Violations = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -Path $TestsDir -Recurse -Filter '*.cs' | Where-Object { $_.BaseName -ne 'CippTestHelpers' }) {
        $id = $file.BaseName
        if (-not $Declared.ContainsKey($id)) { continue }  # config tests keyed differently; class id == file
        $body = Get-Content $file.FullName -Raw
        $read = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in $LiteralRe.Matches($body)) { [void]$read.Add($m.Groups[1].Value) }
        foreach ($m in $FbifRe.Matches($body)) { [void]$read.Add($m.Groups[1].Value) }
        $declaredSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Declared[$id]), [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ty in $read) {
            if (-not $declaredSet.Contains($ty)) { $script:Violations.Add("$id directly reads '$ty' but does not declare it in dataTypes") }
        }
    }
}

Describe 'tests.registry.json dataTypes completeness' {
    It 'every cached type a test directly reads is declared in its dataTypes' {
        $script:Violations | Should -BeNullOrEmpty -Because ("`n" + ($script:Violations -join "`n"))
    }
}
