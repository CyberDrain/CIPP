#Requires -Version 7.0

# Writes the slice of the vendored Graph beta CSDL that classic Intune policy templates use: every
# property's declared type, the members of each enum, and the entity type each template type deploys
# as. The template editor types its fields from it and Test-CIPPIntuneTemplate checks payloads
# against it. Settings catalog policies are typed by the setting catalog instead, so they are not here.
#
# Inheritance is flattened, so a type lists every property it carries, and nested types are named by
# their full name so a consumer can follow them. Runs offline against the vendored CSDL; it is
# rerun by vendor-graph-metadata.ps1 whenever that file is refreshed.
#
# Run:  pwsh build/tools/Update-IntuneGraphSchema.ps1

[CmdletBinding()]
param(
    [string]$MetadataPath = "$PSScriptRoot/../../backend/Config/graph-metadata/beta.xml",
    [string[]]$OutputPath = @(
        "$PSScriptRoot/../../backend/Config/intune-graph-schema.json"
        "$PSScriptRoot/../../frontend/public/intune-graph-schema.json"
    )
)

$ErrorActionPreference = 'Stop'

# The entity type a template of each type deploys as. A payload's own @odata.type wins when it has
# one; this is what a payload without one (feature update profiles, for example) is checked against.
$TemplateTypes = [ordered]@{
    Device                       = 'microsoft.graph.deviceConfiguration'
    deviceCompliancePolicies     = 'microsoft.graph.deviceCompliancePolicy'
    windowsDriverUpdateProfiles  = 'microsoft.graph.windowsDriverUpdateProfile'
    windowsFeatureUpdateProfiles = 'microsoft.graph.windowsFeatureUpdateProfile'
    windowsQualityUpdatePolicies = 'microsoft.graph.windowsQualityUpdatePolicy'
    windowsQualityUpdateProfiles = 'microsoft.graph.windowsQualityUpdateProfile'
    hardwareConfigurations       = 'microsoft.graph.hardwareConfiguration'
    AppProtection                = 'microsoft.graph.managedAppPolicy'
}

$Xml = [System.Xml.XmlDocument]::new()
$Xml.Load((Resolve-Path $MetadataPath).Path)
$Ns = [System.Xml.XmlNamespaceManager]::new($Xml.NameTable)
$Ns.AddNamespace('edm', 'http://docs.oasis-open.org/odata/ns/edm')

# References use a schema's alias ('graph.x') and its namespace ('microsoft.graph.x') interchangeably.
$AliasOf = @{}
foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Ns)) {
    if ($Schema.Alias) { $AliasOf[$Schema.Alias] = $Schema.Namespace }
}
$FullName = {
    param([string]$Type)
    $IsCollection = $Type.StartsWith('Collection(')
    $Bare = $IsCollection ? $Type.Substring(11, $Type.Length - 12) : $Type
    $Dot = $Bare.LastIndexOf('.')
    $Prefix = $Bare.Substring(0, $Dot)
    if ($AliasOf.ContainsKey($Prefix)) { $Bare = $AliasOf[$Prefix] + $Bare.Substring($Dot) }
    $IsCollection ? "Collection($Bare)" : $Bare
}

$Raw = @{}
$Enums = @{}
foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Ns)) {
    foreach ($Node in $Schema.SelectNodes('edm:EntityType | edm:ComplexType', $Ns)) {
        $Properties = [ordered]@{}
        foreach ($Property in $Node.SelectNodes('edm:Property', $Ns)) {
            $Properties[$Property.Name] = & $FullName $Property.Type
        }
        # A contained navigation property is written inline with the policy (a compliance policy's
        # scheduledActionsForRule), so a payload carries it like any other property.
        $Contained = [System.Collections.Generic.List[string]]::new()
        foreach ($Property in $Node.SelectNodes('edm:NavigationProperty[@ContainsTarget="true"]', $Ns)) {
            $Properties[$Property.Name] = & $FullName $Property.Type
            $Contained.Add($Property.Name)
        }
        $Raw["$($Schema.Namespace).$($Node.Name)"] = @{
            Base       = $Node.BaseType ? (& $FullName $Node.BaseType) : $null
            Complex    = $Node.LocalName -eq 'ComplexType'
            Properties = $Properties
            Contained  = $Contained
        }
    }
    foreach ($Node in $Schema.SelectNodes('edm:EnumType', $Ns)) {
        $Enums["$($Schema.Namespace).$($Node.Name)"] = [ordered]@{
            flags   = $Node.IsFlags -eq 'true'
            members = @(foreach ($Member in $Node.SelectNodes('edm:Member', $Ns)) { $Member.Name })
        }
    }
}

