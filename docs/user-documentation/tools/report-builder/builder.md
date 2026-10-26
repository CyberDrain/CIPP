# Report Builder

The builder is where a report template is assembled. A report is built from blocks, each of which contributes a section: a test result, data pulled from the cache database, a chart, or prose you write yourself. Blocks are added, reordered and edited here, then saved as a template or scheduled to generate on a recurring basis.

{% hint style="info" %}
Live test results and database content are loaded for the tenant selected in [tenant-select.md](../../shared-features/menu-bar/tenant-select.md "mention"), so what you see while building is that tenant's real data. Blocks you fill in by hand, such as text, layout and **Manual** charts, work without a tenant selected. When the template is later generated for a different tenant, the data is collected fresh for that tenant.
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
| Always use the latest saved version of this template | Ties the schedule to the saved template rather than to a copy of the blocks. Only offered once the report has been saved as a template. |

The delivery options behave differently:

* **Email** sends the report body as the message, to the address configured in [notifications.md](../../cipp/settings/notifications.md "mention"). The report is attached as a PDF, followed by any database blocks marked for attachment. An attachment that would take the email over Microsoft's 4 MB limit is uploaded to storage instead and listed in the email as a download link, kept for the period set under [Report Attachment Retention](../../cipp/settings/README.md#report-attachment-retention). If the upload fails, the attachment is left off.
* **PSA** raises a ticket with the report body as its content. Raw data is not attached.
* **Webhook** posts a JSON payload of the task metadata and results.
* **Push (notify me)** sends a notification to the devices you registered under [user-settings.md](../../shared-features/menu-bar/user-settings.md "mention"). It tells you when each run has finished. Only you receive it, and the schedule is only saved with it once you have registered at least one device.

What the schedule generates depends on **Always use the latest saved version of this template**. With it on, the schedule points at the saved template, so every run picks the template up as it stands at that moment and later edits are applied automatically. Anything you have changed in the builder but not yet saved to the template is not included, so save before you schedule.

With it off, and on any report that has not been saved as a template yet, the schedule captures the blocks and page setup as they stand when you create it. Editing the template afterwards does not change that schedule, so recreate the schedule if the report changes.

</details>

<details>

<summary>Preview PDF</summary>

Opens the rendered report in a dialog so you can check pagination, branding and layout before saving. The preview includes its own **Download PDF** button.

</details>

**Download PDF** renders the report and downloads it immediately, without saving anything.

## Adding Blocks

Blocks are added from the **Report Settings** card. Choose a **Category**, then a **Block** from that category, complete whatever fields appear for it, and select **Add Block**. Repeat for each section the report needs. Blocks are appended to the bottom and can be reordered afterwards.

**Text**

| Block         | Description                                                                                              |
| ------------- | -------------------------------------------------------------------------------------------------------- |
| Custom Block  | A free-form section you write yourself using a rich text editor, for structure, narrative or commentary. |
| Note          | A small italic aside, the size of a caption.                                                             |
| Bullet List   | A list of points, each with a bold lead and the text that follows it.                                    |
| Numbered List | A numbered list of steps.                                                                                |
| Indented Text | Body text stepped in under a heading.                                                                    |
| Code Block    | A command or snippet in a monospaced block.                                                              |
| Callout       | A boxed callout with a title and text, styled as Info, Good news or Warning.                             |
| Callout Grid  | Several callouts laid out 1, 2 or 3 across.                                                              |

**Data**

| Block         | Description                                                                                                                                                                                                                                          |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Test Result   | A section tied to CIPP's test suite results. Choose a **Test Suite**, then one or more tests under **Select Tests**. Selecting several tests adds a separate block for each, and **Add All Tests** adds every test in the chosen suite in one go. |
| Database Data | A section populated from the cache database. Choose a **Data Source** and a **Format** of Table (Text), CSV or JSON.                                                                                                                                 |
| Table         | A formatted table with columns you name, filled by hand or from a data source.                                                                                                                                                                       |

**Visuals**

| Block         | Description                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------- |
| Chart         | A donut, bar or trend line chart, at full width or half width so two sit side by side.      |
| Flow (Sankey) | A flow diagram whose ribbon widths show how a total splits between stages or measures.      |
| Score Cards   | A row of headline figures, each a figure and a label.                                       |
| Progress Bars | Labelled bars showing a value against a maximum, useful for coverage figures.               |

**Layout**

| Block       | Description                                                                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Cover       | The cover page. Leave the title blank to use the report's name.                                                                               |
| Titled Page | Starts a new page with a title and subtitle in its header. The blocks that follow land on it.                                                 |
| Infographic | A full page with a big figure, headline and supporting text over a background image that bleeds to the paper edge.                             |
| Divider     | A horizontal rule to separate sections.                                                                                                       |
| Page Break  | Forces the following content onto a new page.                                                                                                 |

The **Background** of an Infographic block offers the stock cover images and every cover uploaded in [branding.md](../../cipp/settings/branding.md "mention"), listed by the name given to it there.

**Pre-built**

Pre-built blocks arrive already set up to draw from the tenant's data, so common dashboard visuals do not have to be assembled by hand. The **Block** list offers a topic, and where the topic has more than one visual, a **Chart type** field appears to choose between them.

