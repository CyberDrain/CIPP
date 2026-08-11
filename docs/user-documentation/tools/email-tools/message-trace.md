# Message Trace

Message Trace searches how messages travelled through a tenant's Exchange Online organization, filtered by sender, recipient, status, IP address, or a specific message ID. Each result can be expanded to show the individual routing events for that message, and handed off to Defender for deeper analysis.

{% hint style="info" %}
Exchange Online holds <mark style="color:blue;">90 days</mark> of message trace data, but a single query can only span <mark style="color:blue;">10 days</mark>. To look further back, use **Start / End** and move a window of ten days or less across the period you care about. A search also returns at most 1000 results, so narrow the date range or add a sender or recipient rather than expecting a broad search to be complete.
{% endhint %}

## Message Trace Options

| Option                   | Description                                                                                                                                                                |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Date Filter Type         | Choose **Relative** to search back a number of days from now, or **Start / End** to search a specific window.                                                              |
| Number of days to search | Shown for **Relative**. The number of days back from now to search, defaulting to 2. Values above 10 will be rejected by Exchange Online.                                  |
| Start Date               | Shown for **Start / End**. The date and time the search begins.                                                                                                            |
| End Date                 | Shown for **Start / End**. The date and time the search ends. The window must be 10 days or less.                                                                          |
| Sender                   | The sending address to filter on. Accepts more than one address, so you can trace several senders in a single search.                                                      |
| Recipient                | The receiving address to filter on. Accepts more than one address.                                                                                                         |
| Message ID               | The internet message ID of a specific message. Entering a value here disables every other option, as the search runs on the ID alone.                                      |
| Status                   | The delivery statuses to include, chosen from None, Getting Status, Failed, Pending, Delivered, Expanded, Quarantined and Filtered As Spam. More than one may be selected. |
| From IP                  | Restricts results to messages originating from this IP address. Accepts IPv4 or IPv6.                                                                                      |
| To IP                    | Restricts results to messages delivered to this IP address. Accepts IPv4 or IPv6.                                                                                          |

**Search** runs the trace and **Clear** resets every option back to its default.

{% hint style="warning" %}
Wildcards are not supported in the Sender, Recipient or Message ID fields. Exchange Online's message trace cmdlet rejects them, so a value such as `*@contoso.com` returns nothing rather than every address at that domain. Enter full addresses instead.
{% endhint %}

## Table Details

Below are the default columns displayed in the table. Additional columns, including the message trace ID and the from and to IP addresses, are available through the **Toggle Column Visibility** button at the top of the table.

| Column            | Description                                                                                        |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| Received          | When Exchange Online received the message, in UTC.                                                 |
| Status            | The delivery status of the message.                                                                |
| Sender Address    | The address the message was sent from.                                                             |
| Recipient Address | The address the message was sent to. A message with several recipients appears once per recipient. |
| Subject           | The subject line of the message.                                                                   |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Details</td><td>Opens the <a data-mention href="message-trace.md#message-trace-details">#message-trace-details</a>dialog showing each routing event recorded for the selected message and recipient.</td><td>true</td></tr><tr><td>View in Explorer</td><td>Opens the message in Threat Explorer in the Microsoft Defender portal, under Email &#x26; Collaboration, with the message already filtered.</td><td>false</td></tr></tbody></table>

## Message Trace Details

The details dialog traces one message to one recipient, so a message delivered to several people is inspected one recipient at a time. Where a message was rejected, deferred or redirected, the reason appears here rather than in the results table.

| Column | Description                                                                    |
| ------ | ------------------------------------------------------------------------------ |
| Date   | When the event occurred, in UTC.                                               |
| Event  | The stage of processing the message reached, such as receive, send or deliver. |
| Action | What Exchange Online did to the message at that stage.                         |
| Detail | The supporting detail for the event, including the reason for any failure.     |

{% include "../../../../.gitbook/includes/feature-request.md" %}
