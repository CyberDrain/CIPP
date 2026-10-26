---
description: Review a tenant's Conditional Access policies as a set, score them, and find the gaps between them.
---

# CA Gap Analysis

This tab reviews the tenant's Conditional Access policies as a whole rather than one sign-in at a time. It looks for well-known weaknesses such as MFA required in one policy but excluded in another, exemptions that let whole groups of apps bypass a policy, older sign-in methods left open, policies left in report-only mode, no emergency-access account, and guests or admins left out of the policies that should cover them. It is one of the three tabs of [README.md](README.md "mention"), needs a single tenant selected, and changes nothing.

{% hint style="warning" %}
The analysis works from CIPP's stored copy of the tenant's policies, so a policy changed in the tenant a few minutes ago is not reflected until that copy next refreshes. The tenant needs an Entra ID P1 or P2 licence; without one, the tab shows a warning instead of results.
{% endhint %}

## Conditional Access score

A number out of 10 for how well the policies cover what they should. Enforced controls count in full and report-only controls count half, across every persona and control in the grid that applies to the tenant. Critical and high findings then take off up to two points. The caption shows how many of the expected controls are enforced, and how many critical and high findings there are. The score is green from 8, amber from 5, and red below that.

{% hint style="info" %}
Do not aim for 10 out of 10. Use the findings to decide which gaps are worth closing rather than chasing every point.
{% endhint %}

## Coverage by persona

A grid of the kinds of identity the policies target against the controls they should be subject to. The header counts the tenant's policies by state: enforced, report-only, and disabled. Hover a cell to see the policies behind it.

Personas come from how each policy targets identities, not from its name. A policy that targets all users counts towards Admins unless it excludes a privileged role. Excluding a role that is not privileged, such as the directory synchronisation role, does not take admins out of it.

| Persona             | Controls expected                                                                                                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Admins              | Multifactor authentication, Phishing-resistant authentication, Managed device, Legacy authentication blocked, Sign-in risk response, User risk response, Session limits, Location restrictions |
| Users               | All of the above except Phishing-resistant authentication                                                                                                                                  |
| Guests              | Multifactor authentication, Legacy authentication blocked, Sign-in risk response, Session limits, Location restrictions                                                                    |
| Workload identities | Sign-in risk response, Location restrictions                                                                                                                                               |

Each cell shows one of these states:

| State          | Meaning                                                                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Enforced       | An enabled policy applies this control to the persona.                                                                                    |
| Report-only    | Only a report-only policy applies it, so nothing is enforced yet.                                                                         |
| No policy      | No policy applies it.                                                                                                                     |
| Unlicensed     | The tenant lacks the licence the control needs: Entra ID P2 for the risk controls, Intune for Managed device, or Workload ID Premium for workload identity sign-in risk. |
| Not applicable | The control is not expected for this persona.                                                                                             |

## Policy findings

Every issue found, most severe first. Only critical, high, and medium findings are listed. Each finding shows:

| Field                   | Description                                                                         |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Title                   | What is wrong, followed by its severity and category.                               |
| Description             | Why it matters.                                                                     |
| Policies                | The policies the finding affects.                                                   |
| Fix                     | What to change.                                                                     |
| Microsoft Documentation | Opens Microsoft's guidance for the control. Shown where the finding maps to it.     |

Findings are grouped into categories such as Multifactor coverage, Administrator coverage, Guest coverage, Emergency access, Older sign-in methods, Risk-based access, Application coverage, Locations, Platform coverage, and Persona coverage. A Persona coverage finding is raised for every No policy cell in the grid, except for workload identities.

{% include "../../../../.gitbook/includes/feature-request.md" %}
