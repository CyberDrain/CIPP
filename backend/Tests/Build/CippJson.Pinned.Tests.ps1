# Pins what CippJson.ConvertFromJson builds - every type, value, property order and error - against ConvertFrom-Json,
# over real audit-record shapes and edge cases, so a change to its internals cannot drift silently.

BeforeDiscovery {
    $script:SignIn = '{"CreationTime":"2026-10-17T02:18:04","Id":"1adbe533-c764-4bde-a967-ebdb0ef1f012","Operation":"UserLoggedIn","OrganizationId":"7e62aa0a-1df9-4d78-9c65-39382b0537e6","RecordType":15,"ResultStatus":"Success","UserKey":"211c70cf-4995-4399-84aa-eac137dc76fb","UserType":0,"Version":1,"Workload":"AzureActiveDirectory","ClientIP":"185.12.4.200","ObjectId":"00000003-0000-0000-c000-000000000000","UserId":"user0@contoso.com","AzureActiveDirectoryEventType":1,"ExtendedProperties":[{"Name":"ResultStatusDetail","Value":"Redirect"},{"Name":"UserAgent","Value":"Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},{"Name":"RequestType","Value":"OAuth2:Authorize"}],"ModifiedProperties":[],"Actor":[{"ID":"211c70cf-4995-4399-84aa-eac137dc76fb","Type":0},{"ID":"user0@contoso.com","Type":5}],"ActorContextId":"7e62aa0a-1df9-4d78-9c65-39382b0537e6","InterSystemsId":"5b0cd9e5-7c31-4bb5-a1b8-0d9a0d0f1e10","IntraSystemId":"a2b6c0b5-6f1f-4b3a-9c57-0d6a8b7e1f20","SupportTicketId":"","Target":[{"ID":"00000003-0000-0000-c000-000000000000","Type":0}],"TargetContextId":"7e62aa0a-1df9-4d78-9c65-39382b0537e6","ApplicationId":"00000003-0000-0000-c000-000000000000","DeviceProperties":[{"Name":"OS","Value":"Windows10"},{"Name":"BrowserType","Value":"Edge"},{"Name":"IsCompliant","Value":"False"},{"Name":"SessionId","Value":"0f8fad5b-d9cb-469f-a165-70867728950e"}],"ErrorNumber":"0"}'
    $script:InboxRule = '{"CreationTime":"2026-10-17T01:02:03","Id":"6d0a1b2c-3d4e-4f50-8a6b-7c8d9e0f1a2b","Operation":"New-InboxRule","OrganizationId":"7e62aa0a-1df9-4d78-9c65-39382b0537e6","RecordType":1,"ResultStatus":"True","UserKey":"10032000A1B2C3D4","UserType":2,"Version":1,"Workload":"Exchange","ClientIP":"[2001:db8::1]:51234","ObjectId":"contoso.onmicrosoft.com\\user0","UserId":"user0@contoso.com","AppId":"00000002-0000-0ff1-ce00-000000000000","AppAccessContext":{"AADSessionId":"0b6c1f6e-1e7c-4a25-9b6f-0e2b7f8d9a01","IssuedAtTime":"2026-10-17T00:02:03","UniqueTokenId":"aBcDeFgHiJkLmNoPqRsTuV"},"OrganizationName":"contoso.onmicrosoft.com","OriginatingServer":"SY4PR01MB1234 (15.20.8000.010)","Parameters":[{"Name":"AlwaysDeleteOutlookRulesBlob","Value":"False"},{"Name":"Force","Value":"False"},{"Name":"Name","Value":"Archive"},{"Name":"ForwardTo","Value":"someone@external.example"},{"Name":"MarkAsRead","Value":"True"}],"SessionId":"c8e7d6b5-a4f3-4e2d-9c1b-0a9f8e7d6c5b"}'
    $script:RoleChange = '{"CreationTime":"2026-10-17T03:04:05","Id":"9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b","Operation":"Add member to role.","OrganizationId":"7e62aa0a-1df9-4d78-9c65-39382b0537e6","RecordType":8,"ResultStatus":"Success","UserKey":"211c70cf-4995-4399-84aa-eac137dc76fb","UserType":0,"Version":1,"Workload":"AzureActiveDirectory","ObjectId":"user9@contoso.com","UserId":"admin@contoso.com","AzureActiveDirectoryEventType":1,"ExtendedProperties":[{"Name":"additionalDetails","Value":"{}"},{"Name":"extendedAuditEventCategory","Value":"User"}],"ModifiedProperties":[{"Name":"Role.ObjectID","NewValue":"62e90394-69f5-4237-9190-012177145e10","OldValue":""},{"Name":"Role.DisplayName","NewValue":"Global Administrator","OldValue":""},{"Name":"StrongAuthenticationRequirement","NewValue":"[]","OldValue":"[{\"State\":1,\"RememberDevicesNotIssuedBefore\":\"2026-01-01T00:00:00Z\"}]"}],"Actor":[{"ID":"admin@contoso.com","Type":5}],"Target":[{"ID":"User_6a8b3c2d-1e0f-4a9b-8c7d-6e5f4a3b2c1d","Type":2},{"ID":"user9@contoso.com","Type":5}]}'
    $script:Records = @{ SignIn = $script:SignIn; InboxRule = $script:InboxRule; RoleChange = $script:RoleChange }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    # Type-annotated, order-preserving rendering of a parsed value.
    function Get-Dump($Value) {
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            return '{' + (@(foreach ($Property in $Value.PSObject.Properties) { '{0}={1}' -f $Property.Name, (Get-Dump $Property.Value) }) -join ',') + '}'
        }
        if ($Value -is [string]) { return 'String:' + $Value }
        if ($Value -is [System.Collections.IList]) { return $Value.GetType().Name + '[' + (@(foreach ($Item in $Value) { Get-Dump $Item }) -join ',') + ']' }
        if ($Value -is [datetime]) { return 'DateTime:{0}:{1}' -f $Value.Kind, $Value.ToString('o') }
        if ($Value -is [double]) { return 'Double:' + $Value.ToString('R', [cultureinfo]::InvariantCulture) }
        '{0}:{1}' -f $Value.GetType().Name, $Value
    }

}

