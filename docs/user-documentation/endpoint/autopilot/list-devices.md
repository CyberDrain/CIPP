# Autopilot Devices

Autopilot Devices lists the Windows devices registered to the tenant's Autopilot service, along with the hardware details and group tag each was registered with. From here you can assign a device to a user or remove that assignment, rename it, change its group tag, or deregister it.

## Action Buttons

{% content-ref url="add-device.md" %}
[add-device.md](add-device.md)
{% endcontent-ref %}

<details>

<summary>Sync Devices</summary>

Asks the Autopilot deployment service to sync, pulling in device registrations made outside CIPP, such as those uploaded by an OEM, reseller or distributor. New devices will not appear in the list until a sync has run and completed.

{% hint style="info" %}
Microsoft only accepts a sync request every ten minutes. Requesting one sooner returns an error rather than queuing.
{% endhint %}

</details>

## Table Details

The properties returned are for the Graph resource type `windowsAutopilotDeviceIdentity`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-enrollment-windowsautopilotdeviceidentity?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign device</td><td>Assigns the device to a user, so that user is pre-populated at sign-in during Autopilot enrolment. Select the user from the list.</td><td>true</td></tr><tr><td>Unassign User</td><td>Removes the user assigned to the device, so no user is pre-populated at sign-in during Autopilot enrolment. Not offered for a device that has no assigned user.</td><td>true</td></tr><tr><td>Rename Device</td><td>Sets the computer name the device will take when it enrols. Existing enrolled devices are not renamed retrospectively.</td><td>true</td></tr><tr><td>Edit Group Tag</td><td>Sets the device's group tag, which is what dynamic device groups usually key off to decide which deployment profile a device receives. Clearing the field removes the tag.</td><td>true</td></tr><tr><td>Delete Device</td><td>Deregisters the device from Autopilot. The hardware can be re-registered later, but until it is, it will no longer receive an Autopilot deployment profile.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Display names entered for **Rename Device** must be 15 characters or fewer, may contain only letters, numbers and hyphens, cannot contain spaces, and cannot be made up entirely of numbers. Group tags are limited to 128 characters. Both are validated in the browser and again by CIPP, so an invalid value is rejected rather than silently applied.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
