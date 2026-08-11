# Browse All Templates

The Template Catalog browses every template published across your registered sources in one place, so you can search the whole collection rather than working through repositories one at a time. Templates are previewed here and imported into your own instance.

Arriving from a source card filters the catalog to that source. The selected sources are held in the page address, so a filtered view can be bookmarked or shared with a colleague.

**Back to Sources** returns to the list of registered repositories.

## Finding a Template

| Filter           | Description                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------------- |
| Search Templates | Matches on the template name, its category, its path in the repository, or the repository itself.          |
| Repository       | Restricts results to one or more sources. Prefilled when you arrive from a source card.                    |
| Type             | Restricts results to particular kinds of template, such as Intune Policy, Conditional Access or Standards. |
| Category         | Restricts results to a category, where the source publishes them.                                          |

A count at the right of the toolbar shows how many templates the current filters match out of the total available.

Two toggle groups sit alongside the filters. The first switches between card and list views, the second filters by import state:

| Status       | Shows                                                                   |
| ------------ | ----------------------------------------------------------------------- |
| All          | Every template matching the filters.                                    |
| Not Imported | Templates you have not yet imported.                                    |
| Imported     | Templates already in your instance.                                     |
| Updates      | Templates you have imported where the source now holds a newer version. |

## Reading the Results

Each template shows its name, its type, its category and the repository it comes from, with the repository name linking through to GitHub.

| Badge            | Meaning                                                                       |
| ---------------- | ----------------------------------------------------------------------------- |
| Imported         | This template is already in your instance and matches the published version.  |
| Update Available | You have imported this template, and the source has since published a change. |

A template with neither badge has not been imported. Cards are also outlined in the matching color, so the state is visible at a glance when scanning a long list.

## Importing

**Preview** opens the template's full configuration before you commit to anything, rendered in a structured view for Intune, Conditional Access and Standards templates. The dialog carries its own **Import** button so you can act on what you have just read.

**Import** on a card brings that single template in.

To import in bulk, tick the templates you want, or use the select-all checkbox to take everything currently matching your filters, then select **Import Selected**. The checkbox label shows how many are selected.

{% hint style="info" %}
**Force re-import** overwrites a template you already hold with the published version, discarding any local changes you have made to it. Leave it off to skip templates that are already imported and up to date.
{% endhint %}

{% hint style="warning" %}
Where CIPP could not read one of your sources, a warning is shown above the results. The catalog still lists everything it could reach, so a shorter than expected list is worth checking against those warnings before concluding a template is missing.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
