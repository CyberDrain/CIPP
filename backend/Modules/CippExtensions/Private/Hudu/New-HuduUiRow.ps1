function New-HuduUiRow {
    <#
        .SYNOPSIS
        Label on the left, value on the right. An empty value renders a muted "Not set".
    #>
    param([string]$Label, [AllowNull()][string]$Value, [string]$Note, [string]$ExtraStyle = '')
    $V = if ([string]::IsNullOrWhiteSpace($Value)) { '<span style="opacity:.55">Not set</span>' } else { ConvertTo-HuduUiText $Value }
    $N = if ($Note) { " <span style=`"opacity:.65`">($(ConvertTo-HuduUiText $Note))</span>" } else { '' }
    "<div style=`"display:flex;justify-content:space-between;padding:7px 0;border-top:1px solid rgba(128,128,128,.2);font-size:13px$ExtraStyle`"><span style=`"opacity:.7;margin-right:12px`">$(ConvertTo-HuduUiText $Label)</span><span style=`"text-align:right;min-width:0;word-break:break-word`">$V$N</span></div>"
}
