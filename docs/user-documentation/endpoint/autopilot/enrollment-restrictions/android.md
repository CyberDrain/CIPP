# Android

Lists the Android device platform restrictions on the selected tenant that apply to specific groups, followed by the tenant's default restriction for Android.

Intune stores each Android restriction as two sets of settings under one name: one for Android Enterprise (work profile) and one for Android device administrator. CIPP shows them as a single row, and creates, edits, deletes, and saves them as templates together.

## Action Buttons

<details>

<summary>Add Restriction</summary>

Opens the Add Enrollment Restriction drawer for Android. The tenant, name, priority, description, and assignment fields are described on [README.md](README.md "mention"). The platform settings are split into two sections.

**Android Enterprise (work profile)**

| Field                          | Description                                                                                         |
| ------------------------------ | --------------------------------------------------------------------------------------------------- |
| Block platform                 | Stops users the restriction applies to from enrolling Android devices with a work profile.         |
| Block personally owned devices | Stops users the restriction applies to from enrolling personally owned devices with a work profile. |
| Minimum OS version             | The oldest Android version allowed to enrol, for example `13.0`. Leave blank for no minimum.       |
| Maximum OS version             | The newest Android version allowed to enrol. Leave blank for no maximum.                           |

**Android device administrator**

| Field                                         | Description                                                                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Block platform                                | Stops users the restriction applies to from enrolling with Android device administrator. On by default.                    |
| Block personally owned devices                | Stops users the restriction applies to from enrolling personally owned devices with Android device administrator.          |
| Minimum OS version                            | The oldest Android version allowed to enrol with device administrator. Leave blank for no minimum.                         |
| Maximum OS version                            | The newest Android version allowed to enrol with device administrator. Leave blank for no maximum.                         |
| Blocked manufacturers (device administrator) | Manufacturers whose devices cannot enrol with device administrator. Type a name, for example Samsung, and press Enter.     |

</details>

{% hint style="info" %}
Where one of the two parts of an Android restriction is missing, for example because it was deleted in Intune, editing the restriction shows a warning and saving it creates the missing part.
{% endhint %}

## Table Details

The columns are the same as on [README.md](README.md "mention").

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Restriction</td><td>Opens the restriction in the Add Enrollment Restriction drawer to change its settings, priority, or assignment. Greyed out for the default restriction.</td><td>false</td></tr><tr><td>Save as Template</td><td>Saves both parts of the restriction and its assignment as an enrollment restriction template. Groups are saved by name, so the template finds the matching groups in each tenant it is deployed to. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>Delete Restriction</td><td>Deletes both parts of the restriction from the tenant. Users it applied to fall back to the next restriction by priority, or to the default restriction. Greyed out for the default restriction.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
