function New-HuduUiRow {
    <#
        .SYNOPSIS
        Label on the left, value on the right. An empty value renders a muted "Not set"; a value too wide to sit beside its label wraps onto its own line.
    #>
    param([string]$Label, [AllowNull()][string]$Value, [string]$Note, [string]$ExtraStyle = '')
    $V = if ([string]::IsNullOrWhiteSpace($Value)) { '<span style="opacity:.55">Not set</span>' } else { ConvertTo-HuduUiText $Value }
    $N = if ($Note) { " <span style=`"opacity:.65`">($(ConvertTo-HuduUiText $Note))</span>" } else { '' }
    "<div style=`"display:flex;flex-wrap:wrap;justify-content:space-between;padding:7px 0;border-top:1px solid rgba(128,128,128,.2);font-size:13px$ExtraStyle`"><span style=`"opacity:.7;margin-right:12px;white-space:nowrap`">$(ConvertTo-HuduUiText $Label)</span><span style=`"margin-left:auto;text-align:right;max-width:100%;overflow-wrap:anywhere`">$V$N</span></div>"
}
