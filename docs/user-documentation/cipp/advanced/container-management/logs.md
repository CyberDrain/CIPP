# Logs

The Logs page lets you view and search the application logs produced by the CIPP API container. Logs are read directly from the container's local log files, which are rotated by size and retained on disk, so you can investigate recent activity, warnings, or errors from within CIPP itself. Because it reads the logs of the running instance, this is a diagnostic tool.

Logs can be queried in two ways, selected by the tabs at the top of the Log Query panel: a free-form **Query Editor** for writing filter expressions directly, and a **Guided Filter** for building a search from labelled fields. Each mode has its own Clear button, which resets the form and empties the results. The panel collapses automatically once a query runs so the results have room, and can be expanded again from its header.

## Log Query

### Query Editor

The Query Editor lets you write a filter using a KQL-inspired pipe syntax. Clauses are separated with the `|` character and applied in order. Enter your expression in the Log Query box and select **Run Query** to execute it.

The supported clauses are:

| Clause                                         | Purpose                                               |
| ---------------------------------------------- | ----------------------------------------------------- |
| `where Level == "ERR"`                         | Match a single log level exactly.                     |
| `where Level in ("ERR", "CRT")`                | Match any of several log levels.                      |
| `where Level != "DBG"`                         | Exclude a log level.                                  |
| `where Message contains "text"`                | Match entries whose message contains the text.        |
| `where Message !contains "text"`               | Exclude entries whose message contains the text.      |
| `where Message matches regex "err\|fail"`      | Match messages against a regular expression.          |
| `where Timestamp > ago(1h)`                    | Match entries newer than a relative time (s/m/h/d/w). |
| `where Timestamp between (ago(2h) .. ago(1h))` | Match entries within a time range.                    |
| `take 500`                                     | Limit the number of results returned.                 |
| `sort by Timestamp desc`                       | Sort the results, newest first.                       |
| `search all files`                             | Include rotated log files in the search.              |

The **Load Preset** dropdown loads a built-in example query into the editor as a starting point, which you can then run as-is or adjust. The available presets are:

| Preset                            | What it returns                                                              |
| --------------------------------- | ---------------------------------------------------------------------------- |
| Recent Errors (Last 1h)           | Error and critical entries from the last hour.                               |
| Warnings & Errors (Last 24h)      | Warning, error, and critical entries from the last 24 hours.                 |
| All Logs (Last 15 min)            | Every entry from the last 15 minutes.                                        |
| Startup Logs                      | Entries recording service startup, with heartbeat noise removed.             |
| Graph API Errors                  | Error and critical entries mentioning Graph, from the last 24 hours.         |
| Token / Auth Issues               | Entries mentioning token or authentication problems, from the last 24 hours. |
| Timeout Errors                    | Entries mentioning timeouts or canceled tasks, from the last 24 hours.      |
| All Errors (Search All Files)     | Error and critical entries across all log files, including rotated ones.     |
| Standards Processing              | Entries relating to Standards processing, from the last 24 hours.            |
| Full Log (Last 1h, no heartbeats) | All entries from the last hour with heartbeat noise removed.                 |

### Guided Filter

The Guided Filter builds a search from labelled fields without writing a query, reading the local log files directly. Set the fields you need and select **Search Logs** to run the search.

| Field                                | Description                                                                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Time Range                           | Restrict results to a preset window (from the last 15 minutes up to the last 24 hours), a custom range, or no time filter at all. |
| Log Level                            | Restrict results to a single severity, or all levels.                                                                             |
| Search Text                          | Only include lines containing this text.                                                                                          |
| Max Lines                            | The maximum number of matching lines to return. Defaults to 500.                                                                  |
| Exclude Text                         | Omit any lines containing this text.                                                                                              |
| Regex Pattern                        | Only include lines matching this regular expression.                                                                              |
| Newest First                         | Sort the results with the most recent entries at the top.                                                                         |
| From (UTC) / To (UTC)                | Shown only when Time Range is set to Custom Range. The start and end of the custom window, entered in UTC.                        |
| Log File                             | Choose which log file to search: the current log, or a specific rotated file (rotated files show their size).                     |
| Search All Files (including rotated) | Search across every log file rather than a single one. When enabled, the individual Log File selection is ignored.                |

## Table Details

Results are shown in a table with the following columns. Selecting a row opens a details flyout showing the entry's full message and, where it differs, the raw log line it was parsed from.

| Column    | Description                                  |
| --------- | -------------------------------------------- |
| Timestamp | The date and time the log entry was written. |
| Level     | The severity of the log entry.               |
| Message   | The log message text.                        |

Log entries are categorised by severity level:

| Level       | Code |
| ----------- | ---- |
| Debug       | DBG  |
| Information | INF  |
| Warning     | WRN  |
| Error       | ERR  |
| Critical    | CRT  |

{% include "../../../../../.gitbook/includes/feature-request.md" %}
