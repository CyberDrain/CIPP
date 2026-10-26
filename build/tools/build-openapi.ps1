#Requires -Version 7.0

# Generate Config/openapi.json, the OpenAPI 3.1 description of the CIPP HTTP API.
#
# The spec is not documentation-only: Get-CippMcpSpec reads this file at runtime
# and Get-CippMcpToolList projects every read-only operation in it into an MCP
# tool definition. A wrong schema here is a wrong tool contract in production,
# so this runs on every build the same way build-function-parameters.ps1 does.
#
# Everything is derived from the PowerShell AST of the entrypoints themselves
# (Parser::ParseFile, no module import). That matters: the previous generator
# regex-scanned the source and truncated member chains, so
# `$Request.Body.onedriveAccessUser.value` was recorded as the parameter
# `onedriveAccessUser` and emitted as a plain string. Callers sent a string,
# the backend read `.value` off it, got $null, and the endpoint silently no-oped.
# A real AST walk keeps the whole chain, so the nesting is recovered structurally
# for every endpoint instead of one hand-written override at a time.
#
# Routing is name-based (New-CippCoreRequest does 'Invoke-{0}' -f CIPPEndpoint),
# so the file name IS the path. There is no route table to reconcile against.

[CmdletBinding()]
param(
    [string]$EntrypointPath = "$PSScriptRoot/../../backend/Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions",
    # Shared modules are indexed so a body handed to a helper can be followed into it.
    # Pass an empty or non-existent path to document only what the entrypoints read.
    [string]$ModulesPath = "$PSScriptRoot/../../backend/Modules",
    # The UI declares which fields it renders per list endpoint. Nothing in the
    # PowerShell describes the response, so this is the only static signal there is.
    [string]$FrontendPath = "$PSScriptRoot/../../frontend/src",
    [string]$OverridePath = "$PSScriptRoot/../../backend/Config/openapi-overrides",
    # Vendored Graph CSDL. Endpoints that fetch a Graph collection and return it untouched
    # name no field in their own source, but Graph publishes the entity's shape.
    [string]$GraphMetadataPath = "$PSScriptRoot/../../backend/Config/graph-metadata",
    [string]$OutputPath = "$PSScriptRoot/../../backend/Config/openapi.json",
    # Second copy, served as a static asset at /openapi.json. The in-app Swagger UI reads
    # that instead of calling the API for it, and external consumers can pull the spec
    # without occupying a PowerShell worker. Skipped when the directory does not exist,
    # which is the case in the image's openapi build stage - there the Dockerfile injects
    # it into the exported frontend after `yarn build`, so the compile stays cached.
    [string]$PublicPath = "$PSScriptRoot/../../frontend/public/openapi.json",
    [string]$ReportPath,
    [string]$Endpoint,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $EntrypointPath)) {
    throw "Entrypoint source not found at '$EntrypointPath'."
}

# -- AST vocabulary ------------------------------------------------------------

# Members that exist on every PowerShell object rather than on the JSON payload.
# Reading one says something about the shape of the parent but is never itself a
# request field: $Request.Body.Users.Count means Users is a collection, it does
# not mean the caller sends a "Count".
$AutoMembers = @{
    'count'       = 'array'
    'length'      = 'array'
    'longlength'  = 'array'
    'rank'        = 'array'
    'syncroot'    = 'array'
    'keys'        = 'object'
    'values'      = 'object'
    'psobject'    = 'skip'
    'psbase'      = 'skip'
    'psadapted'   = 'skip'
    'psextended'  = 'skip'
    'pstypenames' = 'skip'
    'gettype'     = 'skip'
    'tostring'    = 'skip'
    'equals'      = 'skip'
    'gethashcode' = 'skip'
    'isfixedsize' = 'skip'
    'isreadonly'  = 'skip'
    'issynchronized' = 'skip'
    'item'        = 'skip'
}

# [type] casts and -as targets, mapped to the JSON Schema they imply.
$CastTypes = @{
    'bool'           = @{ type = 'boolean' }
    'boolean'        = @{ type = 'boolean' }
    'switch'         = @{ type = 'boolean' }
    'int'            = @{ type = 'integer' }
    'int32'          = @{ type = 'integer' }
    'int64'          = @{ type = 'integer' }
    'long'           = @{ type = 'integer' }
    'uint32'         = @{ type = 'integer' }
    'byte'           = @{ type = 'integer' }
    'double'         = @{ type = 'number' }
    'decimal'        = @{ type = 'number' }
    'single'         = @{ type = 'number' }
    'float'          = @{ type = 'number' }
    'string'         = @{ type = 'string' }
    # [ordered] so the two-key leaf serialises in a fixed order. A plain @{} enumerates
    # in bucket order, which .NET derives from per-process randomised string hashes, so
    # ConvertTo-JsonSchema would emit type/format in a coin-flip order that differs between
    # processes - spurious spec drift and a flaky -Check once any date-time field exists.
    'datetime'       = [ordered]@{ type = 'string'; format = 'date-time' }
    'guid'           = [ordered]@{ type = 'string'; format = 'uuid' }
    'timespan'       = @{ type = 'string' }
    'version'        = @{ type = 'string' }
    'semver'         = @{ type = 'string' }
    'hashtable'      = @{ type = 'object' }
    'pscustomobject' = @{ type = 'object' }
    'psobject'       = @{ type = 'object' }
}

# Casts whose only meaning is "treat as a collection". The element type comes
# from whatever the code does with the elements, not from the cast.
$ArrayCastTypes = @('array', 'object[]', 'string[]', 'int[]', 'psobject[]', 'list', 'collection')

function Get-UnwrappedAst {
    # Strips the pipeline/command/paren wrappers PowerShell inserts around
    # expressions in statement position. A foreach condition and an assignment
    # right-hand side both arrive as a PipelineAst even when the source is a bare
    # member access, so every caller that wants to pattern-match has to unwrap first.
    param($Ast)

    $Node = $Ast
    while ($null -ne $Node) {
        if ($Node -is [System.Management.Automation.Language.PipelineAst]) {
            if ($Node.PipelineElements.Count -ne 1) { return $Node }
            $Node = $Node.PipelineElements[0]
        } elseif ($Node -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Node = $Node.Expression
        } elseif ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $Node = $Node.Pipeline
        } else {
            return $Node
        }
    }
    return $Node
}

# Cmdlets that filter or reorder a pipeline without changing the shape of its
# elements. `$Request.Body | Where-Object {...} | ForEach-Object { $_.x }` reads the
# same field as `$Request.Body | ForEach-Object { $_.x }`, so they are walked through.
$TransparentCommands = @(
    'Where-Object', '?', 'Sort-Object', 'Select-Object', 'Get-Unique', 'Get-Random', 'Tee-Object'
)

function Get-PipelineSourceAst {
    # Resolves what a pipeline actually yields, skipping the shape-preserving stages.
    # Returns the expression at the head of the pipeline, or the pipeline itself when
    # a stage transforms the elements (Group-Object, Measure-Object, ...) and the
    # result can no longer be traced back to a request field.
    param($Ast)

    $Node = Get-UnwrappedAst -Ast $Ast
    if ($Node -isnot [System.Management.Automation.Language.PipelineAst]) { return $Node }

    for ($i = $Node.PipelineElements.Count - 1; $i -ge 0; $i--) {
        $Element = $Node.PipelineElements[$i]
        if ($Element -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return Get-UnwrappedAst -Ast $Element.Expression
        }
        if ($Element -is [System.Management.Automation.Language.CommandAst]) {
            $Name = $Element.GetCommandName()
            if ($null -eq $Name -or $Name -notin $TransparentCommands) { return $Node }
            continue
        }
        return $Node
    }
    return $Node
}

function Get-AstMemberChain {
    # Walks a property-access chain down to the variable it is rooted at and
    # returns the literal property names in source order.
    #
    # This is the whole reason the generator is written against the AST: the chain
    # is walked to its end, so `$Request.Body.user.value` yields ('Body','user','value')
    # rather than stopping at the first segment a regex happens to match.
    #
    # ArrayAt holds the indexes of segments that were subscripted ($x.list[0].name
    # marks 'list'), which is how element access is distinguished from a property
    # literally named after the index. Returns $null for chains that cannot be
    # resolved statically: computed member names ($Request.Body.$field) and method
    # calls, which terminate the property path.
    param($Ast)

    $Segments = [System.Collections.Generic.List[string]]::new()
    $IndexDepths = [System.Collections.Generic.List[int]]::new()
    $Node = $Ast

    while ($true) {
        if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $Segments.Reverse()
            $Total = $Segments.Count
            # depths were recorded counting from the leaf; flip them to indexes from the root
            $ArrayAt = @($IndexDepths | ForEach-Object { $Total - $_ - 1 } | Where-Object { $_ -ge 0 })
            return [pscustomobject]@{
                Root     = $Node.VariablePath.UserPath
                Segments = @($Segments)
                ArrayAt  = $ArrayAt
            }
        }

        if ($Node -is [System.Management.Automation.Language.IndexExpressionAst]) {
            $IndexDepths.Add($Segments.Count)
            $Node = $Node.Target
            continue
        }

        # InvokeMemberExpressionAst derives from MemberExpressionAst, so it has to be
        # tested first. `$Request.Body.x.Trim()` is a method call, not a field named
        # Trim; the receiver is picked up separately as its own chain.
        if ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            return $null
        }

        if ($Node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if ($Node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return $null
            }
            $Segments.Add($Node.Member.Value)
            $Node = $Node.Expression
            continue
        }

        return $null
    }
}

function Resolve-RequestPath {
    # Turns a raw member chain into a request access: which half of the request it
    # reads (Body or Query) and the field path underneath. Chains rooted at a local
    # variable are resolved through $Aliases, which is what lets the common
    # `$UserObj = $Request.Body` / `$UserObj.displayName` idiom resolve to a body field.
    param($Chain, [hashtable]$Aliases)

    if ($null -eq $Chain) { return $null }

    if ($Chain.Root -eq 'Request') {
        if ($Chain.Segments.Count -eq 0) { return $null }
        $Section = $Chain.Segments[0]
        if ($Section -notmatch '^(?i)(Body|Query)$') { return $null }
        $Rest = @($Chain.Segments | Select-Object -Skip 1)
        # ArrayAt indexes shift by one now that the section segment is dropped
        $ArrayAt = @($Chain.ArrayAt | ForEach-Object { $_ - 1 } | Where-Object { $_ -ge 0 })
        return [pscustomobject]@{
            Section  = (Get-Culture).TextInfo.ToTitleCase($Section.ToLowerInvariant())
            Segments = $Rest
            ArrayAt  = $ArrayAt
        }
    }

    $Alias = $Aliases[$Chain.Root]
    if (-not $Alias) { return $null }

    $Segments = @($Alias.Segments) + @($Chain.Segments)
    $Offset = $Alias.Segments.Count
    $ArrayAt = [System.Collections.Generic.List[int]]::new()
    foreach ($i in $Alias.ArrayAt) { $ArrayAt.Add($i) }
    foreach ($i in $Chain.ArrayAt) { if (($i + $Offset) -ge 0) { $ArrayAt.Add($i + $Offset) } }
    # a foreach/pipeline alias names the *element*, so the thing it was bound to is an
    # array. index -1 means the request body itself is an array, which is how bulk
    # endpoints like ExecBulkLicense are shaped: the payload is a list, not an object
    if ($Alias.IsElement) { $ArrayAt.Add($Offset - 1) }

    return [pscustomobject]@{
        Section  = $Alias.Section
        Segments = @($Segments)
        ArrayAt  = @($ArrayAt | Sort-Object -Unique)
    }
}

function Resolve-PipelineItemPath {
    # Resolves $_ / $PSItem inside ForEach-Object or Where-Object to the upstream
    # pipeline source. This cannot go through the flat alias map: every pipeline in a
    # function binds its own $_, so the meaning depends on where the use site sits.
    # Walking up from the use site to the enclosing script block gets the right one.
    #
    # Bulk endpoints depend on this - ExecBulkLicense reads its fields as
    # `$Request.Body | ForEach-Object { $_.userIds }` and is otherwise invisible.
    param($Node, [hashtable]$Aliases, [int]$Depth = 0)

    if ($Depth -gt 4) { return $null }

    $Current = $Node
    while ($null -ne $Current) {
        $Parent = $Current.Parent
        if ($Current -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $null -ne $Parent) {

            if ($Parent -is [System.Management.Automation.Language.CommandAst]) {
                $CommandName = $Parent.GetCommandName()
                if ($CommandName -match '^(?i)(ForEach-Object|Where-Object|%|\?)$') {
                    $Pipeline = $Parent.Parent
                    if ($Pipeline -is [System.Management.Automation.Language.PipelineAst]) {
                        $Index = $Pipeline.PipelineElements.IndexOf($Parent)
                        # walk back past filters and sorts to whatever actually produced
                        # the elements
                        while ($Index -gt 0) {
                            $Upstream = $Pipeline.PipelineElements[$Index - 1]
                            if ($Upstream -is [System.Management.Automation.Language.CommandAst] -and
                                $Upstream.GetCommandName() -in $TransparentCommands) { $Index--; continue }
                            return Resolve-UpstreamElementPath -Element $Upstream -Aliases $Aliases -Depth $Depth
                        }
                    }
                }
            }

            # the .ForEach{} / .Where{} method form
            if ($Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $Parent.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $Parent.Member.Value -match '^(?i)(ForEach|Where)$') {
                return Resolve-UpstreamElementPath -Element $Parent.Expression -Aliases $Aliases -Depth $Depth
            }
        }
        $Current = $Parent
    }
    return $null
}

