# Domain Migration

This page moves users, and optionally groups, from one domain to another in a single tenant, for example after a rebrand or to move them off the tenant's onmicrosoft.com domain. It changes each user's sign-in name (UPN) and primary email address together, because Microsoft no longer supports a sign-in name that differs from the primary email address, and keeps the old address as an alias so mail sent to it still arrives. You find it under **Tools > Tenant Tools**. It needs the `Tenant.DomainMigration.ReadWrite` permission, which the built-in editor and admin roles include.

## Options

| Option                                | What it does                                                                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Move from domain / Move to domain     | The domain the users are on now, and the verified domain they move to. The part before the @ stays the same: `jane@old.com` becomes `jane@new.com`.             |
| Skip users and groups whose new address is already in use | On by default. Leaves out a user or group when another user, group or contact already has the new sign-in name or email address.          |
| Include shared mailboxes              | Also lists shared mailboxes on the old domain.                                                                                                                  |
| Include Microsoft 365 groups and distribution lists | Off by default. Also lists Microsoft 365 groups, distribution lists, mail-enabled security groups and dynamic distribution lists whose primary email address is on the old domain. Groups have no sign-in name, so only their email address changes. |

## Preview and move

Select **Preview changes** to list every user and group the move would change, with their current and new sign-in name and email address. Nothing is changed yet. Select the rows to move in the table, then choose **Move to the new domain** from the bulk actions. The results show what happened for each user and group, and the preview reloads afterwards.

Users and groups are skipped, with the reason shown, when:

* a user's sign-in name and primary email address would not match after the move, for example `jsmith@old.com` with the address `john.smith@old.com`. Make them match first, then move the user.
* they are synced from on-premises Active Directory. Change their sign-in name and email addresses there and let them sync. Users and groups whose source of authority has been moved to the cloud are not skipped.
* the new address is already in use and **Skip users and groups whose new address is already in use** is on.
* one of their email addresses contains a `%` sign. Change them in the Exchange admin center.
* a user holds a privileged admin role and your CIPP role cannot manage privileged users.

## Fix users whose sign-in name and email address differ

Users skipped because their sign-in name and primary email address differ can be fixed from the same table. Select them and choose one of these actions:

* **Use the sign-in name as the email address** makes the user's sign-in name their primary email address. The current primary address stays as an alias, so mail sent to it still arrives.
* **Use the email address as the sign-in name** makes the user's primary email address their sign-in name. The address must be on a verified domain of the tenant. The user has to sign in again with the new name.

Neither action removes an email address. The preview reloads afterwards, so you can then move the fixed users.

## Add the new domain as an alias only

Choose **Add the new domain as an alias only** under **What to do** to give mailboxes an address on the new domain without moving anyone yet, for example so they can receive mail on the new domain before you switch them over. Each mailbox and group whose primary email address is on the old domain gets the same address on the new domain as an extra address: `jane@old.com` also receives mail sent to `jane@new.com`. Sign-in names and primary email addresses do not change, so nobody has to sign in again. Users without a mailbox are not listed.

Select **Preview changes**, select the rows, then choose **Add the alias** from the bulk actions. A mailbox or group is skipped, with the reason shown, when it already has the new address, when the new address belongs to someone else and **Skip users and groups whose new address is already in use** is on, when it is synced from on-premises Active Directory (unless its source of authority is in the cloud, or its Exchange attributes are managed in the cloud), or when one of its addresses contains a `%` sign. Users whose sign-in name and email address differ are not skipped in this mode.

You can also open this page from the **Domains** page: the **Move users to this domain** action on a verified domain opens it with that domain already chosen as the domain to move to.

{% hint style="warning" %}
A changed sign-in name takes effect straight away: the user has to sign in again with the new name on every device and app. Let users know before you move them.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
