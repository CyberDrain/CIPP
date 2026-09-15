# Guards the registry's per-test `dataTypes` against drift. The C# engine schedules tests and releases
# each cached type once its last DECLARED consumer has run, so a test that reads a type it doesn't
# declare would have that type freed too early. This test statically extracts every cached type each
# test reads — direct data.Get/Has("X"), FirstByIdentityOrFirst(data,"X"), and types reached through
# CippTestHelpers — and asserts they are all present in the test's dataTypes in tests.registry.json.

BeforeAll {
    $Backend = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $TestsDir = Join-Path $Backend 'Shared/CIPPSharp/Tests'
    $HelpersFile = Join-Path $TestsDir 'CippTestHelpers.cs'
    $RegistryPath = Join-Path $Backend 'Modules/CIPPTests/tests.registry.json'

    $LiteralRe = [regex]'data\.(?:Get|Has)\("([A-Za-z0-9_]+)"\)'
    $FbifRe = [regex]'FirstByIdentityOrFirst\(\s*data\s*,\s*"([A-Za-z0-9_]+)"'
    $MethodRe = [regex]'public\s+static\s+[^\n(]+?\b([A-Za-z0-9_]+)\s*\('

    function Get-Literals([string]$Body) {
        $set = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in $LiteralRe.Matches($Body)) { [void]$set.Add($m.Groups[1].Value) }
        foreach ($m in $FbifRe.Matches($Body)) { [void]$set.Add($m.Groups[1].Value) }
        , $set
    }
    function Get-BraceBody([string]$Text, [int]$From) {
        $i = $Text.IndexOf('{', $From); if ($i -lt 0) { return '' }
        $depth = 0
        for ($j = $i; $j -lt $Text.Length; $j++) {
            $c = $Text[$j]
            if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $Text.Substring($i, $j - $i + 1) } }
        }
        return $Text.Substring($i)
    }

    # Parse helpers: name -> direct literal types, name -> callee helper names.
    $HelperText = Get-Content $HelpersFile -Raw
    $HelperNames = [System.Collections.Generic.HashSet[string]]::new()
    $HelperBody = @{}
    foreach ($m in $MethodRe.Matches($HelperText)) {
        $name = $m.Groups[1].Value
        [void]$HelperNames.Add($name)
        $HelperBody[$name] = Get-BraceBody $HelperText $m.Index
    }
    $HelperLits = @{}; $HelperCalls = @{}
    foreach ($name in $HelperNames) {
        $body = $HelperBody[$name]
        $HelperLits[$name] = Get-Literals $body
        $calls = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($other in $HelperNames) {
            if ($other -eq $name) { continue }
            if ($body -match "(?<![A-Za-z0-9_])$([regex]::Escape($other))\s*\(") { [void]$calls.Add($other) }
        }
        $HelperCalls[$name] = $calls
    }
    # Transitive closure: helper -> all types it can read.
    $HelperTypes = @{}
    function Resolve-Helper([string]$Name, [System.Collections.Generic.HashSet[string]]$Stack) {
        if ($HelperTypes.ContainsKey($Name)) { return $HelperTypes[$Name] }
        if ($Stack.Contains($Name)) { return [System.Collections.Generic.HashSet[string]]::new() }
        [void]$Stack.Add($Name)
        $t = [System.Collections.Generic.HashSet[string]]::new([string[]]@($HelperLits[$Name]))
        foreach ($c in $HelperCalls[$Name]) { foreach ($x in (Resolve-Helper $c $Stack)) { [void]$t.Add($x) } }
        $HelperTypes[$Name] = $t
        return $t
    }
    foreach ($name in $HelperNames) { Resolve-Helper $name ([System.Collections.Generic.HashSet[string]]::new()) | Out-Null }

    # Declared dataTypes per test id, from the registry.
    $Registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json
    $Declared = @{}
    foreach ($suite in $Registry.suites) {
        foreach ($t in $suite.tests) { $Declared[$t.id] = @($t.dataTypes) }
    }

    # Static types per class test, and the drift violations.
    $script:Violations = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -Path $TestsDir -Recurse -Filter '*.cs' | Where-Object { $_.BaseName -ne 'CippTestHelpers' }) {
        $id = $file.BaseName
        if (-not $Declared.ContainsKey($id)) { continue }  # config tests keyed differently; class id == file
        $body = Get-Content $file.FullName -Raw
        $static = Get-Literals $body
        foreach ($other in $HelperNames) {
            if ($body -match "(?<![A-Za-z0-9_])$([regex]::Escape($other))\s*\(") {
                foreach ($x in $HelperTypes[$other]) { [void]$static.Add($x) }
            }
        }
        $declaredSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Declared[$id]), [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ty in $static) {
            if (-not $declaredSet.Contains($ty)) { $script:Violations.Add("$id reads '$ty' but does not declare it in dataTypes") }
        }
    }
}

Describe 'tests.registry.json dataTypes completeness' {
    It 'every cached type a test reads is declared in its dataTypes' {
        $script:Violations | Should -BeNullOrEmpty -Because ("`n" + ($script:Violations -join "`n"))
    }
}