function Resolve-UpstreamElementPath {
    # The request path an upstream pipeline element produces, marked as referring to
    # that path's *elements* rather than the collection itself.
    param($Element, [hashtable]$Aliases, [int]$Depth = 0)

    $Expression = Get-PipelineSourceAst -Ast $Element
    $Chain = Get-AstMemberChain -Ast $Expression
    if ($null -eq $Chain) { return $null }

    if ($Chain.Root -in @('_', 'PSItem')) {
        # a nested pipeline: resolve the outer $_ first, then descend
        $Outer = Resolve-PipelineItemPath -Node $Expression -Aliases $Aliases -Depth ($Depth + 1)
        if ($null -eq $Outer) { return $null }
        $Segments = @($Outer.Segments) + @($Chain.Segments)
        $ArrayAt = @($Outer.ArrayAt) + @($Chain.ArrayAt | ForEach-Object { $_ + $Outer.Segments.Count })
        return [pscustomobject]@{
            Section  = $Outer.Section
            Segments = @($Segments)
            ArrayAt  = @(@($ArrayAt) + @($Segments.Count - 1) | Sort-Object -Unique)
        }
    }

    $Resolved = Resolve-RequestPath -Chain $Chain -Aliases $Aliases
    if ($null -eq $Resolved) { return $null }
    return [pscustomobject]@{
        Section  = $Resolved.Section
        Segments = $Resolved.Segments
        ArrayAt  = @(@($Resolved.ArrayAt) + @($Resolved.Segments.Count - 1) | Sort-Object -Unique)
    }
}

function Resolve-AccessPath {
    # Single entry point for turning a member-access node into a request access,
    # covering both named locals ($UserObj.field) and pipeline items ($_.field).
    param($Node, [hashtable]$Aliases)

    $Chain = Get-AstMemberChain -Ast $Node
    if ($null -eq $Chain) { return $null }

    if ($Chain.Root -in @('_', 'PSItem')) {
        $Base = Resolve-PipelineItemPath -Node $Node -Aliases $Aliases
        if ($null -eq $Base) { return $null }
        $Segments = @($Base.Segments) + @($Chain.Segments)
        $Offset = $Base.Segments.Count
        $ArrayAt = @($Base.ArrayAt) + @($Chain.ArrayAt | ForEach-Object { $_ + $Offset })
        return [pscustomobject]@{
            Section  = $Base.Section
            Segments = @($Segments)
            ArrayAt  = @($ArrayAt | Sort-Object -Unique)
        }
    }

    return Resolve-RequestPath -Chain $Chain -Aliases $Aliases
}

function Get-RequestAliasMap {
    # Builds local-variable -> request-path bindings, run to a fixed point so that
    # chained aliases ($a = $Request.Body; $b = $a.user; $b.value) resolve.
    #
    # Two binding forms matter: assignment ($x = <request path>) binds the path
    # itself, and foreach ($x in <request path>) binds an *element* of it, which is
    # both how array-ness is discovered and how element field names are attributed
    # to the item schema rather than to the array.
    param($FunctionAst, [hashtable]$Seed)

    $Aliases = @{}
    if ($Seed) { foreach ($Key in $Seed.Keys) { $Aliases[$Key] = $Seed[$Key] } }
    $Assignments = $FunctionAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
        }, $true)
    $ForEachStatements = $FunctionAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst]
        }, $true)

    for ($Pass = 0; $Pass -lt 5; $Pass++) {
        $Changed = $false

        foreach ($Assignment in $Assignments) {
            if ($Assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $Name = $Assignment.Left.VariablePath.UserPath
            if ($Aliases.ContainsKey($Name)) { continue }

            $Right = Get-UnwrappedAst -Ast $Assignment.Right
            # `$x = $Request.Body.a ?? $Request.Body.b` binds to the first operand;
            # both operands are still recorded as accesses in their own right.
            if ($Right -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $Right.Operator -eq [System.Management.Automation.Language.TokenKind]::QuestionQuestion) {
                $Right = Get-UnwrappedAst -Ast $Right.Left
            }

            $Resolved = Resolve-RequestPath -Chain (Get-AstMemberChain -Ast $Right) -Aliases $Aliases
            if ($null -eq $Resolved) { continue }

            $Aliases[$Name] = [pscustomobject]@{
                Section   = $Resolved.Section
                Segments  = $Resolved.Segments
                ArrayAt   = $Resolved.ArrayAt
                IsElement = $false
            }
            $Changed = $true
        }

        foreach ($Loop in $ForEachStatements) {
            $Name = $Loop.Variable.VariablePath.UserPath
            if ($Aliases.ContainsKey($Name)) { continue }

            $Source = Get-PipelineSourceAst -Ast $Loop.Condition
            $Resolved = Resolve-RequestPath -Chain (Get-AstMemberChain -Ast $Source) -Aliases $Aliases
            if ($null -eq $Resolved) { continue }

            $Aliases[$Name] = [pscustomobject]@{
                Section   = $Resolved.Section
                Segments  = $Resolved.Segments
                ArrayAt   = $Resolved.ArrayAt
                IsElement = $true
            }
            $Changed = $true
        }

        if (-not $Changed) { break }
    }

    return $Aliases
}

function Get-UsageSchemaHint {
    # Infers a field's type from what the surrounding code does with it. The JSON
    # payload carries no type information, so usage is the only evidence there is:
    # a [bool] cast, a numeric comparison, a -split, being enumerated by foreach.
    #
    # Returns $null when the context says nothing, which is the common case and
    # correctly leaves the field as the default string.
    param($Node)

    $Parent = $Node.Parent
    # a parenthesised access still has the surrounding context one level up
    while ($Parent -is [System.Management.Automation.Language.ParenExpressionAst] -or
        $Parent -is [System.Management.Automation.Language.PipelineAst] -or
        $Parent -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $Node = $Parent
        $Parent = $Parent.Parent
    }
    if ($null -eq $Parent) { return $null }

    if ($Parent -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $TypeName = $Parent.Type.TypeName.Name.ToLowerInvariant() -replace '^system\.', ''
        if ($ArrayCastTypes -contains $TypeName) { return @{ IsArray = $true } }
        if ($CastTypes.ContainsKey($TypeName)) { return @{ Schema = $CastTypes[$TypeName] } }
        return $null
    }

    if ($Parent -is [System.Management.Automation.Language.IndexExpressionAst]) {
        if ([object]::ReferenceEquals($Parent.Target, $Node)) { return @{ IsArray = $true } }
        return $null
    }

    if ($Parent -is [System.Management.Automation.Language.ForEachStatementAst]) {
        return @{ IsArray = $true }
    }

    if ($Parent -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $IsLeft = [object]::ReferenceEquals((Get-UnwrappedAst -Ast $Parent.Left), $Node)
        $Other = if ($IsLeft) { Get-UnwrappedAst -Ast $Parent.Right } else { Get-UnwrappedAst -Ast $Parent.Left }

        switch -Regex ($Parent.Operator.ToString()) {
            '^(I|C)?(eq|ne)$' {
                if ($Other -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $Var = $Other.VariablePath.UserPath.ToLowerInvariant()
                    if ($Var -in @('true', 'false')) { return @{ Schema = @{ type = 'boolean' } } }
                }
                if ($Other -is [System.Management.Automation.Language.ConstantExpressionAst] -and
                    $Other -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    if ($Other.Value -is [int] -or $Other.Value -is [long]) { return @{ Schema = @{ type = 'integer' } } }
                    if ($Other.Value -is [double] -or $Other.Value -is [decimal]) { return @{ Schema = @{ type = 'number' } } }
                }
                if ($Other -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    return @{ Observed = $Other.Value }
                }
                return $null
            }
            '^(I|C)?(gt|ge|lt|le)$' { return @{ Schema = @{ type = 'number' } } }
            '^(I|C)?split$' { if ($IsLeft) { return @{ Schema = @{ type = 'string' } } } return $null }
            '^(I|C)?join$' { if ($IsLeft) { return @{ IsArray = $true } } return $null }
            '^(I|C)?(not)?contains$' { if ($IsLeft) { return @{ IsArray = $true } } return $null }
            '^(I|C)?(not)?in$' { if (-not $IsLeft) { return @{ IsArray = $true } } return $null }
            '^(I|C)?(not)?(match|like)$' { if ($IsLeft) { return @{ Schema = @{ type = 'string' } } } return $null }
            '^As$' {
                if (-not $IsLeft) { return $null }
                if ($Other -is [System.Management.Automation.Language.TypeExpressionAst]) {
                    $TypeName = $Other.TypeName.Name.ToLowerInvariant() -replace '^system\.', ''
                    if ($ArrayCastTypes -contains $TypeName) { return @{ IsArray = $true } }
                    if ($CastTypes.ContainsKey($TypeName)) { return @{ Schema = $CastTypes[$TypeName] } }
                }
                return $null
            }
            default { return $null }
        }
    }

    return $null
}

function Get-SourceComment {
    # Pulls the developer's own comment for a field, so descriptions come from the
    # source instead of being synthesised. CIPP entrypoints routinely annotate the
    # request reads (see Invoke-ExecSharePointPerms), and that prose is the best
    # description available anywhere in the codebase.
    #
    # Matches a trailing comment on the same line first, then the comment block
    # sitting directly above the statement. Consecutive # lines are separate tokens,
    # so the block is walked upward and rejoined - taking only the last line would
    # quote a sentence fragment.
    param($Node, $CommentsByEndLine, $CommentsByStartLine, $StatementStartLine)

    $Line = $Node.Extent.StartLineNumber
    $Trailing = $CommentsByStartLine[$Line]
    if ($Trailing -and $Trailing.Extent.StartColumnNumber -gt $Node.Extent.StartColumnNumber) {
        $Text = $Trailing.Text -replace '^#+\s*', ''
        if ($Text.Trim()) { return $Text.Trim() }
    }

    $Lines = [System.Collections.Generic.List[string]]::new()
    for ($Candidate = $StatementStartLine - 1; $Candidate -gt 0; $Candidate--) {
        $Comment = $CommentsByEndLine[$Candidate]
        if (-not $Comment -or -not $Comment.Text.StartsWith('#') -or $Comment.Text.StartsWith('#>')) { break }
        # the token must own the whole line; a trailing comment belongs to the line above it
        if ($Comment.Extent.StartLineNumber -ne $Candidate) { break }
        $Text = ($Comment.Text -replace '^#+\s*', '').Trim()
        # a divider like "# ---------" carries no information and ends the block
        if (-not $Text -or $Text -match '^[\s\-=#*]+$') { break }
        $Lines.Insert(0, $Text)
        if ($Lines.Count -ge 6) { break }
    }

    if ($Lines.Count -eq 0) { return $null }
    return ($Lines -join ' ')
}

function Get-EnclosingStatementLine {
    # The line a comment would sit above: the top of the statement containing the
    # access, not the access itself, which may be mid-expression.
    param($Node)

    $Current = $Node
    while ($null -ne $Current) {
        if ($Current -is [System.Management.Automation.Language.StatementAst]) {
            return $Current.Extent.StartLineNumber
        }
        $Current = $Current.Parent
    }
    return $Node.Extent.StartLineNumber
}

# -- Schema tree ---------------------------------------------------------------

function Initialize-SchemaNode {
    return [pscustomobject]@{
        Children    = [ordered]@{}
        Schemas     = [System.Collections.Generic.List[hashtable]]::new()
        Observed    = [System.Collections.Generic.List[string]]::new()
        Enum        = $null
        IsArray     = $false
        IsDynamic   = $false
        Description = $null
        Required    = $false
    }
}

function Add-AccessToTree {
    # Inserts one observed access into the field tree. Segments marked in ArrayAt
    # become array nodes and everything below them describes the array's items,
    # which is how `foreach ($u in $Request.Body.users) { $u.upn }` produces
    # users: array of { upn } instead of a field literally called users.upn.
    param($Root, $Access, $Hint, $Description)

    $Node = $Root
    $Count = $Access.Segments.Count

    # -1 marks the root: the request body is a JSON array and everything below
    # describes one of its elements
    if ($Access.ArrayAt -contains -1) { $Root.IsArray = $true }

    for ($i = 0; $i -lt $Count; $i++) {
        $Name = $Access.Segments[$i]
        $Key = $Name.ToLowerInvariant()

        if ($AutoMembers.ContainsKey($Key)) {
            # not a request field: it tells us about the parent and then the path ends
            $Kind = $AutoMembers[$Key]
            if ($Kind -eq 'array') { $Node.IsArray = $true }
            if ($Kind -eq 'object') { $Node.IsDynamic = $true }
            return
        }

        if (-not $Node.Children.Contains($Name)) {
            $Node.Children[$Name] = Initialize-SchemaNode
            $Script:DiscoveredFieldCount++
        }
        $Node = $Node.Children[$Name]

        if ($Access.ArrayAt -contains $i) { $Node.IsArray = $true }
    }

    if ($Count -eq 0) {
        # a bare `$Request.Body` reference that is neither an alias binding nor an
        # enumeration: the payload is forwarded wholesale, so the documented fields
        # are a floor, not the contract
        if ($Access.ArrayAt -notcontains -1) { $Root.IsDynamic = $true }
        return
    }

    if ($Hint) {
        if ($Hint.IsArray) { $Node.IsArray = $true }
        if ($Hint.Schema) { $Node.Schemas.Add($Hint.Schema) }
        if ($Hint.Observed -and -not $Node.Observed.Contains($Hint.Observed)) { $Node.Observed.Add($Hint.Observed) }
    }
    if ($Description -and -not $Node.Description) { $Node.Description = $Description }
}

# Bumped every time a field is discovered. Comparing it either side of a followed
# call says whether that call taught us anything, without rewalking the tree - the
# check runs once per call site and the trees get large.
$Script:DiscoveredFieldCount = 0

function Resolve-TreeNode {
    # Finds an existing node by dotted path, for attaching enum/required facts
    # discovered by a separate pass.
    param($Root, [string[]]$Segments)

    $Node = $Root
    foreach ($Name in $Segments) {
        if ($AutoMembers.ContainsKey($Name.ToLowerInvariant())) { return $null }
        if (-not $Node.Children.Contains($Name)) { return $null }
        $Node = $Node.Children[$Name]
    }
    return $Node
}

