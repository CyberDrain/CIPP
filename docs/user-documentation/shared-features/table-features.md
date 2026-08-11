# Table Features

Most list pages in CIPP share the same table component, so the toolbar, filtering, sorting and export behavior described here applies across the application. Individual pages may hide features that do not apply to them, but where a feature is present it works the same way everywhere.

## Live and Cached Data

Some tables can display either live data, pulled directly from Microsoft Graph, Exchange or another upstream service, or a cached copy held in CIPP's reporting database and refreshed periodically.

The current mode is shown as a chip at the top of the page:

| Chip       | Meaning                                                          |
| ---------- | ---------------------------------------------------------------- |
| **Live**   | Data is being retrieved from the upstream service on every load. |
| **Cached** | Data is being read from CIPP's reporting database.               |

Where the page supports both modes, clicking the chip switches between them. On pages that only ever read from the reporting database the chip is not clickable, and hovering over it explains why.

When the table is in cached mode a **Sync** button appears alongside the chip. This queues a background task to refresh the cache for the selected tenant, and the queue tracker will update the table once the sync completes.

Cached mode also adds a **Cache Timestamp** column so you can see how old the data is. When AllTenants is selected, a **Tenant** column is added as well.

{% hint style="info" %}
AllTenants always uses cached data, even on pages that otherwise allow the toggle. The **Sync** button is disabled under AllTenants unless the page explicitly supports syncing every tenant at once.
{% endhint %}

## Toolbar

The toolbar sits above every table and holds the search box, filtering, column selection and export controls.

### Refresh

The circular arrows button reloads the table data. While a request is in progress the icon spins and the button is disabled. If CIPP could not retrieve every page of a large result set the icon changes to a warning symbol, and clicking it retries the outstanding requests.

### Search

Typing in the search box filters the table to rows containing the text you enter, matched against all visible columns. The search is applied shortly after you stop typing rather than on every keystroke, so large tables stay responsive. Clearing the box restores the full result set.

