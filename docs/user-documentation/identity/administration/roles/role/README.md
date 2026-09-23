---
description: Everything CIPP knows about a single directory role, its assignments and its PIM configuration
---

# View Individual Role

This page opens one directory role from the [Roles & PIM](../README.md) list and is where a review of who holds a role, and on what terms, is carried out. The header shows the role's display name and its role definition id, which can be copied, along with a **View in Entra** button that opens role management in the Microsoft Entra admin center. The display name is also a switcher, so another role can be opened without returning to the list: see [entity-switcher.md](../../../../shared-features/entity-switcher.md "mention").

Two chips appear in the header where they apply. **Privileged** marks a role on CIPP's privileged-roles list, the same list the standards and alerts use. **Policy below floor** marks a role whose PIM settings are weaker than CIPP's secure floor. Both carry an explanation on hover.

A single tenant must be selected. With **All Tenants** selected the page explains that and shows nothing, because a role definition only means something in the context of one directory.

## Tabs

| Tab                       | Description                                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------- |
| Overview                  | The role's details and its assignments, covered below.                                             |
| [PIM Settings](pim.md)    | The assignment breakdown and the role's PIM policy.                                                |
| [Role Audit](audit.md)    | Directory audit events recorded against this role.                                                 |

## Role Details

A card on the left summarising the role itself.

| Field                                     | Description                                                                                                     |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Description                               | What the role grants, as Entra describes it.                                                                    |
| Role Definition ID                        | The role's identifier, used when matching templates and standards to a role.                                    |
| Privileged Role                           | Whether the role is on CIPP's privileged-roles list. The help icon beside it lists the roles that qualify.       |
| Members / Permanent / Eligible / Active   | The four counts in one line: everyone holding the role, those holding it with no end date, those who can activate it through PIM, and those holding it with an end date. |

Beneath the role name the card states whether this is a built-in role or a custom one.

## Assignments

Every principal holding the role, one row per principal and scope.

### Table Details

| Column            | Description                                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Principal         | The user, group or service principal holding the role.                                                                   |
| UPN               | The principal's user principal name, where it has one.                                                                   |
| Principal Type    | Whether the holder is a user, a group or a service principal.                                                             |
| Assignment Type   | Permanent, Eligible, Active, or ActivatedFromEligible where an eligible administrator has activated the role.             |
| Member Type       | Whether the role is held directly or inherited through a role-assignable group.                                           |
| Scope             | The whole directory, or a single administrative unit.                                                                     |
| End Date          | When the assignment expires, where it has an end.                                                                        |

### Table Actions

These are the same assignment actions offered from the Roles & PIM list, described in full under [#assignments](../README.md#assignments "mention"), plus one addition.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Convert to eligible</td><td>Replaces a permanent assignment with a PIM eligibility of the chosen lifetime.</td><td>true</td></tr><tr><td>Grant time-bound active assignment</td><td>Gives an eligible principal an active assignment that expires automatically.</td><td>true</td></tr><tr><td>Extend</td><td>Pushes out the end of a time-bound assignment or an eligibility.</td><td>true</td></tr><tr><td>Renew</td><td>Renews an expired time-bound assignment or eligibility.</td><td>true</td></tr><tr><td>Remove assignment</td><td>Removes the eligibility or the active assignment.</td><td>true</td></tr><tr><td>View sign-ins</td><td>Opens the holder's own page, where their sign-in activity can be reviewed. Greyed out for anything that is not a user.</td><td>false</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
