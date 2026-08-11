# Inactive Users

This report lists accounts that have not signed in for six months or more, so licenses sitting on dormant accounts can be found and reclaimed. Both interactive and non-interactive sign-ins are taken into account, and the most recent of the two decides whether an account counts as inactive.

{% hint style="info" %}
Accounts that have never signed in at all are included, since an account with no sign-in history has by definition not signed in during the period. Days Since Last Sign In is empty for those.
{% endhint %}

{% hint style="info" %}
Disabled accounts and guests are left out. A disabled account is already handled, and guest activity is recorded differently, so including either would add noise to a list meant to drive license reclamation.
{% endhint %}

## Table Details

| Column                                 | Description                                                                                                                                                                                                                                              |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant                                 | The tenant the user belongs to. Shown when All Tenants is selected.                                                                                                                                                                                      |
| Tenant Display Name                    | The tenant's name.                                                                                                                                                                                                                                       |
| User Principal Name                    | The user's sign-in name.                                                                                                                                                                                                                                 |
| Display Name                           | The user's name.                                                                                                                                                                                                                                         |
| Last Sign In Date Time                 | The most recent interactive sign-in, where the user signed in themselves.                                                                                                                                                                                |
| Last Non Interactive Sign In Date Time | The most recent sign-in performed by a client on the user's behalf, such as a mail client refreshing a token. See [Microsoft Learn](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-noninteractive-sign-ins) for what counts. |
| Number Of Assigned Licenses            | How many licenses the account holds, which is the figure that turns this report into a reclamation list.                                                                                                                                                 |
| Days Since Last Sign In                | How long the account has been dormant, counted from the later of the two sign-in dates.                                                                                                                                                                  |
| Last Refreshed Date Time               | When this report was produced.                                                                                                                                                                                                                           |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View User</td><td>Opens the full details page for the selected user.</td><td>false</td></tr><tr><td>Edit User</td><td>Opens the Edit User page for the selected user.</td><td>false</td></tr><tr><td>Block Sign In</td><td>Blocks the account from signing in, without removing it or its data.</td><td>true</td></tr><tr><td>Delete User</td><td>Deletes the account. Deleted accounts remain recoverable from Deleted Items for 30 days.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Removing a license from a dormant account starts a clock on the data attached to it. A mailbox left unlicensed stops receiving mail and is eventually removed, and OneDrive content follows its own retention schedule. Where the data still matters, convert the mailbox to shared or run the account through the offboarding-wizard.md rather than simply stripping the license.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
