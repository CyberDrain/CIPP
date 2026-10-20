function New-HuduUiCard {
    <#
        .SYNOPSIS
        A bordered card with a heading, an optional count and an optional right-hand note or flag.

        .PARAMETER Body
        Already-rendered HTML.

        .PARAMETER Icon
        A Font Awesome solid icon name shown as a brand badge before the title.

        .PARAMETER Flag
        Already-rendered HTML shown at the right of the heading when there is no Right text.
    #>
    param(
        [string]$Title, [string]$Count, [string]$Right, [Parameter(Mandatory)][string]$Body,
        [string]$Flag, [string]$Icon, [switch]$Spaced, [int]$HeadingGap = 8
    )
    $Margin = if ($Spaced) { ';margin-top:12px' } else { '' }
    $Cnt = if ($Count) { " <span style=`"font-weight:400;opacity:.65;font-size:13px`">$(ConvertTo-HuduUiText $Count)</span>" } else { '' }
    $Badge = if ($Icon) { Get-HuduUiIcon -Name $Icon -Badge } else { '' }
    $RightHtml = if ($Right) { "<span style=`"font-size:12px;opacity:.7`">$(ConvertTo-HuduUiText $Right)</span>" } else { $Flag }
    $Head = if ($RightHtml) {
        "<div style=`"display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;margin:0 0 $($HeadingGap)px`"><h3 style=`"display:flex;align-items:center;margin:0 8px 0 0;font-size:15px;font-weight:600;line-height:1.4`">$Badge<span>$(ConvertTo-HuduUiText $Title)$Cnt</span></h3>$RightHtml</div>"
    } else {
        "<h3 style=`"display:flex;align-items:center;margin:0 0 $($HeadingGap)px;font-size:15px;font-weight:600;line-height:1.4`">$Badge<span>$(ConvertTo-HuduUiText $Title)$Cnt</span></h3>"
    }
    "<div style=`"border:1px solid rgba(128,128,128,.3);border-radius:6px;padding:14px 16px;box-sizing:border-box$Margin`">$Head$Body</div>"
}
