# Pins what audit log alert rules match, feature by feature, on real (scrubbed) audit records from
# Fixtures/AuditLogPresetSamples.json. Every case runs two ways and both must give the same answer:
#   Direct - the record through Test-CIPPAuditLogRules, as a Graph search record or a stored feed record is checked.
#   Feed   - the record as the Management Activity feed handles it: the blob needle check, the index, the prefilter's
#            candidate selection (Select-CIPPAuditLogCandidate), then Test-CIPPAuditLogRules.
# A case names the rules (conditions as the alert form stores them), the record, and which rule the record alerts on
# ($null: none). Only storage, Graph, the directory, geo-IP and tenant variables are stubbed.

BeforeDiscovery {
    function C([string]$Property, [string]$Operator, $Value, $Group) {
        $Condition = [ordered]@{ Property = @{ value = 'String'; label = $Property }; Operator = @{ value = $Operator; label = $Operator } }
        $Condition.Input = if ($Value -is [array]) { @(foreach ($Item in $Value) { @{ value = $Item; label = $Item } }) } else { @{ value = $Value; label = $Value } }
        if ($null -ne $Group) { $Condition.Group = $Group }
        $Condition
    }
    $SignIn = C 'Operation' 'eq' 'UserLoggedIn'
    $Rule = { param($Key, [object[]]$Conditions, $Log = 'Audit.AzureActiveDirectory', $Excluded, $Threshold, $Priority) @{ Key = $Key; Conditions = $Conditions; Log = $Log; Excluded = $Excluded; Threshold = $Threshold; Priority = $Priority } }

    $Cases = @(
        # --- Operators, on a real sign-in -------------------------------------------------------------------------------
        @{ Name = 'Equals matches, ignoring case'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'ResultStatus' 'eq' 'SUCCESS'))) }
        @{ Name = 'Equals fails on another value'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'ResultStatus' 'eq' 'Failed'))) }
        @{ Name = 'Not Equals'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'ResultStatus' 'ne' 'Failed'))) }
        @{ Name = 'Like with * and ?'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'like' 'cipp.audit.preset.2026101717224?@*'))) }
        @{ Name = 'Like with a [] class'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'like' '[a-c]ipp.*'))) }
        @{ Name = 'Not like'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'notlike' '*@contoso.onmicrosoft.com'))) }
        @{ Name = 'In'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'in' @('UserLoginFailed', 'UserLoggedIn')), (C 'ResultStatus' 'in' @('Success', 'Interrupted')))) }
        @{ Name = 'Not In'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'ResultStatus' 'notin' @('Success', 'Interrupted')))) }
        @{ Name = 'Greater than compares a number as a number'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'RecordType' 'gt' '9'))) }
        @{ Name = 'Less than compares a number as a number'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'RecordType' 'lt' '9'))) }
        @{ Name = 'Does not match (regex), ignoring case'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'UserAgent' 'notmatch' 'POWERSHELL/7\.\d'))) }
        @{ Name = 'Matches (regex)'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'UserAgent' 'match' 'PowerShell/7\.\d+\.\d+'))) }
        @{ Name = 'A regex with nested quantifiers still runs'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'UserAgent' 'notmatch' '^(\w+\s?)*!'))) }
        @{ Name = 'A regex that cannot be read never matches'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'UserAgent' 'match' '(PowerShell'))) }

        # --- Properties ---------------------------------------------------------------------------------------------------
        @{ Name = 'A dotted path into an object'; Sample = 'exo-new-inboxrule-forward'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'New-InboxRule'), (C 'AppAccessContext.UniqueTokenId' 'eq' 'u9IAkUXitkuOMpMGN82hAA')) 'Audit.Exchange') }
        @{ Name = 'A dotted path into a list tests every entry (Equals)'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'Actor.ID' 'eq' 'cipp.audit.preset.20261017172249@contoso.onmicrosoft.com'))) }
        @{ Name = 'A dotted path into a list tests every entry (Like)'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'Actor.ID' 'like' '*@contoso.onmicrosoft.com'))) }
        @{ Name = 'Exchange Parameters are properties of their own'; Sample = 'exo-new-inboxrule-forward'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'New-InboxRule'), (C 'ForwardTo' 'like' '*@example.com')) 'Audit.Exchange') }
        @{ Name = 'ExtendedProperties are properties of their own'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'RequestType' 'eq' 'OAuth2:Token'))) }
        @{ Name = 'DeviceProperties are properties of their own'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'OS' 'eq' 'Windows10'))) }
        @{ Name = 'A changed property holds its new value'; Sample = 'aad-update-user-jobtitle'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Update user.'), (C 'JobTitle' 'like' '*cipp-audit 20261017172249*'))) }
        @{ Name = 'Previous_Value_ holds the old value'; Sample = 'aad-update-user-jobtitle'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Update user.'), (C 'Previous_Value_JobTitle' 'eq' '[]'))) }
        @{ Name = 'A missing property is not equal to anything'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'NoSuchProperty' 'ne' 'x'))) }
        @{ Name = 'A missing property is not in any list'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'NoSuchProperty' 'notin' @('x', 'y')))) }
        @{ Name = 'A missing property is not like anything'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'NoSuchProperty' 'notlike' 'x*'))) }
        @{ Name = 'A missing property does not match a regex'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'NoSuchProperty' 'notmatch' '.'))) }
        @{ Name = 'A missing property equals nothing'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'NoSuchProperty' 'eq' 'x'))) }

        # --- Fields CIPP adds ------------------------------------------------------------------------------------------------
        @{ Name = 'CIPPUserKey is the UPN behind UserKey'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPUserKey' 'eq' 'mapped.user@contoso.onmicrosoft.com'))) }
        @{ Name = 'CIPP<Property> for an app is its directory entry'; Sample = 'app-sp-secret'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Add service principal credentials.'), (C 'CIPPObjectId.displayName' 'eq' 'Audit Test App'))) }
        @{ Name = 'CIPPAddedKeyTypes'; Sample = 'app-sp-secret'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Add service principal credentials.'), (C 'CIPPAddedKeyTypes' 'eq' 'Password'))) }
        @{ Name = 'CIPPActorType'; Sample = 'app-sp-secret'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Add service principal credentials.'), (C 'CIPPActorType' 'eq' 'ServicePrincipal'))) }
        @{ Name = 'CIPPActor joins every actor identity'; Sample = 'app-sp-secret'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Add service principal credentials.'), (C 'CIPPActor' 'like' '*ServicePrincipal_aa368e81*'))) }
        @{ Name = 'CIPPGeoLocation from the IP address'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPGeoLocation' 'notin' @('AU', 'NZ')))) }
        @{ Name = 'CIPPGeoLocation in an allowed country'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPGeoLocation' 'notin' @('US', 'AU')))) }
        @{ Name = 'CIPPBadRepIP'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPBadRepIP' 'eq' 'True'))) }
        @{ Name = 'A trusted address has no location'; Sample = 'aad-user-logged-in'; Expect = $null; Trusted = '203.0.113.10'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPGeoLocation' 'notin' @('AU', 'NZ')))) }
        @{ Name = 'An address without a location never matches a location condition'; Sample = 'aad-user-logged-in'; Expect = $null; NoGeo = $true; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPGeoLocation' 'notin' @('AU', 'NZ')))) }
        @{ Name = 'A user excluded from location alerts'; Sample = 'aad-user-logged-in'; Expect = $null; LocationExcluded = 'mapped.user@contoso.onmicrosoft.com'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPGeoLocation' 'notin' @('AU', 'NZ')))) }
        @{ Name = 'CIPPIPDetected without the port'; Sample = 'exo-new-inboxrule-forward'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'New-InboxRule'), (C 'CIPPIPDetected' 'eq' '203.0.113.10')) 'Audit.Exchange') }
        @{ Name = 'CIPPTimeUtc inside a window'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPTimeUtc' 'between' '17:00-18:00'))) }
        @{ Name = 'CIPPTimeUtc inside a window across midnight'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPTimeUtc' 'between' '17:30-06:00'))) }
        @{ Name = 'CIPPTimeUtc outside a window'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPTimeUtc' 'notbetween' '17:00-18:00'))) }
        @{ Name = 'CIPPDayUtc'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPDayUtc' 'in' @('Saturday', 'Sunday')))) }
        @{ Name = 'CIPPDateUtc'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CIPPDateUtc' 'gt' '2026-10-16'), (C 'CIPPDateUtc' 'lt' '2026-10-18'))) }

        # --- Groups and rule order -----------------------------------------------------------------------------------------
        @{ Name = 'An OR group matches when an earlier group does not'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'ResultStatus' 'eq' 'Failed' 0), (C 'Operation' 'eq' 'UserLoggedIn' 1), (C 'OS' 'eq' 'Windows10' 1))) }
        @{ Name = 'No OR group matches'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'ResultStatus' 'eq' 'Failed' 0), (C 'Operation' 'eq' 'UserLoginFailed' 1))) }
        @{ Name = 'Groups on different operations each anchor'; Sample = 'aad-user-login-failed'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'Operation' 'eq' 'UserLoginFailed' 1), (C 'ResultStatus' 'eq' 'Failed' 1))) }
        @{ Name = 'A condition for every group holds the alert back in every group'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'Operation' 'in' @('UserLoggedIn', 'UserLoginFailed') 1), (C 'UserId' 'ne' 'cipp.audit.preset.20261017172249@contoso.onmicrosoft.com' -1))) }
        @{ Name = 'A condition for every group lets the alert through when it holds'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoginFailed' 0), (C 'Operation' 'eq' 'UserLoggedIn' 1), (C 'UserId' 'ne' 'someone.else@contoso.onmicrosoft.com' -1))) }
        @{ Name = 'A group without an anchor is skipped, the others still run'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'ResultStatus' 'eq' 'Success' 0), (C 'Operation' 'eq' 'UserLoggedIn' 1))) }
        @{ Name = 'A record alerts once, on the first rule in table order'; Sample = 'aad-user-logged-in'; Expect = 'a'; Rules = @((& $Rule 'a' @($SignIn)), (& $Rule 'b' @($SignIn, (C 'OS' 'eq' 'Windows10')))) }
        @{ Name = 'A later rule alerts when the first does not match'; Sample = 'aad-user-logged-in'; Expect = 'b'; Rules = @((& $Rule 'a' @($SignIn, (C 'OS' 'eq' 'MacOs'))), (& $Rule 'b' @($SignIn, (C 'OS' 'eq' 'Windows10')))) }
        @{ Name = 'An excluded tenant never alerts'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn) 'Audit.AzureActiveDirectory' 'contoso.onmicrosoft.com') }
        @{ Name = 'An alert on another log never matches'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn) 'Audit.Exchange') }
        @{ Name = 'A General log record matches a General alert'; Sample = 'teams-channel-deleted'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'ChannelDeleted'), (C 'TeamName' 'eq' 'Project Team')) 'Audit.General') }
        @{ Name = 'A SharePoint record matches a SharePoint alert'; Sample = 'spo-file-downloaded'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'FileDownloaded'), (C 'SourceRelativeUrl' 'like' 'Shared Documents/*')) 'Audit.SharePoint') }

        @{ Name = 'Three OR groups, the last matching'; Sample = 'exo-set-inboxrule-forward'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'New-InboxRule' 0), (C 'Operation' 'eq' 'Set-Mailbox' 1), (C 'Operation' 'like' '*InboxRule' 2), (C 'ForwardTo' 'like' '*@*' 2)) 'Audit.Exchange') }
        @{ Name = 'Several conditions for every group must all hold'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'Operation' 'eq' 'UserLoginFailed' 1), (C 'OS' 'eq' 'Windows10' -1), (C 'ResultStatus' 'eq' 'Failed' -1))) }
        @{ Name = 'The operation anchor ignores case'; Sample = 'exo-set-inboxrule-plain'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'Set-InboxRule')) 'Audit.Exchange') }
        @{ Name = 'A Like operation anchor'; Sample = 'exo-set-inboxrule-plain'; Expect = 'r'; Rules = @(& $Rule 'r' @((C 'Operation' 'like' '*-InboxRule')) 'Audit.Exchange') }
        @{ Name = 'An excluded rule never takes the record from a later one'; Sample = 'aad-user-logged-in'; Expect = 'b'; Rules = @((& $Rule 'a' @($SignIn) 'Audit.AzureActiveDirectory' 'contoso.onmicrosoft.com'), (& $Rule 'b' @($SignIn))) }
        @{ Name = 'A rule on another log never takes the record from a later one'; Sample = 'aad-user-logged-in'; Expect = 'b'; Rules = @((& $Rule 'a' @($SignIn) 'Audit.Exchange'), (& $Rule 'b' @($SignIn))) }
        @{ Name = 'A repeated activity alert never fires on one record'; Sample = 'exo-new-inboxrule-forward'; Expect = $null; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'New-InboxRule')) 'Audit.Exchange' $null '{"Count":2,"Minutes":20}') }
        @{ Name = 'Contains on a list property'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'Actor.ID' 'contains' 'c02023e2-fa6a-4823-9061-70e4f6cab116'))) }
        @{ Name = 'In against a list property never matches (use Equals or Contains)'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'Actor.ID' 'in' @('c02023e2-fa6a-4823-9061-70e4f6cab116')))) }
        @{ Name = 'A timestamp compares as a date'; Sample = 'aad-user-logged-in'; Expect = 'r'; Rules = @(& $Rule 'r' @($SignIn, (C 'CreationTime' 'gt' '2026-10-17T17:00:00'), (C 'CreationTime' 'lt' '2026-10-17T18:00:00'))) }
        @{ Name = 'A timestamp is not text, so Like does not match it (use CIPPDateUtc)'; Sample = 'aad-user-logged-in'; Expect = $null; Rules = @(& $Rule 'r' @($SignIn, (C 'CreationTime' 'like' '2026-10-17*'))) }

        @{ Name = 'An alert with a priority is checked before one without'; Sample = 'aad-user-logged-in'; Expect = 'b'; Rules = @((& $Rule 'a' @($SignIn)), (& $Rule 'b' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 500)) }
        @{ Name = 'The lowest priority number is checked first'; Sample = 'aad-user-logged-in'; Expect = 'c'; Rules = @((& $Rule 'a' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 20), (& $Rule 'b' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 10), (& $Rule 'c' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 2)) }
        @{ Name = 'Alerts with the same priority keep their stored order'; Sample = 'aad-user-logged-in'; Expect = 'a'; Rules = @((& $Rule 'a' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 5), (& $Rule 'b' @($SignIn) 'Audit.AzureActiveDirectory' $null $null 5)) }
        @{ Name = 'A prioritised alert that does not match leaves the record to the next'; Sample = 'aad-user-logged-in'; Expect = 'a'; Rules = @((& $Rule 'a' @($SignIn)), (& $Rule 'b' @($SignIn, (C 'OS' 'eq' 'MacOs')) 'Audit.AzureActiveDirectory' $null $null 1)) }

        # --- Variables -----------------------------------------------------------------------------------------------------
        @{ Name = 'A variable takes the tenant''s value'; Sample = 'aad-user-logged-in'; Expect = 'r'; Vars = @{ '%breakglass%' = 'cipp.audit.preset.20261017172249@contoso.onmicrosoft.com' }; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'eq' '%breakglass%'))) }
        @{ Name = 'A variable lists several values for In'; Sample = 'aad-user-logged-in'; Expect = 'r'; Vars = @{ '%breakglass%' = 'bg@contoso.onmicrosoft.com, cipp.audit.preset.20261017172249@contoso.onmicrosoft.com' }; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'in' @('%breakglass%')))) }
        @{ Name = 'A variable in a condition for every group'; Sample = 'aad-user-logged-in'; Expect = $null; Vars = @{ '%breakglass%' = 'cipp.audit.preset.20261017172249@contoso.onmicrosoft.com' }; Rules = @(& $Rule 'r' @((C 'Operation' 'eq' 'UserLoggedIn' 0), (C 'Operation' 'eq' 'UserLoginFailed' 1), (C 'UserId' 'notin' @('%breakglass%') -1))) }
        @{ Name = 'A built-in variable'; Sample = 'aad-user-logged-in'; Expect = 'r'; Vars = @{ '%defaultdomain%' = 'contoso.onmicrosoft.com' }; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'like' '*@%defaultdomain%'))) }
        @{ Name = 'A variable the tenant has no value for is never compared'; Sample = 'aad-user-logged-in'; Expect = $null; Vars = @{}; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'ne' '%breakglass%'))) }
        @{ Name = 'A variable value the engine will not run is never compared'; Sample = 'aad-user-logged-in'; Expect = $null; Vars = @{ '%breakglass%' = 'a$b@contoso.onmicrosoft.com' }; Rules = @(& $Rule 'r' @($SignIn, (C 'UserId' 'ne' '%breakglass%'))) }
    )
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $script:Fixture = Get-Content (Join-Path $PSScriptRoot 'Fixtures/AuditLogPresetSamples.json') -Raw | ConvertFrom-Json
    $script:Tenant = 'contoso.onmicrosoft.com'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$NoProjection) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream, $ComplexFilter, $NoPagination) }
    function Get-CIPPPartnerUserLookup { @{} }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }

    foreach ($Helper in @(
            'Authentication/Get-CIPPIPAllowBlockList.ps1'
            'Authentication/Resolve-CIPPIPAllowBlockList.ps1'
            'Authentication/Test-IpInRange.ps1'
            'Authentication/ConvertTo-CIPPIPRange.ps1'
            'BEC/ConvertTo-CIPPBecHostAddress.ps1'
            'Tools/Test-CIPPConditionFilter.ps1'
            'Webhooks/Get-CIPPAuditLogRuleSet.ps1'
            'Webhooks/Test-CIPPAuditLogRules.ps1'
            'Webhooks/Get-CIPPAuditLogPrefilter.ps1'
            'Webhooks/Select-CIPPAuditLogCandidate.ps1'
            'Webhooks/Get-CIPPAuditLogRuleAnchor.ps1'
            'Webhooks/Split-CIPPAuditLogConditions.ps1'
            'Webhooks/Resolve-CIPPAuditLogConditionVariable.ps1'
        )) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

    # The rule a record alerts on, by the rule's key, or $null; through the engine directly or the feed's path.
    function Invoke-Engine {
        param([object[]]$Rules, [string]$Sample, [switch]$Feed)
        $script:RuleRows = @(foreach ($Rule in $Rules) {
                [pscustomobject]@{
                    PartitionKey      = 'Webhookv2'
                    RowKey            = $Rule.Key
                    Tenants           = (@(@{ label = 'Contoso'; value = $script:Tenant }) | ConvertTo-Json -Compress -Depth 10 | Out-String)
                    excludedTenants   = $(if ($Rule.Excluded) { @(@{ label = 'Contoso'; value = $Rule.Excluded }) | ConvertTo-Json -Compress -Depth 10 | Out-String })
                    Conditions        = (@($Rule.Conditions) | ConvertTo-Json -Compress -Depth 10 | Out-String)
                    Actions           = '[]'
                    Type              = $Rule.Log
                    AlertComment      = $Rule.Key
                    Threshold         = $Rule.Threshold
                    Priority          = $Rule.Priority
                    CustomSubject     = ''
                    PsaTicketPriority = ''
                }
            })
        $script:AuditRuleSetCache = $null
        $script:AuditRuleSearchLookups = $null
        $script:AuditRuleLookupCache = @{}
        $script:AuditRuleListCache = @{}
        $script:AuditRuleClauseCache = @{}
        $script:PartnerUserMemo = $null
        $Record = $script:Fixture.samples.$Sample.auditData
        $Log = switch ([string]$Record.Workload) {
            'AzureActiveDirectory' { 'Audit.AzureActiveDirectory' }
            'Exchange' { 'Audit.Exchange' }
            { $_ -in 'SharePoint', 'OneDrive' } { 'Audit.SharePoint' }
            default { 'Audit.General' }
        }
        $Json = '[' + ($Record | ConvertTo-Json -Depth 20 -Compress) + ']'
        $Rows = @([CIPP.CippJson]::ConvertFromJson($Json))
        if ($Feed) {
            # As Get-CIPPAuditLogContent does with a blob.
            $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter $script:Tenant
            $Shadowed = $Json.IndexOf('"Name":"Operation"', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or $Json.IndexOf('"Name":"ClientIP"', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            $Found = $Shadowed
            foreach ($Needle in $Prefilter.Needles) { if ($Json.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $Found = $true; break } }
            if (-not $Found) { return $null }
            $Rows = if ($Shadowed) {
                @(Select-CIPPAuditLogCandidate -Prefilter $Prefilter -Records $Rows)
            } else {
                @(Select-CIPPAuditLogCandidate -Prefilter $Prefilter -Index ([CIPP.CippJson]::IndexRecords($Json, [string[]]@('Operation', 'ClientIP', 'UserId', 'CreationTime'), [string[]]$Prefilter.RecordNeedles)))
            }
            if ($Rows.Count -eq 0) { return $null }
            $script:AuditRuleSearchLookups = $null
        }
        $Result = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows $Rows -EvaluateOnly -LogType $Log 3>$null 6>$null
        if ($Result.Error) { throw $Result.Error }
        if ($Result.MatchedLogs -gt 0) {
            # The matched record names its rule, which the alert links to.
            @($Result.DataToProcess)[0].CIPPRuleKey | Should -Be @($Result.DataToProcess)[0].CIPPAlertComment
            [string]@($Result.DataToProcess)[0].CIPPAlertComment
        }
    }
}

Describe 'Audit log alert rules on real audit records' {
    BeforeEach {
        $script:Vars = @{}
        $script:TrustedRows = @()
        $script:ExclusionRows = @()
        $script:GeoByIp = @{
            '203.0.113.10' = [pscustomobject]@{ CountryOrRegion = 'US'; Proxy = $true; Hosting = $false }
            '203.0.113.22' = [pscustomobject]@{ CountryOrRegion = 'AU'; Proxy = $false; Hosting = $false }
        }
        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            switch ($TableName) {
                'WebhookRules' { $script:RuleRows }
                'trustedIps' { $script:TrustedRows }
                'AuditLogUserExclusions' { $script:ExclusionRows }
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                default { @() }
            }
        }
        Mock -CommandName Get-AzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { param($TenantFilter) [pscustomobject]@{ value = @($TenantFilter.value) } }
        Mock -CommandName Get-CIPPGeoIPLocationBatch -MockWith { param($IPs) $Map = @{}; foreach ($Ip in $IPs) { if ($script:GeoByIp[$Ip]) { $Map[$Ip] = $script:GeoByIp[$Ip] } }; $Map }
        Mock -CommandName Write-LogMessage -MockWith { }
        # The directory: one user (the sign-in's UserKey) and one app (the credential record's ObjectId).
        Mock -CommandName Get-CIPPTestData -MockWith {
            param($TenantFilter, $Type)
            switch ($Type) {
                'Users' { [pscustomobject]@{ id = 'c02023e2-fa6a-4823-9061-70e4f6cab116'; displayName = 'Mapped User'; userPrincipalName = 'mapped.user@contoso.onmicrosoft.com'; accountEnabled = $true } }
                'ServicePrincipals' { [pscustomobject]@{ id = '365757f7-d131-49c5-be44-2561828d876d'; appId = '11111111-2222-4333-8444-555555555555'; displayName = 'Audit Test App'; appDisplayName = 'Audit Test App'; accountEnabled = $true; servicePrincipalType = 'Application'; tags = @() } }
                default { @() }
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($TenantFilter, $Text) $Out = [string]$Text; foreach ($Key in $script:Vars.Keys) { $Out = $Out.Replace($Key, $script:Vars[$Key]) }; $Out }
    }

    It '<Name>' -ForEach $Cases {
        if ($Vars) { $script:Vars = $Vars }
        if ($Trusted) { $script:TrustedRows = @([pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = $Trusted; state = 'Trusted' }) }
        if ($LocationExcluded) { $script:ExclusionRows = @([pscustomobject]@{ PartitionKey = $script:Tenant; RowKey = $LocationExcluded; Type = 'Location' }) }
        if ($NoGeo) { $script:GeoByIp = @{} }
        $Direct = Invoke-Engine -Rules $Rules -Sample $Sample
        $Feed = Invoke-Engine -Rules $Rules -Sample $Sample -Feed
        $Direct | Should -Be $Expect -Because 'the engine on the record'
        $Feed | Should -Be $Expect -Because 'the feed path (needle check, index, prefilter) must agree with the engine'
    }
}
