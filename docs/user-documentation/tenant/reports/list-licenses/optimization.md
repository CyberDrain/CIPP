# Optimization

The License Optimization tab looks at how a tenant's licences are actually used and suggests where money can be saved: licences to remove, cheaper plans that still cover what people use, bundles that cost less than the plans they replace, and seats worth moving to a yearly commitment. Each suggestion carries its reason and an estimated monthly saving, and the whole analysis can be handed to a client as a branded PDF. It requires a single tenant to be selected and is not available for All Tenants.

Every money figure is calculated from the monthly per-seat prices on the [pricing.md](pricing.md "mention") tab, in the currency chosen under **Analysis Settings**. A licence with no price in that currency cannot be costed, so it is left out of the plan-change suggestions and adds nothing to the savings figures.

Licences on the [licenses.md](../../../cipp/settings/licenses.md "mention") excluded list are left out of the analysis, as are licences the tenant holds only on trial subscriptions, since trial seats cost nothing. Trial licences still appear on the licences page.

## Action Buttons

### Client Report

Opens the **Licensing Report** dialog, which builds a client-ready PDF of the figures on this tab for the selected tenant. Greyed out while the analysis is loading and when the tenant has no licence data yet.

The **Report Sections** panel on the left chooses what goes into the PDF. The summary page is always included, and the preview on the right redraws as sections are switched on or off.

| Section                 | Contains                                                        |
| ----------------------- | --------------------------------------------------------------- |
| What you pay for        | Every plan, seats owned versus in use, and monthly cost.        |
| Licenses you can remove | Unassigned, switched-off, inactive and duplicate licences.      |
| Cheaper plans           | People whose plan includes more than they use.                  |
| Better plans            | Bundles that cost less, and people with no security protection. |
| Yearly or monthly       | How many seats are stable enough to commit to for a year.       |
| How this was measured   | Sources, time window and assumptions.                           |

The report uses the same settings as the table, so a recommendation type switched off under **Analysis Settings** has nothing to show in its section. **Download PDF** saves the report once the preview has rendered.

The report's look comes from the preset chosen for the **Licensing Report** under **Default Preset Per Report** in [branding.md](../../../cipp/settings/branding.md "mention"), or from the default branding when no preset is set there.

## Summary

A row of headline figures sits above the table. Hover over a figure for the detail behind it.

| Figure                        | Description                                                                                                                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Monthly spend                 | What the tenant's assigned seats cost each month, counting only licences that have a price. The detail shows the number of assigned seats and the share of them that have a price. |
| Potential saving / month      | The combined monthly saving of every removal, cheaper plan, cheaper bundle and term change suggested. The detail shows the same figure per year.                                   |
| Suggestions                   | The number of suggestions in the table. The detail shows how many seats can be removed outright.                                                                                   |
| Protection investment / month | What it would cost each month to give protection to the users who have none. This is extra spend, so it is kept out of the savings. The detail shows how many users it covers.     |

## Analysis Settings

Expand **Analysis Settings** to change what the analysis looks for. The heading summarises the settings currently in force, and **Apply Settings** runs the analysis again with your changes. Your choices are remembered in this browser, and the currency is shared with the Pricing tab.

