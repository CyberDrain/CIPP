---
description: Create and manage administrative units and their members
---

# Administrative Units

Administrative units group users, groups and devices so that an admin role can be scoped to just that set instead of the whole tenant. This page lists the tenant's administrative units and lets you create, edit and delete them and manage who is in them.

## Table Details

| Column                         | Description                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| Display Name                   | The name of the administrative unit.                                                             |
| Description                    | The description entered for the unit.                                                            |
| Membership Type                | Assigned (members are added by hand) or Dynamic (members come from a rule).                      |
| Membership Rule                | The rule that selects members, for dynamic units.                                                |
| Membership Rule Processing State | Whether a dynamic unit's rule is running (On) or paused.                                       |
| Visibility                     | Whether anyone in the tenant can see the members, or only admins scoped to the unit.             |
| Is Member Management Restricted | When enabled, only admins with a role scoped to this unit can change the users, groups and devices in it. |
| Members                        | Opens the list of the unit's current members.                                                    |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Administrative Unit</td><td>Opens the unit's settings and members for editing.</td><td>false</td></tr><tr><td>Where is this used</td><td>Shows the Entra and Exchange role assignments scoped to the unit, and lets you grant a time-bound scoped role through PIM (needs Entra ID P2).</td><td>false</td></tr><tr><td>Add Members</td><td>Adds users, groups or devices to an assigned unit. Adding a group adds the group itself, not its members.</td><td>true</td></tr><tr><td>Remove Members</td><td>Removes selected members from an assigned unit.</td><td>false</td></tr><tr><td>Pause dynamic membership</td><td>Stops a dynamic unit's rule. Members stay as they are until it is turned back on.</td><td>false</td></tr><tr><td>Resume dynamic membership</td><td>Turns a paused rule back on, so members are re-evaluated.</td><td>false</td></tr><tr><td>Delete Administrative Unit</td><td>Deletes the unit. Its members are kept, but every role assignment scoped to it stops applying.</td><td>false</td></tr></tbody></table>

## Adding or Editing a Unit

Use **Add Administrative Unit** to create one. You set the display name, description, membership visibility, membership type and whether management is restricted. Dynamic units take a membership rule instead of hand-picked members, and require Entra ID P1. A rule selects users or devices, not both, and groups cannot be added dynamically.

{% hint style="warning" %}
Check **Where is this used** before deleting a unit. A deleted unit can be restored from [Deleted Items](deleted-items.md) for 30 days.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
