# Copilot usage reports reject the period of the other report version: v2 answers D30 with
# "The period value 'RL30' is not supported with version 'v2'. Use 'RL28' instead." and v1 the
# reverse. Get-CopilotReportPeriod retries once with the other period on exactly that error and
# rethrows everything else. The Copilot cache collectors depend on the retry also working with
# -Stream, where the rows flow straight into Add-CIPPDbItem.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CopilotReportPeriod.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Template = "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='{0}')"
}

Describe 'Get-CopilotReportPeriod' {
    It 'retries a v2 tenant with D28 when D30 is rejected' {
        Mock New-GraphGetRequest { throw "The period value 'RL30' is not supported with version 'v2'. Use 'RL28' instead." } -ParameterFilter { $uri -like "*period='D30'*" }
        Mock New-GraphGetRequest { @{ upn = 'a@contoso.com' }, @{ upn = 'b@contoso.com' } } -ParameterFilter { $uri -like "*period='D28'*" }

        $Rows = @(Get-CopilotReportPeriod -UriTemplate $script:Template -Period 'D30' -TenantFilter $script:Tenant)

        $Rows.Count | Should -Be 2
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*period='D28'*" }
    }

    # The v1 wording is assumed to mirror the observed v2 one; the regex accepts either direction.
    It 'retries a v1 tenant with D30 when D28 is rejected' {
        Mock New-GraphGetRequest { throw "The period value 'RL28' is not supported with version 'v1'. Use 'RL30' instead." } -ParameterFilter { $uri -like "*period='D28'*" }
        Mock New-GraphGetRequest { @{ upn = 'a@contoso.com' } } -ParameterFilter { $uri -like "*period='D30'*" }

        @(Get-CopilotReportPeriod -UriTemplate $script:Template -Period 'D28' -TenantFilter $script:Tenant).Count | Should -Be 1
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*period='D30'*" }
    }

    It 'passes AsApp and Stream through to both attempts' {
        Mock New-GraphGetRequest { throw "The period value 'RL30' is not supported with version 'v2'. Use 'RL28' instead." } -ParameterFilter { $uri -like "*period='D30'*" }
        Mock New-GraphGetRequest { @{ upn = 'a@contoso.com' } } -ParameterFilter { $uri -like "*period='D28'*" }

        $Piped = [System.Collections.Generic.List[object]]::new()
        Get-CopilotReportPeriod -UriTemplate $script:Template -Period 'D30' -TenantFilter $script:Tenant -AsApp $true -Stream | ForEach-Object { $Piped.Add($_) }

        $Piped.Count | Should -Be 1
        Should -Invoke New-GraphGetRequest -Times 2 -Exactly -ParameterFilter { $AsApp -eq $true -and $Stream -and $tenantid -eq $script:Tenant }
    }

    It 'rethrows any other error without retrying' {
        Mock New-GraphGetRequest { throw 'Invalid permission.' }

        { Get-CopilotReportPeriod -UriTemplate $script:Template -Period 'D30' -TenantFilter $script:Tenant } | Should -Throw 'Invalid permission.'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }

    It 'does not retry a period that has no 28/30-day counterpart' {
        Mock New-GraphGetRequest { throw "The period value 'RL30' is not supported with version 'v2'. Use 'RL28' instead." }

        { Get-CopilotReportPeriod -UriTemplate $script:Template -Period 'D7' -TenantFilter $script:Tenant } | Should -Throw
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }
}
