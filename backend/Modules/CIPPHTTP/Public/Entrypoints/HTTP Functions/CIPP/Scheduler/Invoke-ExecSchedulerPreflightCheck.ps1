function Invoke-ExecSchedulerPreflightCheck {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.ReadWrite
    .DESCRIPTION
        Runs the scheduled-task preflight check immediately instead of waiting for its six-hourly
        timer. Used after remediating a licence shortage so the at-risk view reflects reality without
        the polling lag. The check itself is unchanged - this only changes when it runs.

        ExecCippFunction can already run it, but that endpoint is SuperAdmin-gated; this exposes just
        the one safe operation at the same permission the scheduler views require. Synchronous on
        purpose: the check is one Graph call per distinct tenant, and returning after it finishes
        means the caller's table refresh shows the updated flags.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $null = Start-CIPPTaskPreflightCheck
        $Result = 'Preflight check complete. The at-risk list now reflects current licence availability.'
        Write-LogMessage -headers $Headers -API $APIName -message 'Ran an on-demand scheduler preflight check' -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to queue the preflight check: $($ErrorMessage.NormalizedError)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to queue the preflight check: $($ErrorMessage.NormalizedError)" }
            })
    }
}
