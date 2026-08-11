# View Individual User

This page brings together everything CIPP knows about a single user, and is where most investigation starts before an action is taken. The header shows the user's display name along with their user principal name, object ID and creation date, each of which can be copied, and a **View in Entra** button that opens the same account in the Microsoft Entra admin center. The **Actions** menu in the header offers the same [#table-actions](../#table-actions "mention") available from the Users list, minus the ones that navigate elsewhere: View User, Edit User and Research Compromised Account are reachable from the tabs instead.

Apart from the profile photo, the MFA method controls and the role removal action described below, everything on this page is read only. Use the Edit User tab to change the account.

## Tabs

{% content-ref url="edit.md" %}
[edit.md](edit.md)
{% endcontent-ref %}

{% content-ref url="exchange.md" %}
[exchange.md](exchange.md)
{% endcontent-ref %}

{% content-ref url="bec.md" %}
[bec.md](bec.md)
{% endcontent-ref %}

{% content-ref url="conditional-access.md" %}
[conditional-access.md](conditional-access.md)
{% endcontent-ref %}

## User Details

The card on the left holds the account's directory properties. The work, contact and address sections only show the fields that have a value, and display a short placeholder when the account has none of them.

| Field                                                       | Description                                                                 |
| ----------------------------------------------------------- | --------------------------------------------------------------------------- |
| Profile photo                                               | The user's Entra ID photo, or their initials when no photo is set.          |
| Account Enabled                                             | Whether the account is currently able to sign in.                           |
| Synced from AD                                              | Whether the account is synchronised from on-premises Active Directory.      |
| Display Name                                                | The name shown throughout Microsoft 365.                                    |
| Email Address                                               | The addresses on the account, taken from its proxy addresses.               |
| User Principal Name                                         | The sign-in name for the account.                                           |
| Licenses                                                    | The licenses currently assigned. A note is shown when the account has none. |
| Job Title, Company Name, Department, Manager                | The account's work information.                                             |
| Mobile Phone, Business Phones                               | The contact numbers on the account.                                         |
| Street Address, City, Postal Code, Country, Office Location | The account's address information.                                          |

{% hint style="info" %}
Buttons below the photo change or remove it. Uploads must be JPEG or PNG and no larger than 4 MB, and the new photo appears as soon as it has been written to Entra ID.
{% endhint %}

## Latest Logon

The most recent sign-in recorded for the user, shown as success or failure along with the address it came from and the application that was signed in to. Expanding the entry adds the client app used, the operating system or browser detected, the MFA method used and any additional detail Entra recorded against the result. When the sign-in carries location data, the expanded view also plots it on a map alongside the city, state and country or region.

**More Sign-In Logs** opens a dialog with the user's last 50 sign-ins, listing the time, result, IP address, client app, target resource, error code and location for each. The location is a button that opens a map of where the sign-in came from.

{% hint style="info" %}
Sign-in logs require Microsoft Entra ID P1 or higher. Without it this card reports an error rather than data, and the same applies to the Applied Conditional Access Policies card, which is built from the same sign-in record.
{% endhint %}

## Applied Conditional Access Policies

The Conditional Access policies that applied successfully during the sign-in shown above. This is a record of one sign-in rather than a list of every policy targeting the user, so a policy that did not apply on that occasion will not appear here. Expanding an entry shows the grant controls and session controls the policy enforced, and the conditions that were satisfied.

The card reports separately when the sign-in applied no policies at all and when no policy data is available.

{% hint style="info" %}
To see how a policy would behave for this user rather than how one behaved on a single sign-in, use the conditional-access.md tab.
{% endhint %}

## Multi-Factor Authentication Devices

Every authentication method registered against the account, other than the password itself. Each entry names the method type and the detail that distinguishes it, and shows when the method was last used where Graph reports it.

| Method                                 | Shown alongside the method name                                                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Microsoft Authenticator                | The device name registered with the app.                                                                                                |
| Microsoft Authenticator (passwordless) | The device name. This registration type has been retired by Graph but still appears on users who registered before the two were merged. |
| Phone                                  | The number and which slot it occupies, such as mobile, alternate mobile or office.                                                      |
| Passkey (FIDO2)                        | The key's model, or its name where no model is reported.                                                                                |
| Software OATH token                    | The name given to the registration. Any app producing time-based codes appears here, not just Microsoft Authenticator.                  |
| Hardware OATH token                    | The token's serial number, which Graph only returns when the device relationship is expanded.                                           |
| Email                                  | The address used for verification.                                                                                                      |
| Windows Hello for Business             | The name of the registration.                                                                                                           |
| Platform credential                    | The name, or the platform where no name is set.                                                                                         |
| Temporary Access Pass                  | Nothing further, as Graph returns no identifying detail.                                                                                |
| QR code                                | Nothing further, as Graph returns only the identifier and last used date.                                                               |
| External provider                      | The name of the registration.                                                                                                           |

A method type CIPP does not yet recognize still appears, labelled with the type name Graph returned.

Two markers can appear on a method:

| Marker           | Meaning                                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| User default     | The method matches the user's chosen second factor.                                                                            |
| System-preferred | The method matches the one Microsoft would select while system-preferred multifactor authentication is enabled for the tenant. |

Both preferences are held against a method type rather than an individual registration, so every method of a preferred type carries the marker. A mobile number backs both SMS and voice, for example, so it is marked for either.

Expanding a method shows its device name, app version, creation date and the underlying Graph method type.

### Managing methods

The bin icon on a method removes that single registration, leaving the user's other methods intact.

**Set Default MFA Method** sets the user's preferred second factor. The list only offers preferences the user can actually satisfy, drawn from what they have registered: Microsoft Authenticator push, an authenticator app or hardware token code, SMS, and voice calls to the mobile, alternate mobile or office number. Methods such as passkeys, Windows Hello for Business, email and Temporary Access Pass cannot be a default second factor, so a user registered only with those has the button disabled.

Both controls require user write permissions.

{% hint style="warning" %}
While system-preferred multifactor authentication is enabled, Microsoft selects the strongest registered method at sign-in and the user's chosen default is not used.
{% endhint %}

## Memberships

Two cards list what the account belongs to, each showing a count in its header.

**Groups** lists the groups the user is a member of, with the group name, its types, and whether it is security enabled and mail enabled. The row action opens the [edit.md](../../groups/edit.md "mention") page for that group, where the membership itself can be changed.

**Admin Roles** lists the directory roles assigned to the user, with the role name and description. The row action removes the user from that role, and requires role write permissions.

## Managed Devices

The Intune managed devices registered to this user, matched on their user principal name. Each row shows the device name, operating system, OS version and management type, and the row action opens the device.md page. The card reports separately when the user has no managed devices and when the device lookup failed.

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
