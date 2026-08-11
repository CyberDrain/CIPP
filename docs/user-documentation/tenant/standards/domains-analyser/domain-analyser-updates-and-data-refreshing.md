---
description: >-
  Domains in CIPP don’t always update instantly. This page explains how and when
  the Domain Analyzer refreshes, why some domains might not appear, and what
  happens if you delete one.
---

# Domain Analyzer Updates & Data Refreshing

## How the Analyzer Gets Its Data

The Domain Analyzer does not query Microsoft Graph for your domain list. It reads from CIPP's cached tenant data, then performs its own DNS lookups against the domains it finds there.

This two-stage arrangement explains most of the timing surprises on this page. A domain has to reach CIPP's cache before the analyzer can see it, and no amount of re-running the analysis will pull in a domain the cache has not collected yet. Where a tenant has no cached domain data at all, the analyzer logs that analysis is being skipped until data collection completes, and moves on.

The analysis itself runs automatically once a day, in the early hours of the morning in your deployment's configured timezone.

## Domain Visibility

Sometimes a domain is missing from the analyzer even though it appears elsewhere in CIPP. The common reasons are:

| Reason                  | Detail                                                                                                                      |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Not verified            | Only verified domains are analyzed. A domain added but not yet verified in Microsoft 365 is ignored.                        |
| Excluded service domain | CIPP skips domains belonging to Microsoft and to known cloud signature and voice providers. See below.                      |
| Tenant excluded in CIPP | If a tenant is marked as excluded, the analyzer removes that tenant's domains from its data rather than just skipping them. |
| Repeated Graph failures | Tenants with a high accumulated Graph error count are skipped entirely until the underlying access problem is resolved.     |
| Not yet cached          | A newly added domain appears only once CIPP's tenant data collection has picked it up.                                      |

### Excluded Domains

The following patterns are never analyzed, because they either belong to Microsoft or are used by cloud signature and voice services where the DNS records are outside your control:

* `*.microsoftonline.com`
* `*.mail.onmicrosoft.com`
* `*.exclaimer.cloud`
* `*.excl.cloud`
* `*.codetwo.online`
* `*.call2teams.com`
* `*.signature365.net`
* `*.myteamsconnect.io`
* `*.teams.dstny.com`
* `*.msteams.8x8.com`
* `*.ucconnect.co.uk`
* `*.teams-sbc.dk`

{% hint style="info" %}
The same exclusions are applied by the Add DKIM standard, so a domain that is invisible here will also be skipped there.
{% endhint %}

## Deleting and Restoring Domains

**Delete from analyzer** removes the domain from CIPP's own records. It does not remove the domain from Microsoft 365, and it does not change any DNS.

Because the analyzer rebuilds its list from cached tenant data on each run, a deleted domain reappears at the next daily run, or sooner if you use **Run Analysis Now**. If the domain was genuinely removed from Microsoft 365, or is no longer verified, it will not come back.

## Refreshing Results

Use **Run Analysis Now** to refresh outside the daily cycle. It is worth doing when:

* You have changed DNS records and want to confirm the new score.
* You want to repopulate a domain you deleted, without waiting for the next run.
* You suspect the stored results are stale.

{% hint style="warning" %}
Re-running the analysis re-checks DNS for domains CIPP already knows about. It does not refresh the underlying tenant domain list, so a domain added to Microsoft 365 in the last few minutes may still not appear. If a newly verified domain is missing, the tenant data cache is the thing that has not caught up, not the analyzer.
{% endhint %}

{% hint style="info" %}
For most tenants this is rarely needed. The daily job keeps results current on its own.
{% endhint %}

## Troubleshooting

| Symptom                                                  | What to check                                                                                                              |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Domain missing after adding it                           | Confirm it is verified in Microsoft 365, then allow time for CIPP's tenant data to refresh before re-running the analysis. |
| Domain visible elsewhere in CIPP but not in the analyzer | Check it is not on the excluded list above, and that it is verified.                                                       |
| All of a tenant's domains have vanished                  | Check whether the tenant has been excluded in CIPP, which clears its domains from the analyzer.                            |
| A tenant is never analyzed                               | Check the tenant for repeated Graph failures. Tenants with a high error count are skipped until access is fixed.           |
| Results not updating at all                              | Confirm CIPP and CIPP-API are up to date, and review the Domain Analyzer entries in the CIPP logs.                         |

{% include "../../../../../.gitbook/includes/feature-request.md" %}
