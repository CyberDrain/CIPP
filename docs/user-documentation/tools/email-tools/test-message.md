# Test Mail Flow Rules

Sends a test message through the selected tenant's mail flow rule pipeline, and optionally its unified DLP rules, without delivering it. Exchange evaluates the message against every rule, drops it, and emails a report to the address you choose. CIPP then watches the message trace for the dropped message and shows the rules that acted on it, with the action each one took, usually within a minute. Rules that were evaluated but did not match are listed only in the emailed report.

This runs Exchange Online's `Test-Message`. Because the message really enters the pipeline, rule actions such as block, moderate or notify can fire for it, and any notifications those rules are configured to send will be sent.

## Fields

| Field                      | Description                                                                                                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sender                     | The address the test message is sent from. It does not have to be a mailbox in the tenant.                                                                                       |
| Recipients                 | One or more addresses the message is addressed to. Type each address and press Enter.                                                                                            |
| Send report to             | A mailbox in the tenant that receives the rule evaluation report. Required.                                                                                                     |
| Subject, Body              | The content of the test message CIPP builds. Leave blank for a generic test message.                                                                                             |
| Evaluate mail flow rules   | Runs the message against the tenant's mail flow (transport) rules. On by default.                                                                                               |
| Evaluate unified DLP rules | Also runs the message against the tenant's unified DLP rules.                                                                                                                   |

## Testing a real message

To replay an actual message rather than one CIPP composes, open it in the [message-viewer.md](message-viewer.md "mention") and use **Test Mail Flow Rules** there. The uploaded `.eml` is sent to Exchange as-is, so headers and attachments are evaluated exactly as they arrived; the sender and recipients are pre-filled from its headers and can be changed.

## Results

Once the dropped test message appears in the tenant's message trace, its events are listed below the form: a row per rule that acted, including any redirect, header change or other action, and the final intentional drop. A test with no rule rows means nothing matched. If the message has not appeared after five minutes, the emailed report is the fallback; the trace can lag during busy periods.

{% include "../../../../.gitbook/includes/feature-request.md" %}
