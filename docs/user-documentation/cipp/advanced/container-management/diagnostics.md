# Diagnostics

The Diagnostics page answers the question "why did my instance misbehave, and what was happening at the time". A sample of the container's own log is taken every five minutes and reduced into a health record, so the page can look back over days rather than only at the current moment. It turns those samples into a set of health checks, a timeline of requests, egress, heap and worker pressure, a list of restart and out-of-memory events, and a breakdown of which API clients the traffic came from. Samples are kept for 14 days, which covers the longest window the page offers.

Immediately after a new instance is deployed there is nothing to show, and the page says so. It fills in as the instance keeps running.

## Page Controls

| Control | Description                                                                                                                  |
| ------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Window  | Sets the period every section reports on: 6h, 24h, 3d, 7d, or 14d. The page opens on 24h.                                     |
| Refresh | Reloads the checks and the timeline for the selected window. A spinner beside the window buttons shows while data is loading. |

## Checks

Health checks for the selected window, worst first, so anything failing is at the top. Each check reports one of four states: Failed, Warning, Info, or Passed. Selecting a row opens a flyout that adds the suggested fix, which is only present on checks that are not passing.

| Check                  | Description                                                                                                                                                    |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Out of memory          | Whether any out-of-memory errors were recorded. Any at all is a failure, and means the process hit its memory limit.                                            |
| Heap headroom          | Peak memory use against the limit. Warns as headroom gets tight, and fails when the instance is one burst away from an out-of-memory restart.                   |
| Watchdog restarts      | Whether the process failed to stay up and had to be restarted.                                                                                                 |
| HTTP worker pool       | Whether requests had to queue because no worker was free.                                                                                                      |
| Stalled runs           | Whether any run reported pending work with nothing actually running.                                                                                            |
| `egress`               | How much API data has been served today against the daily budget, where one is set. Fails once the budget is reached and requests are being turned away.        |
| API clients            | How many authenticated API calls were made, from how many clients, and which was busiest. Warns when a single integration dominates the instance.               |
| Container restarts     | How many times the container restarted. Repeated restarts usually follow an out-of-memory kill or an update loop.                                               |
| Orchestrator           | Whether a run has sat with pending work for more than two hours. A stalled run can be cancelled from [worker-health.md](worker-health.md "mention") so its work re-queues. |
| Platform container log | Container stop events recorded by the hosting platform, which shows the platform cycling the container even where CIPP itself logged nothing.                   |

## Health Timeline

Charts sharing the selected window and the same five-minute intervals, so a spike in one can be lined up against the others.

| Chart                | Shows                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| API Requests / 5 min | Authenticated API requests, stacked by client. The four busiest clients over the window each get their own colour, and everything else is grouped as Other.                                     |
| API Egress / 5 min   | Data served to API clients. The caption gives today's total, and the share of the daily budget it represents where one is set. Only appears when egress is being accounted for.                 |
| Heap (MB)            | Memory in use over time, with a dashed line marking the limit, and dashed markers where a restart or an out-of-memory event occurred.                                                           |
| Pool Pressure        | How often the worker pool ran out, alongside the longest a request waited for a worker. Only appears where there was pool exhaustion, or a wait of ten seconds or more.                         |

Below the timeline, an API Egress card shows a used-of-cap gauge for the instance total and a stacked per-client trend, switchable between 24h, 3d and 7d. It only appears on hosted instances with egress accounting enabled, and is separate from the API Egress / 5 min chart above, which follows the page's own window selector rather than its own range toggle.

## Restart & Out-of-Memory Events

Every container restart and out-of-memory event in the window, alongside the traffic that preceded it, so an event can be tied to whatever was pushing the instance at the time.

| Column                      | Description                                                                                                                                       |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Time                        | When the event happened.                                                                                                                          |
| Event                       | Container restarted, or Out of memory.                                                                                                            |
| Outage                      | For a restart, how long the instance was unavailable.                                                                                             |
| Busiest Client Before Event | The API client making the most calls in the hour before the event.                                                                                |
| Requests In Prior Hour      | How many calls that client made in that hour.                                                                                                     |
| Baseline / Hr               | What that client normally makes in an hour, for comparison.                                                                                       |
| Ratio                       | The prior hour against the baseline. A high multiple points at the client that caused the event, rather than one that is simply always busy.       |

Selecting a row lists every client active around the event, with the same counts, baselines and ratios. Selecting one of those clients shows its individual log lines, which is the fastest route from "the instance restarted" to "this is what it was being asked to do".

## API Clients

Every API client seen in the window, busiest first, whether or not anything went wrong.

| Column  | Description                                         |
| ------- | ----------------------------------------------------- |
| Client  | The application making the calls.                   |
| IP      | The address the calls came from.                    |
| Count   | Total calls in the window.                          |
| Share % | That client's share of all API calls in the window. |

Selecting a row shows the log lines for that client, with their timestamp, level and message.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
