# Message Trace

Message Trace searches how messages travelled through a tenant's Exchange Online organisation, filtered by sender, recipient, subject, status, IP address, or a specific message ID. Each result can be expanded to show the individual routing events for that message, and handed off to Defender for deeper analysis. The page has a second tab, [Historical Search](historical-search.md), for reports that reach beyond a single trace window.

{% hint style="info" %}
Exchange Online holds <mark style="color:blue;">90 days</mark> of message trace data, but a single query can only span <mark style="color:blue;">10 days</mark>. To look further back, use **Pick a date range** and move a window of ten days or less across the period you care about, or run a [Historical Search](historical-search.md) for one report across the whole period. Each search returns every matching message in the selected window.
{% endhint %}

{% hint style="warning" %}
Message Trace uses the Microsoft Graph message trace API, which requires the **`ExchangeMessageTrace.Read.All`** permission. It has been added to the CIPP-SAM application, so refresh CPV permissions on your tenants after updating. The first search in a tenant also provisions Microsoft's **Transport Data Platform** service principal automatically; Microsoft can take a few hours to activate it, during which CIPP falls back to the `Get-MessageTraceV2` cmdlet so results are still returned. A short notice appears above the results while the fallback is in use. Microsoft does not offer the Graph message trace API to GCC tenants, so searches in a GCC tenant use the same fallback.
{% endhint %}

## Find a message

| Option                    | Description                                                                                                                                                          |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| When was it sent?         | Choose **Last 48 hours**, **Last 7 days** or **Last 10 days**, or **Pick a date range** to search a specific window of 10 days or less.                              |
| Start Date / End Date     | Shown for **Pick a date range**. The window the search covers.                                                                                                       |
| Who sent it?              | The sending address to filter on. Accepts more than one address, so you can trace several senders in a single search. Leave empty to include every sender.           |
| Who was it sent to?       | The receiving address to filter on. Accepts more than one address. Leave empty to include every recipient.                                                           |
| What was the subject line? | Matches from the start of the subject, so "Invoice" finds "Invoice 4482 overdue". The match style can be changed under the advanced filters.                         |

**Show advanced filters** reveals the technical options:

| Option          | Description                                                                                                                                                     |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Subject Match   | How the subject filter is applied: **Starts with**, **Ends with** or **Contains**. Starts with and Ends with are the faster searches.                           |
| Delivery Status | The delivery statuses to include, chosen from Delivered, Expanded, Failed, Filtered As Spam, Getting Status, Pending and Quarantined. More than one may be selected. |
| Message ID      | The internet message ID of a specific message. Narrows the search along with the other filters.                                                                 |
| From IP         | Restricts results to messages originating from this IP address. Accepts IPv4 or IPv6.                                                                           |
| To IP           | Restricts results to messages delivered to this IP address. Accepts IPv4 or IPv6.                                                                               |

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

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Details</td><td>Opens the <a data-mention href="message-trace.md#message-trace-details">#message-trace-details</a> panel showing each routing event recorded for the selected message and recipient.</td><td>true</td></tr><tr><td>View in Explorer</td><td>Opens the message in Threat Explorer in the Microsoft Defender portal, under Email &#x26; Collaboration, with the message already filtered.</td><td>false</td></tr></tbody></table>

## Message Trace Details

The details panel traces one message to one recipient, so a message delivered to several people is inspected one recipient at a time. Where a message was rejected, deferred or redirected, the reason appears here rather than in the results table.

| Column | Description                                                                    |
| ------ | ------------------------------------------------------------------------------ |
| Date   | When the event occurred, in UTC.                                               |
| Event  | The stage of processing the message reached, such as receive, send or deliver. |
| Action | What Exchange Online did to the message at that stage.                         |
| Detail | The supporting detail for the event, including the reason for any failure.     |

{% include "../../../../.gitbook/includes/feature-request.md" %}
