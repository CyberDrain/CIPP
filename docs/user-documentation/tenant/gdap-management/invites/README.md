---
description: Easily find all the valid unused GDAP invites in your partner organization.
---

# Invites

This page lists the GDAP invites that have been generated but not yet used. Each row holds the two links produced when the invite was created: one for the customer to approve the relationship, and one for a CIPP administrator to complete onboarding once it has been approved.

Use the [add.md](add.md "mention") button to generate more.

## Table Details

| Column         | Description                                                                                                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Timestamp      | How long ago the invite was created.                                                                                                                    |
| Row Key        | The identifier of the relationship the invite will create.                                                                                              |
| Reference      | The internal note recorded against the invite, for example a client name or ticket number.                                                              |
| Technician     | The CIPP user who generated the invite. Invites created through the API show the application name, and those created by a scheduled task show `System`. |
| Invite Url     | The link for a Global Administrator in the customer tenant to approve the relationship.                                                                 |
| Onboarding Url | The link a CIPP administrator opens to start onboarding once the invite has been approved.                                                              |
| Role Mappings  | The role mappings from the template the invite was generated with.                                                                                      |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Update Internal Reference</td><td>Sets or changes the internal note recorded against the invite.</td><td>true</td></tr><tr><td>Delete Invite</td><td>Removes the invite record from CIPP. This only deletes the entry, it does not withdraw a relationship that is already awaiting approval.</td><td>true</td></tr></tbody></table>

{% hint style="warning" %}
GDAP relationships cannot be terminated once they have reached approval pending status, so deleting an invite here removes only CIPP's record of it. The pending relationship remains in Partner Center until the customer approves it or it lapses.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
