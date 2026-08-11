# Report Builder

The builder is where a report template is assembled. A report is built from blocks, each of which contributes a section: a test result, data pulled from the cache database, a chart, or prose you write yourself. Blocks are added, reordered and edited here, then saved as a template or scheduled to generate on a recurring basis.

{% hint style="info" %}
Live test results and database content are loaded for the tenant selected in [tenant-select.md](../../shared-features/menu-bar/tenant-select.md "mention"), so what you see while building is that tenant's real data. Custom, chart and divider blocks work without a tenant selected. When the template is later generated for a different tenant, the data is collected fresh for that tenant.
{% endhint %}

## Action Buttons

The name of the template being edited is shown at the top of the page alongside a chip naming the current tenant. All four buttons stay unavailable until the report has at least one block, and **Schedule** additionally requires a tenant to be selected.

<details>

<summary>Save Template</summary>

Opens a dialog asking for a **Template Name**, then saves the blocks and the page setup as a template. Editing an existing template saves over it rather than creating a copy.

</details>

<details>

<summary>Schedule</summary>

Opens the **Schedule Report Generation** dialog, which creates a scheduled task that generates this report on a recurring basis. The task name is prefilled from the template name and the current tenant.

| Field                  | Description                                                                                                                                                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Task Name              | The name the task appears under in the scheduler.                                                                                                                                                                               |
| Recurrence             | How often the report is generated. Choose Once, Every day, Every 7 days, Every 30 days, or Every 90 days. The interval runs from the moment the schedule is created, and Once generates the report immediately and never again. |
| Post Execution Actions | How the finished report is delivered. More than one may be selected.                                                                                                                                                            |

The delivery options behave differently:

* **Email** sends the report body as the message, to the address configured in [notifications.md](../../cipp/settings/notifications.md "mention"). Database blocks marked for attachment are sent as files.
* **PSA** raises a ticket with the report body as its content. Raw data is not attached.
* **Webhook** posts a JSON payload of the task metadata and results.

The schedule captures the blocks and page setup as they stand when you create it. Editing the template afterwards does not update an existing schedule, so recreate the schedule if the report changes.

</details>

<details>

<summary>Preview PDF</summary>

Opens the rendered report in a dialog so you can check pagination, branding and layout before saving. The preview includes its own **Download PDF** button.

</details>

**Download PDF** renders the report and downloads it immediately, without saving anything.

## Adding Blocks

Choose a **Block Type**, complete whatever fields appear for it, then select **Add Block**. Repeat for each section the report needs. Blocks are appended to the bottom and can be reordered afterwards.

| Block Type      | Description                                                                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom Block    | A free-form section you write yourself using a rich text editor, for structure, narrative or commentary.                                                                     |
| Test Result     | A section tied to CIPP's test suite results. Choose a **Test Suite**, then one or more tests under **Select Tests**. Selecting several tests adds a separate block for each. |
| Database Data   | A section populated from the cache database. Choose a **Data Source** and a **Format** of Table (Text), CSV or JSON.                                                         |
| Chart           | A donut, bar or trend line chart built from data points you enter by hand.                                                                                                   |
| Score Cards     | A row of headline figures, each a label and a value.                                                                                                                         |
| Progress Bars   | Labelled bars showing a value against a maximum, useful for coverage figures.                                                                                                |
| Section Divider | A full-width heading with optional subtext, footer text and a background image, for separating a report into parts.                                                          |
| Page Break      | Forces the following content onto a new page.                                                                                                                                |

Two switches sit below the block controls:

| Setting                                    | Description                                                                                                                                          |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Remove Remediation recommendations         | Strips the remediation guidance from test result content, leaving the findings alone. Useful for a report going to a client rather than an engineer. |
| Include database items as email attachment | Attaches the raw data from database blocks to the scheduled email. Only shown once the report contains at least one database block.                  |

## Page Setup & Branding

| Setting     | Description                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------------- |
| Branding    | The branding preset the report renders against, which carries the cover, footer and watermark. |
| Page Size   | The paper size the PDF is rendered at.                                                         |
| Orientation | Portrait or landscape.                                                                         |

{% hint style="info" %}
Cover, footer and watermark are no longer set per template. They belong to the branding preset, so a template records which preset to render against and nothing more. Where the preset saved with a template has since been deleted, a warning is shown and the global branding settings are used instead.
{% endhint %}

## Working with Blocks

Each block is shown as a card. The header carries the block title and chips describing its state.

| Chip           | Description                                                                                                     | Shown on      |
| -------------- | --------------------------------------------------------------------------------------------------------------- | ------------- |
| Test status    | The outcome of the test: Passed, Failed, Investigate, or a plain chip for a test that only reports information. | Test Result   |
| Live or Edited | Whether the block still reflects the live test result or has been edited and detached from it.                  | Test Result   |
| Custom         | Marks a free-form block.                                                                                        | Custom Block  |
| Database       | The data source, the format in use, and the number of rows returned.                                            | Database Data |
| Chart type     | Which chart is being rendered.                                                                                  | Chart         |

The actions on each card are:

| Action              | Description                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Edit                | Opens the block for editing. On a test block this converts it to static content, detaching it from the live result.   |
| Revert to live data | Returns an edited test block to the live result, discarding your changes. Only shown on blocks that have been edited. |
| Refresh data        | Re-reads the data source. Only shown on database blocks.                                                              |
| Move up / Move down | Reorders the block within the report. Unavailable at the top and bottom of the list.                                  |
| Remove block        | Deletes the block from the report.                                                                                    |

### Custom Block Editing

Custom blocks use a rich text editor with headings, bold, italic, underline, strikethrough, lists, inline code and code blocks, undo and redo, and full table support including inserting and deleting rows and columns.

### Database Block Controls

The chip beside the title switches the display between **Table (Text)**, **CSV** and **JSON**. Below it, a checkbox list controls which columns appear, with **Select All** and **Deselect All** for working quickly through a wide data source.

### Structured Block Editing

Chart, Score Cards and Progress Bars blocks are edited as small tables of values. Add a row for each data point, giving it a label and a value, with an optional color on chart data points. Charts also take a caption, and a donut chart takes a center label and an optional maximum.

{% include "../../../../.gitbook/includes/feature-request.md" %}