Describe 'CippJson.ConvertFromJson builds exactly what ConvertFrom-Json builds' {
    It 'matches for <Name>' -ForEach @(
        @{ Name = 'an Entra sign-in record'; Json = $script:SignIn }
        @{ Name = 'an Exchange inbox-rule record'; Json = $script:InboxRule }
        @{ Name = 'an Entra role-change record'; Json = $script:RoleChange }
        @{ Name = 'a page of records'; Json = "[$script:SignIn,$script:InboxRule,$script:RoleChange]" }
        @{ Name = 'integers'; Json = '{"zero":0,"one":1,"neg":-1,"i32max":2147483647,"i32over":2147483648,"i64max":9223372036854775807,"i64min":-9223372036854775808}' }
        @{ Name = 'reals'; Json = '{"half":1.5,"tiny":-2.25e-5,"exp":1e2,"onePointZero":1.0,"big":1.7976931348623157e308,"small":5e-324}' }
        @{ Name = 'booleans and nulls'; Json = '{"t":true,"f":false,"n":null,"arr":[true,null,false]}' }
        @{ Name = 'escaped and non-ASCII strings'; Json = '{"q":"a\"b\\c\/d","u":"café 😀","ws":"line\nnext\ttab\r","raw":"Zoë 日本"}' }
        @{ Name = 'empty containers'; Json = '{"o":{},"a":[],"s":"","nested":{"a":[[]],"o":[{}]}}' }
        @{ Name = 'nested arrays and objects'; Json = '{"m":[[1,2],[3,[4,{"x":[5]}]]],"d":{"a":{"b":{"c":{"d":{"e":1}}}}}}' }
        @{ Name = 'awkward property names'; Json = '{"@odata.nextLink":"x","with space":1,"dotted.name":2,"Ünïcode":3}' }
        @{ Name = 'date-looking strings'; Json = '{"iso":"2026-10-17T02:18:04","isoZ":"2026-10-17T02:18:04Z","isoOff":"2026-10-17T02:18:04+10:00","frac":"2026-10-17T02:18:04.1234567Z","dateOnly":"2026-10-17","minute":"2026-10-17T02:18","ms":"/Date(1700000000000)/","msOff":"/Date(1700000000000+1000)/","notDate":"2026-13-45T99:99:99"}' }
        @{ Name = 'a scalar root'; Json = '"text"' }
        @{ Name = 'a number root'; Json = '42' }
        @{ Name = 'a null root'; Json = 'null' }
        @{ Name = 'an empty array root'; Json = '[]' }
        @{ Name = 'a mixed array root'; Json = '[1,"two",null,{"a":1},[2]]' }
        @{ Name = 'surrounding whitespace'; Json = "  `r`n {`"a`" : [ 1 , 2 ] }  `n" }
    ) {
        Get-Dump ([CIPP.CippJson]::ConvertFromJson($Json)) | Should -BeExactly (Get-Dump (ConvertFrom-Json -InputObject $Json -NoEnumerate -Depth 1024))
    }

    It 'reads an integer past Int64 as a Double, where ConvertFrom-Json gives a BigInteger' {
        $Parsed = [CIPP.CippJson]::ConvertFromJson('{"n":9223372036854775808,"m":-123456789012345678901234567890}')
        Get-Dump $Parsed | Should -BeExactly '{n=Double:9.223372036854776E+18,m=Double:-1.2345678901234568E+29}'
        (ConvertFrom-Json -InputObject '{"n":9223372036854775808}').n.GetType().Name | Should -Be 'BigInteger'
    }

    It 'returns null for an empty string' {
        $null -eq [CIPP.CippJson]::ConvertFromJson('') | Should -BeTrue
    }

    It 'throws on <Name>' -ForEach @(
        @{ Name = 'truncated JSON'; Json = '{"a":' }
        @{ Name = 'a trailing comma'; Json = '{"a":1,}' }
        @{ Name = 'a comment'; Json = '{"a":1 /* c */}' }
        @{ Name = 'two roots'; Json = '{"a":1}{"b":2}' }
        @{ Name = 'whitespace only'; Json = '   ' }
        @{ Name = 'a single-quoted string'; Json = "{'a':1}" }
        @{ Name = 'an empty property name, which ConvertFrom-Json accepts'; Json = '{"":1}' }
    ) {
        { [CIPP.CippJson]::ConvertFromJson($Json) } | Should -Throw
    }

    It 'gives each parse its own objects' -ForEach $script:Records {
        $First = [CIPP.CippJson]::ConvertFromJson($SignIn)
        $Second = [CIPP.CippJson]::ConvertFromJson($SignIn)
        $First.ExtendedProperties[0].Value = 'changed'
        $Second.ExtendedProperties[0].Value | Should -Be 'Redirect'
    }
}

Describe 'CippJson.ConvertFromJson field projection' {
    It 'keeps only the named top-level fields of each record, matched case-insensitively, each with its whole subtree' -ForEach $script:Records {
        $Parsed = [CIPP.CippJson]::ConvertFromJson("[$SignIn,$InboxRule]", [string[]]@('operation', 'ExtendedProperties', 'AppAccessContext'))
        Get-Dump $Parsed | Should -BeExactly (Get-Dump @(
                foreach ($Record in (ConvertFrom-Json -InputObject "[$SignIn,$InboxRule]")) {
                    $Kept = [pscustomobject]@{}
                    foreach ($Property in $Record.PSObject.Properties) { if ($Property.Name -in 'operation', 'ExtendedProperties', 'AppAccessContext') { $Kept.PSObject.Properties.Add([psnoteproperty]::new($Property.Name, $Property.Value)) } }
                    $Kept
                }))
    }

    It 'keeps everything for a null or empty field list' -ForEach $script:Records {
        Get-Dump ([CIPP.CippJson]::ConvertFromJson($RoleChange, [string[]]@())) | Should -BeExactly (Get-Dump ([CIPP.CippJson]::ConvertFromJson($RoleChange)))
        Get-Dump ([CIPP.CippJson]::ConvertFromJson($RoleChange, $null)) | Should -BeExactly (Get-Dump ([CIPP.CippJson]::ConvertFromJson($RoleChange)))
    }

    It 'leaves a scalar root and scalar array items as they are' {
        Get-Dump ([CIPP.CippJson]::ConvertFromJson('[1,{"a":1,"b":2},"x"]', [string[]]@('a'))) | Should -BeExactly 'Object[][Int64:1,{a=Int64:1},String:x]'
    }
}

Describe 'CippJson.ConvertFromJsonEach' {
    It 'builds for each text exactly what ConvertFromJson builds for it' -ForEach $script:Records {
        $Texts = [string[]]@($SignIn, $InboxRule, '[1,2]', '"text"', $RoleChange)
        $Each = [CIPP.CippJson]::ConvertFromJsonEach($Texts)
        for ($i = 0; $i -lt $Texts.Count; $i++) { Get-Dump $Each[$i] | Should -BeExactly (Get-Dump ([CIPP.CippJson]::ConvertFromJson($Texts[$i]))) }
    }
}
