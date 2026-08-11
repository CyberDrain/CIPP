# Message Viewer

The Message Viewer opens a raw email so you can inspect what an email client would otherwise hide: the routing chain, the authentication results, the anti-spam verdict, and the attachments. Load a saved `.eml` file, or paste the headers or full source copied out of a mail client.

{% hint style="info" %}
Everything on this page happens in your browser. The message is never uploaded to CIPP or sent to Microsoft, no tenant is involved, and nothing is written to the logs. That makes it safe for handling a reported phishing sample, and it means the tool works just as well on a message from an organization you do not manage.
{% endhint %}

## Loading a Message

The toggle at the top of the page switches between the two input methods. Changing mode clears whatever is currently loaded.

### Upload EML

Drag an `.eml` file onto the drop area, or click it to browse. One file at a time is accepted, and the message renders as soon as it has been read.

### Paste Headers / Source

Paste the raw headers or the complete message source into the box and click **Analyze**. The button stays unavailable until something has been entered. Once the analysis runs, the input box collapses so the results have room, and the arrow beside **Analyze** brings it back if you want to amend what you pasted.

Pasting headers alone is enough for the delivery and authentication analysis. The message body and attachments only appear if you paste the full source.

{% hint style="warning" %}
If the content cannot be parsed as an email, an error card is shown with the raw text below it so you can still read what you supplied. This is common when only part of a header block has been copied.
{% endhint %}

## Delivery Information

The first card reconstructs the journey the message took from its `Received` headers, which is the quickest way to spot where a delayed message actually sat.

A chip shows the total delivery time, and further chips show the SPF, DKIM, DMARC, CompAuth and ARC results taken from the `Authentication-Results` and `ARC-Authentication-Results` headers. The chips are color coded by result, and only appear for checks the message actually carries.

| Column | Description                                                                                                                                                                   |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| #      | The position of the hop in the chain, counting from the first server to handle the message.                                                                                   |
| Delay  | How long the message spent at the previous hop before this one received it, shown as a bar relative to the slowest hop in the chain. Delays over ten seconds are highlighted. |
| From   | The host the message was received from. Hovering over the value shows the complete `Received` header for that hop.                                                            |
| By     | The host that received the message at this stage.                                                                                                                             |
| With   | The protocol used for the handover, such as SMTP or ESMTPS.                                                                                                                   |
| Time   | The timestamp recorded for that hop.                                                                                                                                          |

## Message Details

The second card renders the message itself.

The sender's display name and address appear at the top with a shield icon beside them. Its color summarizes the DMARC, DKIM, SPF and ARC results from the message's own `Authentication-Results` header, and hovering over it gives the individual verdicts. A message carrying no authentication results at all is flagged rather than treated as a pass.

Recipients, any CC addresses, and the message date with a relative age are shown below the sender. The body renders as sanitised HTML where the message has an HTML part, falling back to the plain text part. Inline images referenced by content ID are re-embedded so the message looks as it did to the recipient. A sun and moon icon above the body switches the preview between light and dark backgrounds independently of your CIPP theme, which is useful for messages that assume one or the other.

Attachments appear as buttons named after the file, each with an icon reflecting its type. Clicking one offers:

* **Download** saves the attachment to your machine.
* **View** opens it in a dialog without saving. Available for text, PDF, image and email attachments. An attached `.eml` opens in a nested message viewer, so a forwarded phishing sample can be analyzed without extracting it first.

{% hint style="danger" %}
Downloading an attachment from a suspicious message puts the file on your own machine. Prefer **View** where the type allows it, and treat anything you do download with the same caution you would apply to a sample from any other untrusted source.
{% endhint %}

## Message Actions

The buttons alongside the message subject open the raw data behind the rendered message.

| Action           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| View Headers     | Opens a dialog containing the message's full header block as plain text. Shown only where headers could be parsed from the source.                                                                                                                                                                                                                                                                                                                                                                |
| Anti-Spam Report | Decodes the `X-Forefront-Antispam-Report` header into readable fields, covering the spam confidence level, the filtering verdict, the connecting IP address and its country, the reverse DNS of the sender, the bulk mail rating, and the protection policy category that applied. Values that map to a known meaning are expanded into a description rather than left as their raw code. Shown only on messages that passed through Exchange Online Protection, since Microsoft adds the header. |
| View Source      | Opens a dialog containing the complete raw message exactly as it was loaded, headers and body together.                                                                                                                                                                                                                                                                                                                                                                                           |

{% include "../../../../.gitbook/includes/feature-request.md" %}