{% hint style="info" %}
For more precise matching, use column filters instead. These support a full range of operators, described under [#column-filtering-options](table-features.md#column-filtering-options "mention").
{% endhint %}

### Filters

The **Filters** button opens a menu of preset filters for the page you are viewing. When any filter is active the button is highlighted and shows a count, for example **Filters (2)**.

| Menu entry                                | Description                                                                                                                                                                                                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Show Column Filters / Hide Column Filters | Toggles the per-column filter row beneath the column headers.                                                                                                                                                                               |
| Reset all filters                         | Clears every active filter, the search box and any column selections made by a preset, returning the table to its default state.                                                                                                            |
| Edit filters                              | Opens the filter builder so you can construct or amend a query by hand. Only shown on pages backed by Graph Explorer.                                                                                                                       |
| Graph filters                             | Presets that change the request sent upstream, for example by narrowing the properties returned or applying a server-side query. On Graph Explorer backed pages, any custom presets you have saved appear here alongside the built-in ones. |
| Table filters                             | Presets that filter the rows already loaded into the table.                                                                                                                                                                                 |

Graph filters and table filters occupy separate slots, so one of each can be active at the same time and their effects stack. Active presets are marked with a tick, and selecting a preset that is already active clears it. Within the table slot only one preset applies at a time, so choosing a new one replaces the previous selection.

If you enable **Save last used table filter** in your user preferences, CIPP remembers the filters you had applied on each page and restores them the next time you visit.

### Columns

The **Columns** button controls which columns are visible.

| Menu entry                 | Description                                                                             |
| -------------------------- | --------------------------------------------------------------------------------------- |
| Reset to preferred columns | Restores the column selection to the page defaults.                                     |
| Save as preferred columns  | Saves the current selection so it is applied automatically whenever you open this page. |
| Delete preferred columns   | Removes your saved selection for this page.                                             |
| Column list                | Tick or untick individual columns to show or hide them.                                 |

Preferred columns are stored per page in your browser's local storage, so they follow the browser and profile you are working in rather than your CIPP account.

### Export

The **Export** button offers several ways to take the data out of CIPP.

| Menu entry             | Description                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| Export to CSV          | Downloads every filtered row, using the currently visible columns.                        |
| Export to PDF          | Produces a PDF report of every filtered row, using the currently visible columns.         |
| Export Selected to CSV | Downloads only the rows you have ticked. Shown when at least one row is selected.         |
| Export Selected to PDF | Produces a PDF of only the rows you have ticked. Shown when at least one row is selected. |
| View API Response      | Opens a flyout showing the raw JSON returned by the API call behind the table.            |

### Queue Status

When a page has queued a long-running background task, a queue status button appears on the right of the toolbar with a badge showing outstanding work. Clicking it opens a panel with the task name, progress and per-item results. When the task finishes, the table refreshes automatically.

### Narrow Screens

On smaller viewports, and whenever the toolbar runs out of room, the **Filters**, **Columns** and **Export** buttons collapse into a single menu behind the vertical ellipsis. That menu also offers **Fullscreen**, which expands the table to fill the window, and **Exit Fullscreen** to return.

## Row Selection and Actions

Most tables include an **Actions** column pinned to the right of the table. Clicking the ellipsis in a row opens the actions available for that row.

Ticking the checkboxes at the left of one or more rows shows a count of the selected rows in the toolbar along with a **Bulk Actions** button, which applies a single action to every row you have selected. Only actions that support bulk operation appear in this menu. Where an action only applies to certain rows, the selection is narrowed automatically to the eligible ones.

The selection checkbox column is pinned to the left and the actions column to the right, so both stay visible as you scroll horizontally. The column headers remain fixed as you scroll vertically.

## Column Options

Clicking the menu icon in a column header opens the options for that column.

| Option                            | Description                                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Clear sort                        | Removes any sorting applied to this column.                                                             |
| Sort by \<column name> ascending  | Sorts the column from smallest to largest, 0 to 9, or A to Z.                                           |
| Sort by \<column name> descending | Sorts the column from largest to smallest, 9 to 0, or Z to A.                                           |
| Clear filter                      | Clears any filter applied to this column.                                                               |
| Filter by \<column name>          | Reveals the filter row and focuses this column's filter input.                                          |
| Pin to left                       | Freezes the column against the left edge of the table so it stays visible while scrolling horizontally. |
| Pin to right                      | Freezes the column against the right edge of the table.                                                 |
| Unpin                             | Returns a pinned column to its normal position in the column order.                                     |
| Hide \<column name> column        | Removes the column from view without changing your saved preferences.                                   |
| Show all columns                  | Makes every available column visible, including those hidden by default.                                |

{% hint style="info" %}
Dates, numbers and true/false values are sorted using rules appropriate to their type rather than as plain text, so dates order chronologically and numbers order by value. Rows with no value in the sorted column are always placed at the end, in both ascending and descending order.
{% endhint %}

## Column Filtering Options

Each column filter has an operator, chosen from the icon inside the filter input. The operators offered depend on the type of data in the column.

| Filter                   | Description                                                                                                                                            |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Fuzzy                    | Returns all results where the value is similar to what is input.                                                                                       |
| Contains                 | Returns all results where the value contains the input.                                                                                                |
| Starts With              | Returns all results where the value starts with the input.                                                                                             |
| Ends With                | Returns all results where the value ends with the input.                                                                                               |
| Equals                   | Returns all results where the value exactly matches the input.                                                                                         |
| Not Equals               | Returns all results where the value does not match the input.                                                                                          |
| Between                  | Returns all results where the value falls between the two inputs, excluding the inputs themselves.                                                     |
| Between Inclusive        | Returns all results where the value falls between the two inputs, including the inputs themselves.                                                     |
| Greater Than             | Returns all results where the value is greater than the input.                                                                                         |
| Greater Than Or Equal To | Returns all results where the value is greater than or equal to the input.                                                                             |
| Less Than                | Returns all results where the value is less than the input.                                                                                            |
| Less Than Or Equal To    | Returns all results where the value is less than or equal to the input.                                                                                |
| Empty                    | Returns all results where there is no value for this column.                                                                                           |
| Not Empty                | Returns all results where there is a value for this column.                                                                                            |
| Not Contains             | Returns all results where the value does not contain the input.                                                                                        |
| Regex                    | Returns all results matching the regular expression you supply. Matching is case insensitive, and an invalid expression leaves the results unfiltered. |

Columns holding true/false values present a drop-down in place of the text input, letting you filter on `Yes` for true and `No` for false.

## Value Display

Some values are given a graphical representation for ease of reading.

| Value type      | Description                                                                                                                                                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Boolean         | Displayed as a tick for `true` and a crossed circle for `false` rather than the words themselves. Exports render these as `Yes` and `No`.                                                                                  |
| List of values  | Displayed as a row of chips. The first four are shown, followed by a **+N more** link that expands the rest and a **Show less** link to collapse them again. Clicking a chip copies its value to the clipboard.            |
| Complex data    | Displayed as a button showing the number of items it contains. Clicking the button opens a dialog with a second table listing the contents. Where there is nothing to show, the button reads **No items** and is disabled. |
| Dates and times | Displayed as a relative time, for example "about 2 months ago".                                                                                                                                                            |

## Column Sizing

Column widths are calculated when the table loads, based on the length of the column heading and a sample of the values in that column, within fixed minimum and maximum limits. Columns holding chips or item buttons are sized to suit that content rather than the underlying text.

You can adjust a width yourself by hovering over the divider between two column headers and dragging it. Manual resizing is not saved and resets the next time the page loads.

## Pagination

Tables are paged, with a control at the foot of the table for moving between pages and choosing how many rows are shown at a time. The available page sizes are 25, 50, 100, 250 and 500. The starting value comes from the **Default Page Size** setting in your user preferences.

Only the rows and columns currently in view are rendered, which keeps large result sets responsive while scrolling.

{% include "../../../.gitbook/includes/feature-request.md" %}
