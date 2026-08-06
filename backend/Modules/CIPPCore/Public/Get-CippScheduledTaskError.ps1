function Get-CippScheduledTaskError {
    <#
    .SYNOPSIS
        Returns the error messages logged during the currently running scheduled task.
    .DESCRIPTION
        Companion to Set-CippScheduledTaskContext. Write-LogMessage appends every Error and Critical entry
        it writes to CIPPCore module-scoped AsyncLocal storage while a scheduled task context is active,
        which lets the scheduler engine tell the difference between a task that completed cleanly and one
        that completed while a step inside it failed.

        This is what catches partial failures that never throw, such as a user being created successfully
        but the licence assignment failing because no licences are available.

        Returns an empty collection when no task context is active.

        Call this as @(Get-CippScheduledTaskError). PowerShell unrolls a collection on return, so the
        bare form yields $null for no errors and a plain string for one. Do NOT try to defeat that by
        returning with a leading comma: the output stream strips the outer array again, so callers
        using the @() form receive a single nested array instead - which counts as one error even when
        there are none, and joins to "System.Object[]".
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CippScheduledTaskErrorStorage -or $null -eq $script:CippScheduledTaskErrorStorage.Value) {
        return @()
    }

    return @($script:CippScheduledTaskErrorStorage.Value)
}
