---
description: Single pane of glass review of common Indicators of Compromise (IoC)
---

# Compromise Remediation

Upon page load, CIPP will run an analysis on the user to identify common Indicators of Compromise (IoC). Once that analysis is returned, review the information presented and determine if the user has been compromised. The analysis performs the checks listed in the table below. A green check will indicate that information was found for the check and needs review.

{% hint style="warning" %}
Note: This page is intended to surface information about potential information that should be reviewed when a compromise is suspected. The existence of information in one of the indicators should not be interpreted as an absolute sign of compromise but rather as a useful tool to help quickly surface the basic information that should be reviewed during your investigation.
{% endhint %}

## Indicators of Compromise Checks

| Check                      | What It Looks For                                                                                                                                                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Mailbox Rules              | Inbox rules currently on the mailbox, plus any rule create/change/remove operations in the last 7 days. Flags a potential breach when a rule moves mail to an `RSS`-type folder, and highlights rules created or changed within the last 7 days. |
| Recently Added Users       | Users created in the tenant within the last 14 days.                                                                                                                                                                                             |
| New Applications           | App registrations / service principals recently added to the tenant (display name, app ID, created date).                                                                                                                                        |
| Mailbox Permission Changes | Delegated mailbox permission grants and changes (actor, operation, permission level).                                                                                                                                                            |
| Sent Messages              | Messages sent from the mailbox within the analysis window — subject, recipient, status, received time and source IP — for spotting suspicious outbound activity.                                                                                 |
| MFA Devices                | Authentication / MFA methods registered on the account (method type, display name, registration date).                                                                                                                                           |
| Password Changes           | Most recent password-change timestamps across the tenant's users.                                                                                                                                                                                |
| Trusted & Blocked Senders  | The mailbox's trusted and blocked sender/domain safelist, plus any changes to that list in the last 7 days.                                                                                                                                      |

## Actions

| Action              | Description                                                                                                                                                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Refresh Data        | This will refresh the analysis for the user and update the Indicators of Compromise checks. This button is found at the top of the overview card.                                                                                                                 |
| Remediate User      | This action will block user sign-in, reset the user's password, disconnect all current sessions, remove all MFA methods for the user, disable all inbox rules for the user, and Disable OneDrive sharing. The button is found at the bottom of the overview card. |
| Generate PDF Report | Generates a PDF of the report data, including helpful data points on user education. This button is found in the Report expandable card at the bottom of the list of checks.                                                                                      |
| Download JSON       | This will download a JSON file for the checks completed in the analysis. This button is found in the Report expandable card at the bottom of the list of checks.                                                                                                  |

***

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
