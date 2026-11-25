# Devices

This page lists the devices registered in the tenant's directory, covering everything Entra ID knows about regardless of whether it is managed by Intune. It is the place to check a device's join type and sign-in state, block a device that should no longer authenticate, or retrieve its recovery key.

## Table Details

The properties returned are for the Graph resource type `device`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/device?view=graph-rest-beta#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Device</td><td>Opens the <a data-mention href="devices/device.md">device.md</a> page for the device, with its extension attributes and groups.</td><td>false</td></tr><tr><td>View in Entra</td><td>Opens the device in the Microsoft Entra admin center in a new tab.</td><td>false</td></tr><tr><td>Enable Device</td><td>Allows the device to authenticate with tenant credentials again. Greyed out for a device that is already enabled.</td><td>true</td></tr><tr><td>Disable Device</td><td>Blocks the device from authenticating with tenant credentials, without removing it from the directory. Greyed out for a device that is already disabled.</td><td>true</td></tr><tr><td>Retrieve BitLocker Keys</td><td>Returns the device's BitLocker recovery key from Entra ID, displayed in the result.</td><td>true</td></tr><tr><td>Retrieve LAPS password</td><td>Returns the device's Windows LAPS local administrator password, displayed in the result. Greyed out for anything other than a Windows device.</td><td>true</td></tr><tr><td>Add to Group</td><td>Adds the device to one or more groups. Mail-enabled groups and distribution lists cannot hold devices.</td><td>false</td></tr><tr><td>Set Extension Attribute</td><td>Sets one of the device's extension attributes 1 to 15, or clears it when the value is left empty. These attributes are often used in dynamic device group rules.</td><td>false</td></tr><tr><td>Delete Device</td><td>Removes the device from Entra ID. Any recovery keys held against it are lost with it, so retrieve them first if they may still be needed.</td><td>true</td></tr></tbody></table>

{% hint style="warning" %}
Retrieving a BitLocker key or a LAPS password returns a live credential in plain text, so treat the result as sensitive and avoid leaving it in a ticket or a chat message. Each retrieval is written to the CIPP audit log, recording who asked for it and when.
{% endhint %}

{% hint style="info" %}
Disabling a device stops it authenticating but leaves the object in place, so the action can be reversed and the device's recovery keys stay available. Deleting is the destructive option, and a device that is still in use will simply register itself again the next time it is joined.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
