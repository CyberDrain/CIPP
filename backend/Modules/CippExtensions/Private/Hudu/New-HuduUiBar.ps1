function New-HuduUiBar {
    <#
        .SYNOPSIS
        A horizontal usage bar. Pct is an invariant-culture number.
    #>
    param([string]$Pct, [string]$Color, [string]$Title, [int]$Height = 8)
    $Radius = [int]($Height / 2)
    "<div style=`"height:$($Height)px;border-radius:$($Radius)px;background:rgba(128,128,128,.22);overflow:hidden`" title=`"$(ConvertTo-HuduUiText $Title)`"><div style=`"height:$($Height)px;width:$(ConvertTo-HuduUiText $Pct)%;background:$Color`"></div></div>"
}
