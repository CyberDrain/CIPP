---
description: Intune script management
---

# Scripts

Lists the scripts configured in the selected tenant, covering Windows PowerShell scripts, macOS shell scripts, remediation scripts and Linux scripts. From here you can view and edit a script's contents, change how it is assigned, or remove it from the tenant.

## Table Details

| Column                  | Description                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Script Type             | Which kind of script this is: Windows, MacOS, Remediation or Linux.                                                                  |
| Display Name            | The name of the script.                                                                                                              |
| Script Assignment       | The groups and broad targets the script is assigned to. All Devices and All Licensed Users appear here where those targets are used. |
| Script Exclude          | The groups excluded from the script.                                                                                                 |
| Description             | The description recorded against the script.                                                                                         |
| Run As Account          | Whether the script runs in the system or user context.                                                                               |
| Last Modified Date Time | When the script was last changed.                                                                                                    |

The remaining properties are those of the Graph resource type matching the script's own type. For more information on the properties please see the Graph documentation:

* Windows: [deviceManagementScript](https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicemanagementscript?view=graph-rest-beta#properties)
* MacOS: [deviceShellScript](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-deviceshellscript?view=graph-rest-beta#properties)
* Remediation: [deviceHealthScript](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-devicehealthscript?view=graph-rest-beta#properties)
* Linux: [deviceManagementConfigurationPolicy](https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta#properties)

{% hint style="info" %}
Where a script type cannot be retrieved from the tenant, a single row appears for that type carrying the error Graph returned in place of a script name. That usually means the tenant is not licensed for it rather than that anything is wrong.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign to All Users</td><td>Assigns the script to all licensed users.</td><td>true</td></tr><tr><td>Assign to All Devices</td><td>Assigns the script to all devices.</td><td>true</td></tr><tr><td>Assign Globally (All Users / All Devices)</td><td>Assigns the script to both all licensed users and all devices.</td><td>true</td></tr><tr><td>Assign to Custom Group</td><td>Assigns the script to specific groups, or excludes specific groups from it. Selecting Exclude together with Replace and no groups clears all existing exclusions while leaving the included assignments in place.</td><td>true</td></tr><tr><td>Edit Script</td><td>Opens the script's contents in an editor. Save with the icon in the top right of the dialog, or close with the cross. Closing with unsaved changes asks for confirmation first.</td><td>true</td></tr><tr><td>Delete Script</td><td>Deletes the script from the tenant.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Every assignment action offers an assignment mode. **Append** keeps the existing assignments and adds the new ones. **Replace** overwrites existing assignments, and for Assign to Custom Group it replaces only the direction you chose, include or exclude, leaving the other direction and any All Users or All Devices targets intact.
{% endhint %}

## Editing a Script

Selecting **Edit Script** fetches the script's contents and opens them in a syntax-highlighted editor. Windows and remediation scripts are shown as PowerShell; macOS and Linux scripts as shell.

Remediation scripts carry two payloads, so the dialog shows Detection Script and Remediation Script on separate tabs, each edited and saved independently of the other.

{% hint style="warning" %}
Built-in Microsoft remediation scripts are read-only. The editor opens and the script can be read, but the save control is not offered, because Intune rejects changes to them.
{% endhint %}

{% hint style="info" %}
Some script types hold no editable content, in which case the dialog says so rather than opening an editor.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
