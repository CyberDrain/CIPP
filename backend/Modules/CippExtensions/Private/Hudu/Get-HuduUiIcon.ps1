function Get-HuduUiIcon {
    <#
        .SYNOPSIS
        Returns the markup for a named icon.

        .DESCRIPTION
        Hudu strips inline SVG from rich text but loads Font Awesome, so icons are Font Awesome classes.
    #>
    param([ValidateSet('External', 'Warning')][string]$Name)
    switch ($Name) {
        'External' { '<i class="fas fa-external-link-alt" style="opacity:.6;font-size:11px;margin-left:6px"></i>' }
        'Warning' { '<i class="fas fa-exclamation-triangle" style="margin-right:8px"></i>' }
    }
}
