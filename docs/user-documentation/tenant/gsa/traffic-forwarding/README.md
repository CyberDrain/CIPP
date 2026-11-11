# Traffic Forwarding

This page lists the Global Secure Access traffic forwarding profiles in the selected tenant, read live from the tenant: **Microsoft 365**, **Internet Access** and **Private Access**. A traffic forwarding profile decides which traffic the Global Secure Access client and remote networks send through Microsoft's network, and who it applies to.

The **Remote networks** tab lists the tenant's branch sites and the profiles they use.

{% content-ref url="remote-networks.md" %}
[remote-networks.md](remote-networks.md)
{% endcontent-ref %}

The tenant must be onboarded to Global Secure Access. If it is not, the page says so.

## Table Details

| Column          | Description                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Name            | The profile name.                                                                                                            |
| State           | Whether the profile is enabled or disabled.                                                                                  |
| Assignment      | **All users**, the number of users and groups it is assigned to, **Not assigned**, or **Unknown** when it could not be read. |
| Policies        | The profile's policy groups and whether each is enabled.                                                                     |
| Remote Networks | The branch sites that send their traffic through this profile.                                                               |

If part of a profile could not be read, the rest is still shown, and the full row (**More Info**) lists what failed under `readErrors`.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Profile</td><td>Opens the profile in the <a href="edit.md">editor</a>.</td><td>false</td></tr><tr><td>Enable Profile</td><td>Enables the profile. Shown for a disabled profile.</td><td>false</td></tr><tr><td>Disable Profile</td><td>Disables the profile, so its traffic no longer goes through Global Secure Access. Shown for an enabled profile.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full profile.</td><td>false</td></tr></tbody></table>

Changes take about 10 seconds to show when the page is refreshed.
