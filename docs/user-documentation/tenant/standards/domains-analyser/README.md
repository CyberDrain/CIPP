---
description: Check your managed domains against security and configuration best practices.
---

# Domains Analyzer

The Domains Analyzer runs a series of best practice checks against every mail-enabled domain across your delegated Microsoft 365 tenants. It inspects the public DNS records for each domain and scores them, so you can see at a glance which clients have gaps in their mail authentication.

It assesses the following areas:

* Sender Policy Framework (SPF)
* Domain-based Message Authentication, Reporting & Conformance (DMARC)
* DomainKeys Identified Mail (DKIM)
* Domain Name System Security Extensions (DNSSEC)
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

## Table Details

The table shows results for all domains in the tenant or tenants selected in the tenant-select.md dropdown.

| Column                  | Description                                                                                                                                               |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Domain                  | The domain name being analyzed.                                                                                                                           |
| Score Percentage        | The domain's score as a percentage of the maximum of 160. See below.                                                                                      |
| Mail Provider           | The detected mail provider, for example Microsoft, Google, or Unknown, derived from the MX lookup.                                                        |
| SPF Pass All            | Whether the SPF record passes all validation checks with no failures.                                                                                     |
| MX Pass Test            | Whether the MX record passes all validation checks with no failures.                                                                                      |
| DMARC Present           | Whether a DMARC record exists for the domain.                                                                                                             |
| DMARC Action Policy     | The enforced DMARC policy: Reject, Quarantine, or None.                                                                                                   |
| DMARC Percentage Pass   | Whether the DMARC percentage (`pct`) is set to 100.                                                                                                       |
| DNSSEC Present          | Whether DNSSEC passes with no validation failures or warnings.                                                                                            |
| DKIM Enabled            | Whether at least one DKIM record is found and passes validation. Uses your configured selectors, falling back to the Microsoft selectors if none are set. |
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
| Unexpected: `<value>` | The CNAME resolves to something CIPP does not recognize.                                                                 |
| No CNAME              | The record is missing.                                                                                                   |

## Scoring

Each domain is scored out of a maximum of **160**, and the Score Percentage column is that score expressed as a percentage.

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
| DNSSEC passes                                        | 20     |
| DKIM active and valid                                | 20     |

{% hint style="info" %}
The reject and quarantine awards are mutually exclusive, so a domain reaches 160 only with a full reject policy. A policy of `none` scores nothing for enforcement and adds "DMARC is not being enforced" to the score explanation. Note also that reject only scores where the subdomain policy is reject as well.
{% endhint %}

{% hint style="info" %}
DMARC reporting is scored but is not one of the default columns. To see it, open the Extended Info flyout for the domain.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Add/Modify DKIM Selectors</td><td>Sets the DKIM selectors used when checking the selected domain or domains. Accepts a comma-separated list.</td><td>true</td></tr><tr><td>Delete from analyzer</td><td>Removes the selected domain or domains from the analyzer.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

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
