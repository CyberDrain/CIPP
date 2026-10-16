#Requires -Version 7.0
using namespace System.Management.Automation.Language
<#
.SYNOPSIS
    Writes the Microsoft Graph permissions each function needs into its comment-based help.
.DESCRIPTION
    Every function that calls Graph gets one .NOTES line per call and permission type:

        Permission: Graph | GET /users/{id} | Delegated | User.ReadBasic.All | User.Read.All, User.ReadWrite.All

    Columns: API | operation | Delegated or Application | least privileged | higher privileged [| condition].
    A line covers the function's own calls. build-openapi.ps1 rolls the lines up through everything an
    endpoint calls into x-cipp-permissions in openapi.json.

    URIs, methods and -AsApp come from the AST. Paths are checked against the vendored Graph schema
    (backend/Config/graph-metadata) and matched to Microsoft's permissions map (graph-permissions.json, from
    microsoftgraph/microsoft-graph-devx-content). Where several permissions are least privileged, the one the
    CIPP SAM app requests wins. When the map has no entry for a valid path, the permission comes from a path
    it does list for the same resource type.

    Lines the script cannot derive are written by hand and kept: any API other than Graph, and Graph lines
    in a function with a call the script cannot read or match. A hand-written line for a call the script
    can derive is replaced, keeping its condition column.

    Run:          pwsh build/tools/Update-PermissionAnnotations.ps1
    CI:           pwsh build/tools/Update-PermissionAnnotations.ps1 -Check
    Refresh map:  pwsh build/tools/Update-PermissionAnnotations.ps1 -Refresh
