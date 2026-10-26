# User Preferences

The Preferences page holds the interface settings that control how CIPP looks and behaves for you, along with defaults used elsewhere in the application. Most settings on this page can be saved either for your own account or for all users of the instance, chosen from the Actions card before saving. Where a setting is saved for all users, an individual user's own preference takes precedence over it.

The page opens on whichever scope currently applies to you: your own settings if you have saved any, and the all-users settings if you have not.

## General Settings

| Setting                                   | Description                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Default usage location for users          | The country pre-selected as the usage location when creating a new user. Required.                                                                                                                                                                                                                                                                                                           |
| Default Page Size                         | How many rows tables show per page by default, chosen from 25, 50, 100, or 250. Required.                                                                                                                                                                                                                                                                                                    |
| Table view on small screens               | How tables present themselves when the window is narrow: **Automatic (cards on mobile)** shows a card list below roughly 900px and the classic table above it, **Always card list** shows cards at every width, and **Always classic table** keeps the table at every width. See [mobile-layout.md](../mobile-layout.md "mention").                                                                             |
| Default test suite on the Home page       | The test suite whose results are shown on the Home page by default, chosen from your saved test reports.                                                                                                                                                                                                                                                                                     |
| Added Attributes when creating a new user | Additional user attributes to make available on the new user form. Anything selected here appears as an extra field when creating a user. The available attributes are `consentProvidedForMinor`, `employeeId`, `employeeHireDate`, `employeeLeaveDateTime`, `employeeType`, `faxNumber`, `legalAgeGroupClassification`, `officeLocation`, `otherMails`, `showInAddressList`, and `sponsor`. |
| Save last used table filter               | When enabled, the filter you last applied to a table is remembered and re-applied the next time you open it.                                                                                                                                                                                                                                                                                 |

{% hint style="info" %}
**Default Page Size** sets the starting value only. An individual table's own rows-per-page control offers 500 as well, and choosing it there applies for as long as you stay on that page.
{% endhint %}

## Navigation Settings

| Setting                | Description                                                           |
| ---------------------- | --------------------------------------------------------------------- |
| Show Sidebar Bookmarks | Shows your bookmarked pages in the sidebar.                           |
| Show Popover Bookmarks | Shows your bookmarked pages in a popover opened from the menu bar.    |
| Bookmark Reorder Mode  | How bookmarks are reordered: with Arrow Buttons, or by Drag and Drop. |
| Compact Navigation     | Reduces the size of the navigation menu so more of it fits on screen. |

## Offboarding Default Settings

Sets which offboarding options are pre-selected when you offboard a user, so that routine offboardings do not have to be configured each time. These are defaults only and can still be changed for an individual offboarding.

A label on the card indicates which defaults are currently in effect: **Using Tenant Defaults**, **Using User Defaults**, **Using All Users Defaults**, or **Using Default Settings** where none have been saved.

| Setting                                       | Description                                                            |
| --------------------------------------------- | ---------------------------------------------------------------------- |
| Convert to Shared Mailbox                     | Converts the user's mailbox to a shared mailbox.                       |
| Remove from all groups                        | Removes the user from every group they belong to.                      |
| Remove group ownership                        | Removes the user as owner of every group they own. The replacement owner is chosen in the wizard itself. |
| Hide from Global Address List                 | Hides the user's mailbox from the address list.                        |
| Remove Licenses                               | Removes all licences assigned to the user.                             |
| Cancel all calendar invites                   | Cancels the meetings the user has organised.                           |
| Revoke all sessions                           | Signs the user out of all active sessions.                             |
| Remove users mailbox permissions              | Removes the permissions the user holds on other mailboxes.             |
| Remove users calendar permissions             | Removes the permissions the user holds on other calendars.             |
| Remove all Rules                              | Removes the inbox rules on the user's mailbox.                         |
| Reset Password                                | Resets the user's password.                                            |
| Keep copy of forwarded mail in source mailbox | Where mail is being forwarded, retains a copy in the original mailbox. |
| Delete User                                   | Deletes the user account.                                              |
| Wipe Mobile Devices (account data only)       | Wipes the Exchange account data from the user's registered mobile devices, without removing the devices themselves. |
| Remove all Mobile Devices                     | Removes the user's registered mobile devices.                          |
| Disable Sign in                               | Blocks the user from signing in.                                       |
| Remove all MFA Devices                        | Removes the user's registered multi-factor authentication methods.     |
| Remove Teams Phone DID                        | Removes the phone number assigned to the user in Teams.                |
| Clear Immutable ID                            | Clears the user's immutable ID.                                        |
| Disable OneDrive Sharing Links                | Disables the sharing links the user created in OneDrive.               |
| Out of Office Message                         | Default automatic reply for offboardings. Leave blank to not set. Supports CIPP `%variable%` tokens (for example `%tenantname%` and tenant custom variables), which are resolved when the offboarding job runs. `%username%` is not the offboarded user. |

