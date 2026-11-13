# Inactive Users

This report lists accounts that have not signed in for six months or more, so licences sitting on dormant accounts can be found and reclaimed. Interactive sign-ins, non-interactive sign-ins and successful sign-ins are all taken into account, and the most recent of the three decides whether an account counts as inactive.

{% hint style="info" %}
Accounts that have never signed in at all are included, since an account with no sign-in history has by definition not signed in during the period. Days Since Last Sign In is empty for those.
{% endhint %}

{% hint style="info" %}
Guests are left out, since guest activity is recorded differently and would add noise to a list meant to drive licence reclamation. Disabled (blocked) accounts are kept: a dormant account that is already blocked is still a licence-reclamation and cleanup candidate, and **Account Enabled** shows which inactive accounts are already blocked.
{% endhint %}

## Filters

| Filter          | Shows                                    |
| --------------- | ----------------------------------------- |
| Sign-in allowed | Inactive accounts that can still sign in. |
| Sign-in blocked | Inactive accounts already blocked.        |

## Table Details

| Column                                 | Description                                                                                                                                                                                                                                                 |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Display Name                    | The tenant's name.                                                                                                                                                                                                                                          |
| User Principal Name                    | The user's sign-in name.                                                                                                                                                                                                                                    |
| Display Name                           | The user's name.                                                                                                                                                                                                                                            |
| Account Enabled                        | Whether the account is allowed to sign in.                                                                                                                                                                                                                   |
| Last Sign In Date Time                 | The most recent interactive sign-in attempt, where the user signed in themselves. Attempts that failed are recorded here as well as ones that worked.                                                                                                       |
| Last Non Interactive Sign In Date Time | The most recent sign-in attempt made by a client on the user's behalf, such as a mail client refreshing a token. See [Microsoft Learn](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-noninteractive-sign-ins) for what counts. |
| Last Successful Sign In Date Time      | The most recent sign-in that actually succeeded, whether the user signed in themselves or a client did it for them. This is the column to trust when judging whether an account is still in use.                                                            |
| Number Of Assigned Licenses            | How many licences the account holds, which is the figure that turns this report into a reclamation list.                                                                                                                                                    |
| Days Since Last Sign In                | How long the account has been dormant, counted from the most recent of the three sign-in dates.                                                                                                                                                             |
| Last Refreshed Date Time               | When the user data behind this report was last refreshed, which is not the same as when you opened the page.                                                                                                                                                |

{% hint style="warning" %}
The three sign-in columns can disagree with each other. **Last Sign In Date Time** and **Last Non Interactive Sign In Date Time** record attempts, whether or not they succeeded, so an account with a run of failed sign-ins reads as more recently active in those two columns than it really was. **Last Successful Sign In Date Time** is the only one that records access that actually worked.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View User</td><td>Opens the full details page for the selected user.</td><td>false</td></tr><tr><td>Edit User</td><td>Opens the Edit User page for the selected user.</td><td>false</td></tr><tr><td>Block Sign In</td><td>Blocks the account from signing in, without removing it or its data. Greyed out for accounts that are already blocked.</td><td>true</td></tr><tr><td>Offboard User</td><td>Opens the <a data-mention href="../administration/offboarding-wizard.md">offboarding-wizard.md</a> with the selected users already chosen. Several users can be offboarded together, but they must all belong to the same tenant.</td><td>true</td></tr><tr><td>Delete User</td><td>Deletes the account. Deleted accounts remain recoverable from Deleted Items for 30 days.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Removing a licence from a dormant account starts a clock on the data attached to it. A mailbox left unlicensed stops receiving mail and is eventually removed, and OneDrive content follows its own retention schedule. Where the data still matters, convert the mailbox to shared or run the account through the offboarding-wizard.md rather than simply stripping the licence.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