function ConvertTo-JsonSchema {
    # Renders a field node as JSON Schema.
    #
    # The label/value collapse is deliberate and is the fix for the reported bug:
    # a node whose only observed children are label and/or value is CIPP's
    # autocomplete shape, so it is emitted as the LabelValue component rather than
    # as an anonymous object. Callers get { "value": "user@domain" }, which is what
    # the backend actually reads, instead of a bare string that resolves to $null.
    param($Node)

    $Schema = [ordered]@{}
    $ChildNames = @($Node.Children.Keys)

    if ($ChildNames.Count -gt 0) {
        $Lowered = @($ChildNames | ForEach-Object { $_.ToLowerInvariant() })
        $IsLabelValue = ($Lowered -contains 'value') -and (@($Lowered | Where-Object { $_ -notin @('label', 'value') }).Count -eq 0)

        if ($IsLabelValue) {
            $ValueNode = $null
            foreach ($Child in $ChildNames) { if ($Child.ToLowerInvariant() -eq 'value') { $ValueNode = $Node.Children[$Child] } }
            $ValueType = 'string'
            foreach ($Candidate in $ValueNode.Schemas) { if ($Candidate.type -in @('integer', 'number')) { $ValueType = 'number' } }
            $Ref = if ($ValueType -eq 'number') { '#/components/schemas/LabelValueNumber' } else { '#/components/schemas/LabelValue' }

            if ($Node.IsArray) {
                $Inner = [ordered]@{ type = 'array'; items = [ordered]@{ '$ref' = $Ref } }
            } else {
                $Inner = [ordered]@{ '$ref' = $Ref }
            }
        } else {
            $Properties = [ordered]@{}
            $Required = [System.Collections.Generic.List[string]]::new()
            foreach ($Child in ($ChildNames | Sort-Object -CaseSensitive)) {
                $Properties[$Child] = ConvertTo-JsonSchema -Node $Node.Children[$Child]
                if ($Node.Children[$Child].Required) { $Required.Add($Child) }
            }
            $Object = [ordered]@{ type = 'object'; properties = $Properties }
            if ($Required.Count -gt 0) { $Object['required'] = @($Required) }
            if ($Node.IsDynamic) { $Object['additionalProperties'] = $true }

            if ($Node.IsArray) {
                $Inner = [ordered]@{ type = 'array'; items = $Object }
            } else {
                $Inner = $Object
            }
        }
    } else {
        $Leaf = [ordered]@{}
        # a cast or comparison beats the string default; when several disagree the
        # most specific non-string wins, since a [string] cast is often just formatting
        $Chosen = $null
        foreach ($Candidate in $Node.Schemas) {
            if ($null -eq $Chosen) { $Chosen = $Candidate; continue }
            if ($Chosen.type -eq 'string' -and $Candidate.type -ne 'string') { $Chosen = $Candidate }
        }
        if ($Chosen) { foreach ($Pair in $Chosen.GetEnumerator()) { $Leaf[$Pair.Key] = $Pair.Value } }
        if (-not $Leaf.Contains('type')) { $Leaf['type'] = 'string' }

        if ($Node.IsArray) {
            $Inner = [ordered]@{ type = 'array'; items = $Leaf }
        } else {
            $Inner = $Leaf
        }
    }

    if ($Node.Enum -and $Node.Enum.Count -gt 0 -and -not $Inner.Contains('$ref')) {
        $Target = if ($Inner['items']) { $Inner['items'] } else { $Inner }
        if (-not $Target.Contains('$ref')) { $Target['enum'] = @($Node.Enum) }
    }

    foreach ($Pair in $Inner.GetEnumerator()) { $Schema[$Pair.Key] = $Pair.Value }

    if ($Node.Description) {
        # $ref must never carry siblings in OAS 3.1; wrap when there is something to add
        if ($Schema.Contains('$ref')) {
            $Schema = [ordered]@{ allOf = @([ordered]@{ '$ref' = $Schema['$ref'] }); description = $Node.Description }
        } else {
            $Schema['description'] = $Node.Description
        }
    }

    if ($Node.Observed.Count -ge 2 -and -not $Schema.Contains('allOf') -and -not $Schema.Contains('$ref') -and -not $Schema.Contains('enum')) {
        # values the endpoint explicitly compares against. non-normative: the code may
        # accept more than it branches on, so this is a hint, not an enum
        $Schema['x-cipp-observed-values'] = @($Node.Observed | Sort-Object -CaseSensitive)
    }

    return $Schema
}

# -- Endpoint extraction -------------------------------------------------------

function Get-HelperSourceIndex {
    # Maps helper function name -> file, by scanning declarations textually. Full
    # parsing is deferred to Get-HelperDefinition so only the handful of helpers an
    # endpoint actually calls is ever parsed.
    param([string[]]$SearchPath)

    $Index = @{}
    $Declaration = [regex]::new('(?im)^\s*function\s+([A-Za-z][\w-]*)\s*(\{|$)')
    foreach ($Root in $SearchPath) {
        if (-not (Test-Path $Root)) { continue }
        # Sorted on a separator-normalized path: first declaration wins, and NTFS
        # enumerates sorted while ext4 does not, so an unsorted scan makes the winner
        # differ between a local build and the ubuntu runner.
        foreach ($File in Get-ChildItem -Path $Root -Filter '*.ps1' -Recurse -File | Sort-Object { $_.FullName.Replace('\', '/') }) {
            foreach ($Match in $Declaration.Matches([IO.File]::ReadAllText($File.FullName))) {
                $Name = $Match.Groups[1].Value
                if (-not $Index.ContainsKey($Name)) { $Index[$Name] = $File.FullName }
            }
        }
    }
    return $Index
}

$HelperAstCache = @{}

function Get-HelperDefinition {
    # Parsed AST + comment maps for a helper, cached across endpoints. Many endpoints
    # call the same helpers, so this is parsed once per build, not once per caller.
    param([string]$Name, [hashtable]$Index)

    if (-not $Index.ContainsKey($Name)) { return $null }
    $Path = $Index[$Name]
    $CacheKey = "$Path|$Name"
    if ($HelperAstCache.ContainsKey($CacheKey)) { return $HelperAstCache[$CacheKey] }

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    $Result = $null
    if ($Errors.Count -eq 0) {
        $Definition = $Ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($Definition) {
            $Result = [pscustomobject]@{
                Definition = $Definition
                Comments   = Get-CommentMap -Path $Path -Tokens $Tokens
            }
        }
    }
    $HelperAstCache[$CacheKey] = $Result
    return $Result
}

function Get-CommentMap {
    # A comment block above a statement documents it; a comment trailing code on the
    # same line documents that line. Telling them apart needs the source, since both
    # look identical in the token stream.
    param([string]$Path, $Tokens)

    $SourceLines = [IO.File]::ReadAllLines($Path)
    $ByEndLine = @{}
    $ByStartLine = @{}
    foreach ($Token in $Tokens) {
        if ($Token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) { continue }
        $LineIndex = $Token.Extent.StartLineNumber - 1
        $Prefix = if ($LineIndex -ge 0 -and $LineIndex -lt $SourceLines.Count) {
            $SourceLines[$LineIndex].Substring(0, [Math]::Min($Token.Extent.StartColumnNumber - 1, $SourceLines[$LineIndex].Length))
        } else { '' }
        if ([string]::IsNullOrWhiteSpace($Prefix)) {
            $ByEndLine[$Token.Extent.EndLineNumber] = $Token
        } else {
            $ByStartLine[$Token.Extent.StartLineNumber] = $Token
        }
    }
    return [pscustomobject]@{ ByEndLine = $ByEndLine; ByStartLine = $ByStartLine }
}

function Get-BoundParameterName {
    # The callee parameter a `-Name value` argument binds to. PowerShell accepts any
    # unambiguous prefix at the call site, so `-UserObj` and `-User` may name the same
    # parameter; an ambiguous prefix binds nothing and is skipped.
    param([string]$Written, $CalleeAst)

    $Parameters = $CalleeAst.Parameters
    if (-not $Parameters -and $CalleeAst.Body.ParamBlock) { $Parameters = $CalleeAst.Body.ParamBlock.Parameters }
    $Names = @(@($Parameters) | Where-Object { $_ } | ForEach-Object { $_.Name.VariablePath.UserPath })

    $Exact = @($Names | Where-Object { $_ -eq $Written })
    if ($Exact.Count -eq 1) { return $Exact[0] }
    $Prefix = @($Names | Where-Object { $_ -like "$Written*" })
    if ($Prefix.Count -eq 1) { return $Prefix[0] }
    return $null
}

$Script:HelperReadsCache = @{}

function Test-HelperReadsParameter {
    # Whether a helper reads any property off the named parameter, directly or through
    # a local it is bound to. A helper that only forwards or logs the value teaches us
    # nothing, and following it is pure cost.
    param($Helper, [string]$ParameterName, [string]$Name)

    $Key = "$Name|$ParameterName"
    if ($Script:HelperReadsCache.ContainsKey($Key)) { return $Script:HelperReadsCache[$Key] }

    # a sentinel path stands in for the caller's: the answer is the same either way
    $Seed = @{
        $ParameterName = [pscustomobject]@{
            Section = 'Body'; Segments = @(); ArrayAt = @(); IsElement = $false
        }
    }
    $Aliases = Get-RequestAliasMap -FunctionAst $Helper.Definition -Seed $Seed

    $Reads = $false
    foreach ($Member in $Helper.Definition.FindAll({
                param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst]
            }, $true)) {
        $Access = Resolve-AccessPath -Node $Member -Aliases $Aliases
        if ($null -ne $Access -and $Access.Segments.Count -gt 0) { $Reads = $true; break }
    }

    $Script:HelperReadsCache[$Key] = $Reads
    return $Reads
}

function Add-DownstreamAccess {
    # Follows a request payload into the helper that consumes it.
    #
    # CIPP entrypoints routinely bind the body and hand it straight on
    # (`$UserObj = $Request.Body` then `Set-CIPPUser -UserObj $UserObj`), so for the
    # busiest endpoints most of the contract lives in CIPPCore, not in the entrypoint.
    # Reading only the entrypoint documents a handful of fields and silently omits the
    # rest. Following the call recovers them from source, which is what the old
    # generator was approximating by scraping the React form components.
    #
    # Deliberately conservative: named arguments only, known helpers only, and a depth
    # cap, because a wrong attribution here invents fields that do not exist.
    param($FunctionAst, [hashtable]$Aliases, $Trees, [hashtable]$Index, [int]$Depth, [hashtable]$Visited, $Followed)

    if ($Depth -le 0) { return }

    foreach ($Command in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {

        $CommandName = $Command.GetCommandName()
        if (-not $CommandName -or -not $Index.ContainsKey($CommandName)) { continue }

        $Elements = $Command.CommandElements
        for ($i = 1; $i -lt $Elements.Count; $i++) {
            $Element = $Elements[$i]
            if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            $Argument = $Element.Argument
            if ($null -eq $Argument -and ($i + 1) -lt $Elements.Count) {
                $Next = $Elements[$i + 1]
                if ($Next -isnot [System.Management.Automation.Language.CommandParameterAst]) { $Argument = $Next }
            }
            if ($null -eq $Argument) { continue }

            $Access = Resolve-AccessPath -Node (Get-PipelineSourceAst -Ast $Argument) -Aliases $Aliases
            if ($null -eq $Access) { continue }

            $Helper = Get-HelperDefinition -Name $CommandName -Index $Index
            if ($null -eq $Helper) { continue }

            $ParameterName = Get-BoundParameterName -Written $Element.ParameterName -CalleeAst $Helper.Definition
            if (-not $ParameterName) { continue }

            # Nearly every endpoint hands a request value to Write-LogMessage and the
            # Graph helpers, and none of them read fields off it. Whether a helper reads
            # anything off a given parameter does not depend on the caller, so it is
            # answered once and reused instead of re-walking those ASTs 640 times.
            if (-not (Test-HelperReadsParameter -Helper $Helper -ParameterName $ParameterName -Name $CommandName)) { continue }

            $VisitKey = "$CommandName|$ParameterName|$($Access.Section)|$($Access.Segments -join '.')"
            if ($Visited.ContainsKey($VisitKey)) { continue }
            $Visited[$VisitKey] = $true

            # inside the callee the parameter stands in for the request path it was
            # given, so the ordinary extraction runs against it unchanged
            $Seed = @{
                $ParameterName = [pscustomobject]@{
                    Section   = $Access.Section
                    Segments  = $Access.Segments
                    ArrayAt   = $Access.ArrayAt
                    IsElement = $false
                }
            }
            $CalleeAliases = Get-RequestAliasMap -FunctionAst $Helper.Definition -Seed $Seed

            # every endpoint hands request values to Write-LogMessage and the Graph
            # helpers; only the calls that actually taught us a field are worth naming
            $Before = $Script:DiscoveredFieldCount
            Add-MemberAccess -FunctionAst $Helper.Definition -Aliases $CalleeAliases -Trees $Trees `
                -Comments $Helper.Comments -Touched $null
            Add-DownstreamAccess -FunctionAst $Helper.Definition -Aliases $CalleeAliases -Trees $Trees `
                -Index $Index -Depth ($Depth - 1) -Visited $Visited -Followed $Followed
            $After = $Script:DiscoveredFieldCount

            if ($After -gt $Before -and -not $Followed.Contains($CommandName)) { $Followed.Add($CommandName) }
        }
    }
}

function Add-MemberAccess {
    # Walks every property access in a function and records the request fields it
    # reads. Shared by the entrypoint pass and the downstream-helper pass.
    param($FunctionAst, [hashtable]$Aliases, $Trees, $Comments, $Touched)

    foreach ($Member in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst]
            }, $true)) {

        $Access = Resolve-AccessPath -Node $Member -Aliases $Aliases
        if ($null -eq $Access) { continue }

        # A bare `$Request.Body` is only a passthrough when the payload is handed on
        # whole. Binding it to a local, enumerating it, or reading a member off it are
        # all ordinary field access and must not mark the schema open-ended.
        if ($Access.Segments.Count -eq 0 -and $Access.ArrayAt -notcontains -1) {
            $Parent = $Member.Parent
            $Piped = $false
            while ($Parent -is [System.Management.Automation.Language.CommandExpressionAst] -or
                $Parent -is [System.Management.Automation.Language.PipelineAst]) {
                if ($Parent -is [System.Management.Automation.Language.PipelineAst] -and
                    $Parent.PipelineElements.Count -gt 1) { $Piped = $true }
                $Parent = $Parent.Parent
            }
            $IsBinding = $Piped -or
                $Parent -is [System.Management.Automation.Language.AssignmentStatementAst] -or
                $Parent -is [System.Management.Automation.Language.ForEachStatementAst] -or
                $Parent -is [System.Management.Automation.Language.MemberExpressionAst]
            if ($IsBinding) { continue }
        }

        if ($null -ne $Touched) { $Touched[$Access.Section] = $true }
        $Hint = Get-UsageSchemaHint -Node $Member
        $StatementLine = Get-EnclosingStatementLine -Node $Member
        $Description = Get-SourceComment -Node $Member -CommentsByEndLine $Comments.ByEndLine `
            -CommentsByStartLine $Comments.ByStartLine -StatementStartLine $StatementLine

        Add-AccessToTree -Root $Trees[$Access.Section] -Access $Access -Hint $Hint -Description $Description
    }
}

function Get-EndpointContract {
    param([string]$Path, [string]$RootPath, [hashtable]$HelperIndex, [hashtable]$ColumnMap, [int]$FollowDepth = 2)

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count -gt 0) {
        return [pscustomobject]@{ ParseError = "$($Errors[0].Message) (line $($Errors[0].Extent.StartLineNumber))"; Path = $Path }
    }

    $Definition = $Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -like 'Invoke-*'
        }, $false) | Select-Object -First 1
    if (-not $Definition) { return $null }

    $Help = $Definition.GetHelpContent()
    $Functionality = (($Help.Functionality ?? '') + '').Trim()
    # the marker is what separates an HTTP endpoint from a helper that happens to
    # live in the tree; ",AnyTenant" additionally means it runs without a tenant
    if ($Functionality -notmatch '(?i)\bEntrypoint\b') { return $null }

    $Name = $Definition.Name -replace '^Invoke-', ''
    $AnyTenant = $Functionality -match '(?i)AnyTenant'

    $Comments = Get-CommentMap -Path $Path -Tokens $Tokens

    $Aliases = Get-RequestAliasMap -FunctionAst $Definition
    $Trees = @{ Body = Initialize-SchemaNode; Query = Initialize-SchemaNode }
    $Touched = @{ Body = $false; Query = $false }

    Add-MemberAccess -FunctionAst $Definition -Aliases $Aliases -Trees $Trees -Comments $Comments -Touched $Touched

    # most of the contract for the busiest endpoints lives in the helper the body is
    # handed to, not in the entrypoint
    $Followed = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $HelperIndex -and $FollowDepth -gt 0) {
        Add-DownstreamAccess -FunctionAst $Definition -Aliases $Aliases -Trees $Trees `
            -Index $HelperIndex -Depth $FollowDepth -Visited @{} -Followed $Followed
    }

    # switch ($Request.Body.type) { 'a' {} 'b' {} } enumerates the accepted values
    # exactly; -Regex/-Wildcard switches match patterns, so they are not enums
    $Switches = $Definition.FindAll({
            param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst]
        }, $true)
    foreach ($Switch in $Switches) {
        if ($Switch.Flags -band [System.Management.Automation.Language.SwitchFlags]::Regex) { continue }
        if ($Switch.Flags -band [System.Management.Automation.Language.SwitchFlags]::Wildcard) { continue }

        $Access = Resolve-AccessPath -Node (Get-UnwrappedAst -Ast $Switch.Condition) -Aliases $Aliases
        if ($null -eq $Access -or $Access.Segments.Count -eq 0) { continue }
        $Node = Resolve-TreeNode -Root $Trees[$Access.Section] -Segments $Access.Segments
        if ($null -eq $Node) { continue }

        $Values = [System.Collections.Generic.List[string]]::new()
        $AllLiteral = $true
        foreach ($Clause in $Switch.Clauses) {
            if ($Clause.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $Values.Add($Clause.Item1.Value)
            } else { $AllLiteral = $false }
        }
        if ($AllLiteral -and $Values.Count -gt 0) { $Node.Enum = @($Values | Sort-Object -CaseSensitive -Unique) }
    }

    # a guard that rejects the request when a field is absent is the only place the
    # source states a field is mandatory, so it is the only honest source for required[]
    foreach ($If in $Definition.FindAll({
                param($n) $n -is [System.Management.Automation.Language.IfStatementAst]
            }, $true)) {
        foreach ($Clause in $If.Clauses) {
            $Body = $Clause.Item2.Extent.Text
            if ($Body -notmatch '(?i)\bthrow\b|BadRequest|Conflict|PreconditionFailed') { continue }

            foreach ($Guarded in Get-GuardedPath -Condition $Clause.Item1 -Aliases $Aliases) {
                $Node = Resolve-TreeNode -Root $Trees[$Guarded.Section] -Segments $Guarded.Segments
                if ($null -ne $Node) { $Node.Required = $true }
            }
        }
    }

    $StatusCodes = [System.Collections.Generic.List[string]]::new()
    foreach ($Match in [regex]::Matches($Definition.Extent.Text, '\[HttpStatusCode\]::(\w+)')) {
        $Code = $Match.Groups[1].Value
        if (-not $StatusCodes.Contains($Code)) { $StatusCodes.Add($Code) }
    }
    if ($Definition.Extent.Text -match '\bGet-CippBulkStatusCode\b') {
        foreach ($Code in 'OK', 'MultiStatus', 'InternalServerError') {
            if (-not $StatusCodes.Contains($Code)) { $StatusCodes.Add($Code) }
        }
    }

    $Relative = [IO.Path]::GetRelativePath($RootPath, (Split-Path -Parent $Path))
    $Tag = if ($Relative -eq '.') { 'General' } else { ($Relative -split '[\\/]' -join ' > ') }

    return [pscustomobject]@{
        Name         = $Name
        Role         = (($Help.Role ?? '') + '').Trim()
        Synopsis     = (($Help.Synopsis ?? '') + '').Trim()
        Description  = (($Help.Description ?? '') + '').Trim()
        AnyTenant    = $AnyTenant
        Tag          = $Tag
        BodyTree     = $Trees.Body
        QueryTree    = $Trees.Query
        UsesBody     = $Touched.Body
        UsesQuery    = $Touched.Query
        StatusCodes  = @($StatusCodes)
        Downstream   = @($Followed)
        Columns      = @(if ($ColumnMap -and $ColumnMap.ContainsKey($Name)) { $ColumnMap[$Name] } else { @() })
        ReturnsArray  = (Test-ArrayResponse -FunctionAst $Definition)
        HasResults    = (Test-ResultsEnvelope -FunctionAst $Definition)
        BackendFields = @(Get-BackendRecordField -FunctionAst $Definition -BodyVariable (Get-ResponseBodyVariable -FunctionAst $Definition))
        TableNames    = @(Get-TableReadName -FunctionAst $Definition)
        GraphRefs     = @(Get-GraphEntityReference -FunctionAst $Definition)
        GraphSelect   = @(Get-GraphSelectField -FunctionAst $Definition)
        OutputNames   = @(Get-OutputMemberName -FunctionAst $Definition)
        Path         = $Path
    }
}