| Topic              | Visuals                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| Secure Score       | Trend, Controls to improve (table)                                                               |
| Licences           | Usage (bar), Summary (table), Flow (Sankey)                                                      |
| MFA                | Registration (donut), Coverage flow (Sankey), Auth methods (Sankey)                              |
| Conditional Access | By state (donut)                                                                                 |
| Devices            | Compliance (donut), Compliance flow (Sankey), By OS, By manufacturer, By ownership, By encryption (all donut) |
| Users              | By type (donut)                                                                                  |
| Mailboxes          | By type (donut), Busiest by items, Largest by storage, Top senders, Top recipients (all bar)     |
| Groups             | By type (donut)                                                                                  |
| Domains            | Mail security (table)                                                                            |
| Risky users        | By risk level (donut)                                                                            |
| Tenant             | Summary (cards)                                                                                  |

A pre-built block is an ordinary block once added, so it can be edited like any other. Where CIPP holds no data for the tenant on that topic, the block shows that no data is available rather than failing the report.

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
| Rows           | The number of rows in the table.                                                                                | Table         |
| Flow           | The number of nodes, or **from data** when the flow is read from a data source.                                 | Flow (Sankey) |
| Callout style  | The callout's style, or the number of callouts in a grid.                                                       | Callout, Callout Grid |

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

Some values are presented for readability rather than shown as the data source holds them. Licence assignments appear as product names, such as Microsoft 365 Business Premium, separated by commas. A Cloud PC that reports no encryption state is shown as **Encrypted (platform-managed)**, because Cloud PCs are encrypted by the platform rather than by BitLocker. Both apply in all three formats.

The preview lists every licence assigned, falling back to the licence's SKU name and then its identifier where the product name is not known. A generated report names licences the way the rest of CIPP does, so the licences you have excluded in [licenses.md](../../cipp/settings/licenses.md "mention") do not appear in it. Where CIPP holds no licence data for the tenant, the raw values are shown instead.

### Structured Block Editing

Chart, Flow (Sankey), Table, Score Cards and Progress Bars blocks each start with a choice of where their data comes from.

| Source             | Description                                                                                                                                                                                                                                                      |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Manual             | The values are typed in as a small table. Add a row for each data point, giving it a label and a value, with an optional colour on chart data points and score cards.                                                                                           |
| Reporting database | The values are read from data CIPP has collected for the tenant each time the report is generated. Pick a **Collection**, then choose what to **Show** (a count of rows or a field's value) and what to show it **Per**. **Only rows where** narrows the rows counted. |

The collections on offer include the tenant's test results alongside its collected data, so a chart or table can summarise test outcomes too.

Score card colours and captions, and each progress bar's own target, are only set in **Manual**. Using a data source, each bar is filled by its share of the total.

Manual score card and progress bar figures also accept data tokens, which are read when the report is generated. `&Users&` counts a collection, `&Devices.complianceState=compliant&` counts the rows that match, and `&Mailboxes.TotalItemSize:sum&` adds a field up.

Charts also take a caption. A donut chart takes a centre label, and a trend line takes an **Axis maximum**, which uses the highest value when left blank.

### Flow (Sankey) Editing

A Flow block also takes a title and a **Caption**. In **Manual**, the diagram is described in two tables:

| Table | Description                                                                                                                                  |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Nodes | The boxes in the diagram. Each has a **Node ID**, a **Colour** in hex or `hsl()`, and an optional **Label** shown in place of the ID.         |
| Links | The ribbons between boxes. Each joins a **From (node ID)** to a **To (node ID)**, and its **Value** sets how thick the ribbon is drawn.        |

Columns and box heights are worked out from the links, so there is no layout to arrange by hand.

With **Reporting database**, pick a **Collection** and then the shape of the flow:

| Shape               | Description                                                                                                                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Flow between fields | Rows flow from one field's values to the next. Choose a **From field** and a **To field**, and optionally a third stage under **Then (optional)**. Ribbon widths reflect the number of rows taking each path. |
| Split by measures   | One **Category field** on the left fans out into numeric fields on the right, for example a licence splitting into assigned and available. Add a row per measure, giving the **Value field** and how it is **Shown as**. |

**Only rows where** narrows the rows used, with a **Condition** of is or is not and a **Value** to match.

A Flow block added from **Pre-built** matches the equivalent dashboard diagram and has no fields to edit. **Switch to a custom flow** replaces it with an empty data-driven flow you set up yourself.

### Callout Editing

A Callout takes a **Callout title**, a **Style** of Info, Good news or Warning, and its **Text**, which accepts Markdown for bold, italic and links. An Info callout also takes a **Tone** of Default, Positive or Attention to tint it. **Label : value lines** switches the text to one `Label: value` pair per line, set as tight lines.

A Callout Grid sets its **Layout** to 1, 2 or 3 across and shows the callouts arranged that way while you edit. Each callout has its own **Title** and **Text**. **Add callout** adds another, and **Remove callout** deletes one, down to a minimum of one.

{% include "../../../../.gitbook/includes/feature-request.md" %}
