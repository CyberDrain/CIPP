# Mailbox Forwarding

This report lists the mailboxes in the selected tenant that have forwarding configured, whether that forwarding points inside the organization or out to an external address. Mailboxes with no forwarding are left out entirely, so anything appearing here is worth a look, and unexpected external forwarding is one of the clearest signs of a compromised account.

## Filters

Preset filters are available from the **Filters** button:

| Filter               | Shows                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| External Forwarding  | Mailboxes forwarding to an address outside the organization.                |
| Internal Forwarding  | Mailboxes forwarding to another recipient inside the organization.          |

## Table Details

| Column                         | Description                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| UPN                            | The user principal name of the mailbox that is forwarding.                                                       |
| Display Name                   | The friendly name of the mailbox.                                                                                |
| Recipient Type Details         | The kind of mailbox, for example `UserMailbox` or `SharedMailbox`.                                               |
| Forwarding Type                | `External` where an SMTP forwarding address is set, or `Internal` where the target is a recipient in the tenant. |
| Forward To                     | The address mail is being sent on to.                                                                            |
| Deliver To Mailbox And Forward | Whether a copy is also kept in the mailbox. Where this is `No`, mail is forwarded and nothing is retained.       |

Where a mailbox has both an external and an internal forwarding address configured, external wins in **Forwarding Type** and **Forward To**. The two underlying values are still reported separately as **Forwarding Smtp Address** and **Internal Forwarding Address**.

{% hint style="info" %}
This report covers forwarding set on the mailbox itself. Forwarding created by an inbox rule is not shown here, so a mailbox that looks clean on this page can still be forwarding mail through a rule.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
