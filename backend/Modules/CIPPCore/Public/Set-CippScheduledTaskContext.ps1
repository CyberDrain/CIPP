function Set-CippScheduledTaskContext {
    <#
    .SYNOPSIS
        Stores the scheduled task id in CIPPCore module-scoped AsyncLocal storage for the current invocation.
    .DESCRIPTION
        Used by the scheduler engine (Push-ExecScheduledCommand in CIPPActivityTriggers) so that CIPPCore functions
        like Write-LogMessage can attribute log entries to the running scheduled task. Module script scope
        is used instead of global scope, which is not reliable in Azure Functions.

        Setting a task id also resets the error collection used by Get-CippScheduledTaskError, so errors
        logged by a previous task cannot leak into the next one running on the same worker.
    .PARAMETER TaskId
        The scheduled task RowKey. Pass $null or empty to clear.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TaskId
    )

    if (-not $script:CippScheduledTaskIdStorage) {
        $script:CippScheduledTaskIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    $script:CippScheduledTaskIdStorage.Value = $TaskId

    if (-not $script:CippScheduledTaskErrorStorage) {
        $script:CippScheduledTaskErrorStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    $script:CippScheduledTaskErrorStorage.Value = [System.Collections.Generic.List[string]]::new()
}