| Setting                               | Description                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Recommend downgrades                  | Suggests the cheapest plan that still covers everything each active user was seen using: email, Teams, file storage, the desktop Office apps, a large mailbox or archive, and Copilot. Where nobody used anything a plan provides, such as a Copilot add-on that is never opened, it suggests removing the plan instead. Users with no usage data get no suggestion. On by default.                                                        |
| Recommend upgrades                    | Suggests replacing several plans held by one user with a single bundle that covers the same features for less, and suggests a plan for users who have no device management, sign-in security, or device threat protection at all. On by default.                                                                                                                                                                                           |
| Recommend yearly/monthly split        | Suggests moving seats on a monthly commitment to a yearly one where they have been held long enough to count as stable. On by default.                                                                                                                                                                                                                                                                                                     |
| Protect security features             | When on, a suggested cheaper plan must keep every security, compliance, identity, and device management feature of the current plan, because usage reports cannot show whether those are relied on. A plan carrying such features is never suggested for removal just because its other features went unused. When off, only the features the user was seen using have to be kept, and the reason lists what would be lost. On by default. |
| Treat a user as inactive after        | How long without a sign-in before a licensed user's licences are suggested for removal: 30, 60, 90, 120, or 180 days. The analysis draws on the last 180 days of Microsoft's usage reports, the longest period they cover, and this setting decides how much of that the downgrade analysis counts: email, Teams, file storage, and Copilot only count as used if they were used within it. Use of the desktop Office apps is judged over the full 180 days. Defaults to 90 days.                                                                                                                                                                                                                               |
| Treat a seat as stable (yearly) after | How long a user must have held a licence before the seat counts as stable enough for a yearly commitment: 3, 6, 9, or 12 months. Defaults to 6 months.                                                                                                                                                                                                                                                                                     |
| Currency                              | The currency every figure is shown in. Only prices held in that currency are used.                                                                                                                                                                                                                                                                                                                                                         |

A plan is only ever suggested if it has a price in the selected currency, and a cheaper plan or bundle must cost less than what the user holds now. Business plans are not suggested for a tenant with more than 300 licensed users, unless the user already holds one.

{% hint style="info" %}
On a tenant with no sign-in data, which needs Entra ID P1, a user counts as inactive when they have had no email, Teams, OneDrive, or SharePoint activity within the inactive period. The reason on the row says so.
{% endhint %}

{% hint style="warning" %}
When the tenant conceals user names in its usage reports, the analysis cannot match usage to people, so no downgrade suggestions are made. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off.
{% endhint %}

## Table Details

Each row is one thing you can act on. Suggestions about a person name the user; suggestions about seats, such as reducing a seat count or changing a term, leave the user blank. Rows are sorted by the largest monthly saving first.

| Column         | Description                                                                                                                 |
| -------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Type           | The kind of suggestion. See below.                                                                                          |
| User           | The user the suggestion applies to, where it applies to one person.                                                         |
| License        | The licence the suggestion is about. For a combined-licence suggestion, every plan the user holds.                          |
| Suggestion     | What to do, for example "Change Microsoft 365 Business Premium to Microsoft 365 Business Standard".                         |
| Reason         | Why the suggestion was made, for example the number of days since the last sign-in or the features the user was seen using. |
| Monthly saving | The estimated saving per month. Negative for **Add protection**, which costs more.                                          |

The Extended Info flyout also shows the user's display name, the suggested plan, the number of seats, the annual saving, the features the user was seen using, and the features a plan change would drop.

### Suggestion Types

| Type             | Meaning                                                                                                                                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reduce seats     | Seats are bought but assigned to nobody. Licences the tenant uses without assigning them to anyone, such as extra file storage, are not counted.                                                                      |
| Remove license   | The licence can go: the account is disabled, the user has not signed in within the inactive period, another assigned licence already includes everything this one provides, or nothing the licence provides was used. |
| Change license   | A cheaper plan covers everything the user was seen using.                                                                                                                                                             |
| Combine licenses | One bundle covers the same features as the several plans the user holds, for less.                                                                                                                                    |
| Add protection   | The user has no device management, sign-in security, or device threat protection, and the suggested plan adds them.                                                                                                   |
| Change term      | Seats on a monthly commitment have been held long enough to move to a yearly one. The saving is the premium a monthly commitment carries, shown in the reason.                                                        |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove license from user</td><td>Removes the licence from the user after you confirm. Greyed out unless the row is a <strong>Remove license</strong> suggestion for a named user.</td><td>true</td></tr><tr><td>Set price</td><td>Sets the monthly price per seat for the row's licence, in the currency currently selected. The price is saved on the Pricing tab and applies to every tenant. Greyed out when the licence already has a price.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
