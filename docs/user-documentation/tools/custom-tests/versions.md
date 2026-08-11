# View Versions

Every time a custom test is saved, CIPP keeps the previous version rather than overwriting it. This page shows the full history for a single test, so you can see what changed, compare an older version against the current one, and roll back if a change broke something.

## Table Details

| Column           | Description                                                        |
| ---------------- | ------------------------------------------------------------------ |
| Version          | The version number, with the highest being the current one in use. |
| Script Name      | The display name the script carried at that version.               |
| Description      | The description set on the script at that version.                 |
| Enabled          | Whether the test was set to run at that version.                   |
| Alert On Failure | Whether alerting was configured at that version.                   |
| Return Type      | `JSON` or `Markdown`.                                              |
| Category         | The category the script was filed under at that version.           |
| Risk             | The risk label carried at that version.                            |
| Created By       | The UPN of the user who saved that version.                        |
| Created Date     | Relative time since that version was saved.                        |

Because each row is a snapshot, the values shown are those in force when that version was saved rather than the test's current settings. This is a smaller set of columns than the main list, which also carries the result mode, pillar, user impact and implementation effort.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Restore to This Version</td><td>Makes the selected version current again. Every version newer than the one selected is permanently deleted.</td><td>true</td></tr><tr><td>Compare to Latest</td><td>Opens a side-by-side difference between the selected version and the current one. Not shown on the current version, as there is nothing to compare it against.</td><td>true</td></tr></tbody></table>

{% hint style="danger" %}
Restoring is destructive and cannot be undone. Every version newer than the one you restore to is deleted along with it, so restoring version 3 of a test that has reached version 7 discards versions 4 through 7 entirely. Where you only want to look at an older version, use **Compare to Latest** instead.
{% endhint %}

## Comparing Versions

The **Compare Test Versions** dialog shows what changed between the version you selected and the current one, with both named by their version number and the user who saved them.

**Test Content Diff** compares the script itself. Added lines, removed lines and the unchanged remainder are each summarized as a count above the comparison, then shown line by line. Where the two versions are the same, the dialog says so rather than showing an empty comparison.

**Markdown Result Template Diff** appears below it whenever either version carries a markdown template, and compares those in the same way. A test using the default output has no template and no second comparison.

{% include "../../../../.gitbook/includes/feature-request.md" %}
