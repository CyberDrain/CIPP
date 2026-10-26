# External Users

This page lists the external and guest users that SharePoint knows about in the selected tenant, and classifies each one against Microsoft Entra so you can tell a healthy guest from a leftover. It draws on both the tenant's external users store, which is populated when a guest first redeems a share, and a sweep of every site's user list, which also catches guests who were given membership but never signed in.

{% hint style="info" %}
The **Guest Type** column tells you what each entry really is. **Entra B2B** is a normal guest with a live Entra account. **Orphaned B2B (not in Entra)** means the Entra guest account has been deleted but SharePoint still holds a reference to them. **SharePoint-only (email authenticated)** is a legacy email-authenticated guest that never had an Entra account at all.
{% endhint %}

## Filters

| Filter          | Shows                                                                    |
| --------------- | ------------------------------------------------------------------------ |
| SharePoint-only | Only legacy email-authenticated guests that never had an Entra account.  |
| Orphaned B2B    | Only guests whose Entra account has been deleted.                        |
| Entra B2B       | Only guests backed by a live Entra guest account.                        |

## Table Details

| Column       | Description                                                                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Display Name | The name SharePoint holds for the guest.                                                                                       |
| Accepted As  | The email address the guest actually accepted the invitation with, which is not always the address they were invited on.        |
| Guest Type   | How the guest is classified against Entra: Entra B2B, Orphaned B2B (not in Entra), or SharePoint-only (email authenticated).    |
| In Entra     | Whether a live Entra guest account was found for this person.                                                                   |
| Source       | Where the entry was found: the tenant's external users store, or membership of a site.                                          |
| Sites        | The sites the guest holds membership of. Blank when they have redeemed a share but hold no site membership.                     |
| When Created | When the entry was created in the external users store. Blank for guests found only through site membership.                    |
| Invited By   | The user who invited the guest. Blank for guests found only through site membership.                                            |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove Guest Access</td><td>Fully removes external access for the selected guest. Deletes their Entra guest account, if one exists, and removes them from every site listed in the <strong>Sites</strong> column, so nothing is left orphaned. You are asked to confirm first. Any sharing links they hold are revoked separately from <a data-mention href="reports/sharing-report.md">sharing-report.md</a>, and the leftover SharePoint store entry ages out on its own. Greyed out unless you have SharePoint site write access and the guest either has an Entra account or holds membership of at least one site.</td><td>true</td></tr></tbody></table>

{% include "../../../.gitbook/includes/feature-request.md" %}