function Get-GuardedPath {
    # Recognises the "reject when missing" shapes CIPP uses, and yields the request
    # paths they protect. Only these forms count; a general truthiness test on a
    # local would produce false positives.
    param($Condition, [hashtable]$Aliases)

    $Results = [System.Collections.Generic.List[object]]::new()
    $Expression = Get-UnwrappedAst -Ast $Condition

    $Candidates = [System.Collections.Generic.List[object]]::new()

    if ($Expression -is [System.Management.Automation.Language.UnaryExpressionAst] -and
        $Expression.TokenKind -eq [System.Management.Automation.Language.TokenKind]::Not) {
        $Candidates.Add((Get-UnwrappedAst -Ast $Expression.Child))
    } elseif ($Expression -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $Op = $Expression.Operator.ToString()
        if ($Op -match '^(I|C)?eq$') {
            $Left = Get-UnwrappedAst -Ast $Expression.Left
            $Right = Get-UnwrappedAst -Ast $Expression.Right
            foreach ($Pair in @(@($Left, $Right), @($Right, $Left))) {
                $Other = $Pair[1]
                $IsNullLiteral = ($Other -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Other.VariablePath.UserPath -eq 'null')
                $IsEmptyString = ($Other -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    [string]::IsNullOrEmpty($Other.Value))
                if ($IsNullLiteral -or $IsEmptyString) { $Candidates.Add($Pair[0]) }
            }
        }
    } elseif ($Expression -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        # [string]::IsNullOrEmpty($Request.Body.X) / IsNullOrWhiteSpace
        if ($Expression.Member.Value -match '^IsNullOr') {
            foreach ($Argument in @($Expression.Arguments)) {
                $Candidates.Add((Get-UnwrappedAst -Ast $Argument))
            }
        }
    }

    foreach ($Candidate in $Candidates) {
        $Access = Resolve-AccessPath -Node $Candidate -Aliases $Aliases
        if ($null -ne $Access -and $Access.Segments.Count -gt 0) { $Results.Add($Access) }
    }

    return $Results
}

