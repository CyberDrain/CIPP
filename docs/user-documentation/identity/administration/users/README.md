---
description: Interact with Microsoft 365 users.
---

# Users

The Users page lists the users in the selected tenant and is the starting point for day to day account management. It covers the same ground as [Microsoft 365 admin center > Active Users](https://admin.microsoft.com/Adminportal/Home#/users), and extends it with actions that would otherwise need the Microsoft Entra admin center, Exchange Online PowerShell or the SharePoint admin center.

## Action Buttons

<details>

<summary>Add User</summary>

Creates a single user in the selected tenant. **Create User** submits the form, and once a user has been created the button changes to **Create Another User** so the drawer can be reused.

A user can only be created in one tenant at a time. With **All Tenants** selected, **Create User** is greyed out and a warning explains that a specific tenant must be chosen from the tenant selector first.

**Starting point**

| Field                             | Description                                                                                                                                                                                                       |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Copy properties from another user | Pre-fills the form from an existing user's name, job, address and contact details. Licences and group memberships are not copied by this selector.                                                                |
| User Template (optional)          | Applies a saved user template, filling in the properties, licences, groups and shared access it defines. Templates are managed on the [user-defaults.md](../user-defaults.md "mention") page. |

**Identity**

| Field               | Description                                                                                                                                  |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| First Name          | The user's given name.                                                                                                                       |
| Last Name           | The user's surname.                                                                                                                          |
| Display Name        | The name shown throughout Microsoft 365. Built from the first and last name until it is edited manually.                                     |
| Username            | The part before the @ symbol. Limited to 64 characters, and may contain letters, numbers and the characters `'` `.` `-` `_` `!` `#` `^` `~`. |
| Primary Domain name | The domain used after the @ symbol, chosen from the tenant's verified domains.                                                               |
| Add Aliases         | Additional addresses, one per line, entered without the domain.                                                                              |

{% hint style="warning" %}
If the username and Primary Domain name together match an existing account's user principal name or one of its email aliases, a warning appears below the domain selector naming that account. It does not block creation, and it is checked against the user list already loaded for the tenant, so a match can go unreported. No warning is not confirmation that the address is free.
{% endhint %}

**Settings**

| Setting                               | Description                                                                                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Create password manually              | When off, CIPP generates a password and returns it in the result. When on, a **Password** field appears for a password of your own.                                            |
| Require password change at next logon | Forces the user to set a new password the first time they sign in.                                                                                                             |
| Enforce Per-User MFA                  | When enabled, sets the per-user MFA state to Enforced after the account is created. This is for tenants without Conditional Access; do not combine with CA-based MFA policies. |
| Usage Location                        | The country the account is licensed in. Required before licences can be assigned, and defaults to the usage location set in your preferences.                                  |
| Licenses                              | The licences to assign. Each option shows how many units are currently available.                                                                                              |
| Remove all licenses                   | Strips every licence from the account, which is mainly useful when a template or a copied user has brought licences in that are not wanted.                                    |

{% hint style="info" %}
When the sherweb.md integration is enabled and a selected licence shows `(0 available)`, a **Purchase new licence?** switch appears along with a **Sherweb License** selector. Choosing this purchases a new licence under your terms with Sherweb and assigns it to the user once it becomes available.
{% endhint %}

**Contact and organisation**

| Field                                              | Description                                                                                                                      |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Job Title, Department, Company Name                | Organisational details written to the directory and shown in the address list.                                                   |
| Street, City, State/Province, Postal Code, Country | The user's postal address.                                                                                                       |
| Mobile #, Business #                               | Contact numbers.                                                                                                                 |
| Alternate Email Addresses                          | Secondary addresses, separated by commas.                                                                                        |
| Set Manager                                        | The user recorded as this account's manager.                                                                                     |
| Set Sponsor                                        | The user recorded as this account's sponsor. Only shown when `sponsor` has been added to the attribute list in your preferences. |
| Copy groups from user                              | Adds the new account to the same groups as the chosen user.                                                                      |
| Add to Groups                                      | Adds the new account to specific groups chosen from the tenant.                                                                  |

{% hint style="info" %}
Extra directory attributes can be added to this form under [user-settings.md](../../../shared-features/menu-bar/user-settings.md "mention"). The list offers `consentProvidedForMinor`, `employeeId`, `employeeHireDate`, `employeeLeaveDateTime`, `employeeType`, `faxNumber`, `legalAgeGroupClassification`, `officeLocation`, `otherMails`, `showInAddressList` and `sponsor`, and each selection adds its own field to the form. Every attribute except `sponsor` appears as a plain text field; `sponsor` appears as the **Set Sponsor** user selector.
{% endhint %}

**Shared mailboxes and calendars**

| Field                      | Description                                                                                                                                                 |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shared Mailboxes           | The shared mailboxes the new user should be given access to. Only shared mailboxes in the tenant can be selected.                                           |
| Shared Mailbox Permissions | Any combination of `Full Access`, `Full Access (no Automapping)`, `Send As` and `Send on Behalf`. Defaults to `Full Access`, which also automaps the mailbox so Outlook adds it on its own; the no-automapping variant grants the same access but leaves adding the mailbox to the user. |
| Shared Calendars           | The shared mailboxes whose calendar the user should be given access to.                                                                                     |
| Shared Calendar Permission | The access level granted on those calendars: `Editor`, `Reviewer`, `Limited Details` or `Availability Only`. Defaults to `Editor`.                          |

{% hint style="info" %}
Exchange cannot add a calendar to someone's Outlook directly, so CIPP grants calendar access with a sharing invitation, which the user accepts by clicking the link in the email they receive. Mailbox access needs no invitation: with Full Access, automapping adds the mailbox to Outlook by itself, unless the no-automapping variant was chosen. Only the permission levels listed above are offered for calendars, as those are the ones Exchange sends an invitation for.

A newly created user is not a usable Exchange recipient for the first few minutes, so both grants are queued as scheduled tasks that run 15 minutes after creation. Their progress, and any failure, can be followed on the [scheduler](../../../tools/scheduler/ "mention")page.
{% endhint %}

**Scheduling and notifications**

| Setting                                | Description                                                                                        |
| -------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Schedule user creation                 | Defers creation to a chosen date instead of running it immediately.                                |
| Scheduled creation Date                | The date the creation task should run.                                                             |
| Send results to Webhook / E-mail / PSA | Delivers the outcome of the scheduled task to the notification channels configured for the tenant. |
| HaloPSA Ticket                         | An existing HaloPSA ticket to add the results to as a note, instead of raising a new ticket. Only shown once **Send results to PSA** is on and the HaloPSA integration is enabled. |
| Reference                              | Free text added to the notification title so the task can be recognised later.                     |

</details>

<details>

<summary>Bulk Add Users</summary>

Creates several users at once from a CSV file or from rows entered by hand.

Set the **Usage Location** and any licences under **Assign License** first, as these apply to every user in the batch. **Download Example CSV** produces a file with the expected column headers: `givenName`, `surName`, `displayName`, `mailNickName`, `domain`, `JobTitle`, `streetAddress`, `PostalCode`, `City`, `State`, `Department`, `MobilePhone` and `businessPhones`, plus any extra attributes added in your preferences. Upload the completed file, or use **Add User Manually** to add rows individually.

Every row appears in the **User Preview** table, where it can be checked and removed before submitting. **Create Users** submits the batch.

As with a single user, the whole batch goes to one tenant. With **All Tenants** selected, **Create Users** is greyed out and a warning explains that a specific tenant must be chosen from the tenant selector first.

</details>

<details>

<summary>Invite Guest</summary>

Invites a single external user as a guest in the tenant.

| Field                  | Description                                                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Display Name           | The name the guest appears under in the directory.                                                                                  |
| E-mail Address         | The address the invitation is sent to and the account is based on.                                                                  |
| Redirect URL           | Where the guest lands after redeeming the invitation. Defaults to `https://myapps.microsoft.com` when left blank.                   |
| Custom invite message  | Optional text included in the invitation email.                                                                                     |
| Send invite via e-mail | Controls whether Microsoft sends the standard guest invitation email. When off, the guest account is created but no email goes out. |

</details>

<details>

<summary>Bulk Invite Guests</summary>

Invites several guests at once.

**Send invite via e-mail** and **Custom invite message** apply to the whole batch. **Download Example CSV** produces a file with the columns `displayName`, `mail` and `redirectUri`. Upload the completed file, or use **Add Guest Manually** to add rows individually. Rows appear in the **Guest Preview** table for checking before the invitations are sent.

</details>

<details>

<summary>View Logs</summary>

Opens a flyout showing the CIPP log entries recorded for user actions in this tenant. Entries written by scheduled tasks are excluded, so this shows the actions taken from the interface.

</details>

## Filters

The **Filters** menu offers presets that narrow the rows already loaded into the table. See table-features.md for how filters behave generally.

| Filter           | Shows                                            |
| ---------------- | ------------------------------------------------ |
| Account Enabled  | Accounts that are able to sign in.               |
| Account Disabled | Accounts that have been blocked from signing in. |
| Guest Accounts   | Accounts with a user type of Guest.              |

## Table Details

The properties returned are for the Graph resource type `user`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View User</td><td>Opens the <a data-mention href="user/">user</a> page for the selected user.</td><td>false</td></tr><tr><td>Edit User</td><td>Opens the <a data-mention href="user/edit.md">edit.md</a> page, where properties, licences and group memberships can be changed.</td><td>false</td></tr><tr><td>View in Entra</td><td>Opens the user in the Microsoft Entra admin center in a new tab.</td><td>false</td></tr><tr><td>Create Template from User</td><td>Creates a reusable user template from this account, copying its job title, department, location, licences and group memberships. Prompts for a template name and whether the template becomes the default for the tenant.</td><td>true</td></tr><tr><td>Research Compromised Account</td><td>Opens the <a data-mention href="user/bec.md">bec.md</a> view, which gathers the common indicators of compromise for the account in one place.</td><td>false</td></tr><tr><td>Create Temporary Access Pass</td><td>Issues a time limited passcode the user can sign in with, typically to enrol a passwordless method. The lifetime is validated against the tenant's policy, one-time use can be requested, and the pass can be set to become valid at a future date and time.</td><td>true</td></tr><tr><td>Re-require MFA registration</td><td>Clears the user's registered multi-factor methods so they must register again.</td><td>true</td></tr><tr><td>Send MFA Push</td><td>Opens a dialog showing the user's registered MFA methods and sends a push notification to Microsoft Authenticator on confirm. If Authenticator push is not registered but a code-based method is, asks for a typed OTP code to verify instead. Confirm is disabled if neither is registered.</td><td>true</td></tr><tr><td>Set Per-User MFA</td><td>Sets the legacy per-user MFA state to Enforced, Enabled or Disabled, independently of any Conditional Access policy.</td><td>true</td></tr><tr><td>Convert Mailbox</td><td>Converts the mailbox to a User, Shared, Room or Equipment mailbox, keeping its existing content.</td><td>true</td></tr><tr><td>Enable Online Archive</td><td>Turns on the archive mailbox so older mail can be moved out of the primary mailbox.</td><td>true</td></tr><tr><td>Set Out of Office</td><td>Sets automatic replies to Enabled, Disabled or Scheduled, with separate internal and external messages. When scheduled, the period can also block the user's calendar, decline new invitations, and decline and cancel meetings already booked. Selecting a single user pre-fills the form with their current settings; with several selected, it starts blank.</td><td>true</td></tr><tr><td>Add to Group</td><td>Adds the user to one or more groups in the tenant.</td><td>true</td></tr><tr><td>Manage Licenses</td><td>Adds, removes or replaces licences on the account, with the option to remove or replace everything currently assigned.</td><td>true</td></tr><tr><td>Disable Email Forwarding</td><td>Clears any forwarding set on the mailbox, both internal and external.</td><td>true</td></tr><tr><td>Pre-provision OneDrive</td><td>Creates the user's OneDrive ahead of their first sign-in, so it is ready when they need it.</td><td>true</td></tr><tr><td>Set OneDrive External Sharing</td><td>Sets how far the user's OneDrive can be shared outside the organisation: no external sharing, signed-in guests only, anyone links, or existing guests only.</td><td>true</td></tr><tr><td>Add OneDrive Shortcut</td><td>Adds a shortcut to a chosen SharePoint site into the user's OneDrive, either at the OneDrive root or inside the Shortcuts folder used by Microsoft's own OneDrive and SharePoint interfaces.</td><td>true</td></tr><tr><td>Migrate OneDrive Shortcuts</td><td>Moves every shortcut currently sitting in the user's OneDrive root into the Shortcuts folder.</td><td>true</td></tr><tr><td>Set Sign In State</td><td>Blocks or restores the account's ability to sign in. The current state is pre-selected, and submitting an unchanged state is rejected.</td><td>true</td></tr><tr><td>Reset Password</td><td>Sets a new random password and returns it in the result, optionally requiring a change at the next sign-in.</td><td>true</td></tr><tr><td>Require Password Change at Next Logon</td><td>Requires the user to change their password at next sign-in without resetting it. Not supported for directory-synced accounts.</td><td>true</td></tr><tr><td>Set Password Expiration</td><td>Enables or disables password expiry for the account. With expiry enabled, a password older than the organisation's expiry period prompts the user to change it at their next sign-in.</td><td>true</td></tr><tr><td>Clear Immutable ID</td><td>Clears the on-premises anchor so the account can be matched to a different directory object. Only offered for accounts that are no longer synchronised but still hold an immutable ID. Greyed out for accounts that are still synchronised, and for those with no immutable ID to clear.</td><td>true</td></tr><tr><td>Set Source of Authority</td><td>Switches the account between Cloud Managed and On-Premises Managed. Only offered for accounts that are, or once were, synchronised, and a move back to on-premises takes until the next sync cycle to appear. Greyed out for cloud-native accounts that have never been synchronised.</td><td>true</td></tr><tr><td>Reprocess License Assignments</td><td>Asks Entra to re-evaluate the group-based licences that apply to the user, adding or removing licences as the group membership dictates.</td><td>true</td></tr><tr><td>Revoke all user sessions</td><td>Invalidates the account's refresh tokens so every device has to sign in again.</td><td>true</td></tr><tr><td>Delete User</td><td>Deletes the account. Deleted accounts remain recoverable from Deleted Items for 30 days.</td><td>true</td></tr><tr><td>Edit Properties</td><td>Opens the patch-wizard.md with the selected users loaded, for changing the same properties across all of them.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Most of these actions present a confirmation dialog before anything is sent, and any options the action needs are set in that dialog.

Actions you do not have permission for stay in the menu but are greyed out. Convert Mailbox, Enable Online Archive, Set Out of Office and Disable Email Forwarding need Exchange mailbox write access, Add to Group needs group write access, and most of the rest need user write access. Send MFA Push, Research Compromised Account and Set Source of Authority carry no permission condition of their own.
{% endhint %}

{% hint style="warning" %}
Temporary Access Pass must be enabled in the tenant's authentication method policy before a pass can be created, otherwise the action fails. CIPP checks the policy when the dialog opens and warns you if it is not enabled. See [Configure Temporary Access Pass to register passwordless authentication methods](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass) for the tenant side of the configuration.
{% endhint %}

{% hint style="danger" %}
The standalone Add User page at `/identity/administration/users/add`, reached by URL only, and its support for pre-filling the form from URL query string parameters (including the AutoTask LiveLink pattern this page used to document) have been removed. User creation from the Users page now opens the Add User drawer described above, which does not read query string parameters. A PSA or documentation system linking to that URL to launch a pre-filled user creation will need a different integration approach.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
