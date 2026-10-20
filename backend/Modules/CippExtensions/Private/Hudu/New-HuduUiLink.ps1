function New-HuduUiLink {
    <#
        .SYNOPSIS
        A link opening in a new tab. Url, label and tip are encoded here.

        .PARAMETER Variant
        button: outlined Microsoft/PSA button. cipp: orange CIPP button. strong: bold inline link. text: underlined inline link.
    #>
    param(
        [string]$Url, [string]$Label, [string]$Tip,
        [ValidateSet('button', 'cipp', 'strong', 'text')][string]$Variant = 'button'
    )
    $Common = "href=`"$(ConvertTo-HuduUiText $Url)`" target=`"_blank`" rel=`"noopener noreferrer nofollow`" title=`"$(ConvertTo-HuduUiText $Tip)`""
    $Button = 'display:inline-flex;align-items:center;margin:0 6px 6px 0;padding:4px 7px;border-radius:6px;font-size:13px;font-weight:500;color:inherit;text-decoration:none;line-height:20px'
    switch ($Variant) {
        'button' { "<a $Common style=`"$Button;border:1px solid rgba(128,128,128,.45)`">$(ConvertTo-HuduUiText $Label)$(Get-HuduUiIcon -Name External)</a>" }
        'cipp' { "<a $Common style=`"$Button;border:1px solid rgba(247,127,0,.7);background:rgba(247,127,0,.1)`">$(ConvertTo-HuduUiText $Label)</a>" }
        'strong' { "<a $Common style=`"font-weight:600;color:inherit`">$(ConvertTo-HuduUiText $Label)</a>" }
        'text' { "<a $Common style=`"color:inherit;text-decoration:underline;text-decoration-color:rgba(247,127,0,.7);text-underline-offset:3px`">$(ConvertTo-HuduUiText $Label)</a>" }
    }
}
