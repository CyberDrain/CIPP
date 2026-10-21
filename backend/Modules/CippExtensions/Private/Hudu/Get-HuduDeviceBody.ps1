function Get-HuduDeviceBody {
    <#
        .SYNOPSIS
        Renders the Microsoft 365 rich-text field of a Hudu device asset from a Get-HuduDeviceViewModel model.

        .DESCRIPTION
        Inline styles only, no fixed text colours, so one output reads in Hudu light and dark. Every model value
        is encoded by the building blocks. Sections without data are left out.

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

    $m = $Model
    # Hudu strips the CSS gap property, so spacing is done with margins
    $TableStyle = Get-HuduUiTableStyle
    $Th = $TableStyle.Th
    $Td = $TableStyle.Td
    $Table = $TableStyle.Table
    $Wrap = 'display:flex;flex-wrap:wrap'
    $Sep = '<span style="width:1px;height:20px;background:rgba(128,128,128,.4);margin:0 8px 6px 2px"></span>'
    $LinkLabel = { param($t) "<span style=`"font-size:12px;opacity:.7;margin:0 8px 6px 0`">$t</span>" }
    $Columns = {
        param($Cards, $Basis)
        $Cells = @(foreach ($c in $Cards) { if ($c) { '<div style="flex:1 1 {0}px;min-width:0;margin:6px">{1}</div>' -f $Basis, $c } }) -join ''
        "<div style=`"$Wrap;margin:6px -6px -6px`">$Cells</div>"
    }
    $Muted = '<span style="opacity:.55">&ndash;</span>'
    $h = $m.Header

    # Header card
    $LinkHtml = [System.Collections.Generic.List[string]]::new()
    $LinkHtml.Add((& $LinkLabel 'Microsoft'))
    foreach ($i in $m.Links.Microsoft) { $LinkHtml.Add((New-HuduUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    if ($m.Links.Rmm.Count) {
        $LinkHtml.Add($Sep); $LinkHtml.Add((& $LinkLabel 'RMM'))
        foreach ($i in $m.Links.Rmm) { $LinkHtml.Add((New-HuduUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    }
    $Os = (@($h.Os, $h.OsVersion) | Where-Object { $_ } | ForEach-Object { ConvertTo-HuduUiText $_ }) -join ' '
    $User = if ($h.UserName -and $h.UserPrincipal) { "$(ConvertTo-HuduUiText $h.UserName) ($(ConvertTo-HuduUiText $h.UserPrincipal))" } else { ConvertTo-HuduUiText "$($h.UserName)$($h.UserPrincipal)" }
    $Sub = (@($Os, $User) | Where-Object { $_ }) -join ' &middot; '
    $Synced = if ($SyncedAt) { New-HuduUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
    $HeaderCard = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px 8px;box-sizing:border-box;$Wrap;align-items:center`">" +
    "<div style=`"flex:1 1 320px;min-width:0;margin:0 16px 8px 0`"><div style=`"$Wrap;align-items:center`"><span style=`"font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$(ConvertTo-HuduUiText $h.Name)</span>$(New-HuduUiChip -Text $h.Compliance -Tone $h.ComplianceTone -Strong)</div>" +
    "<div style=`"font-size:13px;opacity:.75`">$Sub</div></div>$Synced" +
    "<div style=`"flex:1 1 100%;$Wrap;align-items:center;padding-top:12px;border-top:1px solid rgba(128,128,128,.2)`">$($LinkHtml -join '')</div></div>"

    # Needs attention
    $Attention = Get-HuduDeviceAttentionItems -Model $m
    $AttentionHtml = if ($Attention.Count) {
        $Items = @(foreach ($a in $Attention) { "<span style=`"margin:4px 24px 0 0`">$(ConvertTo-HuduUiRich $a)</span>" }) -join ''
        "<div style=`"margin-top:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
        "<div style=`"display:flex;align-items:center;font-size:13px;font-weight:600`">$(Get-HuduUiIcon -Name Warning)Needs attention <span style=`"font-weight:400;opacity:.7;margin-left:6px`">$($Attention.Count)</span></div>" +
        "<div style=`"$Wrap;margin-top:2px;font-size:13px`">$Items</div></div>"
    }

    # Device details, hardware, enrollment and security
    $DetailsCard = New-HuduUiCard -Title 'Device details' -Icon 'laptop' -Body ((New-HuduUiRow -Label 'Owner' -Value $m.Details.Owner) +
        (New-HuduUiRow -Label 'Enrolled' -Value $m.Details.Enrolled) +
        (New-HuduUiRow -Label 'Last check-in' -Value $m.Details.LastSync) +
        (New-HuduUiRow -Label 'Management agent' -Value $m.Details.ManagementAgent))

    $S = $m.Hardware.Storage
    $StorageHtml = if ($S.Present) {
        "<div style=`"padding:7px 0;border-top:1px solid rgba(128,128,128,.2);font-size:13px`"><div style=`"display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px`"><span style=`"opacity:.7;margin-right:12px;white-space:nowrap`">Storage</span><span>$(ConvertTo-HuduUiText $S.UsedText) <span style=`"opacity:.7`">of $(ConvertTo-HuduUiText $S.AllocatedText), $(ConvertTo-HuduUiText $S.FreeText) free</span></span></div>" +
        (New-HuduUiBar -Pct $S.Pct -Tone $S.Tone -Title "Storage usage $($S.PctText)") + '</div>'
    }
    $HardwareCard = New-HuduUiCard -Title 'Hardware' -Icon 'microchip' -Body ((New-HuduUiRow -Label 'Serial number' -Value $m.Hardware.Serial) +
        (New-HuduUiRow -Label 'Chassis' -Value $m.Hardware.Chassis) +
        (New-HuduUiRow -Label 'Model' -Value $m.Hardware.Model) +
        (New-HuduUiRow -Label 'Manufacturer' -Value $m.Hardware.Manufacturer) + $StorageHtml)

    $e = $m.Enrollment
    $EnrollmentCard = New-HuduUiCard -Title 'Enrollment and security' -Icon 'shield-alt' -Body ((New-HuduUiRow -Label 'Enrollment type' -Value $e.EnrollmentType) +
        (New-HuduUiRow -Label 'Join type' -Value $e.JoinType) +
        (New-HuduUiRow -Label 'Registration state' -Value $e.RegistrationState) +
        (New-HuduUiRow -Label 'Autopilot enrolled' -Value $e.Autopilot) +
        (New-HuduUiRow -Label 'Device Guard requirements' -Value $e.DeviceGuard) +
        (New-HuduUiRow -Label 'Virtualization-based security' -Value $e.Vbs) +
        (New-HuduUiRow -Label 'Credential Guard' -Value $e.CredentialGuard))
    $RowOne = & $Columns @($DetailsCard, $HardwareCard, $EnrollmentCard) 280

    # Compliance policies
    $PolicyCard = if ($m.Policies.Count) {
        $Rows = @(foreach ($i in $m.Policies) {
                $Grace = if ($i.GraceExpiry) { ConvertTo-HuduUiText $i.GraceExpiry } else { $Muted }
                $Report = if ($i.LastReport) { ConvertTo-HuduUiText $i.LastReport } else { $Muted }
                "<tr><td style=`"$Td;padding-left:0`">$(ConvertTo-HuduUiText $i.Name)</td><td style=`"$Td;white-space:nowrap`">$(New-HuduUiChip -Text $i.StateLabel -Tone $i.StateTone -Strong)</td><td style=`"$Td;white-space:nowrap`">$Report</td><td style=`"$Td;padding-right:0;white-space:nowrap`">$Grace</td></tr>"
            }) -join ''
        $Head = "<th style=`"$Th;padding-left:0`">Policy</th><th style=`"$Th`">State</th><th style=`"$Th`">Last report</th><th style=`"$Th;padding-right:0`">Grace period ends</th>"
        New-HuduUiCard -Title 'Compliance policies' -Icon 'clipboard-check' -Count $m.Policies.Count -Spaced -Body "<table style=`"$Table`"><tbody><tr>$Head</tr>$Rows</tbody></table>"
    }

    # Groups
    $GroupCard = if ($m.Groups.Count) {
        $Chips = @(foreach ($g in $m.Groups) { New-HuduUiChip -Text $g }) -join ''
        New-HuduUiCard -Title 'Groups' -Icon 'users' -Count $m.Groups.Count -Spaced -Body "<div style=`"$Wrap`">$Chips</div>"
    }

    "<div style=`"overflow:hidden`">$HeaderCard$AttentionHtml$RowOne$PolicyCard$GroupCard</div>"
}
