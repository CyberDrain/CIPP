---
description: >-
  How CIPP collects audit logs and checks them against your audit log alerts: what an alert can test, the rules it
  must follow, the limits that keep alerting fast, and why.
---

# How Audit Log Alerts Work

This page is the reference for anyone writing audit log alerts or supporting the people who do. It explains how a Microsoft 365 audit record reaches an alert, what a condition can test, the rules CIPP enforces when you save an alert, and what each limit protects. For the form itself, see [alert.md](alert.md "mention").

## At a glance

| | |
| --- | --- |
| Source | The Office 365 Management Activity API, read for each tenant every 15 minutes. |
| Logs | Entra ID (`Audit.AzureActiveDirectory`), Exchange (`Audit.Exchange`), SharePoint and OneDrive (`Audit.SharePoint`), and General (`Audit.General`: Teams, Microsoft Forms, Defender quarantine, Purview and other workloads). |
| Delay | Microsoft publishes most records within minutes, and some much later. CIPP checks each tenant's logs every 15 minutes, so a typical alert arrives 5 to 30 minutes after the event. |
| Matching | Every record is checked once, against every enabled alert that covers the tenant and reads the record's log. A record raises at most one alert. |
| Kinds of alert | A **single-record alert** fires on each record that matches. A **repeated activity alert** fires when one user or app does something a set number of times within a window. |
| Saved copy | Every record that raises an alert is saved and shown under **Saved Logs**, where you can also check it against your alerts. |

## How a record reaches an alert

Each 15-minute cycle runs these steps for every tenant that has audit log alerts:

