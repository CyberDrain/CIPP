# Apple

Lists the iOS/iPadOS and macOS device platform restrictions on the selected tenant that apply to specific groups, followed by the tenant's default restriction for iOS/iPadOS, macOS, tvOS, and visionOS.

## Action Buttons

<details>

<summary>Add Restriction</summary>

Opens the Add Enrollment Restriction drawer with **iOS/iPadOS** and **macOS** as the platform options. The fields are described on [README.md](README.md "mention"), with one difference: macOS restrictions have no **Minimum OS version** or **Maximum OS version**, as Intune has no OS version limits for macOS restrictions.

</details>

{% hint style="info" %}
tvOS and visionOS show the default restriction only. Microsoft Graph cannot create or read tvOS or visionOS restrictions for specific groups, so these are managed in the Microsoft Intune admin center and do not appear in CIPP.
{% endhint %}

## Table Details

The columns are the same as on [README.md](README.md "mention").

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Restriction</td><td>Opens the restriction in the Add Enrollment Restriction drawer to change its settings, priority, or assignment. Greyed out for the default restriction.</td><td>false</td></tr><tr><td>Save as Template</td><td>Saves the restriction's settings and assignment as an enrollment restriction template. Groups are saved by name, so the template finds the matching groups in each tenant it is deployed to. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>Delete Restriction</td><td>Deletes the restriction from the tenant. Users it applied to fall back to the next restriction by priority, or to the default restriction. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
