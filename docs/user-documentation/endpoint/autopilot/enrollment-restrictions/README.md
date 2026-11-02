# Enrollment Restrictions

Lists the device platform restrictions on the selected tenant that apply to specific groups, followed by the tenant's default restriction. A restriction decides which devices its users can enrol in Intune, by platform, operating system version, and ownership. This tab covers Windows, and further tabs cover [apple.md](apple.md "mention") and [android.md](android.md "mention").

## Action Buttons

<details>

<summary>Add Restriction</summary>

Opens the Add Enrollment Restriction drawer, which creates a restriction in one or more tenants at once. The **Platform** options match the tab the drawer is opened from.

| Field                                                            | Description                                                                                                                                                                                                                                                  |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Select Tenants                                                   | The tenants the restriction is created in. At least one is required.                                                                                                                                                                                         |
| Platform                                                         | The platform the restriction applies to. It cannot be changed once the restriction exists.                                                                                                                                                                  |
| Name                                                             | The restriction's name. Where a tenant already has a restriction with this name on the same platform, that restriction is updated instead of a second one being created.                                                                                     |
| Priority                                                         | 1 is the highest. The restriction is placed at this position and the tenant's other restrictions on the same platform move down one. Leave it blank, or enter a number past the end of the list, to place the restriction below the existing ones.           |
| Description                                                      | Optional text describing the restriction.                                                                                                                                                                                                                    |
| Block platform                                                   | Stops users the restriction applies to from enrolling devices of this platform.                                                                                                                                                                              |
| Block personally owned devices                                   | Stops users the restriction applies to from enrolling personally owned devices of this platform. Corporate-owned devices can still enrol.                                                                                                                     |
| Minimum OS version                                               | The oldest operating system version allowed to enrol, for example `10.0.19045`. Leave blank for no minimum.                                                                                                                                                 |
| Maximum OS version                                               | The newest operating system version allowed to enrol. Leave blank for no maximum.                                                                                                                                                                           |
| Who should this restriction apply to?                            | **Do Not Assign** creates the restriction without an assignment, or leaves an edited restriction's assignment as it is. **Assign to All Users** applies it to every user. **Assign to Custom Group** applies it to the groups chosen below.                    |
| Group(s)                                                         | Shown for **Assign to Custom Group** when a single tenant is selected. Pick the groups from that tenant.                                                                                                                                                     |
| Custom Group Names separated by comma. Wildcards (\*) are allowed | Shown for **Assign to Custom Group** when several tenants are selected. The names are looked up in each tenant. Where nothing matches, the restriction is still created but the result reports the assignment as failed.                                     |

Assigning a restriction replaces its existing assignment with the one chosen here.

</details>

{% content-ref url="../enrollment-restriction-templates/README.md" %}
[README.md](../enrollment-restriction-templates/README.md)
{% endcontent-ref %}

## Table Details

Each row is a restriction for specific groups, built from the Graph resource type `deviceEnrollmentPlatformRestrictionConfiguration`, or the tenant's default restriction. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-onboarding-deviceenrollmentplatformrestrictionconfiguration?view=graph-rest-beta#properties).

| Column            | Description                                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------------- |
| Platform Label    | The platform the restriction applies to.                                                                            |
| Priority          | The restriction's position among the tenant's restrictions on that platform, where 1 is the highest. The default restriction shows **Default**. |
| Display Name      | The restriction's name.                                                                                             |
| Description       | The restriction's description.                                                                                      |
| Policy Assignment | Who the restriction applies to: all users, or the assigned groups by name. The default restriction applies to all users and all devices. |

{% hint style="warning" %}
The default restriction applies to anyone no other restriction covers, and is always listed last on each platform. It is read-only here and is managed by the **Device enrollment restrictions** standard.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Restriction</td><td>Opens the restriction in the Add Enrollment Restriction drawer to change its settings, priority, or assignment. Greyed out for the default restriction.</td><td>false</td></tr><tr><td>Save as Template</td><td>Saves the restriction's settings and assignment as an enrollment restriction template. Groups are saved by name, so the template finds the matching groups in each tenant it is deployed to. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>Delete Restriction</td><td>Deletes the restriction from the tenant. Users it applied to fall back to the next restriction by priority, or to the default restriction. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
