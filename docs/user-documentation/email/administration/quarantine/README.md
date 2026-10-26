# Quarantine

This page lists the messages Microsoft Defender for Office 365 and Exchange Online Protection have quarantined for the selected tenant. From here you can inspect a message safely, trace how it arrived, and release, deny, or delete it without going into the Defender portal.

Quarantine is split into four tabs. This page covers the **Email** tab, which is the one you land on.

| Tab            | Contents                                                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| Email          | Quarantined email messages, with the full set of investigation and remediation actions.              |
| Files          | Files quarantined from SharePoint, OneDrive, and Microsoft Teams. See [files.md](files.md "mention"). |
| Teams Messages | Quarantined Microsoft Teams messages. See [teams.md](teams.md "mention").                             |
| User Reported  | Messages users reported as phishing, junk, or not junk. See [user-reported.md](user-reported.md "mention"). |

## Filters

| Filter                   | Shows                                                                                         |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| Not Released             | Messages still sitting in quarantine with no request against them.                            |
| Released                 | Messages that have already been released to their recipients.                                 |
| Requested                | Messages a recipient has asked to have released, which are the ones waiting on your decision. |
| High Confidence Phishing | Messages quarantined as high confidence phishing.                                             |
| Phishing                 | Messages quarantined as phishing.                                                             |
| Spam                     | Messages quarantined as spam.                                                                 |
| Malware                  | Messages quarantined as malware.                                                              |
| Bulk                     | Messages quarantined as bulk mail.                                                            |
| Transport Rule           | Messages quarantined by a mail flow rule.                                                     |

A release-status filter and a quarantine-reason filter can be active at the same time.

## Table Details

The properties returned are for the Exchange Online PowerShell command `Get-QuarantineMessage`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/powershell/module/exchangepowershell/get-quarantinemessage).

Messages are listed newest first. Choosing AllTenants starts a background job to gather messages from every tenant, so the table reports that it is still loading until that job finishes.

## Message Details

**More Info** opens a flyout holding everything CIPP can establish about the message. The top of the flyout shows the subject, the reason it was quarantined, its release status, and how many attachments and links it contains. Below that are expandable sections:

| Section            | Contents                                                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Quarantine Details | When the message arrived and when it expires, the quarantine reason, the policy that caught it, and its release history.                                    |
| Delivery Details   | Where the message was originally delivered and where it ended up, the detections that fired against it, and the spam, phishing, and bulk confidence levels. |
| Email Details      | Sender display name, addresses, sending IP and location, recipients, direction, message IDs, size, and language.                                            |
| Authentication     | The DMARC, DKIM, SPF, and composite authentication results.                                                                                                |
| URLs               | Every link found in the message, with its threat verdict and the detection method that produced it. Shown only when the message contains links.             |
| Attachments        | Every attachment, with its threat verdict, malware family, size, and SHA256 hash. Shown only when the message has attachments.                              |

Fields with no value are left out rather than shown empty, so the sections vary in length from message to message. The actions offered in the table are repeated at the foot of the flyout.

Where Microsoft Defender for Office 365 has analysed the message, the delivery, authentication, URL, and attachment detail comes from Microsoft's own analysis. Where it has not, CIPP falls back to reading the message headers and the message itself, and the flyout says so. The fallback still lists the links and attachments it finds, but Microsoft's per-link verdicts are not available for them, so their threat type shows as **Not analysed**. Those verdicts need Microsoft Defender for Office 365 Plan 2.

{% hint style="info" %}
The enriched detail needs the `SecurityAnalyzedMessage.Read.All` permission on your Secure Application Model application. Where that permission is missing, the flyout says so directly and links to the [Permissions](../../../cipp/settings/permissions.md) page, where **Repair Permissions** adds it. Where the message could not be analysed for another reason, the flyout falls back to the header-based view instead.
{% endhint %}

## Table Actions

{% hint style="info" %}
Under AllTenants, each action runs against the tenant the message belongs to rather than against the tenant selected at the top of CIPP.
{% endhint %}

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Release</td><td>Releases the message to all of its recipients. Greyed out on a message that has already been released.</td><td>true</td></tr><tr><td>Release &#38; Allow Sender</td><td>Releases the message and adds the sender to the allowed senders list of the anti-spam policy that quarantined it, so future mail from them is not quarantined. Greyed out on a message that has already been released.</td><td>true</td></tr><tr><td>Deny</td><td>Turns down a recipient's request to have the message released. Greyed out unless the recipient has actually requested release.</td><td>true</td></tr><tr><td>Delete from Quarantine</td><td>Permanently deletes the message from quarantine. Greyed out on a message that has already been released.</td><td>true</td></tr><tr><td>Preview Message</td><td>Opens a modal that renders the quarantined message so its contents, headers, and attachments can be inspected safely.</td><td>false</td></tr><tr><td>View Message Headers</td><td>Opens a modal showing the message's raw internet headers.</td><td>false</td></tr><tr><td>Download Message (.eml)</td><td>Downloads the message as a <code>.eml</code> file, named after its subject, for analysis outside CIPP.</td><td>false</td></tr><tr><td>View Message Trace</td><td>Opens a modal with a table of the message's trace history, showing where it was received from and what happened to it at each step.</td><td>false</td></tr><tr><td>Submit to Microsoft for Review</td><td>Sends the message to Microsoft as a threat submission so they can review how it was classified. Asks which category to report it under: clean, spam, phishing, or malware.</td><td>false</td></tr><tr><td>Block Sender</td><td>Adds the sender to the tenant's <a data-mention href="../tenant-allow-block-lists.md">tenant-allow-block-lists.md</a> as a blocked sender. The entry expires after 30 days unless you switch it to never expire, and an optional note can be attached.</td><td>true</td></tr><tr><td>Open Email Entity in Defender</td><td>Opens the message's entity page in Microsoft Defender in a new tab, for the detection detail CIPP does not surface.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
**Release &#38; Allow Sender** adds a standing allow entry to the anti-spam policy, and that entry stays until it is removed by hand. Use it for a sender that is genuinely being caught wrongly, and prefer a plain **Release** otherwise. The message is released either way: if the allow entry cannot be added, the release still goes through and the failure is recorded in the logs.
{% endhint %}

{% hint style="danger" %}
**Delete from Quarantine** removes the message outright. There is no recovery afterwards, so preview or download anything you might need first.
{% endhint %}

{% hint style="info" %}
**Submit to Microsoft for Review** submits the message to Microsoft's threat submission service. Submissions are analysed by Microsoft and help correct both false positives and false negatives, so a message you release because it was wrongly caught is worth reporting as clean.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
