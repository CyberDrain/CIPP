# View Group

This page brings together everything CIPP knows about a single group: its properties, who is in it, who owns it, and what it belongs to. The header shows the group's display name along with its email address, object ID and creation date, each of which can be copied, and a **View in Entra** button that opens the same group in the Microsoft Entra admin center.

{% hint style="info" %}
Opening a group in Entra uses your own account rather than the CIPP service account, so you need rights in that tenant to see it: direct assignment in the partner tenant, or a GDAP relationship for a client tenant.
{% endhint %}

## Actions

The **Actions** menu acts on this group. Entries are greyed out rather than hidden when they do not apply.

| Action                                                         | Description                                                                                                                                                                                                       |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Edit Group                                                     | Opens the [edit.md](edit.md "mention") page, where properties, membership and group settings can be changed.                                                                                                      |
| Set Global Address List Visibility                             | Hides the group from the Global Address List, or shows it again. Has no effect on a group synchronised from on-premises Active Directory.                                                                         |
| Only allow messages from people inside the organization        | Requires sender authentication, so the group only accepts mail from within the tenant.                                                                                                                            |
| Allow messages from people inside and outside the organization | Drops the sender authentication requirement, so the group accepts mail from external senders as well.                                                                                                             |
| Set Source of Authority                                        | Switches the group between Cloud Managed and On-Premises Managed. Greyed out for cloud-native groups that have never been synchronised, and a move back to on-premises takes until the next sync cycle to appear. |
| Create template based on group                                 | Creates a reusable group template from this group, copying its name, description, type, membership rule, alias and external sender setting.                                                                       |
| Create Team from Group                                         | Turns the group into a Microsoft Teams team, with the member, messaging and fun settings set in the dialog. Greyed out for anything other than a Microsoft 365 group.                                             |
| Delete Group                                                   | Deletes the group.                                                                                                                                                                                                |

{% hint style="info" %}
A group has to be at least fifteen minutes old before **Create Team from Group** will work, as Microsoft needs the group to have finished provisioning first.
{% endhint %}

## Group Details

The card on the left summarizes the group, opening with its display name and type.

| Field            | Description                                                                                                                           |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name     | The name of the group as it appears to users.                                                                                         |
| Group ID         | The group's object ID in Entra ID.                                                                                                    |
| Email Address    | The group's email address. Shown only when the group has one.                                                                         |
| Description      | The group's description. Shown only when one is set.                                                                                  |
| Group Type       | The kind of group, worked out from the group's underlying flags: Microsoft 365, Security, Mail-Enabled Security or Distribution List. |
| Mail Enabled     | Whether the group can receive email.                                                                                                  |
| Security Enabled | Whether the group can be used to grant access to resources.                                                                           |
| Created Date     | When the group was created.                                                                                                           |
| Synced from AD   | Shown only when the group is synchronised from on-premises Active Directory.                                                          |

{% hint style="info" %}
Group Type is composed rather than returned by Graph, which spreads the same information across the `groupTypes`, `mailEnabled` and `securityEnabled` properties. A group is Microsoft 365 when its `groupTypes` include `Unified`, Mail-Enabled Security when it is both mail and security enabled, Security when it is security enabled alone, and a Distribution List when it is mail enabled alone.
{% endhint %}

## Members

The group's members, listed with their display name, sign-in name, email address and object type. The row action opens the [user](../users/user/ "mention") page, and is available for members that are users, since the same table also lists nested groups, devices and contacts.

## Owners

The group's owners listed the same way, with the same row action through to the user's own page.

## Memberships

The groups this group belongs to, listed with the group name, its types, and whether it is security enabled and mail enabled. Row actions open the group's own page or its edit page.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
