# User Reported Messages

This tab lists the messages users have reported as phishing, junk, or not junk through the Microsoft report buttons in Outlook, so reports can be reviewed with the same tooling the Email tab offers for quarantined messages: preview the message safely, read its headers, download the EML, and trace its delivery, all without going into the Defender portal.

## Sources

A toggle in the top right of the table switches between two sources.

| Source                  | Shows                                                                                                                                                                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Audit Log (default)     | Every message reported with the Outlook Report button, read from the tenant's unified audit log. Reported phishing simulation messages are included and marked as such in the Source column. Each row carries Microsoft's rescan verdict.                                                       |
| Submissions             | The Microsoft Defender Submissions list. Microsoft only exposes submissions that reached Microsoft analysis here, so Outlook reports usually only appear once an admin has submitted them to Microsoft from the Defender portal. Those rows list with the source `administrator`. |

The Audit Log is the default because the Submissions list leaves out most Outlook reports, even when the tenant sends reported messages to Microsoft. Admin submissions in the Submissions list usually carry no message ID either, so the message actions below are greyed out for them.

{% hint style="info" %}
The Audit Log loads two weeks at a time and keeps loading older windows in the background, up to the audit log's 180-day retention. New reports can take up to 90 minutes to appear in the audit log. Unified audit logging must be turned on in the tenant, which is the Microsoft default.
{% endhint %}

The tip above the table links to the User reported tab of the Defender Submissions page for the selected tenant.

## Filters

With the Audit Log source:

| Filter            | Shows                                                          |
| ----------------- | -------------------------------------------------------------- |
| Verdict: Phish    | Reports Microsoft's rescan judged to be phishing.              |
| Verdict: Spam     | Reports Microsoft's rescan judged to be spam.                  |
| Verdict: Not Spam | Reports Microsoft's rescan judged to be legitimate.            |

With the Submissions source:

| Filter               | Shows                                             |
| -------------------- | ------------------------------------------------- |
| Reported as Phishing | Messages reported as phishing.                    |
| Reported as Junk     | Messages reported as junk.                        |
| Reported as Malware  | Messages reported as malware.                     |
| Reported as Not Junk | Messages reported as incorrectly caught.          |

Switching the source clears any filters you applied.

## Table Details

With the Audit Log source, the rows come from the `MailSubmission` audit records (operations `UserSubmission`, `CustomSubmission` and `AttackSimUserSubmission`). For more information please see the [Microsoft documentation](https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#submission-schema). The Category column shows the record's raw submission type number, which Microsoft does not document, so use the verdict instead.

With the Submissions source, the properties returned are for the Microsoft Graph email threat submissions API. For more information please see the [Microsoft documentation](https://learn.microsoft.com/graph/api/security-emailthreatsubmission-list-emailthreats).

Reports are listed newest first. This list is loaded per tenant, so select a specific tenant to view its reported messages.

## Report Details

**More Info** opens a flyout with the report record: when the message was received and reported, the sender, sending IP, recipient, who reported it, the source, the submission status, and Microsoft's verdict where one exists. Fields with no value are left out rather than shown empty. The actions offered in the table are repeated at the foot of the flyout.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Preview Message</td><td>Renders the reported message safely inside CIPP, without loading remote content or executing anything in it. Greyed out where the report carries no message ID.</td><td>false</td></tr><tr><td>View Message Headers</td><td>Shows the full internet headers of the reported message. Greyed out where the report carries no message ID.</td><td>false</td></tr><tr><td>Download Message (.eml)</td><td>Downloads the reported message as an <code>.eml</code> file for offline analysis. Greyed out where the report carries no message ID.</td><td>false</td></tr><tr><td>View Message Trace</td><td>Runs a message trace on the reported message and shows each delivery event. Greyed out where the report carries no message ID.</td><td>false</td></tr><tr><td>Block Sender</td><td>Adds the sender to the tenant's <a data-mention href="../tenant-allow-block-lists.md">tenant-allow-block-lists.md</a> as a blocked sender, with an optional note and expiration choice. Greyed out where the report has no sender address.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Where the message content comes from

Neither source holds the message itself, only the report, so for the preview, header, and download actions CIPP retrieves the message content in two steps: it first looks for the message in quarantine and exports it from there, and when the message was never quarantined it falls back to reading the copy still in the recipient's (or reporter's) mailbox through the Graph API.

{% hint style="info" %}
The mailbox fallback needs the `Mail.Read` application permission on your Secure Application Model application, which CIPP does not request by default. Without it, preview and download still work for reported messages that are in quarantine, and the actions report a clear error for the rest. The remaining actions on this page work without it.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
