# Universal Search

Universal search finds records across every tenant you have access to from a single box, without switching tenant first. Search for a user by name and you get matches from all of your tenants at once, each labelled with the tenant it came from.

## Opening Search

Two icons in the menu bar open the search dialog, each starting on a different search type. The globe icon opens it ready to search users and entities, and the magnifying glass opens it ready to search CIPP's own pages. Once open, you can switch between any of the search types from the dropdown on the left.

| Shortcut             | Action                                   |
| -------------------- | ---------------------------------------- |
| Ctrl/Cmd + K         | Opens search on **Pages**.               |
| Ctrl/Cmd + Shift + F | Opens search on **Users**.               |
| Ctrl/Cmd + Alt + K   | Moves the cursor to the tenant selector. |

## Search Types

| Type         | What is searched                                                                        | Selecting a result                                             |
| ------------ | --------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Users        | User principal name or display name.                                                    | Opens that user in the tenant they belong to.                  |
| Groups       | Display name, with the group's mail address and description shown alongside each match. | Opens that group in the tenant it belongs to.                  |
| Applications | App registrations and enterprise applications, by name, application ID, or publisher.   | Opens the matching app registration or enterprise application. |
| Licenses     | SKU ID, part number, license name, or service plan.                                     | Opens a flyout with the full license details.                  |
| BitLocker    | Recovery key ID or device ID, chosen from a second dropdown that appears for this type. | Opens a flyout with the recovery key details.                  |
| Pages        | Page names, tab names, paths, and whether a page is tenant-scoped or global.            | Navigates to that page.                                        |

The license search returns a description, its service plans, and the tenants holding it, which is useful for identifying a license when you only have a partial reference such as a SKU part number from elsewhere.

{% hint style="info" %}
The **Pages** search only returns pages your CIPP permissions allow you to open, so the results differ between users.
{% endhint %}

## Running a Search

For **Pages** and **Licenses**, matches appear as you type, because both are matched against data already held in the browser.

For **Users**, **Groups**, **Applications** and **BitLocker**, type your terms and then press Enter or click **Search**. These types query across every tenant, so they run only when you ask rather than on each keystroke.

In the results list, matching text is shown in bold, and each result is labelled with the tenant it was found in. Use the up and down arrow keys to move through the list and Enter to open the highlighted result, or click it. Where nothing matches, the list reads **No results found**.

{% hint style="info" %}
Results for users, groups, applications and licenses come from the CIPP reporting database, so they are only as current as the last cache run. A record created moments ago will not appear until the cache next refreshes. License searches are matched first against the Microsoft SKU catalog built into CIPP, and fall back to cached data only when the catalog has no match.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