function Test-ResultsEnvelope {
    # Action endpoints answer with Body = @{ Results = ... }; CippApiResults on the
    # frontend renders exactly that shape, so detecting it is what distinguishes a
    # StandardResults response from a raw list.
    #
    # Only the success path counts. A list endpoint that rejects a bad argument with
    # Body = @{ Results = 'x is required' } is still a list endpoint, and treating that
    # error branch as the contract documents the whole endpoint as an action - which is
    # exactly what happened to ListGroups when a validation guard was added to it.
    param($FunctionAst)

    foreach ($Hashtable in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.HashtableAst]
            }, $true)) {

        # a literal non-2xx StatusCode alongside the Body marks this as an error response
        $IsErrorResponse = $false
        foreach ($Pair in $Hashtable.KeyValuePairs) {
            if ($Pair.Item1.Extent.Text -notmatch "^'?`"?StatusCode`"?'?$") { continue }
            $Status = $Pair.Item2.Extent.Text
            if ($Status -match '\[HttpStatusCode\]::(\w+)') {
                $Numeric = $null
                try { $Numeric = [int][System.Net.HttpStatusCode]::($Matches[1]) } catch { $Numeric = $null }
                if ($null -ne $Numeric -and $Numeric -ge 400) { $IsErrorResponse = $true }
            }
        }
        if ($IsErrorResponse) { continue }

        foreach ($Pair in $Hashtable.KeyValuePairs) {
            if ($Pair.Item1.Extent.Text -notmatch "^'?`"?Body`"?'?$") { continue }
            $Value = Get-UnwrappedAst -Ast $Pair.Item2
            if ($Value -is [System.Management.Automation.Language.HashtableAst]) {
                foreach ($Inner in $Value.KeyValuePairs) {
                    if ($Inner.Item1.Extent.Text -match "^'?`"?Results?`"?'?$") { return $true }
                }
            }
        }
    }
    return $false
}

function Test-ArrayResponse {
    param($FunctionAst)

    foreach ($Hashtable in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.HashtableAst]
            }, $true)) {
        foreach ($Pair in $Hashtable.KeyValuePairs) {
            if ($Pair.Item1.Extent.Text -notmatch "^'?`"?Body`"?'?$") { continue }
            $Value = Get-UnwrappedAst -Ast $Pair.Item2
            if ($Value -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $Value -is [System.Management.Automation.Language.ArrayLiteralAst]) { return $true }
        }
    }
    return $false
}

# -- OAS emission --------------------------------------------------------------

$StatusDescriptions = @{
    'OK'                  = 'Success'
    'MultiStatus'         = 'Partial success - some items failed; per-item results are in the body'
    'Accepted'            = 'Accepted - work was queued and runs asynchronously'
    'BadRequest'          = 'Bad request - missing required field or invalid input'
    'Unauthorized'        = 'Unauthorized - invalid or missing bearer token'
    'Forbidden'           = 'Forbidden - caller lacks the required RBAC role'
    'NotFound'            = 'Not found'
    'Conflict'            = 'Conflict - the resource already exists or is in a conflicting state'
    'PreconditionFailed'  = 'Precondition failed'
    'TooManyRequests'     = 'Throttled by the upstream Microsoft API'
    'InternalServerError' = 'Internal server error'
    'ServiceUnavailable'  = 'Endpoint disabled by a feature flag'
}

function Get-FrontendColumnMap {
    # Maps endpoint name -> the fields the CIPP UI renders for it, read from
    # `<CippTablePage apiUrl="/api/ListUsers" simpleColumns={[...]} />`.
    #
    # The PowerShell says nothing about response shape, so without this every list
    # endpoint documents an untyped object. These are display columns, not the full
    # record, which is why the emitted schema keeps additionalProperties open and
    # marks each property's provenance.
    #
    # Deliberately literal-only. A ternary (`simpleColumns={x ? [...] : [...]}`)
    # is skipped rather than guessed at, because a loose pattern picks up the
    # scalar branches of nearby ternaries and invents fields like "yes"/"no".
    param([string]$SrcDir)

    $Map = @{}
    if (-not $SrcDir -or -not (Test-Path $SrcDir)) { return $Map }

    $ColumnBlock = [regex]::new('simpleColumns\s*=\s*\{?\s*\[([^\]]*)\]', 'Singleline')
    $Literal = [regex]::new('["'']([A-Za-z_][\w.]*)["'']')
    $ApiUrl = [regex]::new('apiUrl\s*[=:]\s*\{?\s*[""''`]/api/([A-Za-z0-9_]+)')

    foreach ($File in Get-ChildItem -Path $SrcDir -Include '*.js', '*.jsx' -Recurse -File) {
        $Text = [IO.File]::ReadAllText($File.FullName)
        if ($Text -notmatch 'simpleColumns') { continue }

        # a file serving two endpoints cannot have its columns attributed to either
        $Endpoints = @($ApiUrl.Matches($Text) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        if ($Endpoints.Count -ne 1) { continue }

        $Columns = [System.Collections.Generic.List[string]]::new()
        foreach ($Block in $ColumnBlock.Matches($Text)) {
            foreach ($Value in $Literal.Matches($Block.Groups[1].Value)) {
                $Name = $Value.Groups[1].Value
                if (-not $Columns.Contains($Name)) { $Columns.Add($Name) }
            }
        }
        if ($Columns.Count -eq 0) { continue }

        $Endpoint = $Endpoints[0]
        if (-not $Map.ContainsKey($Endpoint)) { $Map[$Endpoint] = [System.Collections.Generic.List[object]]::new() }
        $Map[$Endpoint].Add(@($Columns | Sort-Object -CaseSensitive))
    }

    # Generic endpoints (ListGraphRequest above all) back a dozen unrelated pages, each
    # rendering a different record. Unioning those columns would describe a response no
    # single call ever returns, so a conflict drops the endpoint rather than guessing.
    $Resolved = @{}
    foreach ($Entry in $Map.GetEnumerator()) {
        $Distinct = @($Entry.Value | ForEach-Object { $_ -join "`u{1}" } | Select-Object -Unique)
        if ($Distinct.Count -ne 1) { continue }
        $Resolved[$Entry.Key] = @($Entry.Value[0])
    }
    return $Resolved
}

function Get-GraphMetadataIndex {
    # Parses the vendored Graph CSDL into entity set -> type and type -> properties.
    #
    # Deliberately a second implementation of what Get-CippGraphSchema does at runtime:
    # this script is standalone by design - it parses sources rather than importing the
    # modules - so reaching into CIPPCore here would couple the build to the thing it is
    # describing. The parsing rules are the load-bearing part and both are tested.
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) { return $null }

    $EdmToJson = @{
        'Edm.String' = 'string'; 'Edm.Boolean' = 'boolean'; 'Edm.Int16' = 'integer'
        'Edm.Int32' = 'integer'; 'Edm.Int64' = 'integer'; 'Edm.Double' = 'number'
        'Edm.Single' = 'number'; 'Edm.Decimal' = 'number'; 'Edm.Guid' = 'string'
        'Edm.DateTimeOffset' = 'string'; 'Edm.Date' = 'string'; 'Edm.TimeOfDay' = 'string'
        'Edm.Duration' = 'string'; 'Edm.Binary' = 'string'; 'Edm.Stream' = 'string'
    }

    $Index = @{}
    foreach ($Version in @('v1.0', 'beta')) {
        $File = Join-Path $Path "$Version.xml"
        if (-not (Test-Path $File)) { continue }

        $Xml = [System.Xml.XmlDocument]::new()
        $Xml.Load($File)
        $Ns = [System.Xml.XmlNamespaceManager]::new($Xml.NameTable)
        $Ns.AddNamespace('edm', 'http://docs.oasis-open.org/odata/ns/edm')

        # References use a schema's Namespace and its Alias interchangeably
        # ('microsoft.graph.user' and 'graph.user' are the same type).
        $AliasOf = @{}
        foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Ns)) {
            if ($Schema.Alias) { $AliasOf[$Schema.Alias] = $Schema.Namespace }
        }
        $Expand = {
            param([string]$Type)
            if (-not $Type) { return $null }
            $Bare = $Type -replace '^Collection\(', '' -replace '\)$', ''
            $Prefix = $Bare -replace '\.[^.]+$', ''
            $Leaf = ($Bare -split '\.')[-1]
            if ($AliasOf.ContainsKey($Prefix)) { return '{0}.{1}' -f $AliasOf[$Prefix], $Leaf }
            return $Bare
        }

        # Keyed by fully qualified name: several namespaces declare a type called 'user',
        # and a short-name key lets a usage-report type overwrite microsoft.graph.user.
        $Raw = @{}
        foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Ns)) {
            foreach ($Node in $Schema.SelectNodes('edm:EntityType | edm:ComplexType', $Ns)) {
                $Properties = [ordered]@{}
                foreach ($Property in $Node.SelectNodes('edm:Property', $Ns)) {
                    $Type = $Property.Type
                    $Collection = $Type -match '^Collection\('
                    $Inner = $Type -replace '^Collection\(', '' -replace '\)$', ''
                    $Json = if ($Collection) { 'array' } elseif ($EdmToJson.ContainsKey($Inner)) { $EdmToJson[$Inner] } else { 'object' }
                    $Properties[$Property.Name] = $Json
                }
                $Navigation = [ordered]@{}
                foreach ($Property in $Node.SelectNodes('edm:NavigationProperty', $Ns)) {
                    $Navigation[$Property.Name] = & $Expand $Property.Type
                }
                $Raw['{0}.{1}' -f $Schema.Namespace, $Node.Name] = @{
                    Properties = $Properties
                    Navigation = $Navigation
                    Base       = & $Expand $Node.BaseType
                }
            }
        }

        $Types = @{}
        function Resolve-GraphType {
            param([string]$Name, $Raw, $Types, [System.Collections.Generic.HashSet[string]]$Seen)
            if ($Types.ContainsKey($Name)) { return $Types[$Name] }
            if (-not $Raw.ContainsKey($Name) -or $Seen.Contains($Name)) { return $null }
            $null = $Seen.Add($Name)
            $Merged = @{ Properties = [ordered]@{}; Navigation = [ordered]@{} }
            if ($Raw[$Name].Base) {
                $Parent = Resolve-GraphType -Name $Raw[$Name].Base -Raw $Raw -Types $Types -Seen $Seen
                if ($Parent) {
                    foreach ($Key in $Parent.Properties.Keys) { $Merged.Properties[$Key] = $Parent.Properties[$Key] }
                    foreach ($Key in $Parent.Navigation.Keys) { $Merged.Navigation[$Key] = $Parent.Navigation[$Key] }
                }
            }
            foreach ($Key in $Raw[$Name].Properties.Keys) { $Merged.Properties[$Key] = $Raw[$Name].Properties[$Key] }
            foreach ($Key in $Raw[$Name].Navigation.Keys) { $Merged.Navigation[$Key] = $Raw[$Name].Navigation[$Key] }
            $Types[$Name] = $Merged
            return $Merged
        }
        foreach ($Name in @($Raw.Keys)) {
            $null = Resolve-GraphType -Name $Name -Raw $Raw -Types $Types -Seen ([System.Collections.Generic.HashSet[string]]::new())
        }

        $Sets = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Node in $Xml.SelectNodes('//edm:EntityContainer/edm:EntitySet | //edm:EntityContainer/edm:Singleton', $Ns)) {
            $Type = if ($Node.EntityType) { $Node.EntityType } else { $Node.Type }
            $Sets[$Node.Name] = & $Expand $Type
        }

        $Index[$Version] = @{ Sets = $Sets; Types = $Types }
    }

    return $Index
}

function Get-GraphEntityReference {
    # The Graph paths an entrypoint reads, as @{ Version; Segments }. The WHOLE path is
    # kept, not just its first segment: deviceManagement/windowsAutopilotDeviceIdentities
    # is a collection of autopilot devices, and stopping at 'deviceManagement' resolves it
    # to the tenant-level device management singleton instead - a plausible-looking record
    # made of entirely the wrong fields.
    param($FunctionAst)

    $References = [System.Collections.Generic.List[object]]::new()
    foreach ($Match in [regex]::Matches($FunctionAst.Extent.Text, 'graph\.microsoft\.com/(v1\.0|beta)/([A-Za-z0-9_/]+)')) {
        $Segments = @($Match.Groups[2].Value -split '/' | Where-Object { $_ })
        if ($Segments.Count -eq 0) { continue }
        $Key = '{0}:{1}' -f $Match.Groups[1].Value, ($Segments -join '/')
        if (-not ($References | Where-Object { $_.Key -eq $Key })) {
            $References.Add(@{ Version = $Match.Groups[1].Value; Segments = $Segments; Key = $Key })
        }
    }
    return @($References)
}

function Get-GraphSelectField {
    # Field names from a Graph $select list. CIPP builds these as one long literal
    # ('id,displayName,mail,...') and interpolates it into the URI, so when one is present
    # it says exactly which of an entity's properties actually come back - Graph's user has
    # 89 and a given endpoint may ask for 19.
    param($FunctionAst)

    $Fields = [System.Collections.Generic.List[string]]::new()
    foreach ($String in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)) {
        $Value = $String.Value
        # a select list is a comma-separated run of bare identifiers, nothing else
        if ($Value -notmatch '^[A-Za-z_][\w]*(,[A-Za-z_][\w]*){2,}$') { continue }
        foreach ($Field in ($Value -split ',')) {
            if ($Field -and -not $Fields.Contains($Field)) { $Fields.Add($Field) }
        }
    }
    return @($Fields)
}

