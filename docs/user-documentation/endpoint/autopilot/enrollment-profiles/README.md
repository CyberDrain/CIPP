# Enrollment Profiles

Lists the Windows Autopilot deployment profiles that exist on the selected tenant, with an overview of the settings each one applies. Additional tabs cover [apple-ade.md](apple-ade.md "mention") and [android-enterprise.md](android-enterprise.md "mention").

## Action Buttons

<details>

<summary>Add Profile</summary>

Opens the Autopilot Profile Wizard, which creates a deployment profile in one or more tenants at once.

| Field                                                                      | Description                                                                                                                                                   |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants                                                             | The tenants the profile is created in. At least one is required, and the profile is created identically in each.                                              |
| Display Name                                                               | The profile's name. Intune only accepts letters, numbers, spaces and the characters : " ? . @ $ & \_ \[ ] { } \| \\ and rejects hyphens.                      |
| Language                                                                   | The language applied during out-of-box experience. Operating system default and User Select sit at the top of the list, followed by the individual languages. |
| Description                                                                | Optional text describing the profile.                                                                                                                         |
| Unique Name Template                                                       | The naming pattern applied to devices that receive the profile, for example `%SERIAL%` or `%RAND:x%`. Leave blank to leave device names alone.                |
| Convert all targeted devices to Autopilot                                  | Registers any device the profile is assigned to into Autopilot automatically, rather than requiring it to be imported first.                                  |
| Assign to all devices                                                      | On by default. Assigns the profile to every Autopilot device in the tenant on creation. Turn it off to choose groups instead.                                 |
| Assign to Selected Groups                                                  | Shown when Assign to all devices is off. Assigns the profile to the groups you select, or leave it empty to create the profile with no assignment.            |
| Self-deploying mode                                                        | Enrols the device without a user present, for kiosks and shared devices.                                                                                      |
| Hide Terms and conditions                                                  | Skips the terms and conditions page during out-of-box experience. On by default.                                                                              |
| Hide Privacy Settings                                                      | Skips the privacy settings page during out-of-box experience. On by default.                                                                                  |
| Hide Change Account Options                                                | Always applied and cannot be changed, because the alternative requires Hybrid Microsoft Entra Join, which CIPP does not support.                              |
| Setup user as standard user (Leave unchecked to setup user as local admin) | Makes the enrolling user a standard user. Clearing it makes them a local administrator. On by default.                                                        |
| Allow White Glove OOBE                                                     | Permits pre-provisioning. On by default, and switched off and locked automatically when Self-deploying mode is enabled, since the two are incompatible.       |
| Automatically configure keyboard                                           | Skips the keyboard selection page and applies the layout matching the chosen language. On by default.                                                         |

Group targets are tenant-specific, so the group picker only appears when a single tenant is selected. With several tenants selected, or without the Identity Group Read permission, a warning takes its place and the profile is created without a group assignment.

After a successful creation the drawer stays open so another profile can be created without reopening it.

</details>

## Table Details

The properties returned are for the Graph resource type `windowsAutopilotDeploymentProfile`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-windowsautopilotdeploymentprofile?view=graph-rest-beta#properties).

The **Policy Assignment** column is added by CIPP and lists who the profile is assigned to: **All Devices**, or the assigned groups by name.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign to All Devices</td><td>Assigns the profile to every Autopilot device in the tenant. If the profile is already assigned to all devices the action reports that and makes no changes.</td><td>true</td></tr><tr><td>Assign to Custom Group(s)</td><td>Assigns the profile to one or more Entra ID groups. A dialog lets you search for and select the groups. Groups the profile is already assigned to are skipped automatically.</td><td>true</td></tr><tr><td>Remove Assignment(s)</td><td>Removes assignments from the profile. A <strong>Remove all assignments</strong> switch is on by default and removes every assignment in one action. Turn it off to pick specific assignments to remove instead, including the all devices assignment.</td><td>true</td></tr><tr><td>Delete Profile</td><td>Deletes the profile from the tenant along with its assignments. Devices already deployed with it are unaffected, but devices reset afterwards will no longer receive it.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
