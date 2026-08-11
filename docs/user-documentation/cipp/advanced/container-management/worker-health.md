# Worker Health

The Worker Health page is a real-time monitoring dashboard for the CIPP API container. It surfaces the state of the container's worker pools, the background job queue, resource usage, historical performance trends, the internal test-data cache, and the timing of the container's most recent startup. It is intended for diagnosing performance and capacity issues on a self-hosted CIPP instance. While the page is open it refreshes automatically: the live snapshot every few seconds, with historical trends and cache diagnostics on their own longer intervals.

## Page Controls

A toolbar at the top of the page controls refreshing and lets you capture or review data.

| Control        | Description                                                                                                                                                                         |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Uptime         | How long the container has been running since its last start.                                                                                                                       |
| Pause / Resume | Pauses or resumes the automatic refresh of the page, so you can inspect a moment in time without the figures changing underneath you.                                               |
| Export         | Downloads the current page data (the live snapshot, startup timing, historical trends, and job queue) as a JSON file.                                                               |
| Import         | Loads a previously exported JSON file for review. While imported data is being viewed the page stops refreshing and shows an indicator, which you can clear to return to live data. |

## Status Overview

At the top of the page, a bar of key indicators gives an at-a-glance view of the container's health. Each indicator is color-coded, turning amber or red as it approaches or exceeds its threshold.

| Indicator    | Shows                                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------------------- |
| HTTP Workers | Busy versus total HTTP workers.                                                                         |
| BG Workers   | Busy versus total background workers.                                                                   |
| Job Queue    | The number of jobs currently running and queued.                                                        |
| BG Limiter   | Active versus maximum background concurrency, or a throttled warning when HTTP work is being throttled. |
| Memory       | Container memory used versus its limit, with the usage percentage.                                      |
| CPU          | Container and application CPU usage.                                                                    |

Below the indicator bar, a compact stats panel breaks the same areas down in more detail: the HTTP and BG pools (size, busy count, invocations, utilisation, average duration, and faults); Jobs (running, queued, completed, failed); the Limiter (active/maximum, waiting, and throttle status); Memory (container used and limit, application RSS, other processes, GC heap, committed, GC limit, usage percentage, and garbage-collection counts); and CPU (container, application, and other). Any figure that crosses a warning threshold is shown in red.

## Worker Pools

Two tables list every worker in the container: one for the HTTP pool, which handles interactive and API requests, and one for the Background pool, which runs queued and scheduled jobs. Both tables share the same columns.

| Column      | Description                                                                                               |
| ----------- | --------------------------------------------------------------------------------------------------------- |
| Worker      | The worker's identifier, shown as "W" followed by its number.                                             |
| Status      | Whether the worker is Idle or Busy. When busy, the name of the function it is currently running is shown. |
| Invocations | The total number of function invocations the worker has handled.                                          |
| Utilization | How busy the worker has been, as a percentage.                                                            |
| Avg         | The average execution duration across the worker's invocations.                                           |
| Min         | The shortest execution duration recorded.                                                                 |
| Max         | The longest execution duration recorded.                                                                  |
| Last        | The duration of the worker's most recent invocation.                                                      |
| Alloc       | Total memory allocated by the worker. Hovering shows the total, last, and average allocation per call.    |
| Faults      | The number of faults the worker has encountered.                                                          |

## Job Queue

The Job Queue lists the background jobs known to the worker system, newest first. Two toggles above the table control what is loaded: a status toggle (All, Queued, Running, Completed, Failed, or Canceled) and a load limit (500, 2k, 5k, or 10k).

The status toggle filters on the server, before the load limit is applied, so the limit applies to the selected status rather than to all jobs. This matters on a busy instance: with a large backlog of completed jobs, loading All would fill the entire limit with completed work and show no queued jobs at all. Select Queued to see the jobs still waiting to run, regardless of how much history sits behind them.

### Table Details

| Column          | Description                                                             |
| --------------- | ----------------------------------------------------------------------- |
| Name            | The name of the job's function.                                         |
| RunName         | The name of the run that the job belongs to, where applicable.          |
| Priority        | The job's priority, where 0 is the highest.                             |
| Status          | The job's current state, such as Queued, Running, Completed, or Failed. |
| QueuedUtc       | The date and time the job was queued, in UTC.                           |
| WaitSeconds     | How long the job waited in the queue before it started running.         |
| DurationSeconds | How long the job took to run.                                           |

### Table Actions

| Action          | Description                                                                                      | Bulk Action Available |
| --------------- | ------------------------------------------------------------------------------------------------ | --------------------- |
| Cancel Job      | Cancels the selected job. Available for jobs that are still queued.                              | ☑                     |
| Change Priority | Sets a new priority for the selected queued job, where 0 is the highest.                         | ☑                     |
| Cancel Run      | Cancels every queued job belonging to the same run as the selected job.                          | ☑                     |
| Delete          | Removes the selected job from the list. Available for jobs that are no longer queued or running. | ☑                     |

## Historical Trends

This section charts key metrics over a selected time window. A toggle sets the window (1h, 6h, 24h, 3d, or 7d), and a refresh button reloads the trend data. Collection of trend data begins around 60 seconds after the container starts, so the charts are empty immediately after a restart.

| Chart                  | Shows                                                                             |
| ---------------------- | --------------------------------------------------------------------------------- |
| Worker Utilization %   | HTTP and background worker utilisation over time.                                 |
| Invocations / Interval | HTTP and background invocations per interval.                                     |
| Memory Usage (MB)      | Container total, application RSS, other processes, GC heap, and committed memory. |
| CPU Usage %            | Container, application, and other CPU usage.                                      |
| Job Queue Depth        | The number of queued and running jobs over time.                                  |
| Faults & Avg Duration  | HTTP and background fault counts alongside their average durations.               |

## TestData Cache

This section reports on the container's in-memory test-data cache. The header shows the number of active and expired entries and the estimated size, with an entry-count chip that turns amber or red as the cache grows, and a capacity bar showing the tracked size against the configured maximum. The following figures are reported:

| Statistic | Description                                                                                 |
| --------- | ------------------------------------------------------------------------------------------- |
| Hits      | The number of reads served from the cache.                                                  |
| Misses    | The number of reads that were not found in the cache.                                       |
| Hit Rate  | The proportion of reads served from the cache.                                              |
| Evictions | The number of entries removed to make room for others.                                      |
| Oversized | Values that exceeded the per-entry size cap and were dropped rather than cached.            |
| Accesses  | The total number of times the cache has been accessed.                                      |
| TTL       | How long entries live before expiring. Hovering shows the earliest and latest expiry times. |

When present, a breakdown table lists each cached data type with the number of tenants it covers, the total number of items, and its estimated size in megabytes.

## Startup Timing

At the bottom of the page, a stacked bar shows how long each phase of the container's most recent startup took. The header summarizes the run: the readiness and warmup modes, the CPU count, the HTTP and background pool sizes, and the total startup time. Hovering a segment shows that phase's duration and the number of functions loaded, and the legend reports the shared, HTTP-only, and background-only module counts.

| Phase          | Description                                                |
| -------------- | ---------------------------------------------------------- |
| Base Worker    | Bringing up the base worker process.                       |
| Warmup         | Warming up the workers before serving traffic.             |
| HTTP Ready     | Reaching the point where the HTTP pool can serve requests. |
| HTTP Pool Full | Bringing the full HTTP worker pool online.                 |
| BG Ready       | Reaching the point where the background pool can run jobs. |
| Fully Ready    | The container becoming fully ready.                        |

{% include "../../../../../.gitbook/includes/feature-request.md" %}