foreach ($Root in $TemplateTypes.Values) {
    if (-not $Raw.ContainsKey($Root)) { throw "$Root is not defined in $MetadataPath." }
}

$Children = @{}
foreach ($Name in $Raw.Keys) {
    $Base = $Raw[$Name].Base
    if (-not $Base) { continue }
    if (-not $Children.ContainsKey($Base)) { $Children[$Base] = [System.Collections.Generic.List[string]]::new() }
    $Children[$Base].Add($Name)
}

# Every type a template can name: the root types and all their subtypes, then every complex type and
# enum their properties reach. A complex type pulls in its own subtypes too, because a payload can
# carry one in its place (the subtypes of omaSetting, for example).
$Wanted = [System.Collections.Generic.HashSet[string]]::new()
$WantedEnums = [System.Collections.Generic.HashSet[string]]::new()
$Queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($Root in $TemplateTypes.Values) { $Queue.Enqueue($Root) }
while ($Queue.Count -gt 0) {
    $Name = $Queue.Dequeue()
    if (-not $Raw.ContainsKey($Name) -or -not $Wanted.Add($Name)) { continue }
    foreach ($Child in $Children[$Name]) { $Queue.Enqueue($Child) }
    foreach ($Property in $Raw[$Name].Properties.GetEnumerator()) {
        $Type = $Property.Value
        $Inner = $Type.StartsWith('Collection(') ? $Type.Substring(11, $Type.Length - 12) : $Type
        if ($Enums.ContainsKey($Inner)) { $null = $WantedEnums.Add($Inner) }
        elseif ($Raw.ContainsKey($Inner) -and ($Raw[$Inner].Complex -or $Raw[$Name].Contained.Contains($Property.Key))) { $Queue.Enqueue($Inner) }
    }
}

$Flattened = @{}
foreach ($Name in $Wanted) {
    $Chain = [System.Collections.Generic.List[string]]::new()
    for ($Current = $Name; $Current -and $Raw.ContainsKey($Current); $Current = $Raw[$Current].Base) { $Chain.Insert(0, $Current) }
    $Properties = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($Link in $Chain) {
        foreach ($Property in $Raw[$Link].Properties.GetEnumerator()) { $Properties[$Property.Key] = $Property.Value }
    }
    $Flattened[$Name] = $Properties
}

$Output = [ordered]@{
    source        = 'Generated from backend/Config/graph-metadata/beta.xml by build/tools/Update-IntuneGraphSchema.ps1. Do not edit.'
    templateTypes = $TemplateTypes
    types         = [ordered]@{}
    enums         = [ordered]@{}
}
foreach ($Name in ($Flattened.Keys | Sort-Object -CaseSensitive)) { $Output.types[$Name] = $Flattened[$Name] }
foreach ($Name in ($WantedEnums | Sort-Object -CaseSensitive)) { $Output.enums[$Name] = $Enums[$Name] }

$Json = ConvertTo-Json -InputObject $Output -Depth 10 -Compress
foreach ($Path in $OutputPath) {
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Path), $Json + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $Path ($($Output.types.Count) types, $($Output.enums.Count) enums, $([math]::Round($Json.Length / 1KB)) KB)"
}