#>
[CmdletBinding()]
param(
    [string]$ModulesPath = "$PSScriptRoot/../../backend/Modules",
    [string]$PermissionsPath = "$PSScriptRoot/graph-permissions.json",
    # The permission tables from Microsoft Learn's Graph API pages, built by -Refresh.
    [string]$LearnPath = "$PSScriptRoot/graph-learn-permissions.json",
    [string]$SamManifestPath = "$PSScriptRoot/../../backend/Config/SAMManifest.json",
    [string]$TranslatorPath = "$PSScriptRoot/../../backend/Config/PermissionsTranslator.json",
    [string]$GraphMetadataPath = "$PSScriptRoot/../../backend/Config/graph-metadata",
    # JSON list of the calls that need a hand-written line.
    [string]$ReportPath,
    [switch]$Check,
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'

$GraphAppId = '00000003-0000-0000-c000-000000000000'
$HelpKeyword = '(?im)^\s*\.(SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK|COMPONENT|ROLE|FUNCTIONALITY|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE|EXTERNALHELP)\b'

function ConvertTo-LearnKey([string]$Method, [string]$Path) {
    $Path = $Path.ToLowerInvariant() -replace "\('?\{id\}'?\)", '/{id}' -replace '/microsoft\.graph\.', '/'
    "$($Method.ToUpperInvariant()) $Path"
}

if ($Refresh) {
    $Uri = 'https://raw.githubusercontent.com/microsoftgraph/microsoft-graph-devx-content/master/permissions/new/permissions.json'
    $Content = (Invoke-WebRequest -Uri $Uri -TimeoutSec 300).Content
    if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
    if (-not ($Content | ConvertFrom-Json -AsHashtable).permissions) { throw 'Downloaded file is not a Graph permissions map.' }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($PermissionsPath), $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Refreshed $PermissionsPath"

    # The permission tables on each Learn API page, keyed by the requests the page lists.
    $Docs = Join-Path ([System.IO.Path]::GetTempPath()) "graph-docs-$([guid]::NewGuid().ToString('n'))"
    git clone -q --depth 1 --filter=blob:none --sparse https://github.com/microsoftgraph/microsoft-graph-docs-contrib.git $Docs
    git -C $Docs sparse-checkout set --no-cone 'api-reference/*/api/*.md' 'api-reference/*/includes/permissions/*.md'
    if ($LASTEXITCODE) { throw 'Could not fetch the Microsoft Graph docs.' }
    $RowTypes = @{ 'Delegated (work or school account)' = 'DelegatedWork'; 'Application' = 'Application' }
    $Tables = [System.Collections.Generic.List[string]]::new()
    $TableIndex = @{}
    $Learn = [ordered]@{ tables = $Tables }
    foreach ($Version in 'v1.0', 'beta') {
        $Root = Join-Path $Docs "api-reference/$Version"
        $Ops = [System.Collections.Generic.SortedDictionary[string, int]]::new([StringComparer]::Ordinal)
        # A request listed on several pages belongs to the page that lists the fewest; Intune's generated pages
        # (intune-mam-user-get and friends repeat GET /users/{id}) only when no other page has it.
        $Rank = @{}
        foreach ($Page in Get-ChildItem (Join-Path $Root 'api') -Filter *.md | Sort-Object Name) {
            $Text = [System.IO.File]::ReadAllText($Page.FullName)
            $Include = [regex]::Match($Text, 'includes/permissions/([\w.-]+)\.md')
            $TableText = if ($Include.Success) { [System.IO.File]::ReadAllText((Join-Path $Root "includes/permissions/$($Include.Groups[1].Value).md")) } else { [regex]::Match($Text, '(?s)## Permissions(.*?)(\n## |\z)').Groups[1].Value }
            $Table = [ordered]@{}
            foreach ($Line in $TableText -split '\r?\n') {
                $Cols = @($Line.Trim('|', ' ') -split '\|').ForEach({ $_.Trim() })
                if (-not $RowTypes.ContainsKey($Cols[0])) { continue }
                $Perms = @(($Cols[1..($Cols.Count - 1)] -join ',') -split ',').ForEach({ $_.Trim() }).Where({ $_ -match '^[\w-]+(\.[\w-]+)+$' })
                $LeastCount = if ($Cols.Count -ge 3) { @(($Cols[1] -split ',').Where({ $_.Trim() -match '^[\w-]+(\.[\w-]+)+$' })).Count } else { [Math]::Min(1, $Perms.Count) }
                if ($LeastCount) { $Table[$RowTypes[$Cols[0]]] = [ordered]@{ least = @($Perms[0..($LeastCount - 1)]); higher = @($Perms | Select-Object -Skip $LeastCount) } }
            }
            if (-not $Table.Count) { continue }
            $Json = ConvertTo-Json -InputObject $Table -Depth 4 -Compress
            if (-not $TableIndex.ContainsKey($Json)) { $TableIndex[$Json] = $Tables.Count; $Tables.Add($Json) }
            $Index = $TableIndex[$Json]
            $Http = [regex]::Match($Text, '(?is)## HTTP request(.*?)(\n## |\z)').Groups[1].Value
            $Requests = [regex]::Matches($Http, '(?m)^\s*(GET|POST|PATCH|PUT|DELETE)\s+(/\S[^\r\n]*?)\s*$')
            $PageRank = $Requests.Count + $(if ($Page.Name.StartsWith('intune-')) { 100000 } else { 0 })
            foreach ($Op in $Requests) {
                $Path = (($Op.Groups[2].Value -replace '\{[^}]*\}', '{id}' -replace '\s+', '') -split '\?')[0].TrimEnd('/')
                $Key = ConvertTo-LearnKey $Op.Groups[1].Value $Path
                if (-not $Ops.ContainsKey($Key) -or $PageRank -lt $Rank[$Key]) { $Ops[$Key] = $Index; $Rank[$Key] = $PageRank }
            }
        }
        $Learn[$Version] = $Ops
    }
    Remove-Item -LiteralPath $Docs -Recurse -Force
    $Learn.tables = @($Tables | ForEach-Object { ConvertFrom-Json -InputObject $_ })
    ConvertTo-Json -InputObject $Learn -Depth 6 -Compress | Set-Content -LiteralPath $LearnPath -Encoding utf8NoBOM
    Write-Host "Refreshed $LearnPath ($($Learn['v1.0'].Count) v1.0 and $($Learn['beta'].Count) beta requests)"
}

#region Source files
$Files = foreach ($File in Get-ChildItem -LiteralPath $ModulesPath -Recurse -Filter *.ps1 -File | Sort-Object FullName) {
    $Tokens = $null
    $Ast = [Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$null)
    $Functions = @($Ast.FindAll({ $args[0] -is [FunctionDefinitionAst] }, $true))
    if ($Functions.Count) { [pscustomobject]@{ Path = $File.FullName; Tokens = $Tokens; Functions = $Functions } }
}
#endregion

#region Static value resolution
function Get-ArgAst($Cmd, [string]$Name) {
    $Elements = $Cmd.CommandElements
    for ($i = 1; $i -lt $Elements.Count; $i++) {
        if ($Elements[$i] -is [CommandParameterAst] -and $Elements[$i].ParameterName -ieq $Name) {
            if ($Elements[$i].Argument) { return $Elements[$i].Argument }
            if ($i + 1 -lt $Elements.Count -and $Elements[$i + 1] -isnot [CommandParameterAst]) { return $Elements[$i + 1] }
            return [StringConstantExpressionAst]::new($Elements[$i].Extent, 'true', [StringConstantType]::BareWord)
        }
    }
}

function Get-PipelineExpression($Statement) {
    if ($Statement -is [CommandExpressionAst]) { return $Statement.Expression }
    if ($Statement -is [PipelineAst] -and $Statement.PipelineElements.Count -eq 1 -and $Statement.PipelineElements[0] -is [CommandExpressionAst]) {
        return $Statement.PipelineElements[0].Expression
    }
}

# Every literal value a variable can hold in this function: assignments, parameter defaults, ValidateSet.
function Resolve-Variable([string]$Name, $Fn, [int]$Depth) {
    if ($Depth -gt 3 -or -not $Fn) { return @() }
    $Values = [System.Collections.Generic.List[string]]::new()
    foreach ($Assign in $Fn.FindAll({ $args[0] -is [AssignmentStatementAst] -and $args[0].Operator -eq 'Equals' -and $args[0].Left -is [VariableExpressionAst] -and $args[0].Left.VariablePath.UserPath -ieq $Name }, $true)) {
        $Expr = Get-PipelineExpression $Assign.Right
        if ($Expr) { foreach ($V in (Resolve-Value $Expr $Fn ($Depth + 1))) { $Values.Add($V) } }
    }
    $Param = $Fn.FindAll({ $args[0] -is [ParameterAst] -and $args[0].Name.VariablePath.UserPath -ieq $Name }, $true) | Select-Object -First 1
    if ($Param) {
        if ($Param.DefaultValue) { foreach ($V in (Resolve-Value $Param.DefaultValue $Fn ($Depth + 1))) { $Values.Add($V) } }
        $Set = $Param.Attributes.Where({ $_.TypeName.Name -eq 'ValidateSet' })[0]
        if ($Set) { foreach ($V in $Set.PositionalArguments.Where({ $_ -is [StringConstantExpressionAst] })) { $Values.Add($V.Value) } }
    }
    @($Values.Where({ $_ -ne '{id}' }) | Select-Object -Unique)
}

# Literal string values an expression can take; '{id}' stands in for anything dynamic.
function Resolve-Value($Expr, $Fn, [int]$Depth = 0) {
    if ($Expr -is [StringConstantExpressionAst]) { return @($Expr.Value) }
    if ($Expr -is [ConstantExpressionAst]) { return @([string]$Expr.Value) }
    if ($Expr -is [VariableExpressionAst]) {
        if ($Expr.VariablePath.UserPath -in 'true', 'false') { return @($Expr.VariablePath.UserPath) }
        return @(Resolve-Variable $Expr.VariablePath.UserPath $Fn $Depth)
    }
    if ($Expr -is [ParenExpressionAst]) {
        $Inner = Get-PipelineExpression $Expr.Pipeline
        if ($Inner) { return @(Resolve-Value $Inner $Fn $Depth) }
        return @()
    }
    if ($Expr -is [SubExpressionAst]) {
        $Statements = $Expr.SubExpression.Statements
        if ($Statements.Count -eq 1) { $Inner = Get-PipelineExpression $Statements[0]; if ($Inner) { return @(Resolve-Value $Inner $Fn $Depth) } }
        return @()
    }
    if ($Expr -is [ExpandableStringExpressionAst]) {
        $Text = $Expr.Extent.Text
        $Quote = if ($Text.StartsWith('@')) { 2 } else { 1 }
        $Base = $Expr.Extent.StartOffset + $Quote
        $Results = @($Text.Substring($Quote, $Text.Length - 2 * $Quote))
        foreach ($Nested in ($Expr.NestedExpressions | Sort-Object { $_.Extent.StartOffset } -Descending)) {
            $Options = @(Resolve-Value $Nested $Fn $Depth)
            if (-not $Options.Count -or $Options.Count -gt 6) { $Options = @('{id}') }
            $Start = $Nested.Extent.StartOffset - $Base
            $Results = @(foreach ($R in $Results) { foreach ($O in $Options) { $R.Remove($Start, $Nested.Extent.Text.Length).Insert($Start, $O) } }) | Select-Object -First 24
        }
        return @($Results.ForEach({ $_.Replace('`', '') }))
    }
    if ($Expr -is [BinaryExpressionAst] -and $Expr.Operator -eq 'Format') {
        return @((Resolve-Value $Expr.Left $Fn $Depth).ForEach({ $_ -replace '\{\d+(:[^}]*)?\}', '{id}' }))
    }
    if ($Expr -is [BinaryExpressionAst] -and $Expr.Operator -eq 'Plus') {
        $Left = @(Resolve-Value $Expr.Left $Fn $Depth); if (-not $Left.Count) { $Left = @('{id}') }
        $Right = @(Resolve-Value $Expr.Right $Fn $Depth); if (-not $Right.Count) { $Right = @('{id}') }
        return @(foreach ($L in $Left) { foreach ($R in $Right) { "$L$R" } })
    }
    @()
}

# A splatted command reads its arguments from a hashtable literal assigned in the same function.
function Get-SplatArgument($Cmd, $Fn) {
    $Splat = $Cmd.CommandElements.Where({ $_ -is [VariableExpressionAst] -and $_.Splatted })[0]
    if (-not $Splat) { return @{} }
    $Name = $Splat.VariablePath.UserPath
    $Table = @($Fn.FindAll({ $args[0] -is [AssignmentStatementAst] -and $args[0].Left -is [VariableExpressionAst] -and $args[0].Left.VariablePath.UserPath -ieq $Name }, $true)).ForEach({ Get-PipelineExpression $_.Right }).Where({ $_ -is [HashtableAst] })[0]
    $SplatArgs = @{}
    foreach ($Pair in $Table.KeyValuePairs) { if ($Pair.Item1 -is [StringConstantExpressionAst]) { $SplatArgs[$Pair.Item1.Value] = Get-PipelineExpression $Pair.Item2 } }
    $SplatArgs
}

function Get-CallArg($Cmd, $Splat, [string]$Name) {
    $Arg = Get-ArgAst $Cmd $Name
    if ($Arg) { return $Arg }
    $Splat[$Name]
}

function Test-AsApp($ArgAst, $Fn) {
    if (-not $ArgAst) { return $false }
    # ponytail: a variable -AsApp counts only when a literal $true/'true' can reach it in the same function
    'true' -in @(Resolve-Value $ArgAst $Fn)
}

# Split a URI into the Graph version + path, or report the host it calls instead.
function ConvertTo-GraphPath([string]$Uri) {
    $Version = 'beta'
    if ($Uri -match '^https://graph\.microsoft\.com/(v1\.0|beta)/') { $Version = $Matches[1]; $Uri = $Uri.Substring($Matches[0].Length) }
    elseif ($Uri -match '^https?://([^/:]+)') { return @{ Host = $Matches[1] } }
    elseif ($Uri -match '^/?(v1\.0|beta)/') { $Version = $Matches[1]; $Uri = $Uri.Substring($Matches[0].Length) }
    $Path = ($Uri -split '[?#]')[0].Trim('/') -replace "\('?\{id\}'?\)", '/{id}'
    if (-not $Path -or $Path.StartsWith('{id}') -or $Path.StartsWith('&')) { return $null }
    @{ Version = $Version; Path = "/$Path" }
}
#endregion

#region Graph schema
function ConvertTo-SchemaRef([string]$Type, $Alias) {
    $Many = $Type -match '^Collection\((.+)\)$'
    if ($Many) { $Type = $Matches[1] }
    $Ns, $Short = $Type.ToLowerInvariant() -split '\.(?=[^.]+$)'
    @{ Type = "$($Alias[$Ns] ?? $Ns).$Short"; Many = [bool]$Many }
}

function Read-GraphSchema([string]$Path) {
    $Schemas = @(([xml][System.IO.File]::ReadAllText($Path)).Edmx.DataServices.Schema)
    $Alias = @{}
    foreach ($S in $Schemas) { if ($S.Alias) { $Alias[$S.Alias.ToLowerInvariant()] = $S.Namespace.ToLowerInvariant() } }
    $Model = @{ Root = @{}; Types = @{}; Ops = @{} }
    foreach ($S in $Schemas) {
        $Ns = $S.Namespace.ToLowerInvariant()
        foreach ($T in @(@($S.EntityType) + @($S.ComplexType)).Where({ $_ })) {
            $Members = @{}
            foreach ($M in @(@($T.Property) + @($T.NavigationProperty)).Where({ $_ })) { $Members[$M.Name.ToLowerInvariant()] = ConvertTo-SchemaRef $M.Type $Alias }
            $Model.Types["$Ns.$($T.Name.ToLowerInvariant())"] = @{ Base = if ($T.BaseType) { (ConvertTo-SchemaRef $T.BaseType $Alias).Type }; Members = $Members }
        }
        foreach ($Op in @(@($S.Function) + @($S.Action)).Where({ $_.IsBound -eq 'true' })) {
            $Binding = ConvertTo-SchemaRef @($Op.Parameter)[0].Type $Alias
            $Key = "$($Binding.Type)|$($Binding.Many)"
            if (-not $Model.Ops.ContainsKey($Key)) { $Model.Ops[$Key] = @{} }
            $Return = if ($Op.ReturnType) { ConvertTo-SchemaRef $Op.ReturnType.Type $Alias } else { @{ Type = $null; Many = $false } }
            $Return.Op = $true
            $Model.Ops[$Key][$Op.Name.ToLowerInvariant()] = $Return
        }
        foreach ($C in @($S.EntityContainer).Where({ $_ })) {
            foreach ($E in @($C.EntitySet).Where({ $_ })) { $Model.Root[$E.Name.ToLowerInvariant()] = @{ Type = (ConvertTo-SchemaRef $E.EntityType $Alias).Type; Many = $true } }
            foreach ($E in @($C.Singleton).Where({ $_ })) { $Model.Root[$E.Name.ToLowerInvariant()] = ConvertTo-SchemaRef $E.Type $Alias }
        }
    }
    $Model
}

# A segment is a type cast, a property or navigation, or an operation bound to the type or one of its bases.
function Find-SchemaStep($Model, $State, [string]$Name) {
    if ($Model.Types.ContainsKey($Name)) { return @{ Type = $Name; Many = $State.Many } }
    $Type = $State.Type
    while ($Type) {
        $Def = $Model.Types[$Type]
        if ($Def -and $Def.Members.ContainsKey($Name)) { return $Def.Members[$Name] }
        $Ops = $Model.Ops["$Type|$($State.Many)"]
        if ($Ops -and $Ops.ContainsKey($Name)) { return $Ops[$Name] }
        $Type = $Def.Base
    }
}

function Resolve-SchemaPath($Model, [string]$Path) {
    $State = $null
    # Path addressing (root:/folder/file:, host:/sites/path) names the item it lands on.
    foreach ($Seg in ($Path.ToLowerInvariant() -replace ':/[^:]*(:|$)', '').Trim('/').Split('/')) {
        if ($Seg -in '$ref', '$count', '$value') { continue }
        $Name = $Seg
        $Keyed = $Seg -match '^([^(]+)\((.*)\)$'
        if ($Keyed) { $Name = $Matches[1] }
        $Next = if ($null -eq $State) { $Model.Root[$Name] } else { Find-SchemaStep $Model $State $Name }
        if (-not $Next) {
            if ($State.Many -and -not $Keyed) { $State = @{ Type = $State.Type; Many = $false }; continue }
            return @{ Status = if ($Seg.Contains('{')) { 'dynamic' } else { 'notInSchema' } }
        }
        if ($Keyed -and $Next.Many -and -not $Next.Op) { $Next = @{ Type = $Next.Type; Many = $false } }
        $State = $Next
    }
    @{ Status = 'valid'; Type = $State.Type; Many = $State.Many }
}

$Schemas = @{
    'v1.0' = Read-GraphSchema (Join-Path $GraphMetadataPath 'v1.0.xml')
    'beta' = Read-GraphSchema (Join-Path $GraphMetadataPath 'beta.xml')
}
$SchemaCache = @{}
function Get-SchemaStatus([string]$Version, [string]$Path) {
    $Key = "$Version|$Path"
    if ($SchemaCache.ContainsKey($Key)) { return $SchemaCache[$Key] }
    $Status = Resolve-SchemaPath $Schemas[$Version] $Path
    if ($Status.Status -eq 'notInSchema') {
        $Other = if ($Version -eq 'beta') { 'v1.0' } else { 'beta' }
        $InOther = Resolve-SchemaPath $Schemas[$Other] $Path
        if ($InOther.Status -eq 'valid') { $Status = @{ Status = "${Other}Only"; Type = $InOther.Type; Many = $InOther.Many } }
    }
    $SchemaCache[$Key] = $Status
    $Status
}
#endregion

#region Per-function extraction
function Get-OwningFunction($Node) {
    $P = $Node.Parent
    while ($P -and $P -isnot [FunctionDefinitionAst]) { $P = $P.Parent }
    $P
}

function Get-FunctionCall($Fn) {
    $Calls = [System.Collections.Generic.List[object]]::new()
    $Exo = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Hosts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Unresolved = [System.Collections.Generic.List[string]]::new()
    $BulkCalls = [System.Collections.Generic.List[object]]::new()
    $BulkAsApp = $false

    $AddCall = {
        param($UriAst, $Methods, $AsApp, $Source, $Into, $ScopeAst)
        # A -scope for another resource (SharePoint REST, admin portal) means the call is not Graph.
        if ($ScopeAst) {
            $Scopes = @(Resolve-Value $ScopeAst $Fn)
            if (-not $Scopes.Count) { [void]$Hosts.Add('(dynamic scope)'); return }
            $ScopeHosts = @($Scopes.ForEach({ if ($_ -match '^https?://([^/:]+)') { $Matches[1] } }).Where({ $_ -ne 'graph.microsoft.com' }))
            if ($ScopeHosts.Count) { foreach ($H in $ScopeHosts) { [void]$Hosts.Add($H) }; return }
        }
        $Paths = @((Resolve-Value $UriAst $Fn).ForEach({ ConvertTo-GraphPath $_ }).Where({ $_ }))
        foreach ($H in $Paths.Where({ $_.Host })) { [void]$Hosts.Add($H.Host) }
        if (-not $Paths.Count) { $Unresolved.Add(($Source -replace '\s+', ' ')) }
        $GraphPaths = @($Paths.Where({ $_.Path }))
        # Values are resolved without flow, so a variable set per branch yields every combination; keep the ones Graph has.
        $InSchema = @($GraphPaths.Where({ (Get-SchemaStatus $_.Version $_.Path).Status -ne 'notInSchema' }))
        if ($InSchema.Count) { $GraphPaths = $InSchema }
        foreach ($P in $GraphPaths) {
            foreach ($M in $Methods) { $Into.Add([pscustomobject]@{ Method = $M; Version = $P.Version; Path = $P.Path; AsApp = $AsApp }) }
        }
    }

    foreach ($Cmd in $Fn.Body.FindAll({ $args[0] -is [CommandAst] }, $true)) {
        if ((Get-OwningFunction $Cmd) -ne $Fn) { continue }
        $CmdName = $Cmd.GetCommandName()
        if (-not $CmdName) { continue }
        $Splat = Get-SplatArgument $Cmd $Fn
        switch -Regex ($CmdName) {
            '^New-Graph(Get|POST)Request$' {
                $Methods = @('GET')
                if ($CmdName -ieq 'New-GraphPOSTRequest') {
                    $Type = Get-CallArg $Cmd $Splat 'type'
                    $Methods = if ($Type) { @((Resolve-Value $Type $Fn).ForEach({ $_.ToUpperInvariant() })) } else { @('POST') }
                    if (-not $Methods.Count) { $Methods = @('POST') }
                }
                & $AddCall (Get-CallArg $Cmd $Splat 'uri') $Methods (Test-AsApp (Get-CallArg $Cmd $Splat 'AsApp') $Fn) $Cmd.Extent.Text $Calls (Get-CallArg $Cmd $Splat 'scope')
            }
            '^New-GraphBulkRequest$' { if (Test-AsApp (Get-CallArg $Cmd $Splat 'asapp') $Fn) { $BulkAsApp = $true } }
            '^New-Exo(Bulk)?Request$' {
                $Cmdlet = Get-CallArg $Cmd $Splat 'cmdlet'
                if ($Cmdlet) { foreach ($C in (Resolve-Value $Cmdlet $Fn)) { if ($C -match '^\w+-\w+$') { [void]$Exo.Add($C) } } }
            }
        }
    }

    # Bulk requests are hashtable literals with url + method.
    foreach ($Table in $Fn.Body.FindAll({ $args[0] -is [HashtableAst] }, $true)) {
        if ((Get-OwningFunction $Table) -ne $Fn) { continue }
        $Pairs = @{}
        foreach ($Pair in $Table.KeyValuePairs) { if ($Pair.Item1 -is [StringConstantExpressionAst]) { $Pairs[$Pair.Item1.Value] = Get-PipelineExpression $Pair.Item2 } }
        if ($Pairs['url'] -and $Pairs.ContainsKey('method')) {
            $Methods = @((Resolve-Value $Pairs['method'] $Fn).ForEach({ $_.ToUpperInvariant() }))
            if (-not $Methods.Count) { $Methods = @('GET') }
            & $AddCall $Pairs['url'] $Methods $false $Table.Extent.Text $BulkCalls
        }
    }
    foreach ($C in $BulkCalls) { $C.AsApp = $BulkAsApp; $Calls.Add($C) }

    @{ Calls = $Calls; Exo = $Exo; Hosts = $Hosts; Unresolved = $Unresolved }
}
#endregion

#region Microsoft's path -> permission map
$Granted = @{ DelegatedWork = [System.Collections.Generic.HashSet[string]]::new(); Application = [System.Collections.Generic.HashSet[string]]::new() }
$Translator = @{}
foreach ($Entry in (Get-Content -LiteralPath $TranslatorPath -Raw | ConvertFrom-Json)) { $Translator[$Entry.id] = $Entry.value }
foreach ($Access in ((Get-Content -LiteralPath $SamManifestPath -Raw | ConvertFrom-Json).requiredResourceAccess.Where({ $_.resourceAppId -eq $GraphAppId }).resourceAccess)) {
    $Scheme = if ($Access.type -eq 'Role') { 'Application' } else { 'DelegatedWork' }
    if ($Translator[$Access.id]) { [void]$Granted[$Scheme].Add($Translator[$Access.id]) }
}

$Permissions = (Get-Content -LiteralPath $PermissionsPath -Raw | ConvertFrom-Json -AsHashtable).permissions
$Templates = @{}
foreach ($PermName in $Permissions.Keys) {
    $Def = $Permissions[$PermName]
    $Levels = @{}
    foreach ($SchemeName in $Def.schemes.Keys) { $Levels[$SchemeName] = $Def.schemes[$SchemeName].privilegeLevel }
    foreach ($Set in $Def.pathSets) {
        foreach ($Path in $Set.paths.Keys) {
            $Least = if ($Set.paths[$Path] -match 'least=(.+)') { $Matches[1] -split ',' } else { @() }
            $Key = $Path.ToLowerInvariant()
            if (-not $Templates.ContainsKey($Key)) { $Templates[$Key] = [System.Collections.Generic.List[object]]::new() }
            $Templates[$Key].Add(@{ Perm = $PermName; Methods = $Set.methods; Schemes = $Set.schemeKeys; Least = $Least; Levels = $Levels })
        }
    }
}
# Most literal template wins (/users/delta over /users/{id}); bucketed by first segment.
$ByFirstSegment = @{}
foreach ($T in $Templates.Keys) {
    $First = ($T -split '/')[1] -replace '\(.*$', ''
    if (-not $ByFirstSegment.ContainsKey($First)) { $ByFirstSegment[$First] = [System.Collections.Generic.List[object]]::new() }
    $ByFirstSegment[$First].Add([pscustomobject]@{
            Template = $T
            Regex    = [regex]::new('^' + ([regex]::Escape($T) -replace '\\\{[^}]+}', '[^/]+') + '$', 'IgnoreCase')
            Holes    = ([regex]::Matches($T, '\{')).Count
        })
}
foreach ($K in @($ByFirstSegment.Keys)) { $ByFirstSegment[$K] = @($ByFirstSegment[$K] | Sort-Object Holes, Template) }

$TemplateCache = @{}
function Find-Template([string]$Path) {
    if ($TemplateCache.ContainsKey($Path)) { return $TemplateCache[$Path] }
    $Candidates = $ByFirstSegment[(($Path -split '/')[1] -replace '\(.*$', '')]
    $Try = $Path
    $Hit = $null
    while ($Candidates -and -not $Hit) {
        $Hit = $Candidates.Where({ $_.Regex.IsMatch($Try) }, 'First')[0]
        $Next = $Try -replace '/(microsoft\.graph\.[^/]+|\$count|\$value|\$ref)$', ''
        if ($Next -eq $Try) { break }
        $Try = $Next
    }
    $TemplateCache[$Path] = ${Hit}?.Template
    $TemplateCache[$Path]
}

function Get-LeastPermission($Template, [string]$Method, [string]$Scheme) {
    $Candidates = @($Templates[$Template].Where({ $_.Schemes -contains $Scheme -and $_.Methods -contains $Method }))
    if (-not $Candidates.Count) { return $null }
    # Hyphenated permissions (Group-NestingSupport.*, User-Mail.*) cover a single property.
    $Whole = @($Candidates.Where({ $_.Perm -notmatch '^[^.]+-' }))
    if ($Whole.Count) { $Candidates = $Whole }
    # Microsoft flags "least" per path rather than per method, so a ReadWrite flagged for PATCH also shows
    # up for GET; keep only the lowest level of the flagged set, then prefer Read, then what the SAM app holds.
    $Least = @($Candidates.Where({ $_.Least -contains $Scheme }))
    if ($Method -eq 'GET') {
        $ReadOf = $Least.ForEach({ $_.Perm -replace '\.ReadWrite\.', '.Read.' })
        $Least = @($Least) + @($Candidates.Where({ $_.Perm -in $ReadOf -and $_ -notin $Least }))
    }
    $Pool = if ($Least.Count) { $Least } else { $Candidates }
    # Microsoft's levels are not always ordered (DeviceManagementConfiguration.Read.All app-only rates above its ReadWrite).
    $Pool = @($Pool.Where({ $_.Perm -notmatch '\.ReadWrite' -or ($_.Perm -replace '\.ReadWrite', '.Read') -notin $Pool.Perm }))
    $Min =($Pool.ForEach({ $_.Levels[$Scheme] ?? 9 }) | Measure-Object -Minimum).Minimum
    $Pool = @($Pool.Where({ ($_.Levels[$Scheme] ?? 9) -eq $Min }))
    $Pick = @($Pool | Sort-Object { $_.Perm -notmatch '\.Read(Basic)?(\.|$)' }, { -not $Granted[$Scheme].Contains($_.Perm) }, { $_.Perm -like 'Directory.*' }, { $_.Perm })[0].Perm
    # Microsoft's map lists every permission that reaches a path; Learn pages list only the resource's own family and Directory.*.
    $Family = ($Pick -split '[.-]')[0]
    $Related = @($Candidates.Where({ $Other = ($_.Perm -split '[.-]')[0]; $_.Perm -ne $Pick -and ($Other -eq 'Directory' -or $Other.StartsWith($Family) -or $Family.StartsWith($Other)) }))
    $Higher = @($Related | Sort-Object { $_.Levels[$Scheme] ?? 9 }, { $_.Perm } | ForEach-Object Perm | Select-Object -Unique)
    @{ Permission = $Pick; Higher = $Higher }
}

$Learn = Get-Content -LiteralPath $LearnPath -Raw | ConvertFrom-Json -AsHashtable
# The Learn table row for a request, from the page for the call's Graph version or else the other one.
function Find-LearnRow([string]$Version, [string]$Method, [string]$Path, [string]$Scheme) {
    $Key = ConvertTo-LearnKey $Method $Path
    foreach ($V in $Version, $(if ($Version -eq 'beta') { 'v1.0' } else { 'beta' })) {
        $Index = $Learn[$V][$Key]
        if ($null -ne $Index) { return $Learn.tables[$Index][$Scheme] }
    }
}
#endregion

#region Schema rematch
function Get-ResourceName([string]$Path) {
    @(($Path -replace ':/[^:]*(:|$)', '' -split '/').Where({ $_ -and $_ -notmatch '^(\{[^}]+\}|\$\w+|microsoft\.graph\..*)$' }))[-1] -replace '\(.*$', ''
}

# Map templates by the resource type and collection name they address, shortest path first.
$TemplatesByType = @{}
foreach ($T in @($Templates.Keys | Sort-Object { ($_ -split '/').Count }, { $_ })) {
    $Status = Resolve-SchemaPath $Schemas['beta'] ($T -replace '\{[^}]+\}', '{id}')
    if ($Status.Status -ne 'valid' -or -not $Status.Type) { continue }
    $Key = '{0}|{1}|{2}' -f $Status.Type, $Status.Many, (Get-ResourceName $T)
    if (-not $TemplatesByType.ContainsKey($Key)) { $TemplatesByType[$Key] = [System.Collections.Generic.List[string]]::new() }
    $TemplatesByType[$Key].Add($T)
}

$CallCache = @{}
function Resolve-CallPermission($Call, [string]$Scheme) {
    $Key = '{0}|{1}|{2}|{3}' -f $Call.Version, $Call.Method, $Call.Path, $Scheme
    if ($CallCache.ContainsKey($Key)) { return $CallCache[$Key] }
    $Schema = Get-SchemaStatus $Call.Version $Call.Path
    $Path = $Call.Path.ToLowerInvariant()
    $AltKey = $Path -replace "\(\w+id='?\{id\}'?\)", '/{id}'
    $Tries = @(
        @{ Path = $Path; Method = $Call.Method }
        if ($AltKey -ne $Path) { @{ Path = $AltKey; Method = $Call.Method } }
        if ($AltKey -match '^(.+)/(microsoft\.graph\.[^/]+|\$count)$') { @{ Path = $Matches[1]; Method = $Call.Method } }
        # Microsoft lists adding a reference under neither the collection nor $ref; the matching remove carries the same permission.
        if ($AltKey -match '^(.+)/\$ref$' -and $Call.Method -ne 'GET') {
            @{ Path = $Matches[1]; Method = 'POST' }
            @{ Path = "$($Matches[1])/{id}"; Method = 'DELETE' }
        }
    )
    $Found = $null
    $Hit = $null
    $HitTry = $null
    foreach ($Try in $Tries) {
        $T = Find-Template $Try.Path
        if (-not $T) { continue }
        $Found ??= $T
        $Hit = Get-LeastPermission $T $Try.Method $Scheme
        if ($Hit) { $HitTry = @{ Path = $T; Method = $Try.Method }; break }
    }
    if (-not $Found -and $Schema.Type) {
        foreach ($T in $TemplatesByType['{0}|{1}|{2}' -f $Schema.Type, $Schema.Many, (Get-ResourceName $Path)]) {
            $Hit = Get-LeastPermission $T $Call.Method $Scheme
            if ($Hit) { $HitTry = @{ Path = $T; Method = $Call.Method }; break }
        }
    }

    # Least comes from Microsoft's per-path map: a Learn page covers several requests (GET /me with GET /users/{id}),
    # so its least can be one that only works for some of them. Higher comes from the Learn page.
    $Row = $null
    foreach ($Try in @($Tries) + @($HitTry)) { if ($Try -and ($Row = Find-LearnRow $Call.Version $Try.Method $Try.Path $Scheme)) { break } }
    if ($Row) {
        $FromMap = [bool]$Hit
        $Least = if ($FromMap) { @($Hit.Permission) } else { @($Row.least) }
        $Higher = @((@($Row.least) + @($Row.higher)).Where({ $_ -notin $Least -and -not ($FromMap -and $_ -in $Row.least) }) | Select-Object -Unique)
        $Hit = @{ Permission = $Least; Higher = $Higher }
    }
    $Reason = if ($Hit) { $null }
    elseif ($Schema.Status -eq 'notInSchema') { "not in the Graph $($Call.Version) schema" }
    elseif ($Schema.Status -like '*Only') { "only in the Graph $($Schema.Status -replace 'Only$') schema" }
    elseif ($Schema.Status -eq 'dynamic') { 'dynamic path segment' }
    elseif ($Found) { "no $Scheme permission for $($Call.Method) in Microsoft's map" }
    else { "not in Microsoft's map" }
    $CallCache[$Key] = @{ Permission = $Hit.Permission; Higher = $Hit.Higher; Reason = $Reason }
    $CallCache[$Key]
}
#endregion

#region Annotation lines
function Format-PermissionLine([string[]]$Cols) {
    'Permission: ' + (($Cols -join ' | ') -replace '\|  (?=\|)', '| ').TrimEnd(' |')
}

function ConvertFrom-PermissionLine([string]$Line) {
    $Cols = @(($Line -replace '^\s*Permission:\s*') -split '\|').ForEach({ $_.Trim() })
    @{ Api = $Cols[0]; Operation = $Cols[1]; Type = $Cols[2]; Condition = $Cols[5]; Key = ('{0}|{1}|{2}' -f $Cols[0], $Cols[1], $Cols[2]).ToLowerInvariant(); Text = Format-PermissionLine $Cols }
}

function Get-PermissionLine($Fn) {
    $Notes = $Fn.GetHelpContent().Notes
    if (-not $Notes) { return @() }
    @(($Notes -split '\r?\n').Where({ $_ -match '^\s*Permission:' }).ForEach({ ConvertFrom-PermissionLine $_ }))
}

# The lines a function should carry: one per derived call, then the hand-written lines the script cannot derive.
function Get-DesiredLine($Fn, $Extracted, $Gaps) {
    $Existing = Get-PermissionLine $Fn
    $Derived = [ordered]@{}
    foreach ($C in $Extracted.Calls) {
        $Type = if ($C.AsApp) { 'Application' } else { 'Delegated' }
        $Resolved = Resolve-CallPermission $C $(if ($C.AsApp) { 'Application' } else { 'DelegatedWork' })
        if (-not $Resolved.Permission) { $Gaps.Add("$($C.Method) $($C.Path) ($($Resolved.Reason))"); continue }
        $Key = ('Graph|{0} {1}|{2}' -f $C.Method, $C.Path, $Type).ToLowerInvariant()
        if ($Derived.Contains($Key)) { continue }
        $Derived[$Key] = @('Graph', "$($C.Method) $($C.Path)", $Type, ($Resolved.Permission -join ', '), ($Resolved.Higher -join ', '))
    }
    foreach ($U in $Extracted.Unresolved) { $Gaps.Add("unreadable URI: $U") }

    $Lines = foreach ($Key in ($Derived.Keys | Sort-Object { ($_ -split '\|')[1] -replace '^\w+ ' }, { $_ })) {
        $Cols = @($Derived[$Key])
        $Condition = $Existing.Where({ $_.Key -eq $Key -and $_.Condition })[0].Condition
        Format-PermissionLine (@($Cols) + @($Condition))
    }
    $Manual = foreach ($E in $Existing) {
        if ($Derived.Contains($E.Key)) { continue }
        if ($E.Api -ne 'Graph' -or $Gaps.Count) { $E.Text }
    }
    @(@($Lines) + @($Manual) | Select-Object -Unique)
}
#endregion

#region Help block rewrite
# The comment block PowerShell reads help from: before the function keyword first, then the start of the body.
function Find-HelpToken($Fn, $Tokens, $ByOffset) {
    $i = $ByOffset[$Fn.Extent.StartOffset]
    $j = $i - 1
    $NewLines = 0
    while ($j -ge 0 -and $Tokens[$j].Kind -eq 'NewLine') { $NewLines++; $j-- }
    if ($j -ge 0 -and $NewLines -le 2 -and $Tokens[$j].Kind -eq 'Comment' -and $Tokens[$j].Text.StartsWith('<#') -and $Tokens[$j].Text -match $HelpKeyword) { return $Tokens[$j] }
    for ($j = $ByOffset[$Fn.Body.Extent.StartOffset] + 1; $j -lt $Tokens.Count -and $Tokens[$j].Kind -in 'NewLine', 'Comment'; $j++) {
        if ($Tokens[$j].Kind -eq 'Comment' -and $Tokens[$j].Text.StartsWith('<#') -and $Tokens[$j].Text -match $HelpKeyword) { return $Tokens[$j] }
    }
}

function Get-HelpEdit($Fn, $Tokens, $ByOffset, [string]$Source, [string[]]$Lines, [string]$NL) {
    $Token = Find-HelpToken $Fn $Tokens $ByOffset
    if (-not $Token) {
        if (-not $Lines.Count) { return $null }
        if ($Fn.GetHelpContent()) { throw "$($Fn.Name): help comes from a block this script cannot locate; add the lines by hand." }
        $LineStart = $Source.LastIndexOf("`n", [Math]::Max($Fn.Extent.StartOffset - 1, 0)) + 1
        $Indent = ($Source.Substring($LineStart) -replace '(?s)^([ \t]*).*', '$1') + '    '
        $Block = @("$Indent<#", "$Indent.NOTES") + @($Lines.ForEach({ "$Indent    $_" })) + "$Indent#>"
        $At = $Fn.Body.Extent.StartOffset + 1
        # Comments directly below the new block would join it as help; a blank line keeps them apart.
        $Next = $ByOffset[$Fn.Body.Extent.StartOffset] + 1
        while ($Next -lt $Tokens.Count -and $Tokens[$Next].Kind -eq 'NewLine') { $Next++ }
        $Gap = if ($Tokens[$Next].Kind -eq 'Comment') { $NL } else { '' }
        return @{ Start = $At; Length = 0; Text = $NL + ($Block -join $NL) + $Gap }
    }

    $BlockLines = [System.Collections.Generic.List[string]]::new([string[]]($Token.Text -split '\r?\n'))
    $Last = $BlockLines.Count - 1
    if ($Last -eq 0 -or $BlockLines[$Last].Trim() -ne '#>') {
        $Opening = $Source.Substring($Source.LastIndexOf("`n", [Math]::Max($Token.Extent.StartOffset - 1, 0)) + 1) -replace '(?s)^([ \t]*).*', '$1'
        $BlockLines[$Last] = $BlockLines[$Last] -replace '\s*#>$', ''
        $BlockLines.Add("$Opening#>")
        $Last++
    }
    $KeywordLine = $BlockLines.Where({ $_ -match $HelpKeyword })[0]
    $KeywordIndent = $KeywordLine -replace '^([ \t]*).*', '$1'
    $Notes = -1
    for ($k = 0; $k -lt $Last; $k++) { if ($BlockLines[$k] -match '(?i)^\s*\.NOTES\s*$') { $Notes = $k; break } }
    if ($Notes -lt 0) {
        if (-not $Lines.Count) { return $null }
        $New = @("$KeywordIndent.NOTES") + @($Lines.ForEach({ "$KeywordIndent    $_" }))
        $BlockLines.InsertRange($Last, [string[]]$New)
    } else {
        $End = $Notes + 1
        while ($End -lt $Last -and $BlockLines[$End] -notmatch $HelpKeyword) { $End++ }
        $Kept = @($BlockLines.GetRange($Notes + 1, $End - $Notes - 1).Where({ $_ -notmatch '^\s*Permission:' }))
        $ContentIndent = $Kept.Where({ $_.Trim() })[0] -replace '^([ \t]*).*', '$1'
        if (-not $ContentIndent) { $ContentIndent = "$KeywordIndent    " }
        while ($Kept.Count -and -not $Kept[-1].Trim()) { $Kept = @($Kept | Select-Object -SkipLast 1) }
        $Section = @($Kept) + @($Lines.ForEach({ "$ContentIndent$_" }))
        $Header = $BlockLines[$Notes]
        $BlockLines.RemoveRange($Notes, $End - $Notes)
        if ($Section.Count) { $BlockLines.InsertRange($Notes, [string[]](@($Header) + $Section)) }
    }
    $Text = $BlockLines -join $NL
    if ($Text -ceq $Token.Text) { return $null }
    @{ Start = $Token.Extent.StartOffset; Length = $Token.Extent.EndOffset - $Token.Extent.StartOffset; Text = $Text }
}

function Get-HelpSignature($Help) {
    $Notes = (($Help.Notes ?? '') -split '\r?\n').Where({ $_.Trim() -and $_ -notmatch '^\s*Permission:' }) -join '|'
    '{0}#{1}#{2}#{3}#{4}#{5}' -f "$($Help.Synopsis)".Trim(), "$($Help.Description)".Trim(), "$($Help.Role)".Trim(), "$($Help.Functionality)".Trim(), (@($Help.Parameters.Keys) -join ','), $Notes
}
#endregion

#region Run
$Drift = [System.Collections.Generic.List[string]]::new()
$Problems = [System.Collections.Generic.List[string]]::new()
$Report = [System.Collections.Generic.List[object]]::new()
$Written = 0
$Annotated = 0
foreach ($File in $Files) {
    $ByOffset = @{}
    for ($i = 0; $i -lt $File.Tokens.Count; $i++) { $ByOffset[$File.Tokens[$i].Extent.StartOffset] = $i }
    $Source = [System.IO.File]::ReadAllText($File.Path)
    $NL = if ($Source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $Edits = [System.Collections.Generic.List[object]]::new()
    $Expected = [System.Collections.Generic.List[object]]::new()

    foreach ($Fn in $File.Functions) {
        $Extracted = Get-FunctionCall $Fn
        $Gaps = [System.Collections.Generic.List[string]]::new()
        $Lines = @(Get-DesiredLine $Fn $Extracted $Gaps)
        $Current = @((Get-PermissionLine $Fn).Text)
        if ($Lines.Count) { $Annotated++ }
        $Expected.Add(@{ Signature = Get-HelpSignature $Fn.GetHelpContent(); Lines = $Lines })
        if ($Gaps.Count -or $Extracted.Exo.Count -or $Extracted.Hosts.Count) {
            $Report.Add([ordered]@{ function = $Fn.Name; file = [System.IO.Path]::GetRelativePath($ModulesPath, $File.Path); graphGaps = @($Gaps); exchangeCmdlets = @($Extracted.Exo | Sort-Object); otherHosts = @($Extracted.Hosts | Sort-Object) })
        }
        if ((@($Current) -join "`n") -ceq ($Lines -join "`n")) { continue }
        if ($Check) { $Drift.Add("$($Fn.Name) ($([System.IO.Path]::GetRelativePath($ModulesPath, $File.Path)))"); continue }
        try {
            $Edit = Get-HelpEdit $Fn $File.Tokens $ByOffset $Source $Lines $NL
            if ($Edit) { $Edits.Add($Edit) }
        } catch { $Problems.Add($_.Exception.Message); $Edits.Clear(); break }
    }
    if ($Check -or -not $Edits.Count) { continue }

    $Builder = [System.Text.StringBuilder]::new($Source)
    foreach ($Edit in ($Edits | Sort-Object { $_.Start } -Descending)) { [void]$Builder.Remove($Edit.Start, $Edit.Length).Insert($Edit.Start, $Edit.Text) }
    $NewSource = $Builder.ToString()

    # The rewritten file must parse to the same help everywhere, with exactly the intended lines.
    $Errors = $null
    $NewAst = [Parser]::ParseInput($NewSource, $File.Path, [ref]$null, [ref]$Errors)
    if ($Errors.Count) { throw "$($File.Path): rewrite does not parse: $($Errors[0].Message)" }
    $NewFunctions = @($NewAst.FindAll({ $args[0] -is [FunctionDefinitionAst] }, $true))
    $Changed = @(for ($i = 0; $i -lt $NewFunctions.Count; $i++) {
            $Signature = Get-HelpSignature $NewFunctions[$i].GetHelpContent()
            $Got = @((Get-PermissionLine $NewFunctions[$i]).Text) -join "`n"
            if ($Signature -cne $Expected[$i].Signature -or $Got -cne ($Expected[$i].Lines -join "`n")) { "$($NewFunctions[$i].Name) (help '$($Expected[$i].Signature)' became '$Signature')" }
        })
    if ($Changed.Count) { $Problems.Add("$($Changed -join ', '): rewriting the help block would change it; add the lines by hand."); continue }
    $Bom = [System.IO.File]::ReadAllBytes($File.Path)[0..2] -join ',' -eq '239,187,191'
    [System.IO.File]::WriteAllText($File.Path, $NewSource, [System.Text.UTF8Encoding]::new($Bom))
    $Written++
}

if ($ReportPath) { ConvertTo-Json -InputObject @($Report) -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM }
$GapCount = $Report.Where({ $_.graphGaps.Count }).Count
if ($Check) {
    if ($Drift.Count) {
        $Drift | ForEach-Object { Write-Host "  $_" }
        throw "$($Drift.Count) function(s) have stale Permission lines. Run build/tools/Update-PermissionAnnotations.ps1 and commit the result."
    }
    Write-Host "Permission lines are current ($Annotated functions annotated, $GapCount with Graph calls that need a hand-written line)."
    return
}
Write-Host "Updated $Written file(s). $Annotated functions annotated; $GapCount have Graph calls that need a hand-written line$(if ($ReportPath) { " (see $ReportPath)" })."
if ($Problems.Count) { throw "$($Problems.Count) file(s) were left unchanged:`n  $($Problems -join "`n  ")" }
#endregion
