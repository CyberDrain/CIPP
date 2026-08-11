# Edit Group

The Edit Group page changes the properties, membership, and settings of an existing group. Membership is managed by adding and removing users, groups, contacts, and devices rather than by editing a list, so each save applies the additions and removals you have specified. Which fields appear depends on the group's type, since not every setting applies to every kind of group.

{% hint style="danger" %}
A group synchronised from on-premises Active Directory shows a warning at the top of the page. Changes to those groups belong in the on-premises environment, as edits made here are overwritten by the next synchronisation.
{% endhint %}

## Viewing current membership

A button beside the page title switches between the editing form and a read-only view of the group's current membership. Select **View members** to see who is currently in the group, and **Edit Membership** to return to the form.

| Column              | Description                                                       |
| ------------------- | ----------------------------------------------------------------- |
| Type                | Whether the entry is an Owner, a Member, or a Contact.            |
| User Principal Name | The sign-in name of the user, or the email address for a contact. |
| Display Name        | The name of the user or contact.                                  |

## Group Properties

| Setting          | Description                                                                                                 |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| Display Name     | The name of the group as it appears to users.                                                               |
| Description      | A description of the group's purpose.                                                                       |
| Mail Nickname    | The alias used in the group's email address.                                                                |
| Membership Rules | The rule that determines which objects belong to the group. Shown only for groups using dynamic membership. |

## Add Members

Anything selected here is added to the group when you save. Objects that already belong to the group are filtered out of the lists, so the same member cannot be added twice.

| Setting                       | Description                                                                                                                                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Add Members (Users or Groups) | Adds users or other groups as members. Several can be selected at once.                                                                                                                                            |
| Add Owners                    | Adds users as owners of the group.                                                                                                                                                                                 |
| Add Contacts                  | Adds mail contacts as members. Only Distribution Lists and Mail-Enabled Security groups accept contacts.                                                                                                           |
| Add Devices                   | Adds devices as members. Devices are listed by name, with the operating system shown alongside where it is known. Not offered for Distribution List or Mail-Enabled Security groups, which cannot contain devices. |

{% hint style="info" %}
The **Add Contacts** field is offered for every group type, but Entra ID only allows contacts in Distribution Lists and Mail-Enabled Security groups. Selecting a contact for a Security or Microsoft 365 group returns an error for that contact when you save, while the rest of the changes still apply.
{% endhint %}

## Remove Members

Anything selected here is removed from the group when you save. The lists show only the group's current members, owners, and contacts.

| Setting                          | Description                                                                                                                             |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Remove Members (Users or Groups) | Removes the selected users or groups from the group. Users are listed with their sign-in name, and nested groups with their group type. |
| Remove Owners                    | Removes the selected users as owners.                                                                                                   |
| Remove Contacts                  | Removes the selected mail contacts.                                                                                                     |

## Group Settings

These settings apply to mail-enabled groups, and which of them appear depends on the group's type.

| Setting                                                       | Description                                                                                                                 | Shown for                        |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Group visibility                                              | Whether the group is Public, so anyone can see its content and join, or Private, so membership is controlled by the owners. | Microsoft 365                    |
| Let people outside the organization email the group           | Allows senders from outside your organization to email the group.                                                           | Microsoft 365, Distribution List |
| Send Copies of team emails and events to team members inboxes | Delivers a copy of the group's messages and calendar events to each member's own mailbox.                                   | Microsoft 365                    |
| Hide group mailbox from Outlook                               | Hides the group's mailbox from Outlook clients.                                                                             | Microsoft 365                    |
| Security Enabled                                              | Marks the group as security enabled, so it can be used to grant access to resources as well as for mail.                    | Microsoft 365                    |

## Licenses

Licenses assigned to a group are applied automatically to everyone in it, which is how group-based licensing is managed. Changes can take a few minutes to take effect. This section is shown for Security groups that are not synchronised from on-premises Active Directory, and the licenses the group currently holds are listed above the fields.

| Setting         | Description                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Add Licenses    | Assigns one or more licenses to the group, which are then applied to all of its members.                                        |
| Remove Licenses | Removes one or more of the licenses currently assigned to the group. The list contains only the licenses the group already has. |

## Saving

**Submit** applies your changes. Additions and removals are processed together, and each is reported separately in the result, so a change that cannot be applied is listed as an error while the rest still go through.

{% hint style="info" %}
The five settings under Group Settings are only sent when you have actually changed them, so a toggle you leave alone is not written back. The properties under Group Properties behave differently and are submitted every time, whatever their current value.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
