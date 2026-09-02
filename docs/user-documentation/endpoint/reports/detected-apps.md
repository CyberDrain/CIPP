# Discovered Apps

Lists the applications Intune has detected across the enrolled devices in the selected tenant, with how many devices each one is installed on. This is a software inventory rather than a list of what CIPP or Intune has deployed, so applications installed outside Intune appear here too. Filter buttons narrow the list to Windows, macOS, iOS or Android applications.

## Filters

| Filter       | Shows                                     |
| ------------ | ----------------------------------------- |
| Windows Apps | Applications detected on Windows devices. |
| macOS Apps   | Applications detected on macOS devices.   |
| iOS Apps     | Applications detected on iOS devices.     |
| Android Apps | Applications detected on Android devices. |

## Table Details

The properties returned are for the Graph resource type `detectedApp`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-detectedapp?view=graph-rest-beta#properties).

{% hint style="info" %}
Device Count is how many enrolled devices report the application installed. The same application appears once per version, so a product mid-upgrade shows as several rows with the count split between them.
{% endhint %}

{% hint style="warning" %}
Unmanaged applications are only collected from devices marked as corporate owned. On personal devices Intune never inventories applications it does not manage, so the picture here is incomplete for a tenant with personally owned devices enrolled.
{% endhint %}

{% hint style="info" %}
Intune refreshes this inventory roughly every seven days per device, counted from that device's enrolment date rather than on a tenant-wide schedule, so a newly installed application can take a while to appear. Applications collected by the Intune Management Extension for Win32 apps refresh every 24 hours instead.
{% endhint %}

To see which applications a particular device reports, use the Detected Applications section on [device.md](../mem/devices/device.md "mention").

{% include "../../../../.gitbook/includes/feature-request.md" %}