function Get-OutputMemberName {
    # Literal -NotePropertyName values from Add-Member. When an endpoint reshapes a record
    # it names the output property outright, and that spelling is what reaches the wire -
    # so it settles casing disputes that the other sources get wrong. listStandardTemplates
    # reads a table whose writer stores 'Source' but emits it as 'source', and JSON is
    # case-sensitive, so documenting the writer's spelling sends callers looking for a key
    # that is not there.
    #
    # Used ONLY to correct the case of a field another source already found, never to add
    # one: Add-Member is also used on intermediate objects that never reach the response,
    # and this way such a name can never invent a field.
    param($FunctionAst)

    $Names = [System.Collections.Generic.List[string]]::new()
    foreach ($Command in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {
        # Add-Member names the property outright. Sort-Object/Where-Object -Property name a
        # property of the object being emitted, so they are equally good evidence of the
        # spelling that reaches the wire - listStandardTemplates never writes 'templateName'
        # except in a Sort-Object, and that is the casing the response carries.
        $CommandName = $Command.GetCommandName()
        if ($CommandName -notin @('Add-Member', 'Sort-Object', 'Where-Object')) { continue }
        $Elements = @($Command.CommandElements)
        for ($i = 0; $i -lt $Elements.Count; $i++) {
            $Element = $Elements[$i]
            if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            if ($Element.ParameterName -notmatch '^(NotePropertyName|Property)$') { continue }
            $Value = if ($Element.Argument) { $Element.Argument } elseif (($i + 1) -lt $Elements.Count) { $Elements[$i + 1] } else { $null }
            $Value = Get-UnwrappedAst -Ast $Value
            if ($Value -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $Value.Value) {
                if (-not $Names.Contains($Value.Value)) { $Names.Add($Value.Value) }
            }
        }
    }
    return @($Names)
}

function Get-TableEntityCastType {
    # The JSON type implied by an explicit cast on a table entity's value. Storage writers
    # cast almost everything ([string]$Repo.name, [bool]$Repo.permissions.push) because
    # Azure Table columns are typed, which makes these the one place in CIPP where a
    # response field's type is stated outright rather than guessed.
    param($Ast)

    $Node = Get-UnwrappedAst -Ast $Ast
    if ($Node -isnot [System.Management.Automation.Language.ConvertExpressionAst]) { return $null }

    switch -Regex ($Node.Type.TypeName.Name) {
        '^(string|guid)$' { return 'string' }
        '^bool(ean)?$' { return 'boolean' }
        '^(int|int32|int64|long)$' { return 'integer' }
        '^(double|decimal|single|float)$' { return 'number' }
        '^datetime(offset)?$' { return 'string' }
        default { return $null }
    }
}

function Get-TableWriterIndex {
    # Maps each Azure Table to the fields the code WRITES into it.
    #
    # A third of the endpoints with no describable response read a storage table and hand
    # the rows straight back, so nothing at the read site names a field. The write site
    # does: an entity is built as a hashtable literal with fixed keys, and Azure Table
    # rows are homogeneous by construction, so the writer is an accurate description of
    # what the reader returns. This is the same trick as following a helper for request
    # fields, pointed at the other end of the pipe.
    param([string[]]$SearchPath)

    $Index = @{}

    # Sorted on a separator-normalized path: the type merge below is order-dependent
    # (the first writer that states a type wins), and NTFS enumerates sorted while
    # ext4 does not, so an unsorted scan types fields differently on the ubuntu
    # runner than on a local Windows build and -Check reports a stale spec.
    foreach ($File in Get-ChildItem -Path $SearchPath -Recurse -Filter '*.ps1' -File | Sort-Object { $_.FullName.Replace('\', '/') }) {
        $Tokens = $null; $Errs = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$Errs)
        if ($Errs.Count -gt 0) { continue }

        # $X = Get-CIPPTable -TableName 'Y'  ->  which variable names which table
        $TableOf = @{}
        $Assignments = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
        foreach ($Assign in $Assignments) {
            if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            if ($Assign.Right.Extent.Text -match "(?i)Get-CIPPTable\s+-Table(?:Name)?\s+'?([\w\-]+)'?") {
                $TableOf[$Assign.Left.VariablePath.UserPath] = $Matches[1]
            }
        }
        if ($TableOf.Count -eq 0) { continue }

        foreach ($Command in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            if ($Command.GetCommandName() -notin @('Add-CIPPAzDataTableEntity', 'Update-AzDataTableEntity')) { continue }

            $Elements = @($Command.CommandElements)
            $Table = $null
            $EntityVar = $null
            for ($i = 0; $i -lt $Elements.Count; $i++) {
                $El = $Elements[$i]
                # the splatted table: @Table
                if ($El.Extent.Text -match '^@(\w+)$' -and $TableOf.ContainsKey($Matches[1])) { $Table = $TableOf[$Matches[1]] }
                if ($El -is [System.Management.Automation.Language.CommandParameterAst] -and $El.ParameterName -match '^Entity$') {
                    $Next = if (($i + 1) -lt $Elements.Count) { $Elements[$i + 1] } else { $null }
                    if ($Next -is [System.Management.Automation.Language.VariableExpressionAst]) { $EntityVar = $Next.VariablePath.UserPath }
                }
            }
            if (-not $Table -or -not $EntityVar) { continue }
            if (-not $Index.ContainsKey($Table)) { $Index[$Table] = [ordered]@{} }

            foreach ($Assign in $Assignments) {
                # the entity built as a literal
                if ($Assign.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Assign.Left.VariablePath.UserPath -eq $EntityVar) {
                    $Hash = $Assign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) | Select-Object -First 1
                    if (-not $Hash) { continue }
                    foreach ($Pair in $Hash.KeyValuePairs) {
                        $Key = $Pair.Item1.Extent.Text.Trim("'", '"', ' ')
                        if ($Key -notmatch '^[A-Za-z_][\w.-]*$') { continue }
                        $Type = Get-TableEntityCastType -Ast $Pair.Item2
                        # a later writer that states a type wins over one that does not
                        if (-not $Index[$Table].Contains($Key) -or ($Type -and -not $Index[$Table][$Key])) {
                            $Index[$Table][$Key] = $Type
                        }
                    }
                }

                # fields added conditionally: $Entity.Foo = ...
                if ($Assign.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                    $Assign.Left.Expression.Extent.Text -eq ('$' + $EntityVar)) {
                    $Key = $Assign.Left.Member.Extent.Text.Trim("'", '"')
                    if ($Key -match '^[A-Za-z_][\w.-]*$' -and -not $Index[$Table].Contains($Key)) {
                        $Index[$Table][$Key] = Get-TableEntityCastType -Ast $Assign.Right
                    }
                }
            }
        }
    }

    return $Index
}

function Get-TableReadName {
    # Tables this entrypoint reads rows from. Only a read that is actually returned counts,
    # but entrypoints routinely touch a config table as well as their data table, so the
    # caller requires a single unambiguous table before using its shape.
    param($FunctionAst)

    $Names = [System.Collections.Generic.List[string]]::new()
    $Text = $FunctionAst.Extent.Text
    if ($Text -notmatch 'Get-CIPPAzDataTableEntity') { return @() }

    foreach ($Match in [regex]::Matches($Text, "(?i)Get-CIPPTable\s+-Table(?:Name)?\s+'?([\w\-]+)'?")) {
        $Name = $Match.Groups[1].Value
        if (-not $Names.Contains($Name)) { $Names.Add($Name) }
    }
    return @($Names)
}

function Get-ResponseBodyVariable {
    # The variable handed to Body = ... in the returned HttpResponseContext. Knowing which
    # variable becomes the response is what makes the field extraction below safe: an
    # entrypoint may shape half a dozen intermediate values with Select-Object, and only
    # the one that is actually returned describes the record.
    param($FunctionAst)

    # An endpoint often has several return paths - a cached branch, an AllTenants branch,
    # a placeholder while an orchestrator runs - and any of them can be the one that
    # carries the records, so every Body variable is collected rather than just the first.
    $Variables = [System.Collections.Generic.List[string]]::new()

    foreach ($Hashtable in $FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.HashtableAst]
            }, $true)) {
        foreach ($Pair in $Hashtable.KeyValuePairs) {
            if ($Pair.Item1.Extent.Text -notmatch "^'?`"?Body`"?'?$") { continue }
            $Value = Get-UnwrappedAst -Ast $Pair.Item2
            # Body = $GraphRequest, Body = @($GraphRequest), Body = @{ Results = $x }
            $Var = $Value.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst]
                }, $true) | Select-Object -First 1
            if ($Var -and -not $Variables.Contains($Var.VariablePath.UserPath)) {
                $Variables.Add($Var.VariablePath.UserPath)
            }
        }
    }
    return @($Variables)
}

function Get-SelectObjectField {
    # Property names from one Select-Object call: bare names, and the Name/Label of a
    # calculated property. Returns $null when the call cannot be read statically, which
    # is the signal to give up rather than describe the record wrongly.
    param($CommandAst)

    $Fields = [System.Collections.Generic.List[string]]::new()
    $Open = $false
    $Elements = @($CommandAst.CommandElements)

    for ($i = 1; $i -lt $Elements.Count; $i++) {
        $Element = $Elements[$i]

        if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
            $ParameterName = $Element.ParameterName
            # -ExpandProperty replaces the record with the contents of one property, so
            # nothing collected here would describe the result.
            if ($ParameterName -match '^(Expand|ExpandProperty)$') { return $null }
            if ($ParameterName -match '^(Property|Prop)$') { continue }  # its argument is the list
            # every other switch/parameter (First, Last, Unique, Skip, ExcludeProperty...)
            # takes no property names; skip its argument too when it has one
            if (-not $Element.Argument -and ($i + 1) -lt $Elements.Count -and
                $Elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { $i++ }
            continue
        }

        foreach ($Item in @(if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $Element.Elements } else { $Element })) {
            $Item = Get-UnwrappedAst -Ast $Item

            if ($Item -is [System.Management.Automation.Language.HashtableAst]) {
                foreach ($Pair in $Item.KeyValuePairs) {
                    if ($Pair.Item1.Extent.Text -notmatch "^'?`"?(Name|N|Label|L)`"?'?$") { continue }
                    $Value = Get-UnwrappedAst -Ast $Pair.Item2
                    if ($Value -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $Value.Value) {
                        $Fields.Add($Value.Value)
                    }
                }
                continue
            }

            if ($Item -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $Name = $Item.Value
                # 'Select-Object *' keeps everything, so the record stays open
                if ($Name -match '\*') { $Open = $true; continue }
                if ($Name) { $Fields.Add($Name) }
            }
        }
    }

    return [pscustomobject]@{ Fields = @($Fields); Open = $Open }
}

