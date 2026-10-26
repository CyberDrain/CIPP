# Requests

When JIT Admin approval is switched on, a JIT Admin request that needs approval waits here until enough approvers have agreed. Nothing is created or changed in the tenant while a request is pending. Approval is set up in the JIT Admin Settings card of the [application settings](../../../cipp/settings/README.md#jit-admin-settings), where you choose which tenants and roles need approval, which CIPP roles can approve, and how many approvals each request needs.

## How a request is decided

1. A technician submits the [add.md](add.md "mention") form. If the request is for a tenant and a role that need approval, it is saved here as **Pending** instead of being carried out, and the technician is told it was submitted for approval.
2. The approvers are notified. Each approval is recorded against the request, and each approver counts once.
3. Once the required number of approvals is reached, CIPP creates the JIT Admin exactly as it was requested. Fields cannot be changed during approval; to change a request, reject it and submit a new one.
4. A single rejection ends the request, whatever approvals it already has. A rejection always carries a note, which is passed to the requester.

{% hint style="warning" %}
The person who submitted a request can never approve it, even when they hold an approver role. They can still reject their own request to withdraw it, provided they hold an approver role.
{% endhint %}

The approver roles and the number of approvals are recorded on each request when it is submitted. Changing the approval settings afterwards only affects new requests, not the ones already waiting.

## After approval

The JIT Admin is created and scheduled in the same way as one created without approval, and then appears on the [README.md](README.md "mention") tab.

* If a request is approved after its start date, the access begins at approval and still ends at the requested end date, so the window is shorter rather than moved. A request whose end date has already passed cannot be approved; reject it instead.
* No password or Temporary Access Pass is generated when a request is approved, so the approver never sees the new account's sign-in details. Once the request is approved, the requester uses **Create Temporary Access Pass** or **Reset Password** on the [README.md](README.md "mention") tab to sign in.
* The notification channels chosen on the request are used for the JIT Admin's own start and expiry, the same as for any JIT Admin.

## Notifications

| Event              | Who is told                                                                                                                                                                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Request submitted  | Everyone set up in CIPP's [notifications.md](../../../cipp/settings/notifications.md "mention") settings: the email recipients, the webhook, and the PSA if **Send to integration** is on. On the new CIPP infrastructure, approvers also get a push notification on any device they have registered. The requester does not get a push notification for their own request. |
| Approved           | The same notification settings, with the result of creating the JIT Admin. On the new CIPP infrastructure, the requester also gets a push notification.                                                                                                     |
| Rejected           | The same notification settings, with the rejection note. On the new CIPP infrastructure, the requester also gets a push notification.                                                                                                                       |

{% hint style="info" %}
Push notifications go to devices registered on the **Preferences** page. Approvers are found from the users listed under CIPP Users, so an approver who signs in to CIPP without being listed there does not receive a push, but still receives the email, webhook and PSA notifications.
{% endhint %}

## Filters

| Filter  | Shows                                     |
| ------- | ----------------------------------------- |
| Pending | Requests still waiting for a decision.    |

## Table Details

| Column       | Description                                                                                                                   |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| State        | **Pending** while waiting, **Completed** once approved and created, **Rejected** after a rejection, or **Failed** if the JIT Admin could not be created after approval. |
| Tenant       | The tenant the access was requested in.                                                                                       |
| Target User  | The account the access is for. For a new account, this is the username that will be created.                                 |
| Roles        | The Entra ID directory roles requested.                                                                                       |
| Groups       | The groups requested.                                                                                                         |
| Start Date   | When the access was requested to begin.                                                                                       |
| End Date     | When the access was requested to end.                                                                                         |
| Reason       | The reason given on the request.                                                                                              |
| Requested By | Who submitted the request.                                                                                                    |
| Requested At | When the request was submitted.                                                                                               |
| Approvals    | How many approvals the request has, out of how many it needs.                                                                 |

The **More Info** flyout also shows the approver roles, each decision with who made it, when, and any note, and the results of creating the JIT Admin.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Approve</td><td>Records your approval, with an optional note. When it is the last approval needed, the JIT Admin is created and the results are shown. Greyed out unless the request is pending, you hold an approver role, you did not submit it, and you have not already decided on it.</td><td>false</td></tr><tr><td>Reject</td><td>Ends the request. A note is required and is sent to the requester. Greyed out unless the request is pending, you hold an approver role, and you have not already decided on it.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
While approval is on, CIPP also refuses to grant roles or groups through a JIT Admin that has no approved request behind it in a tenant that needs approval, such as a scheduled task set up directly. A JIT Admin scheduled to start in the future before approval was switched on is held to the same rule, so it does not activate when its start date arrives. The same happens when a tenant starts needing approval between submission and start, for example because it joined a selected tenant group.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