1. **List.** CIPP asks Microsoft which new batches of records each log has published since it last looked. One listing covers at most 3 hours, so a tenant that fell behind catches up over a few cycles. CIPP never reads further back than 6 hours: after a longer outage, the older records are skipped and a warning is logged.
2. **Download.** Batches are downloaded 16 at a time, in tasks of up to 64 batches, with at most 80 tasks per run. A batch that fails to download is retried on later cycles. A batch is queued at most 5 times; after that it is dropped and an error is written to the CIPP logbook. **Diagnostics** shows how many batches failed in each cycle.
3. **Skip what no alert can match.** Before reading a batch, CIPP checks its text for the operation names your alerts use. A batch that contains none of them is skipped unread. Within a batch that is read, only records whose operation (and other plain-text values) some alert could match are fully built. Most records never get past this step, which is why the rules on the Operation condition below matter.
4. **Enrich.** Each remaining record gets the fields CIPP adds (see [Fields CIPP adds](#fields-cipp-adds)): names for the IDs it contains, the location of its IP address, the time of day, and so on.
5. **Match.** The record is checked against each alert that reads its log, in turn. The first alert it matches is the one that fires. Other alerts that would also have matched do not fire for the same record; the alert check on the saved log shows them as **Also matches**. Alerts with a [priority](#priority) are checked first, lowest number first. The rest follow in the order CIPP stores them, by an internal ID, not by name or creation date. Give overlapping alerts a priority to choose which one fires.
6. **Act and save.** The alert's actions run (email, webhook, PSA ticket, disabling the user or BEC remediation), and the record is saved as a log you can open later. Emails and PSA tickets link to the saved log and to the settings of the alert that fired; a webhook carries the same links as `SavedLogUrl` and `AlertConfigurationUrl`.

Repeated activity alerts take a different path after step 3: CIPP counts each user's records of the alert's operations without building them, and fires once a count reaches the threshold. See [Repeated activity alerts](#repeated-activity-alerts).

{% hint style="info" %}
Alert rule changes take effect from the next collection task, within 15 minutes. Changes to tenant groups and custom variables are picked up the same way.
{% endhint %}

## Building conditions

A condition is a **property**, an **operator** and a **value**. All conditions in a group must hold for the group to match.

### Properties

You can test any property of the audit record by name, not only those offered in the list. Typing a name that is not in the list creates it as a text property.

* **Top-level fields** such as `Operation`, `UserId`, `ClientIP`, `ObjectId`, `ResultStatus` and `Workload`.
* **Nested fields**, written with dots, for example `AppAccessContext.UniqueTokenId` or `Actor.ID`.
* **Name/value lists**, which are flattened so each entry is a property of its own. This covers `ExtendedProperties`, `DeviceProperties` and `Parameters` (for example the `UserAgent` of a sign-in, or the `ForwardTo` of `New-InboxRule`).
* **Changed values** (`ModifiedProperties`). Each changed property's new value is available under its own name, and its old value under `Previous_Value_<Name>`.

A flattened entry replaces a top-level field of the same name, and when two lists hold the same name the later one wins, in the order `ExtendedProperties`, `DeviceProperties`, `Parameters`, `ModifiedProperties`. A few `ExtendedProperties` entries that only describe sign-in processing (values `SAS:EndAuth`, `SAS:ProcessAuth`, `deviceAuth:ReprocessTls` and `Consent:Set`) are left out.

**Lists.** When a dotted path leads into a list, such as `Actor.ID`, the property holds every entry:

* Equals, Like, Greater than and Less than match when **any** entry matches.
* Not Equals to matches when any entry differs, so it is almost always true on a list.
* In and Not In compare the whole list, so In never matches and Not In always does. Use Equals, or Contains (available through the API), instead.

**Timestamps.** Fields holding a date and time, such as `CreationTime`, are dates, not text. Greater than and Less than compare them as dates (`CreationTime` Greater than `2026-10-17T17:00:00`), but Equals and Like never match them. Use `CIPPTimeUtc`, `CIPPDayUtc` and `CIPPDateUtc` for times and dates.

Property names may contain only letters, numbers, `_` and `.`.

Microsoft documents every log's properties in the [Management Activity API schema](https://learn.microsoft.com/en-us/office/office-365-management-api/office-365-management-activity-api-schema).

### Fields CIPP adds

| Field | What it holds |
| --- | --- |
| `CIPP<Property>` | For a top-level property whose value is exactly the ID of an object in the tenant. For a user it holds the UPN: `CIPPUserKey` is the UPN behind `UserKey`. For a group, device or app it holds the directory entry, so test one of its fields, such as `CIPPObjectId.displayName`. Partner (GDAP) accounts are named the same way. Values inside nested fields or name/value lists are not looked up. |
| `CIPPGeoLocation` | The two-letter country code of the record's IP address, `Reserved` for a private address, or `Unknown` when it cannot be looked up. |
| `CIPPBadRepIP` | `True` when the IP address belongs to a known VPN, proxy or anonymiser, otherwise `False`; `Reserved` or `Unknown` as for `CIPPGeoLocation`. |
| `CIPPHostedIP` | `True` when the IP address belongs to a hosting provider, otherwise `False`; `Reserved` or `Unknown` as for `CIPPGeoLocation`. |
| `CIPPIPDetected` | The IP address that was looked up, with any port removed. |
| `CIPPActor` | Every identity in the record's `Actor` list, as one text value, so you can test who acted. |
| `CIPPActorType`, `CIPPTargetType` | `User`, `ServicePrincipal` or `Application`: the kind of identity that acted, and the kind acted on. |
| `CIPPActorIsTarget` | `True` when an identity acted on itself (for example an app adding a secret to its own registration). |
| `CIPPAddedKeyTypes`, `CIPPAddedKeys` | For credential changes, the kinds of key added (`Password`, `AsymmetricX509Cert`) and their details. Removed keys and signing keys are left out. |
| `CIPPTimeUtc` | The time of the event in UTC, as `HH:mm`. |
| `CIPPDayUtc` | The day of the week in UTC, such as `Saturday`. |
| `CIPPDateUtc` | The date in UTC, as `YYYY-MM-DD`. |

{% hint style="info" %}
Location fields are filled in for every record CIPP checks in full; each distinct IP address is looked up once per batch. A record from an address listed as **Trusted** in the tenant's IP list gets no location, so `CIPPGeoLocation` conditions never match it, and neither do records from a private or unknown address. A user excluded from location alerts (for example while on holiday) is skipped by every alert with a `CIPPGeoLocation` condition; the exclusion is matched on `CIPPUserKey`. Neither applies to `CIPPBadRepIP` or `CIPPHostedIP`, so pair those with a `CIPPGeoLocation` condition when trusted addresses and exclusions should count.

Names come from a copy of the tenant's directory that CIPP refreshes at most once a day, so an object created since then is not yet named.
{% endhint %}

### Operators

All comparisons ignore case.

| Operator | Matches when the property | Notes |
| --- | --- | --- |
| Equals to / Not Equals to | is (is not) exactly the value | |
| Like / Not like | matches (does not match) a wildcard pattern | `*` matches any text, `?` one character, and `[abc]` or `[a-c]` one of a set. Up to 8 wildcards. |
| In / Not In | is (is not) one of a list of values | Up to 500 values. |
| Greater than / Less than | sorts after (before) the value | Text sorts as text: `2026-11-01` is after `2026-10-31`, and `09:00` is before `17:00`. A number in the record compares as a number, and a timestamp as a date. |
| Does not match | does not match a regular expression | See [Regular expressions](#regular-expressions). |
| Between (UTC) / Not between (UTC) | `CIPPTimeUtc` falls (does not fall) inside a time window | Written `HH:mm-HH:mm`, for example `07:00-19:00`. A window that crosses midnight, such as `22:00-06:00`, works. The form shows the window in your own time. |

{% hint style="info" %}
**Not between** never matches a record that has no time. **Not Equals to**, **Not In**, **Not like** and **Does not match** do match a record that lacks the property altogether, which counts as empty text (so Not like `*` is never true). Pair a negative condition with a positive one when that matters.
{% endhint %}

#### Regular expressions

Regular expressions run without backtracking. Their running time grows only with the length of the value, so a crafted value (such as a sign-in's user agent, which anyone on the internet can choose) cannot slow CIPP down. That rules out back-references, look-arounds and atomic groups, which CIPP refuses when you save. A pattern can be up to 200 characters, and cannot use `|`, `{`, `}` or `$` (see [Values](#values)), so write alternatives as separate conditions or an OR group.

### Values

* A value can be up to 1,024 characters.
* A value cannot contain `;` `|` `` ` `` `$` `{` or `}`.
* A Like value's `[` needs a closing `]`.
* A value can use [variables](#variables).

### OR groups

By default every condition must hold. Use **Add an OR group** to give an alert several groups. The alert fires when **all** conditions of **any one** group hold.

Use **Add a condition for every group** for a condition that applies to all groups, such as an account to leave out. It is added to each group when the alert runs.

Each group needs its own Operation condition (see the rules below).

### Variables

A value can name a custom variable as `%name%`. Each tenant then uses its own value, from the tenant's custom variables, falling back to the global ones. CIPP's own variables work too, such as `%defaultdomain%` and `%tenantid%`.

* With **In** or **Not In**, a variable that holds several values separated by commas becomes a list. A `breakglass` variable of `bg1@contoso.com, bg2@contoso.com` with the condition `UserId In %breakglass%` alerts on either account.
* A tenant with no value for a variable the alert uses is **not checked** by that alert. CIPP never compares against the variable's name, which would make a condition like `UserId Not Equals to %breakglass%` alert on every sign-in.
* A variable's value has the same limits as a typed value: up to 500 values, each up to 1,024 characters, and none of `;` `|` `` ` `` `$` `{` `}`. If it breaks them, the alert is not checked for that tenant.
* The Operation condition cannot use a variable.

Example: alert whenever a break glass account signs in.

| Property | Operator | Value |
| --- | --- | --- |
| `Operation` | Equals to | `UserLoggedIn` |
| `UserId` | In | `%breakglass%` |

### Priority

**Priority (optional)** is a whole number from 1 to 1000. A record raises only the first alert it matches, so when alerts overlap, priority decides which one that is: alerts with a priority are checked first, lowest number first, and alerts with the same priority keep their stored order. Alerts without a priority are checked after every alert that has one. Leave it empty unless alerts overlap.

## Rules every alert must follow

CIPP checks these when you save an alert. Each one exists because breaking it would make the alert check far more records than it needs to, or never work at all.

| Rule | Why |
| --- | --- |
| Each group has exactly **one Operation condition**, using Equals, In or Like. | The operation is what lets CIPP skip batches and records no alert can match (step 3 above). A record has one operation, so a second Operation condition could only repeat or contradict the first. |
| A **Like** on Operation needs at least three characters of plain text, such as `*InboxRule`. | Without text, every record would be a candidate. |
| A **Like** on Operation cannot cover a busy operation (listed below). Name those with Equals or In. | A wildcard such as `*ser*` also covers every sign-in, so the alert would check, and likely match, nearly every record of the tenant. |
| An alert on a **busy operation** needs at least one more condition, such as a user, a location or a time. | On its own it alerts on nearly every record of that operation. To be told when something busy happens many times, use a repeated activity alert. |
| The Operation condition cannot use a **variable**. | The operation text is used before any tenant's variables are known. |
| Lists of at most **500** values; values of at most **1,024** characters; Like values with at most **8** wildcards; regular expressions of at most **200** characters. | Each of these is evaluated for every record the alert checks, so a very long list or a heavily wildcarded pattern slows every record down. Within the limits they cost next to nothing. |
| At most **30** conditions in at most **10** groups. | Keeps an alert readable, and each condition costs time on every candidate record. |
| Values cannot contain `;` `|` `` ` `` `$` `{` `}`, and a Like value's `[` needs a closing `]`. | CIPP refuses to run such a value, so the alert would never fire. |
| A repeated activity alert has **only** the Operation condition. | Counting reads only each record's operation, user and time, so any other condition would be ignored. |

**Busy operations:** `UserLoggedIn`, `UserLoginFailed`, `MailItemsAccessed`, `MailboxLogin`, `Send`, `MessageSent`, `MessageRead`, `MessagesListed`, `ChatRetrieved`, `TeamsSessionStarted`, `CopilotInteraction`, `SearchQueryPerformed`, `FileAccessed`, `FileAccessedExtended`, `FileDownloaded`, `FileModified`, `FileModifiedExtended`, `FilePreviewed`, `FileUploaded`, `FileSyncDownloadedFull`, `FileSyncUploadedFull`, `PageViewed`, `PageViewedExtended`.

{% hint style="info" %}
These rules apply when an alert is saved. Alerts saved before them keep running as they are, and are checked against the rules the next time they are edited. The exception is a group with no valid Operation condition: that group never runs, and an alert without any runnable group is reported in the CIPP logbook once a day.
{% endhint %}

## Repeated activity alerts

Turn on **Only alert when one identity does this repeatedly** to alert when one user or app does something many times in a short time, such as mass file deletion, instead of on every record.

* **How it counts.** Records of the alert's operations, in the log the alert reads, are counted per identity (the record's `UserId`) in 10-minute buckets that start on the hour and every 10 minutes after it. Counts are shared across every batch and every collection task, so a burst split across batches or workers is still counted once. The alert fires when the buckets in any window reach the count. A window is a run of whole buckets, its length rounded up to a multiple of 10 minutes, so a burst that straddles a bucket boundary can need up to one bucket more than the window's length.
* **Once per burst.** After firing for an identity, the alert stays quiet for that identity for an hour or the window's length, whichever is longer. It reports the busiest window of the burst.
* **What it shows.** The alert carries the user or app, the count, and the record that reached the count: the latest of that user's records in the batch that took the count over the threshold. CIPP keeps only counts while counting, not the records behind them; to see the rest of the activity, search the tenant's audit log for that user and time.
* **Limits.**
  * The count must be from 2 to 10,000.
  * The window must be from 10 to 60 minutes. Counts are kept only a few hours, and an alert saved with a longer window is counted over 60 minutes.
  * There can be one group of conditions only, holding just the Operation condition.
  * The Operation condition must use Equals or In (counting needs the exact operations).
  * Only the operations below can be counted.
* **Every identity counts.** A batch with thousands of users doing the operation is counted in full: CIPP stores one small count per 10-minute bucket, not one per user.

| Log | Operations that can be counted |
| --- | --- |
| SharePoint and OneDrive | `FileDeleted`, `FileRecycled`, `FileDeletedFirstStageRecycleBin`, `FileDeletedSecondStageRecycleBin`, `FolderDeleted`, `FolderRecycled`, `FolderDeletedFirstStageRecycleBin`, `FolderDeletedSecondStageRecycleBin`, `FileDownloaded`, `FileSyncDownloadedFull`, `AnonymousLinkCreated`, `CompanyLinkCreated`, `SecureLinkCreated`, `SharingInvitationCreated`, `SharingSet`, `FileMalwareDetected`, `SiteDeleted` |
| Exchange | `HardDelete`, `SoftDelete`, `MoveToDeletedItems`, `New-InboxRule`, `Set-InboxRule`, `Add-MailboxPermission`, `Add-RecipientPermission`, `Set-Mailbox` |
| Entra ID | `Delete user.`, `Disable account.`, `Reset user password.`, `Remove member from group.`, `Remove member from role.`, `Add member to role.`, `Add service principal credentials.` |
| General | `TeamDeleted`, `ChannelDeleted`, `MemberRemoved`, `MessagesExported`, `DeleteForm`, `QuarantineRelease`, `QuarantineExportMessage` |

Only operations where many in a short time means something are offered. Failed sign-ins are not: a password spray tries a different username each time, so no single account's count rises, and counting them would only cost time. Use a single-record alert on `UserLoginFailed` with conditions, such as a location or an error code, instead.

## Checking an alert against a saved log

Open any saved log to see **Would your alerts fire on this log?** It runs the log's record through every alert that covers the tenant, condition by condition, and shows what each condition expected and what the record holds.

| Section | Meaning |
| --- | --- |
| Fires | The alert this record raises: the first one it matches. |
| Also matches | Alerts that match too, but do not fire because another alert came first. |
| Close | Alerts on this operation that fail some conditions. The failing conditions are marked. |
| Repeated activity alerts | Alerts that count this operation instead of matching it. |
| Excluded for this tenant | Alerts that exclude the tenant, with what they would have done. |
| Not checked | Alerts that cannot run for this tenant: none of their groups has a valid Operation condition, or the alert uses a variable the tenant has no usable value for. |
| Other activity / other logs | Alerts on other operations of this log, and alerts on other logs, which cannot fire on this record. |

Each alert has an **Edit alert** link, so you can adjust it and check again. A saved log also has an **Alert settings** button that opens the alert that raised it.

## Saved logs and retention

Every record that raises an alert is saved and listed under **Saved Logs**, with its full record (in sections, as changes, and as raw JSON), its location, and the alert check.

Saved logs are kept for the **Saved Audit Log Retention** period under CIPP settings: 30 to 365 days, 180 by default. Older ones are deleted once a day.

To keep a copy, download it as JSON: **Download (JSON)** on the Saved Logs table downloads one log or all the selected ones, and **Download** on a saved log's page downloads that log. The table's CSV and PDF exports hold only the visible columns, not the full record.

## Log Collection and Diagnostics

**Log Collection** shows, per tenant and log, how far collection has got:

| Status | Meaning |
| --- | --- |
| Up to date | Collected within the last hour. |
| Delayed | More than an hour behind. Usually Microsoft publishing late; CIPP catches up on its own. |
| Error, retrying | The last attempt failed. CIPP retries with a growing delay and shows the error and what to do. |
| Unavailable | The tenant has auditing turned off, or no licence that includes the audit log. Checked again once a day. |
| Waiting to start | Collection for this log has not run yet. |

**Diagnostics** shows each 15-minute cycle: how long it took, how many tenants and batches it covered, how many records were read and checked, and how many alerts were sent, including repeated activity alerts. It covers every tenant, so it needs access to all tenants.

## Writing alerts that stay fast

Every record of every tenant is checked against your alerts, so the shape of an alert decides how much work it adds. Most of that work goes into records CIPP has to build and check in full; anything that lets it rule a record out early keeps alerting fast for every tenant.

* **Start from the operation.** Name the exact operations with Equals or In. CIPP uses them to skip whole batches, and records within a batch, before anything else runs. A Like on Operation is fine for a family of operations such as `*InboxRule`, but check what else it covers: a short or common fragment pulls in unrelated activity.
* **Narrow with something positive.** After the operation, add a condition that says who or what you care about, with Equals, In or Like: a user, an app, a site, a country. When its value contains text, CIPP can rule out records that do not hold that text before building them. Not Equals, Not In, Not like and Does not match only leave things out once a record is built; use them for a few known exceptions, next to a positive condition.
* **Use In rather than many groups.** If OR groups differ only by operation, one In list does the same job more simply.
* **Use variables for per-tenant lists.** A variable such as `%breakglass%` keeps each tenant's list short and relevant, instead of one long list every tenant checks.
* **Prefer Like to regular expressions.** Like covers most matching and is easier to read. Keep regular expressions for patterns Like cannot express.
* **Count instead of matching when the question is "how many".** A repeated activity alert counts records without building them, and sends one alert per burst instead of one per record.
* **Location conditions narrow early.** When every alert a record could match has a `CIPPGeoLocation` condition, CIPP looks up the record's address first and skips the record if no alert's location condition can hold.
* **Avoid overlapping alerts.** A record raises only the first alert it matches. Merge overlapping alerts, or give them a priority, so the one you expect is the one that fires.
* **Check before you rely on it.** Open a saved log and use **Would your alerts fire on this log?** to see, condition by condition, how each alert treats a real record.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
