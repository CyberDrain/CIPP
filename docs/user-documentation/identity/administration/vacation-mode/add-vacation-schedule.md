# Add Vacation Schedule

This wizard schedules a set of temporary changes for one or more users and the reversal of each, so a period of absence is set up once and undone automatically. Four kinds of change are available and any combination can be used, but at least one has to be enabled before the wizard will continue.

{% stepper %}
{% step %}
### Tenant Selection

The tenant the changes apply to. This defaults to the tenant selected in the top menu and can be changed here.
{% endstep %}

{% step %}
### User Selection

The users the vacation applies to. Several can be selected, and the changes below are applied to each of them.
{% endstep %}

{% step %}
### Vacation Actions

Four switches, each revealing its own settings. Enable whichever apply.

#### Enable CA Policy Exclusion

Excludes the selected users from Conditional Access policies for the duration.

| Field                                        | Description                                                                                                                                                                |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Conditional Access Policies                  | The policies to exclude the users from. At least one is required. The list is read from the tenant chosen in step one, so a tenant has to be selected before it populates. |
| Exclude from location-based audit log alerts | Suppresses the alerts that would otherwise fire on sign-ins from an unusual location.                                                                                      |
| Create temporary travel policy               | Creates a named location for the travel destination and a policy that blocks sign-ins from everywhere else, then deletes both at the end date.                             |
| Travel destination countries                 | The countries the users are traveling to. Required when a travel policy is being created.                                                                                 |

{% hint style="warning" %}
Excluding someone from a Conditional Access policy allows sign-ins from anywhere, which is a wider gap than the trip usually warrants. The temporary travel policy is there to close it, restricting sign-ins to the destination for the same period.
{% endhint %}

#### Enable Mailbox Permissions

Grants delegates temporary access to the users' mailboxes.

| Field                        | Description                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Delegates                    | The users receiving access. At least one is required.                                                                                                                                             |
| Permission Types             | Any combination of `Full Access`, `Send As`, and `Send On Behalf`. At least one is required.                                                                                                      |
| Auto-Map Mailbox             | Lets Outlook add the mailbox on its own for the delegate. Offered with `Full Access`.                                                                                                             |
| Include Calendar Permissions | Grants access to the calendar as well as the mailbox.                                                                                                                                             |
| Calendar Permission Level    | The access level on the calendar: `Owner`, `Publishing Editor`, `Editor`, `Publishing Author`, `Author`, `Non Editing Author`, `Reviewer`, `Contributor`, `Limited Details`, or `Available Only`. |
| Can View Private Items       | Allows the delegate to see items marked private.                                                                                                                                                  |

#### Enable Mail Forwarding

Forwards the users' mail for the duration.

| Field                                                     | Description                                                                    |
| --------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Forward to Internal Address / Forward to External Address | Whether mail goes to another recipient in the tenant or to an outside address. |
| External Email Address                                    | The outside address to forward to.                                             |
| Keep a Copy of the Forwarded Mail in the Source Mailbox   | Delivers the message to the user's own mailbox as well as forwarding it.       |

{% hint style="warning" %}
Forwarding is turned off at the end date rather than returned to how it was. Any forwarding the mailbox had configured beforehand is not restored, so check that first if the user already had a forward set.
{% endhint %}

#### Enable Out of Office

Sets automatic replies for the duration.

| Field                                                    | Description                                                                                                       |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Internal Message                                         | The reply sent to people inside the organization. Pre-filled with the mailbox's current message where one is set. |
| External Message (optional)                              | The reply sent to people outside the organization.                                                                |
| Block my calendar for this period                        | Creates a calendar event covering the absence, with a subject of your choosing.                                   |
| Automatically decline new invitations during this period | Declines invitations arriving during the absence.                                                                 |
| Decline and cancel my meetings during this period        | Declines and cancels meetings already booked, with an optional message to organizers.                             |

{% hint style="info" %}
Turning automatic replies off at the end date preserves whatever the message says at that point, so a user who edits their own reply while away does not have it overwritten.
{% endhint %}
{% endstep %}

{% step %}
### Schedule

| Field                  | Description                                                                                                             |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Scheduled Start Date   | When the changes are applied.                                                                                           |
| Scheduled End Date     | When they are reversed.                                                                                                 |
| Post Execution Actions | Which channels are notified as the tasks run: Webhook, Email, or PSA.                                                   |
| Reference              | Free text carried onto every task the vacation creates, which is what ties them together on the [.](./ "mention") page. |
{% endstep %}

{% step %}
### Review & Submit

A summary of everything selected. Submitting creates the scheduled tasks.
{% endstep %}
{% endstepper %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
