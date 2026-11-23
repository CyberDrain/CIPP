# A form field's defaultValue is what gets saved when the user never touches the field. If it is not
# one of the field's option values (a label, say), the standard receives a value its code cannot read.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
    $script:Components = foreach ($RelativePath in 'frontend/src/data/standards.json', 'backend/Config/standards.json') {
        $FullPath = Join-Path $RepoRoot $RelativePath
        if (-not (Test-Path $FullPath)) { continue }
        foreach ($Standard in (Get-Content -Path $FullPath -Raw | ConvertFrom-Json)) {
            foreach ($Component in $Standard.addedComponent) {
                if ($null -eq $Component.PSObject.Properties['defaultValue'] -or $Component.options -isnot [array]) { continue }
                $Default = $Component.defaultValue
                if ($Default -is [pscustomobject]) { $Default = $Default.value }
                @{
                    File    = $RelativePath
                    Name    = $Component.name
                    Default = $Default
                    Values  = @($Component.options.value)
                }
            }
        }
    }
}

Describe 'standards.json form field defaults' {
    It 'finds fields to check' -ForEach @(@{ Count = @($script:Components).Count }) {
        $Count | Should -BeGreaterThan 10
    }

    It '<File>: <Name> defaults to one of its option values' -ForEach $script:Components {
        $Default | Should -BeIn $Values
    }
}
