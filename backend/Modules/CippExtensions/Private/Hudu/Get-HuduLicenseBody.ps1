function Get-HuduLicenseBody {
    <#
        .SYNOPSIS
        Renders the Microsoft 365 rich-text field of a Hudu license asset.

        .DESCRIPTION
        Inline styles only, no fixed text colours, so one output reads in Hudu light and dark. Every model value
        is encoded by the building blocks. Sections without data are left out.

        .PARAMETER Model
        Display-ready strings and lists built by Invoke-HuduExtensionSync: Name, SkuId, Status, StatusTone, AdminUrl,
        CippUrl, PurchasedText, UsedText, FreeText, UsedPercent, UsedPercentText, UsageTone, RenewalDate, Subscriptions,
        Users and Attention.

        .PARAMETER SyncedAt
        Shown in the header when given.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Model,
        [Nullable[datetime]]$SyncedAt,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc
    )

    $TableStyle = Get-CippExtensionUiTableStyle
    $HeadingCellStyle = $TableStyle.Th
    $CellStyle = $TableStyle.Td
    $LinkGroupStyle = 'display:inline-block;vertical-align:middle;font-size:12px;opacity:.7;margin:0 8px 6px 0'
    $EmptyValue = '<span style="opacity:.55">&ndash;</span>'

    $SyncedHtml = if ($SyncedAt) { New-CippExtensionUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
    $HeaderCard = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px 8px;box-sizing:border-box`">" +
    "<div><span style=`"vertical-align:middle;font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$(ConvertTo-CippExtensionUiText $Model.Name)</span> $(New-CippExtensionUiChip -Text $Model.Status -Tone $Model.StatusTone -Strong)</div>" +
    "<div style=`"font-size:13px;opacity:.75`">Microsoft 365 license <code style=`"font-size:11px;word-break:break-all`">$(ConvertTo-CippExtensionUiText $Model.SkuId)</code></div>$SyncedHtml" +
    "<div style=`"margin-top:10px;padding-top:12px;border-top:1px solid rgba(128,128,128,.2)`"><span style=`"$LinkGroupStyle`">Microsoft</span> " +
    (New-CippExtensionUiLink -Url $Model.AdminUrl -Label 'M365 licenses' -Tip 'Open licenses in the Microsoft 365 admin center' -Variant button) +
    " <span style=`"display:inline-block;vertical-align:middle;width:1px;height:20px;background:rgba(128,128,128,.4);margin:0 8px 6px 2px`"></span> <span style=`"$LinkGroupStyle`">CIPP</span> " +
    (New-CippExtensionUiLink -Url $Model.CippUrl -Label 'License report' -Tip 'Open the license report in CIPP' -Variant cipp) + '</div></div>'

    $AttentionHtml = if ($Model.Attention.Count) {
        $AttentionItems = @(foreach ($AttentionItem in $Model.Attention) { "<span style=`"display:inline-block;margin:4px 24px 0 0`">$(ConvertTo-CippExtensionUiRich $AttentionItem)</span>" }) -join ' '
        "<div style=`"margin-top:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
        "<div style=`"font-size:13px;font-weight:600`">$(Get-CippExtensionUiIcon -Name Warning)Needs attention <span style=`"font-weight:400;opacity:.7;margin-left:6px`">$($Model.Attention.Count)</span></div>" +
        "<div style=`"margin-top:2px;font-size:13px`">$AttentionItems</div></div>"
    }

    $SeatsCard = New-CippExtensionUiCard -Title 'Seats' -Icon 'chair' -Body (
        "<tr><td style=`"$($TableStyle.RowLabel);opacity:1;vertical-align:baseline;padding:0 12px 6px 0`"><strong style=`"font-size:20px;font-weight:600`">$(ConvertTo-CippExtensionUiText $Model.UsedText)</strong> <span style=`"opacity:.7`">of $(ConvertTo-CippExtensionUiText $Model.PurchasedText) assigned</span></td><td style=`"$($TableStyle.RowValue);vertical-align:baseline;padding:0 0 6px;opacity:.7`">$(ConvertTo-CippExtensionUiText $Model.UsedPercentText)</td></tr>" +
        "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);padding:0 0 10px`">$(New-CippExtensionUiBar -Pct $Model.UsedPercent -Tone $Model.UsageTone -Title "$($Model.UsedText) of $($Model.PurchasedText) assigned")</td></tr>" +
        (New-CippExtensionUiRow -Label 'Purchased' -Value $Model.PurchasedText) +
        (New-CippExtensionUiRow -Label 'Assigned' -Value $Model.UsedText) +
        (New-CippExtensionUiRow -Label 'Available' -Value $Model.FreeText) +
        (New-CippExtensionUiRow -Label 'Renewal date' -Value $Model.RenewalDate))

    $SubscriptionCard = if ($Model.Subscriptions.Count) {
        $SubscriptionRows = @(foreach ($Subscription in $Model.Subscriptions) {
                $TrialChip = if ($Subscription.IsTrial) { ' ' + (New-CippExtensionUiChip -Text 'Trial' -Tone info -Strong -Small) }
                $SeatsHtml = if ($Subscription.SeatsText) { ConvertTo-CippExtensionUiText $Subscription.SeatsText } else { $EmptyValue }
                $TermEndsHtml = if ($Subscription.TermEnds) { ConvertTo-CippExtensionUiText $Subscription.TermEnds } else { $EmptyValue }
                "<tr><td style=`"$CellStyle;padding-left:0`">$(ConvertTo-CippExtensionUiText $Subscription.Term)$TrialChip</td><td style=`"$CellStyle;white-space:nowrap`">$(New-CippExtensionUiChip -Text $Subscription.Status -Tone $Subscription.StatusTone -Strong)</td><td style=`"$CellStyle;white-space:nowrap;text-align:right`">$SeatsHtml</td><td style=`"$CellStyle;padding-right:0;white-space:nowrap`">$TermEndsHtml</td></tr>"
            }) -join ''
        $SubscriptionHeadings = "<th style=`"$HeadingCellStyle;padding-left:0`">Term</th><th style=`"$HeadingCellStyle`">Status</th><th style=`"$HeadingCellStyle;text-align:right`">Seats</th><th style=`"$HeadingCellStyle;padding-right:0`">Term ends</th>"
        New-CippExtensionUiCard -Title 'Subscriptions' -Icon 'file-invoice' -Count $Model.Subscriptions.Count -Body "<table style=`"$($TableStyle.Table)`"><tbody><tr>$SubscriptionHeadings</tr>$SubscriptionRows</tbody></table>"
    }
    # Hudu's mobile app ignores grid and stacks the cells, which suits a phone
    $CardCells = @(foreach ($Card in $SeatsCard, $SubscriptionCard) { if ($Card) { "<div style=`"min-width:0;margin:6px`">$Card</div>" } }) -join ''
    $CardRow = "<div style=`"display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));margin:6px -6px -6px`">$CardCells</div>"

    $UserCard = if ($Model.Users.Count) {
        $UserRows = @(foreach ($User in $Model.Users) {
                $UserName = if ($User.Url) { New-CippExtensionUiLink -Url $User.Url -Label $User.Name -Tip "Open $($User.Name) in Hudu" -Variant strong } else { "<span style=`"font-weight:600`">$(ConvertTo-CippExtensionUiText $User.Name)</span>" }
                "<tr><td style=`"$CellStyle;padding-left:0`">$UserName</td><td style=`"$CellStyle;padding-right:0`">$(ConvertTo-CippExtensionUiText $User.Address)</td></tr>"
            }) -join ''
        $UserHeadings = "<th style=`"$HeadingCellStyle;padding-left:0`">Person</th><th style=`"$HeadingCellStyle;padding-right:0`">User principal name</th>"
        New-CippExtensionUiCard -Title 'Assigned users' -Icon 'users' -Count $Model.Users.Count -Spaced -Body "<table style=`"$($TableStyle.Table)`"><tbody><tr>$UserHeadings</tr>$UserRows</tbody></table>"
    }

    "<div style=`"overflow:hidden`">$HeaderCard$AttentionHtml$CardRow$UserCard</div>"
}
