---
description: Check your managed domains against security and configuration best practices.
---

# Domains Analyser

The Domains Analyser runs a series of best practice checks against every mail-enabled domain across your delegated Microsoft 365 tenants. It inspects the public DNS records for each domain and scores them, so you can see at a glance which clients have gaps in their mail authentication.

It assesses the following areas:

* Sender Policy Framework (SPF)
* Domain-based Message Authentication, Reporting & Conformance (DMARC)
* DomainKeys Identified Mail (DKIM)
* Domain Name System Security Extensions (DNSSEC)
* SMTP MTA Strict Transport Security (MTA-STS)
* Mail exchanger (MX) records and the detected mail provider
* Microsoft device enrolment and registration CNAME records

Analysis runs automatically once a day. You can also trigger it on demand with **Run Analysis Now**.

{% hint style="info" %}
On a first run you may see an error because no data has been collected yet. Wait for the scheduled analysis or use **Run Analysis Now**.
{% endhint %}

## Action Buttons

{% content-ref url="../../../tools/tenant-tools/individual-domains.md" %}
[individual-domains.md](../../../tools/tenant-tools/individual-domains.md)
{% endcontent-ref %}

<details>

<summary>Run Analysis Now</summary>

Opens the Run Domain Analysis dialog. Pick a single tenant or all tenants and queue a fresh analysis. It can take several minutes to work through all the checks.

</details>

<details>

<summary>Generate Report</summary>

