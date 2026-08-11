# Shared Mailbox with Enabled Account

This report lists the shared mailboxes in the selected tenant whose underlying user account can still sign in. A shared mailbox is meant to be reached through delegation rather than signed into directly, so an enabled account behind one is an unnecessary sign-in surface and is flagged by most security baselines.

## Filters

The table opens with a filter on **Account Enabled** set to `Yes`. This matches what the report already returns, since mailboxes whose account is disabled are left out.

## Table Details

The report pairs each of the tenant's shared mailboxes with its user account and returns only those where the account can still sign in.

| Column                   | Description                                                                                       |
| ------------------------ | --------------------------------------------------------------------------------------------------- |
| User Principal Name      | The sign-in address of the account behind the shared mailbox.                                     |
| Display Name             | The friendly name of the shared mailbox.                                                          |
| Account Enabled          | Whether the account can sign in. Always `Yes` in this report.                                     |
| Assigned Licenses        | Any licenses assigned to the account. A shared mailbox under 50GB should not need one.            |
| On Premises Sync Enabled | Whether the account is synchronised from on-premises Active Directory.                            |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Block Sign In</td><td>Blocks the account behind the shared mailbox from signing in, leaving the mailbox itself and everyone's delegated access to it working normally. Greyed out where <strong>On Premises Sync Enabled</strong> is <code>Yes</code>, because a synchronised account has to be disabled in on-premises Active Directory instead.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
