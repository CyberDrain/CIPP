# Templates

This page lists your saved report templates. A template defines the sections a report is made up of, and is what you generate a report from, either on demand or on a schedule.

## Action Buttons

**New Report** opens the builder with an empty template:

{% content-ref url="builder.md" %}
[builder.md](builder.md)
{% endcontent-ref %}

<details>

<summary>Browse Catalog</summary>

Opens the **Browse Report Template Catalog** flyout, listing report templates published in the community-repos registered with your instance. Search for a template, preview it, then select **Import** to add it to your own templates.

Unlike the equivalent catalogue for Intune and Conditional Access, there is no option to import from one of your tenants, since report templates are not tenant objects.

</details>

## Table Details

| Column       | Description                                                                                                       |
| ------------ | ----------------------------------------------------------------------------------------------------------------- |
| Name         | The name given to the template.                                                                                   |
| Sections     | The total number of blocks in the template, of every type.                                                        |
| Test Count   | The number of Test Result blocks, each of which pulls in the outcome of a CIPP test when the report is generated. |
| Custom Count | The number of Custom Blocks, which are free-form content sections you write yourself.                             |

{% hint style="info" %}
Sections will usually be larger than Test Count and Custom Count added together. Blocks of every other type, including Database Data, Chart, Score Cards, Progress Bars, Section Divider and Page Break, count towards the total but have no column of their own.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Open in Builder</td><td>Opens the selected template in the <a data-mention href="builder.md">builder.md</a> with its content loaded, ready to edit.</td><td>true</td></tr><tr><td>Upload to Repository</td><td>Publishes the selected template to a community repository, so it can be shared or reused elsewhere. You choose the repository and supply a commit message.</td><td>true</td></tr><tr><td>Delete</td><td>Permanently deletes the selected template. Reports already generated from it are not affected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Only repositories you have write access to are offered when uploading. Where the list is empty, the repositories registered with your instance are all read-only, which includes the built-in CyberDrain ones.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