An Out of Office message alone is enough for these defaults to count as configured for the user vs all-users precedence.

A **Send results to** section chooses where the outcome of an offboarding is reported, with options for Webhook, E-mail, PSA, and Push notification.

{% hint style="info" %}
If a tenant has its own offboarding defaults saved, those replace your personal defaults entirely for that tenant, including when the tenant message field is empty.
{% endhint %}

## Push Notification Devices

Lists the browsers and installed apps you have registered to receive push notifications from CIPP, and registers the one you are using now. Notifications are per person: a scheduled task, alert, offboarding or JIT admin grant with **Push (notify me)** selected notifies the devices registered by whoever created it, and nobody else. Each browser and each installed copy of the app counts as its own device.

Push needs at least one device registered here. Until you have one, the post execution actions on the scheduler and the alert forms do not offer **Push (notify me)**, and their helper text points you to this card. Once a device is registered, the same helper text says how many devices will be notified. A scheduled task, alert, report schedule or offboarding that asks for Push without a registered device is not saved, and the message returned points back here.

| Column      | Description                                                                                                                                              |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Device Name | The operating system and browser the device registered from, with **(app)** added for an installed copy of CIPP. The browser you are using now is marked **(this device)**. |
| Created     | When the device was registered.                                                                                                                          |

| Control                | Description                                                                                                                                                                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable on this device  | Asks the browser for notification permission and registers this device. Greyed out, with the reason shown when you hover over it, if the browser does not support push notifications, if notifications are blocked for CIPP in the browser settings, if you are impersonating a role, or if push notifications are not ready on the instance yet. On iOS it is only available once CIPP has been added to the Home Screen and opened from there. While the browser's permission prompt is open a message tells you CIPP is waiting for it, and if you dismiss or refuse the prompt an error says notification permission was not granted and that you need to allow notifications for the site in your browser settings. |
| Send test notification | Sends a test notification to every device you have registered, after you confirm.                                                                                                                                                                                                                 |
| Remove device          | A row action that stops notifications to that device, after you confirm. A device can be removed from any browser; the registration is deleted, not the browser's permission.                                                                                                                   |

{% hint style="info" %}
A device the browser has silently dropped, for example after the site data was cleared, is removed from the list automatically the next time a notification to it fails.
{% endhint %}

## Portal Links Configuration

Chooses which Microsoft portal shortcuts appear in the tenant information flyout. All are enabled by default; switch off any you do not use to shorten the list.

The available portals are M365, Exchange, Entra, Teams, Azure, Intune, SharePoint, Security, Purview, Power Platform, and Power BI. The **Manage Tenant** entry is always shown and cannot be switched off. See [tenant-select.md](tenant-select.md "mention").

**Preselect my account (login_hint)** is switched off by default. Turn it on and the Microsoft portal links in the tenant selector and on the dashboard open with the account you signed in to CIPP with preselected, instead of whichever account the browser or device last used.

## Developer Options

Diagnostic options intended for troubleshooting and development.

| Option               | Description                                                                                                                                         |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| TanStack Query Tools | Enables or disables the query developer tools, used for inspecting how data is fetched and cached.                                                  |
| Advanced Views       | Enables or disables advanced views, which reveal diagnostic pages that are otherwise hidden from day-to-day use, such as audit-log Search Coverage. |

{% hint style="info" %}
These two take effect the moment you click them, and are not part of what the **Save Changes** button commits. They are stored in the browser you are using, so they apply only to you on this device and cannot be set for all users.
{% endhint %}

## CIPP Roles

A read-only card lists the CIPP roles held by the account you are signed in as, so you can confirm what your access allows. Roles cannot be changed here.

## Saving Your Preferences

The Actions card controls who your changes apply to and commits them.

| Control       | Description                                                                                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| User selector | Chooses whether the settings are saved for Current User or for All Users. Selecting a different option reloads the page's values to show the settings that apply to that scope. |
| Save Changes  | Saves the settings for the selected scope. The button is unavailable while any required field is empty or invalid, and a message confirms the save or reports an error.         |

{% include "../../../../.gitbook/includes/feature-request.md" %}
