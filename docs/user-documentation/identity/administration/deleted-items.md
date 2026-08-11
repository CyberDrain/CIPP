---
description: Lists all deleted users, groups and applications in the tenant
---

# Deleted Items

This page lists the directory objects that have been soft-deleted in the tenant and are still recoverable. Nine object types are gathered into one table, so a deletion can be reversed or made permanent without knowing in advance which kind of object it was.

## Table Details

CIPP queries each deleted object type separately and combines the results, adding the Type column so the rows can be told apart.

| Column                   | Description                                                                                                                                                                                                            |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name             | The name the object had when it was deleted.                                                                                                                                                                           |
| Type                     | The kind of object, added by CIPP: Administrative Unit, Application, Certificate Authority Detail, Certificate Based Auth Pki, External User Profile, Group, Pending External User Profile, Service Principal or User. |
| User Principal Name      | The sign-in name, for deleted users. Empty for object types that do not have one.                                                                                                                                      |
| Deleted On               | When the object was deleted.                                                                                                                                                                                           |
| On Premises Sync Enabled | Whether the object was synchronised from on-premises Active Directory.                                                                                                                                                 |

{% hint style="info" %}
Because the table combines nine different Graph resource types, the properties available beyond the columns above differ from row to row. A deleted user carries the full set of user properties, while an administrative unit or a certificate authority record carries its own. The Extended Info flyout is oriented towards deleted users and shows their contact, license and synchronisation details, so it will be sparse for the other types.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Restore Object</td><td>Returns the object to the directory with its original identifier, group memberships and license assignments intact.</td><td>true</td></tr><tr><td>Permanently Delete Object</td><td>Removes the object from the recycle bin. This cannot be undone.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Entra ID keeps soft-deleted objects for 30 days, after which they are removed automatically and cannot be recovered. Anything on this page that still matters should be restored before that window closes.
{% endhint %}

{% hint style="info" %}
Restoring a user does not restore their mailbox content by itself. Exchange Online reconnects the mailbox when the account is restored within the retention window and still holds a license, so check the mailbox afterwards rather than assuming it came back with the account.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