function Get-BackendRecordField {
    # Field names the endpoint demonstrably puts on each record. CIPP shapes nearly every
    # list response with Select-Object - a literal property list plus calculated
    # properties (@{ Name = 'primDomain'; Expression = {...} }) - so those names are a
    # far better description of the payload than the UI's chosen columns, which only say
    # what one page happens to render.
    param($FunctionAst, [string[]]$BodyVariable)

    $Fields = [System.Collections.Generic.List[string]]::new()
    $Seed = @($BodyVariable | Where-Object { $_ })
    if ($Seed.Count -eq 0) { return @() }

    $Assignments = @($FunctionAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true) | Where-Object {
            $_.Left -is [System.Management.Automation.Language.VariableExpressionAst]
        })

    # The record is not always built into the returned variable directly: an endpoint may
    # alias it ($response = $GraphRequest) or wrap it (Body = @{ Results = $Rows }). Follow
    # both, breadth-first, but only two hops - chasing further starts describing
    # intermediate values that never reach the caller.
    $Targets = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $Seed) { if (-not $Targets.Contains($Name)) { $Targets.Add($Name) } }

    $Frontier = @($Seed)
    for ($Hop = 0; $Hop -lt 2 -and $Frontier.Count -gt 0; $Hop++) {
        $Next = [System.Collections.Generic.List[string]]::new()
        foreach ($Assignment in $Assignments) {
            if ($Assignment.Left.VariablePath.UserPath -notin $Frontier) { continue }
            $Right = Get-UnwrappedAst -Ast $Assignment.Right

            # a bare alias: $response = $GraphRequest
            if ($Right -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $Next.Add($Right.VariablePath.UserPath)
                continue
            }

            # an envelope: $Body = @{ Results = $Rows }
            if ($Right -isnot [System.Management.Automation.Language.HashtableAst]) { continue }
            foreach ($Pair in $Right.KeyValuePairs) {
                if ($Pair.Item1.Extent.Text -notmatch "^'?`"?Results?`"?'?$") { continue }
                $Inner = (Get-UnwrappedAst -Ast $Pair.Item2).FindAll({
                        param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst]
                    }, $true) | Select-Object -First 1
                if ($Inner) { $Next.Add($Inner.VariablePath.UserPath) }
            }
        }
        $Frontier = @($Next | Where-Object { $_ -and -not $Targets.Contains($_) } | Select-Object -Unique)
        foreach ($Name in $Frontier) { $Targets.Add($Name) }
    }

    foreach ($Assignment in $Assignments) {
        if ($Assignment.Left.VariablePath.UserPath -notin $Targets) { continue }

        # Select-Object property lists and calculated properties.
        foreach ($Command in $Assignment.Right.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.CommandAst]
                }, $true)) {
            $Name = $Command.GetCommandName()
            if ($Name -notin @('Select-Object', 'select')) { continue }
            $Result = Get-SelectObjectField -CommandAst $Command
            if ($null -eq $Result) { continue }
            foreach ($Field in $Result.Fields) { if (-not $Fields.Contains($Field)) { $Fields.Add($Field) } }
        }

        # An explicitly constructed record: [PSCustomObject]@{ ... }. Only the cast form
        # counts - a bare @{ } assigned to the body is usually the response envelope, not
        # a record, and its keys would describe the wrapper instead of the payload.
        foreach ($Cast in $Assignment.Right.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.ConvertExpressionAst]
                }, $true)) {
            $TypeName = $Cast.Type.TypeName.Name
            if ($TypeName -notmatch '^(PSCustomObject|PSObject)$') { continue }
            $Hashtable = Get-UnwrappedAst -Ast $Cast.Child
            if ($Hashtable -isnot [System.Management.Automation.Language.HashtableAst]) { continue }
            foreach ($Pair in $Hashtable.KeyValuePairs) {
                $Key = $Pair.Item1.Extent.Text.Trim("'", '"', ' ')
                if ($Key -and $Key -notmatch '[^\w.-]' -and -not $Fields.Contains($Key)) { $Fields.Add($Key) }
            }
        }
    }

    return @($Fields)
}

function ConvertTo-RecordSchema {
    # The record shape for a list response. Two independent sources: what the endpoint
    # selects onto each record, and what the UI declares it renders. They are recorded
    # separately in x-cipp-field-source so a surprising field can be traced back.
    param([string[]]$Columns, [string[]]$BackendFields, $StorageFields, $GraphFields, [switch]$GraphProven, [string[]]$OutputNames)

    $Properties = [ordered]@{}
    $Backend = @($BackendFields | Where-Object { $_ })
    $Frontend = @($Columns | Where-Object { $_ })
    $Storage = if ($StorageFields) { [ordered]@{} } else { [ordered]@{} }
    if ($StorageFields) {
        foreach ($Key in $StorageFields.Keys) { $Storage[$Key] = $StorageFields[$Key] }
        # Azure Table stamps these on every row and Get-CIPPAzDataTableEntity returns them,
        # so they are present in the response even though no CIPP code writes them.
        # Confirmed against live responses from ListCustomScripts and ListScheduledItems.
        foreach ($System in @('ETag', 'Timestamp')) {
            if (-not $Storage.Contains($System)) { $Storage[$System] = 'string' }
        }
    }
    $StorageNames = @($Storage.Keys)
    $Graph = if ($GraphFields) { $GraphFields } else { [ordered]@{} }
    $GraphNames = @($Graph.Keys)

    # An explicit Add-Member name is what actually reaches the wire, so where a field was
    # found under a different case it is corrected to that spelling. Only the case changes;
    # a name no other source found is not introduced here.
    $Names = @(@($Backend + $Frontend + $StorageNames + $GraphNames) | Sort-Object -CaseSensitive -Unique)
    if ($OutputNames.Count -gt 0) {
        $Names = @($Names | ForEach-Object {
                $Field = $_
                $Corrected = @($OutputNames | Where-Object { $_ -eq $Field -and $_ -cne $Field }) | Select-Object -First 1
                if ($Corrected) { $Corrected } else { $Field }
            } | Sort-Object -CaseSensitive -Unique)
    }

    foreach ($Name in $Names) {
        $From = [System.Collections.Generic.List[string]]::new()
        if ($GraphNames -contains $Name) { $From.Add($(if ($GraphProven) { 'graph' } else { 'graph-entity' })) }
        if ($StorageNames -contains $Name) { $From.Add('storage') }
        if ($Backend -contains $Name) { $From.Add('backend') }
        if ($Frontend -contains $Name) { $From.Add('frontend') }

        $Property = [ordered]@{}
        # A type only when the source actually states one. Storage writers cast their
        # values because Azure Table columns are typed; a Select-Object property list or a
        # UI column proves only that the field EXISTS, and these records routinely carry
        # numbers, booleans, nested objects and arrays. An omitted type means "any", which
        # is the truth for everything else.
        if ($GraphNames -contains $Name -and $Graph[$Name]) { $Property['type'] = $Graph[$Name] }
        elseif ($StorageNames -contains $Name -and $Storage[$Name]) { $Property['type'] = $Storage[$Name] }
        $Property['x-cipp-field-source'] = ($From -join ',')
        $Properties[$Name] = $Property
    }

    $Sources = [System.Collections.Generic.List[string]]::new()
    if ($Graph.Count -gt 0) { $Sources.Add('the Microsoft Graph entity it queries') }
    if ($Storage.Count -gt 0) { $Sources.Add('the fields written into the storage table it reads') }
    if ($Backend.Count -gt 0) { $Sources.Add('the fields the endpoint selects onto each record') }
    if ($Frontend.Count -gt 0) { $Sources.Add('the columns the CIPP UI renders') }

    # Deliberately hedged in both directions. Storage fields come from the writers, and an
    # endpoint may project only some of them or add computed ones, so this is neither a
    # floor nor a ceiling - it is the best static description available.
    $Description = if ($Graph.Count -gt 0 -and -not $GraphProven) {
        'Derived from {0}. This endpoint returns the Graph response as-is without selecting fields, so these are the properties the entity CAN carry (x-cipp-field-source: graph-entity) rather than a proven projection - Graph returns a default subset unless asked otherwise.' -f ($Sources -join ', and ')
    } elseif ($Graph.Count -gt 0) {
        'Derived from {0}. The fields taken from Graph are the ones this endpoint selects, so they are what the response actually carries.' -f ($Sources -join ', and ')
    } elseif ($Storage.Count -gt 0) {
        'Derived from {0}. Fields taken from the storage writers may be omitted by this endpoint, and the response may carry computed fields not listed here.' -f ($Sources -join ', and ')
    } else {
        'Derived from {0}. The response may carry more; these are the ones known to exist.' -f ($Sources -join ', and ')
    }

    # additionalProperties is deliberately omitted rather than set to $true. The two mean
    # the same thing - JSON Schema permits extra properties by default - but Swagger UI
    # renders an explicit `additionalProperties: true` as a placeholder field called
    # "additionalProp1" in every example, which reads as a real field CIPP returns.
    return [ordered]@{
        type        = 'object'
        description = $Description
        properties  = $Properties
    }
}

function Get-QueryParameterList {
    # Query parameters render the same whether the operation is a GET or a POST that
    # also reads the query string, so both paths go through here.
    param($Contract)

    $Parameters = [System.Collections.Generic.List[object]]::new()
    foreach ($Name in ($Contract.QueryTree.Children.Keys | Sort-Object -CaseSensitive)) {
        $Node = $Contract.QueryTree.Children[$Name]

        # tenantFilter is on nearly every endpoint; reuse the component so its
        # description lives in one place. AnyTenant endpoints run without a tenant,
        # so they get an inline optional copy instead of the required component.
        if ($Name.ToLowerInvariant() -eq 'tenantfilter' -and -not $Contract.AnyTenant) {
            $Parameters.Add([ordered]@{ '$ref' = '#/components/parameters/tenantFilter' })
            continue
        }

        $Parameter = [ordered]@{ name = $Name; 'in' = 'query' }
        if ($Node.Description) { $Parameter['description'] = $Node.Description }
        $Parameter['required'] = [bool]$Node.Required
        $Parameter['schema'] = ConvertTo-JsonSchema -Node $Node
        # the description belongs on the parameter, not duplicated inside its schema
        if ($Parameter['schema'].Contains('description')) { $Parameter['schema'].Remove('description') }
        $Parameters.Add($Parameter)
    }
    return $Parameters
}

function ConvertTo-OasOperation {
    param($Contract, [string]$Method)

    $Operation = [ordered]@{
        summary     = if ($Contract.Synopsis) { $Contract.Synopsis } else { $Contract.Name }
        operationId = $Contract.Name
        tags        = @($Contract.Tag)
    }
    if ($Contract.Description) { $Operation['description'] = $Contract.Description }

    if ($Method -eq 'get') {
        $Parameters = Get-QueryParameterList -Contract $Contract
        if ($Parameters.Count -gt 0) { $Operation['parameters'] = @($Parameters) }
    } else {
        $Properties = [ordered]@{}
        $Required = [System.Collections.Generic.List[string]]::new()
        foreach ($Name in ($Contract.BodyTree.Children.Keys | Sort-Object -CaseSensitive)) {
            $Node = $Contract.BodyTree.Children[$Name]
            $Properties[$Name] = ConvertTo-JsonSchema -Node $Node
            if ($Node.Required -or ($Name.ToLowerInvariant() -eq 'tenantfilter' -and -not $Contract.AnyTenant)) {
                $Required.Add($Name)
            }
        }

        $Schema = [ordered]@{ type = 'object'; properties = $Properties }
        if ($Required.Count -gt 0) { $Schema['required'] = @($Required) }
        if ($Contract.BodyTree.IsDynamic) {
            $Schema['additionalProperties'] = $true
            $Schema['x-cipp-passthrough'] = $true
            $Schema['description'] = 'This endpoint forwards the request body onward rather than reading a fixed set of fields. The properties listed here are the ones it is known to read; others may be accepted.'
        }

        # bulk endpoints POST a JSON array, not an object: the body is enumerated and
        # the fields above describe one element
        if ($Contract.BodyTree.IsArray) {
            $Schema = [ordered]@{
                type        = 'array'
                description = 'The request body is a JSON array. Each element has the shape below.'
                items       = $Schema
            }
        }

        $Operation['requestBody'] = [ordered]@{
            required = ($Required.Count -gt 0 -or $Contract.BodyTree.IsArray)
            content  = [ordered]@{ 'application/json' = [ordered]@{ schema = $Schema } }
        }

        # a POST endpoint that also reads the query string accepts both
        $Parameters = Get-QueryParameterList -Contract $Contract
        if ($Parameters.Count -gt 0) { $Operation['parameters'] = @($Parameters) }
    }

    # What the endpoint selects onto the record, and what the UI declares it renders.
    # Either alone is a partial description; together they cover most list endpoints.
    # The storage shape is only used when the endpoint reads exactly one table. Entrypoints
    # routinely open a config or tenant table alongside their data table, and merging two
    # row shapes would describe a record that never exists.
    $StorageFields = $null
    if ($TableIndex -and $Contract.TableNames.Count -eq 1) {
        $Known = @($Contract.TableNames | Where-Object { $TableIndex.ContainsKey($_) })
        if ($Known.Count -eq 1) { $StorageFields = $TableIndex[$Known[0]] }
    }

    # Same rule as storage: only when the endpoint reads exactly one Graph entity set.
    # Several sets would mean merging two entity shapes into a record that never exists.
    $GraphFields = $null
    $GraphProven = $false
    if ($GraphIndex -and $Contract.GraphRefs.Count -eq 1) {
        $Reference = $Contract.GraphRefs[0]
        $Version = $GraphIndex[$Reference.Version]
        $Entity = $null
        if ($Version -and $Version.Sets.ContainsKey($Reference.Segments[0])) {
            $TypeName = $Version.Sets[$Reference.Segments[0]]
            # Walk the rest of the path through navigation properties. Anything that cannot
            # be resolved - an action, a function, a $ segment - abandons the whole lookup
            # rather than falling back to the last type that did resolve, which would
            # describe a parent object instead of the collection actually being read.
            for ($Segment = 1; $Segment -lt $Reference.Segments.Count; $Segment++) {
                $Current = $Version.Types[$TypeName]
                $Next = if ($Current) { $Current.Navigation[$Reference.Segments[$Segment]] } else { $null }
                if (-not $Next) { $TypeName = $null; break }
                $TypeName = $Next
            }
            if ($TypeName -and $Version.Types.ContainsKey($TypeName)) {
                $Entity = $Version.Types[$TypeName].Properties
            }
        }
        if ($Entity -and $Entity.Count -gt 0) {
            # What the code does with the response decides how much of the entity to claim.
            # Graph never returns a whole entity: without $select it returns a default
            # projection, and CIPP usually narrows further still. Documenting the full type
            # was measurably wrong - ListSharedMailboxAccountEnabled listed 90 fields and
            # returned 8 - so the entity is used as a source of TYPES, and only as a source
            # of FIELDS when the code proves which fields come back.
            $Selected = @($Contract.GraphSelect | Where-Object { $Entity.Contains($_) })
            $Shaped = @($Contract.BackendFields | Where-Object { $Entity.Contains($_) })

            $GraphFields = [ordered]@{}
            if ($Selected.Count -ge 3) {
                # an explicit $select names exactly what Graph returns
                foreach ($Field in $Selected) { $GraphFields[$Field] = $Entity[$Field] }
                $GraphProven = $true
            } elseif ($Shaped.Count -gt 0) {
                # the endpoint reshapes the response itself, so its own field list is the
                # authority and Graph only supplies the types for it
                foreach ($Field in $Shaped) { $GraphFields[$Field] = $Entity[$Field] }
                $GraphProven = $true
            } else {
                # A pure passthrough proves nothing about which fields come back, and that
                # is exactly the case Graph was brought in for - dropping it here would
                # leave these endpoints undescribed again. The entity is used, but marked
                # as the entity rather than as a proven projection, because Graph returns a
                # default subset unless asked otherwise. The distinction is carried in
                # x-cipp-field-source so a caller can tell "this is returned" from "this
                # exists on the type".
                foreach ($Field in $Entity.Keys) { $GraphFields[$Field] = $Entity[$Field] }
                $GraphProven = $false
            }
        }
    }

    $Record = if ($Contract.Columns.Count -gt 0 -or $Contract.BackendFields.Count -gt 0 -or
        ($StorageFields -and $StorageFields.Count -gt 0) -or ($GraphFields -and $GraphFields.Count -gt 0)) {
        ConvertTo-RecordSchema -Columns $Contract.Columns -BackendFields $Contract.BackendFields `
            -StorageFields $StorageFields -GraphFields $GraphFields -GraphProven:$GraphProven -OutputNames $Contract.OutputNames
    } else {
        # Nothing in the source names a field. Most of these hand an upstream response
        # straight back (New-GraphGetRequest to Graph or the admin portal, New-ExoRequest to
        # Exchange), so the shape is decided by Microsoft at runtime and is not recoverable
        # from the entrypoint at all. Say so, rather than leaving a bare open object that a
        # docs viewer renders as a fabricated "additionalProp1" placeholder.
        [ordered]@{
            type        = 'object'
            description = 'Not described statically: this endpoint returns the upstream response as-is, so its fields are determined by the upstream API rather than by CIPP. Call the endpoint to see the actual shape, or add a response schema in backend/Config/openapi-overrides.'
        }
    }

    $SuccessSchema = if ($Contract.HasResults) {
        [ordered]@{ '$ref' = '#/components/schemas/StandardResults' }
    } elseif ($Contract.ReturnsArray -or $Contract.Name -like 'List*') {
        [ordered]@{ type = 'array'; items = $Record }
    } else {
        $Record
    }

    $Responses = [ordered]@{
        '200' = [ordered]@{
            description = 'Success'
            content     = [ordered]@{ 'application/json' = [ordered]@{ schema = $SuccessSchema } }
        }
    }
    # 401/403 come from New-CippCoreRequest before the endpoint runs, so they apply
    # everywhere; the rest are only listed when the endpoint can actually return them
    foreach ($Code in @('Unauthorized', 'Forbidden')) {
        $Responses[[string][int][System.Net.HttpStatusCode]::$Code] = [ordered]@{ description = $StatusDescriptions[$Code] }
    }
    foreach ($Code in ($Contract.StatusCodes | Sort-Object -CaseSensitive)) {
        if ($Code -eq 'OK') { continue }
        $Numeric = $null
        try { $Numeric = [string][int][System.Net.HttpStatusCode]::$Code } catch { continue }
        if ($Responses.Contains($Numeric)) { continue }
        $Responses[$Numeric] = [ordered]@{
            description = if ($StatusDescriptions.ContainsKey($Code)) { $StatusDescriptions[$Code] } else { $Code }
        }
    }
    $Sorted = [ordered]@{}
    foreach ($Code in ($Responses.Keys | Sort-Object)) { $Sorted[$Code] = $Responses[$Code] }
    $Operation['responses'] = $Sorted

    $Operation['security'] = @([ordered]@{ bearerAuth = @() })
    if ($Contract.Role) { $Operation['x-cipp-role'] = $Contract.Role }
    if ($Contract.AnyTenant) { $Operation['x-cipp-any-tenant'] = $true }
    if ($Contract.Downstream.Count -gt 0) {
        # some of the documented fields are read by these helpers rather than by the
        # entrypoint; recorded so a surprising field can be traced back to its source
        $Operation['x-cipp-reads-via'] = @($Contract.Downstream | Sort-Object -CaseSensitive)
    }

    return $Operation
}

function Merge-OpenApiOverride {
    # Deep-merges a hand-authored override over the generated operation. A null
    # value deletes the key, which is the escape hatch for a field the AST sees but
    # the public contract should not advertise.
    param($Base, $Override)

    if ($Override -isnot [System.Collections.IDictionary]) { return $Override }
    if ($Base -isnot [System.Collections.IDictionary]) { $Base = [ordered]@{} }

    foreach ($Key in $Override.Keys) {
        $Value = $Override[$Key]
        if ($null -eq $Value) { if ($Base.Contains($Key)) { $Base.Remove($Key) }; continue }
        if ($Value -is [System.Collections.IDictionary] -and $Base.Contains($Key)) {
            $Base[$Key] = Merge-OpenApiOverride -Base $Base[$Key] -Override $Value
        } else {
            $Base[$Key] = $Value
        }
    }
    return $Base
}

# -- Run -----------------------------------------------------------------------

$RootPath = (Resolve-Path $EntrypointPath).Path

# Entrypoints that hand the body to a helper keep most of their contract in that
# helper (Invoke-EditUser reads 6 fields and passes the body to Set-CIPPUser, which
# reads 30 more), so the shared modules are indexed and followed.
$HelperIndex = $null
if ($ModulesPath -and (Test-Path $ModulesPath)) {
    $HelperRoots = @('CIPPCore', 'CIPPHTTP', 'CIPPStandards', 'CippExtensions') |
        ForEach-Object { Join-Path $ModulesPath $_ 'Public' } |
        Where-Object { Test-Path $_ }
    if ($HelperRoots) { $HelperIndex = Get-HelperSourceIndex -SearchPath $HelperRoots }
}
# Storage tables are written all over the backend (CIPPDB's cache writers, CIPPCore's
# settings and scheduler code), so the writer scan covers every module rather than the
# handful searched for request helpers.
$TableIndex = $null
if ($ModulesPath -and (Test-Path $ModulesPath)) {
    $TableIndex = Get-TableWriterIndex -SearchPath @($ModulesPath)
    Write-Host "Recovered row shapes for $($TableIndex.Count) storage tables."
}

$GraphIndex = Get-GraphMetadataIndex -Path $GraphMetadataPath
if ($GraphIndex) {
    Write-Host "Loaded Graph metadata for: $(($GraphIndex.Keys | Sort-Object) -join ', ')."
} else {
    Write-Host "No Graph metadata at '$GraphMetadataPath'; Graph passthrough responses will be untyped."
}

$ColumnMap = Get-FrontendColumnMap -SrcDir $FrontendPath
if ($ColumnMap.Count -eq 0) {
    Write-Host "No frontend column declarations found at '$FrontendPath'; list responses will be untyped."
}

if ($null -eq $HelperIndex) {
    # not fatal, but the resulting spec is thinner than the committed one, which would
    # make -Check fail for reasons that have nothing to do with the endpoints
    Write-Host "No shared modules found at '$ModulesPath'; documenting only what the entrypoints read directly."
}
$Files = @(Get-ChildItem -Path $RootPath -Filter 'Invoke-*.ps1' -Recurse -File | Sort-Object FullName)
if ($Endpoint) {
    $Files = @($Files | Where-Object { $_.BaseName -eq "Invoke-$Endpoint" })
    if ($Files.Count -eq 0) { throw "No entrypoint file found for endpoint '$Endpoint'." }
}

$Contracts = [System.Collections.Generic.List[object]]::new()
$ParseErrors = [System.Collections.Generic.List[string]]::new()
$Skipped = [System.Collections.Generic.List[string]]::new()

foreach ($File in $Files) {
    $Contract = Get-EndpointContract -Path $File.FullName -RootPath $RootPath -HelperIndex $HelperIndex -ColumnMap $ColumnMap
    if ($null -eq $Contract) { $Skipped.Add($File.Name); continue }
    if ($Contract.PSObject.Properties.Name -contains 'ParseError') {
        $ParseErrors.Add("$($File.Name): $($Contract.ParseError)")
        continue
    }
    $Contracts.Add($Contract)
}

if ($ParseErrors.Count -gt 0) {
    # a file that will not parse is a file whose endpoint silently vanishes from the
    # spec, and from the MCP tool list with it
    $ParseErrors | ForEach-Object { Write-Host "PARSE ERROR $_" }
    throw "$($ParseErrors.Count) entrypoint file(s) failed to parse."
}
if ($Contracts.Count -eq 0) { throw "No entrypoints found under '$RootPath'." }

$Overrides = @{}
if (Test-Path $OverridePath) {
    foreach ($File in (Get-ChildItem -Path $OverridePath -Filter '*.json' -File)) {
        if ($File.BaseName.StartsWith('_')) { continue }
        try {
            $Overrides[$File.BaseName] = Get-Content -Path $File.FullName -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            throw "Override '$($File.Name)' is not valid JSON: $($_.Exception.Message)"
        }
    }
}

$Paths = [ordered]@{}
$TagSet = [System.Collections.Generic.HashSet[string]]::new()
$Report = [System.Collections.Generic.List[object]]::new()

foreach ($Contract in ($Contracts | Sort-Object Name -CaseSensitive)) {
    # Craft dispatches by name and does not filter on verb, but an endpoint that
    # reads the body is a POST and one that only reads the query string is a GET.
    # A path gets both only for the read/action split below; the MCP catalog keeps one
    # tool per name by preferring the POST, which carries the query parameters too.
    $HasBodyShape = $Contract.BodyTree.Children.Count -gt 0 -or $Contract.BodyTree.IsArray -or $Contract.BodyTree.IsDynamic
    $ReadsQuery = $Contract.UsesQuery -or $Contract.QueryTree.Children.Count -gt 0

    # Endpoints written as `$Request.Query.X ?? $Request.Body.X` accept either, and the
    # rule "a body shape means POST" documented all of them as POST-only. That is wrong for
    # the read endpoints: the UI fetches ListCustomScripts as
    # /api/ListCustomScripts?ScriptGuid=..., and a caller following the spec would send a
    # body instead. A List/Get endpoint that reads the query string is therefore documented
    # as GET.
    #
    # Only when every body field can also be supplied on the query string, because the GET
    # form describes query parameters alone - flipping an endpoint with a body-only field
    # would silently drop it from the contract.
    $BodyOnly = @($Contract.BodyTree.Children.Keys | Where-Object { -not $Contract.QueryTree.Children.Contains($_) })
    $IsReadVerb = $Contract.Name -match '^(List|Get)'
    $QueryCoversBody = $BodyOnly.Count -eq 0 -and -not $Contract.BodyTree.IsArray -and -not $Contract.BodyTree.IsDynamic

    # An endpoint that changes something is a POST whatever it happens to read from. Where
    # its arguments come from the query string those stay documented as query parameters -
    # the POST form emits both - so nothing is lost by saying so, and RemoveStandard being
    # documented as GET invited callers, caches and link prefetchers to treat a deletion as
    # a safe request.
    #
    # A .ReadWrite role is the reliable signal for the Exec* endpoints, whose names say
    # nothing either way: ExecServicePrincipals holds Tenant.Application.ReadWrite, while
    # ExecAccessChecks only reads and stays a GET. None of these reach the MCP catalog,
    # which requires a .Read role and rejects mutation-verb names, so this cannot affect
    # how a tool call delivers its arguments.
    $IsMutation = $Contract.Name -match '^(Add|Set|Remove|Delete|Edit|New|Update|Disable|Enable|Reset|Revoke|Push|Clear|Start|Stop|Rename|Move|Copy)' -or
        $Contract.Role -match '\.ReadWrite$'

    # A List/Get endpoint that reads the query but takes some fields only from the body
    # answers a plain GET and also accepts a POST for those fields, as ListTenants does for
    # ClearCache. Documenting only the POST hid the GET every caller actually makes.
    $IsDualMethod = -not $IsMutation -and $IsReadVerb -and $ReadsQuery -and $Contract.UsesBody -and $HasBodyShape -and -not $QueryCoversBody

    $Methods = if ($IsMutation) { @('post') }
    elseif ($IsDualMethod) { @('get', 'post') }
    elseif ($Contract.UsesBody -and $HasBodyShape -and $ReadsQuery -and $IsReadVerb -and $QueryCoversBody) { @('get') }
    elseif ($Contract.UsesBody -and $HasBodyShape) { @('post') }
    elseif ($ReadsQuery) { @('get') }
    elseif ($Contract.UsesBody) { @('post') }
    else { @('get') }

    $Override = $null
    if ($Overrides.ContainsKey($Contract.Name)) {
        $Override = $Overrides[$Contract.Name]
        if ($Override.ContainsKey('method')) { $Methods = @([string]$Override['method']); $Override.Remove('method') }
    }

    $PathItem = [ordered]@{}
    foreach ($Method in $Methods) {
        $Operation = ConvertTo-OasOperation -Contract $Contract -Method $Method
        # operationIds must be unique across the spec, so the POST half of a dual-method
        # endpoint gets a suffix and the GET keeps the plain name.
        if ($Methods.Count -gt 1 -and $Method -ne $Methods[0]) { $Operation['operationId'] = "$($Contract.Name)$($Method.Substring(0,1).ToUpper())$($Method.Substring(1))" }
        if ($Override) { $Operation = Merge-OpenApiOverride -Base $Operation -Override $Override }
        $PathItem[$Method] = $Operation
    }
    $Paths["/api/$($Contract.Name)"] = $PathItem
    $null = $TagSet.Add($Contract.Tag)

    $Report.Add([ordered]@{
            endpoint       = $Contract.Name
            method         = $Methods -join ','
            role           = $Contract.Role
            tag            = $Contract.Tag
            bodyFields     = $Contract.BodyTree.Children.Count
            queryFields    = $Contract.QueryTree.Children.Count
            hasDescription = [bool]($Contract.Synopsis -or $Contract.Description)
            passthrough    = $Contract.BodyTree.IsDynamic
            overridden     = $Overrides.ContainsKey($Contract.Name)
            source         = [IO.Path]::GetRelativePath($RootPath, $Contract.Path)
        })
}

$Spec = [ordered]@{
    openapi    = '3.1.0'
    info       = [ordered]@{
        title       = 'CIPP API'
        version     = 'auto'
        # Normalized to LF. This script is checked out with CRLF on Windows (core.autocrlf),
        # so the here-string absorbs CRLF and ConvertTo-Json escapes it as a literal \r\n
        # inside the description. Git's EOL filter only rewrites physical newlines, not an
        # escaped sequence inside a JSON string, so that difference gets committed and makes
        # -Check fail against the LF spec CI regenerates on ubuntu.
        description = (@'
The CIPP HTTP API. Every path maps one-to-one onto a PowerShell entrypoint:
New-CippCoreRequest resolves /api/<Name> to Invoke-<Name>, so the path segment is
the function name and is case-sensitive.

This spec is generated from the PowerShell AST of those entrypoints on every
build. Request schemas describe the fields the backend actually reads, including
nested ones: a property typed as LabelValue is read as `$Field.value` by the
backend and must be sent as an object, not a bare string.
'@ -replace "`r`n", "`n")
        'x-cipp-docs' = 'https://docs.cipp.app'
    }
    # The server is the deployment root, NOT '/api'. Path keys already carry the /api
    # prefix because routing is name-based and the file name IS the path, so a server of
    # '/api' makes every consumer build /api/api/ListUsers - which is exactly what Swagger
    # UI's "Try it out" did.
    servers    = @([ordered]@{ url = '/'; description = 'This CIPP deployment' })
    security   = @([ordered]@{ bearerAuth = @() })
    tags       = @(($TagSet | Sort-Object -CaseSensitive) | ForEach-Object { [ordered]@{ name = $_ } })
    components = [ordered]@{
        securitySchemes = [ordered]@{
            bearerAuth = [ordered]@{
                type         = 'http'
                scheme       = 'bearer'
                bearerFormat = 'JWT'
                description  = 'Entra ID bearer token, obtained via MSAL against the CIPP API app registration.'
            }
        }
        parameters      = [ordered]@{
            tenantFilter    = [ordered]@{
                name        = 'tenantFilter'
                'in'        = 'query'
                description = "Target tenant: the tenant's default domain, its tenant ID, or 'AllTenants'."
                required    = $true
                schema      = [ordered]@{ type = 'string' }
            }
            selectedTenants = [ordered]@{
                name        = 'selectedTenants'
                'in'        = 'query'
                description = 'Tenant domains to act on, for bulk operations.'
                required    = $false
                schema      = [ordered]@{ type = 'array'; items = [ordered]@{ type = 'string' } }
            }
        }
        schemas         = [ordered]@{
            LabelValue        = [ordered]@{
                type        = 'object'
                description = "CIPP's autocomplete/select shape. The backend reads `$Field.value, so this must be sent as an object - a bare string resolves to null and the field is silently ignored."
                properties  = [ordered]@{
                    label = [ordered]@{ type = 'string'; description = 'Display text. Ignored by the backend.' }
                    value = [ordered]@{ type = 'string'; description = 'The value the backend reads.' }
                }
                required    = @('value')
            }
            LabelValueNumber  = [ordered]@{
                type        = 'object'
                description = 'Autocomplete/select shape whose value is numeric.'
                properties  = [ordered]@{
                    label = [ordered]@{ type = 'string' }
                    value = [ordered]@{ type = 'number' }
                }
                required    = @('value')
            }
            StandardResults   = [ordered]@{
                type        = 'object'
                description = 'Standard CIPP action response envelope.'
                properties  = [ordered]@{
                    Results = [ordered]@{
                        description = 'A message, or one message per operation for bulk actions. Mixes success and error text.'
                    }
                }
            }
        }
    }
    paths      = $Paths
}

if ($Endpoint) {
    $Spec['paths'] | ConvertTo-Json -Depth 30
    return
}

$Json = $Spec | ConvertTo-Json -Depth 30

if ($Check) {
    if (-not (Test-Path $OutputPath)) { throw "No committed spec at '$OutputPath' to check against." }
    $Existing = Get-Content -Path $OutputPath -Raw
    if ($Existing.Trim() -ne $Json.Trim()) {
        throw "openapi.json is stale. Run build/tools/build-openapi.ps1 and commit the result."
    }
    Write-Host "openapi.json is current ($($Paths.Count) endpoints)."
    return
}

$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force
# write-then-move so a container reading through the bind mount never sees a
# half-written spec, matching build-function-parameters.ps1
Set-Content -Path "$OutputPath.tmp" -Value $Json -Encoding UTF8
Move-Item -Path "$OutputPath.tmp" -Destination $OutputPath -Force

# Static copy for the frontend. Written here rather than by the callers so it can never
# go stale: every path that regenerates the spec gets it, not just the dev watcher.
if ($PublicPath) {
    $PublicDir = Split-Path -Parent $PublicPath
    if (Test-Path $PublicDir) {
        Set-Content -Path "$PublicPath.tmp" -Value $Json -Encoding UTF8
        Move-Item -Path "$PublicPath.tmp" -Destination $PublicPath -Force
        Write-Host "Copied the spec to $PublicPath for static serving."
    } else {
        Write-Host "Skipped the static copy: '$PublicDir' does not exist."
    }
}

if ($ReportPath) {
    $Summary = [ordered]@{
        endpoints          = $Report.Count
        skippedNonEntrypoint = $Skipped.Count
        byMethod           = [ordered]@{
            get  = @($Report | Where-Object { $_.method -split ',' -contains 'get' }).Count
            post = @($Report | Where-Object { $_.method -split ',' -contains 'post' }).Count
        }
        withoutRole        = @($Report | Where-Object { -not $_.role }).Count
        withoutDescription = @($Report | Where-Object { -not $_.hasDescription }).Count
        noFields           = @($Report | Where-Object { $_.bodyFields -eq 0 -and $_.queryFields -eq 0 }).Count
        passthrough        = @($Report | Where-Object { $_.passthrough }).Count
        overridden         = @($Report | Where-Object { $_.overridden }).Count
        endpointDetail     = @($Report)
    }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force
    Set-Content -Path $ReportPath -Value ($Summary | ConvertTo-Json -Depth 6) -Encoding UTF8
}

Write-Host "Wrote $($Paths.Count) endpoints to $OutputPath ($($Skipped.Count) non-entrypoint files skipped)."