Opens a client-ready Domain Security Assessment PDF covering every domain the analyser holds for the selected tenant, including onmicrosoft.com domains and any not analysed yet, so no domain can be left out. It is built from the last analysis with no new DNS lookups, so run the analysis first to refresh it. The report groups its findings by check, with a domain-by-check overview, tenant-wide priority actions and the technical details for each domain, which can be switched off. Branding follows the Domain Security Report default. Select a single tenant to enable it. See [#domain-security-report](./#domain-security-report "mention") for what it checks and how to read it.

</details>

## Filters

| Filter                             | Shows                                                                            |
| ---------------------------------- | -------------------------------------------------------------------------------- |
| Mail Provider is not Microsoft 365 | Domains whose detected mail provider is not Microsoft 365.                       |
| onmicrosoft.com Domains            | Domains whose domain name includes onmicrosoft.com, the tenant's default domain. |
| All Except onmicrosoft.com Domains | Domains other than the tenant's default onmicrosoft.com domains.                 |

## Table Details

The table shows results for all domains in the tenant or tenants selected in the tenant-select.md dropdown.

| Column                  | Description                                                                                                                                               |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Domain                  | The domain name being analysed.                                                                                                                           |
| Score Percentage        | The domain's score as a percentage of its maximum (160, or 140 for onmicrosoft.com domains). See below.                                                   |
| Mail Provider           | The detected mail provider, for example Microsoft, Google, or Unknown, derived from the MX lookup.                                                        |
| SPF Pass All            | Whether the SPF record passes all validation checks with no failures.                                                                                     |
| MX Pass Test            | Whether the MX record passes all validation checks with no failures.                                                                                      |
| DMARC Present           | Whether a DMARC record exists for the domain.                                                                                                             |
| DMARC Action Policy     | The enforced DMARC policy: Reject, Quarantine, or None.                                                                                                   |
| DMARC Percentage Pass   | Whether the DMARC percentage (`pct`) is set to 100.                                                                                                       |
| DNSSEC Present          | Whether DNSSEC passes with no validation failures or warnings.                                                                                            |
| DKIM Enabled            | Whether at least one DKIM record is found and passes validation. Uses your configured selectors, falling back to the Microsoft selectors if none are set. |
| MTASTS                  | MTA-STS status: Enforced, Testing, Invalid or Not configured. Not applicable for onmicrosoft.com domains.                                                 |
| Enterprise Enrollment   | CNAME check for `enterpriseenrollment.<domain>`. See below.                                                                                               |
| Enterprise Registration | CNAME check for `enterpriseregistration.<domain>`. See below.                                                                                             |

{% hint style="info" %}
Further columns are collected for information and are not shown by default. They feed the Extended Info flyout available on each row.
{% endhint %}

### Enrolment and Registration Values

Both CNAME checks report one of the following. Neither contributes to the score, but a value other than Correct is added to the score explanation.

| Value                 | Meaning                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Correct               | Enrolment points at `enterpriseenrollment-s.manage.microsoft.com`, registration at `enterpriseregistration.windows.net`. |
| Legacy                | Enrolment only. Points at the older `enterpriseenrollment.manage.microsoft.com` endpoint.                                |
| Unexpected: `<value>` | The CNAME resolves to something CIPP does not recognise.                                                                 |
| No CNAME              | The record is missing.                                                                                                   |

## Scoring

Custom domains are scored out of a maximum of **160**, and the Score Percentage column is that score expressed as a percentage. Microsoft hosts the DNS for `*.onmicrosoft.com` domains, so DNSSEC and MTA-STS cannot be configured on them: they are left out of the score and those domains are scored out of **140**.

| Check                                                | Points |
| ---------------------------------------------------- | ------ |
| SPF record present (exactly one record)              | 10     |
| SPF record passes all validation                     | 20     |
| MX record passes validation                          | 10     |
| DMARC record present                                 | 10     |
| DMARC policy and subdomain policy both set to reject | 30     |
| DMARC policy set to quarantine                       | 20     |
| DMARC reporting active (at least one `rua` address)  | 20     |
| DMARC percentage set to 100                          | 20     |
| DKIM active and valid                                | 20     |
| DNSSEC passes                                        | 10     |
| MTA-STS policy enforced                              | 10     |
| MTA-STS policy in testing mode                       | 5      |

{% hint style="info" %}
The reject and quarantine awards are mutually exclusive, so a domain reaches 160 only with a full reject policy. A policy of `none` scores nothing for enforcement and adds "DMARC is not being enforced" to the score explanation. Note also that reject only scores where the subdomain policy is reject as well.
{% endhint %}

{% hint style="info" %}
DNSSEC and MTA-STS are hardening steps that need changes at the DNS host and a web host, so they carry few points. A custom domain with everything else in place scores 140 of 160 (88%) without either.
{% endhint %}

{% hint style="info" %}
DMARC reporting is scored but is not one of the default columns. To see it, open the Extended Info flyout for the domain.
{% endhint %}

## Domain Security Report

**Generate Report** produces a client-ready Domain Security Assessment PDF for the selected tenant. It always covers every domain the analyser holds for that tenant, including onmicrosoft.com domains and domains that have not been analysed yet, so a domain that looks unused cannot be left out of the assessment.

The report is built from the stored analyser results and makes no DNS lookups of its own. It is only as current as the last analysis, so use **Run Analysis Now** first if records have changed. Branding follows the **Domain Security Report** default under report branding.

### What the Report Checks

Each domain is graded on six checks. The device enrolment records are listed for information only.

| Check                                         | Pass                                                                   | Needs attention / Recommended                                                           | Fail                                    |
| --------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------- |
| DMARC                                         | Domain and subdomain policies at reject, reporting active, `pct` 100.   | Needs attention: policy at quarantine, subdomains not at reject, reporting not set, or `pct` under 100. | No DMARC record, or a policy of `none`. |
| SPF                                           | The record passes all validation.                                      | -                                                                                       | Missing, multiple or failing records.   |
| DKIM                                          | A valid key is found for at least one configured selector.             | -                                                                                       | No valid key found.                     |
| MX                                            | The MX records pass validation.                                        | -                                                                                       | Missing or failing MX records.          |
| DNSSEC                                        | DNSSEC validates.                                                      | Recommended: not configured. DNSSEC never shows as a fail.                             | -                                       |
| MTA-STS                                       | The policy is enforced.                                                | Recommended, Testing or Invalid. MTA-STS never shows as a fail.                         | -                                       |
| Enterprise Enrollment / Enterprise Registration | Informational only. Not graded and not part of the score.            |                                                                                         |                                         |

{% hint style="info" %}
DKIM is checked against the selectors set with **Add/Modify DKIM Selectors**, falling back to the Microsoft selectors. A domain that signs with another selector shows as a fail until that selector is added and the analysis is run again.
{% endhint %}

### Scores

* **Domain score:** the domain's Score Percentage from the analyser. See [#scoring](./#scoring "mention").
* **Average score:** the mean score of every analysed domain in the tenant.
* **Rating:** each domain, and the tenant overall from its average, is rated **Good** (80% and above), **Needs attention** (50% to 79%) or **At risk** (below 50%).
* **Domains needing work:** domains rated Needs attention or At risk.

### Domains at a Glance

The summary page has a grid with one row per domain, worst score first, and one column per check. Domains that have not been analysed yet are listed last with a score of Pending.

| Status  | Meaning                                                                            |
| ------- | ---------------------------------------------------------------------------------- |
| Pass    | The protection is in place.                                                        |
| Fail    | The protection is missing or broken.                                               |
| Review  | The protection works but has issues to address.                                    |
| Advised | A recommended hardening step (DNSSEC or MTA-STS) is not yet in place.              |
| N/A     | Managed by Microsoft and cannot be changed. See Microsoft-managed domains below.   |
| Unknown | The check could not be completed when the domain was last analysed.                |
| -       | The domain has not been analysed yet.                                              |

### Report Layout

1. **Cover:** the report title and the tenant name.
2. **Summary:** an overview, the domain count, average score, domains needing work and domains at risk, the Domains at a Glance grid, and the priority actions. Priority actions are grouped by check, core checks before DNSSEC and MTA-STS, and list the domains each applies to.
3. **Findings by check:** for each check, why it matters, a table of the affected domains with what was found, a short recommendation shared by every domain that needs the same fix, and the domains that pass or are managed by Microsoft.
4. **Device enrolment records:** the enrolment and registration status of every domain.
5. **Technical details (optional):** the published records and every individual test result for each domain. When technical details are included, each recommendation also gives the target value, for example `v=DMARC1; p=reject; rua=mailto:<reporting address>`.
6. **Disclaimer:** a point-in-time statement dated from the analysis.

Switch off **Include technical details** in the preview for a shorter report aimed at a non-technical reader.

### Microsoft-managed Domains

Microsoft hosts the DNS for `*.onmicrosoft.com` domains. It sets up SPF, DKIM and MX for them, and a DMARC record is the only record that can be added. DNSSEC and MTA-STS cannot be configured, so the report shows them as N/A, leaves them out of the counts and recommendations, and the analyser scores these domains out of 140.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Add/Modify DKIM Selectors</td><td>Sets the DKIM selectors used when checking the selected domain or domains. Accepts a comma-separated list.</td><td>true</td></tr><tr><td>Delete from analyser</td><td>Removes the selected domain or domains from the analyser.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Reviewing the Extended Info Flyout

The flyout breaks the domain down test by test, with the full record returned for each.

### Settings

The settings icon reveals additional options for the check. You can supply a specific SPF record to test against, set a DKIM selector, and enable an HTTPS certificate check against a list of subdomains. Click **Check** to rerun the tests with your chosen options.

### Results

* Pass and fail are shown with green ticks and red exclamation marks, including for the individual parts of multi-part tests.
* Each test shows the detail of what was returned.
* The three dots icon opens a further panel with the full result of that specific test.
* The question mark icon opens external documentation explaining how to influence that test's result.

## Common Problems

* This feature requires that your Secure Application Model (SAM) app has the delegated permission `Domain.Read.All`.
* Allow enough time for the analysis to complete. In an environment with 100 tenants this takes around two minutes.
* Check your permissions under **CIPP > Application Settings > Permissions** and review the Permissions Check results.
* Make sure both CIPP-API and CIPP are fully up to date. There is extensive logging in the CIPP-API Function App.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
