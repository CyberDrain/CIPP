# Edit User

This page changes an existing user's properties, licenses and group memberships in one submission. The header carries the same details as the [.](./ "mention") tab: display name, user principal name, object ID, creation date and a **View in Entra** button. **Submit** applies every change on the page at once.

{% hint style="danger" %}
An account synchronised from on-premises Active Directory shows a warning at the top of the page. Graph accepts some of these edits, but the next directory synchronisation overwrites them, so changes to a synced account belong in the on-premises environment.
{% endhint %}

## Identity

| Field               | Description                                                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First Name          | The user's given name.                                                                                                                                  |
| Last Name           | The user's surname.                                                                                                                                     |
| Display Name        | The name shown throughout Microsoft 365. Unlike the Add User form, this is not rebuilt from the first and last name, so it keeps whatever it is set to. |
| Username            | The part before the @ symbol. Limited to 64 characters, and may contain letters, numbers and the characters `'` `.` `-` `_` `!` `#` `^` `~`.            |
| Primary Domain name | The domain used after the @ symbol, chosen from the tenant's verified domains.                                                                          |
| Add Aliases         | Additional addresses, one per line, entered without the domain.                                                                                         |

{% hint style="warning" %}
The user principal name is rebuilt from **Username** and **Primary Domain name** on every submission, so changing either renames the account's sign-in name. The old address remains as an alias, but anything keyed to the sign-in name, including saved credentials and existing sessions, is affected.
{% endhint %}

{% hint style="info" %}
Aliases entered here are added to the account. This form does not remove aliases, so clearing the box leaves the existing ones in place.
{% endhint %}

## Settings

| Setting                               | Description                                                                                                                                                               |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Create password manually              | Reveals a **Password** field. The password is only changed when one is entered here, so an edit that leaves this off makes no change to the existing password.            |
| Require password change at next logon | Forces the user to set a new password the next time they sign in.                                                                                                         |
| Usage Location                        | The country the account is licensed in. Required before licenses can be assigned, and falls back to the usage location set in your preferences when the account has none. |
| Licenses                              | The licenses the account should hold after the edit. Anything selected is added and anything currently assigned but not selected is removed.                              |
| Remove all licenses                   | Strips every license from the account and ignores whatever is selected in the license box.                                                                                |

{% hint style="info" %}
Emptying the **Licenses** box on its own does nothing, because an edit with no licenses selected and this switch off is treated as no license change at all. Use **Remove all licenses** to take the last license off an account.
{% endhint %}

{% hint style="info" %}
When the [sherweb.md](../../../../cipp/integrations/sherweb.md "mention")d integration is enabled and a selected license shows `(0 available)`, a **Purchase new license?** switch and a **Sherweb License** selector appear. The purchase is placed immediately and the assignment is queued as a scheduled task, so the license lands on the account shortly afterwards rather than as part of this submission.
{% endhint %}

## Contact and organization

| Field                                              | Description                                                                                                                      |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Job Title, Department, Company Name                | Organizational details written to the directory and shown in the address list.                                                   |
| Street, City, State/Province, Postal Code, Country | The user's postal address.                                                                                                       |
| Mobile #, Business #                               | Contact numbers.                                                                                                                 |
| Alternate Email Addresses                          | Secondary addresses, separated by commas.                                                                                        |
| Set Manager                                        | The user recorded as this account's manager.                                                                                     |
| Set Sponsor                                        | The user recorded as this account's sponsor. Only shown when `sponsor` has been added to the attribute list in your preferences. |

{% hint style="info" %}
Emptying one of these boxes clears the property in Entra ID, rather than leaving it as it was. This applies only to fields you actually edit during this visit: a field that was already empty when the page loaded is left alone, so the form does not wipe properties it was never asked about. The fields that behave this way are First Name, Last Name, Job Title, Department, Company Name, Mobile #, Business #, Street, City, State/Province, Postal Code, Country and Alternate Email Addresses. Display Name cannot be cleared this way.
{% endhint %}

## Group membership

| Field                 | Description                                                                                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Copy groups from user | Copies another user's group memberships onto this account. Groups that cannot be copied, such as dynamic groups, synchronised groups and memberships the user already holds, are reported in the result rather than silently skipped. |
| Add to Groups         | Adds the account to the groups selected. The list only offers groups the user is not already a member of.                                                                                                                             |
| Remove from Groups    | Removes the account from the groups selected, chosen from the groups it currently belongs to.                                                                                                                                         |

{% hint style="info" %}
Group changes are applied in the order they appear above: the copy runs first, then additions, then removals. Distribution lists and mail-enabled security groups are handled through Exchange rather than Graph, which CIPP works out per group at the time of the change.
{% endhint %}

## Custom attributes and custom data

Any directory attributes added under [user-settings.md](../../../../shared-features/menu-bar/user-settings.md "mention") appear here as their own fields, pre-filled with the account's current values. [custom-data](../../../../cipp/custom-data/ "mention") attributes mapped for manual entry against users in this tenant appear under a **Custom Data** heading, with the field type matching how the attribute was defined.

## Scheduling and notifications

| Setting                                | Description                                                                                                                   |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Schedule this user edit                | Defers the edit to a chosen date instead of applying it immediately, which suits changes tied to a start date or a departure. |
| Scheduled edit date                    | The date the edit should run.                                                                                                 |
| Send results to Webhook / E-mail / PSA | Delivers the outcome of the scheduled edit to the notification channels configured for the tenant.                            |
| Reference                              | Free text added to the notification title so the task can be recognized later.                                                |

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
