---
description: Analyze external domain's mail-related DNS entries
---

# Individual Domain Check

The individual domain check runs a full set of mail and DNS health checks against any domain, whether or not it belongs to one of your tenants. This lets you check vendors, prospects, competitors, or a domain seen in a suspicious message. You are responsible for ensuring your use of this tool complies with applicable laws, registry terms, and the terms of service for the Google and Cloudflare DNS APIs.

{% hint style="info" %}
Lookups use the DNS resolver configured for your CIPP instance, either Google or Cloudflare, defaulting to Google. This is set in settings.
{% endhint %}

## Domain Check

Enter the domain into the **Domain Name** field and click **Check**. Internationalised domain names are converted to punycode automatically, so you can paste a domain in its native script. Every check runs at once and each result appears in its own card as it completes.

The settings icon on the card reveals the optional inputs below. Adjusting an option and clicking **Check** again re-runs the affected checks. **Clear** empties the domain and all the options.

| Field              | Description                                                                                                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SPF Record         | Simulates a change to the domain's SPF record. Enter the record you are considering, and CIPP validates that syntax instead of whatever is currently published. Useful for proving a change is valid before you make it live. |
| DKIM Selector      | Checks a specific list of selectors rather than the ones detected from the domain's mail provider. Supply a comma separated list.                                                                                             |
| Enable HTTPS check | Adds the **HTTPS Certificate** card, which tests the certificate presented by the domain. Off by default.                                                                                                                     |
| HTTPS Subdomains   | The subdomains to test alongside the domain itself, as a comma separated list. Only shown when the HTTPS check is enabled. Leaving it empty tests `www`.                                                                      |

{% hint style="info" %}
Where no custom selectors are supplied, CIPP falls back to the standard Microsoft selectors. If you have the admin or editor role, any custom selectors you enter are saved against that domain and reused automatically the next time it is checked, including by the Domain Analyzer. Users without those roles get a one-off check that is not saved.
{% endhint %}

## Result Cards

| Card              | What it checks                                                                                                 |
| ----------------- | -------------------------------------------------------------------------------------------------------------- |
| Whois Results     | The domain's registration details, showing the registrar on the card.                                          |
| NS Records        | The nameservers the domain is delegated to.                                                                    |
| MX Records        | The mail exchangers, with the detected mail provider shown as a chip.                                          |
| SPF Record        | The published SPF record, or the simulated one if you supplied a record in the options.                        |
| DMARC Policy      | The published DMARC record and whether the policy it sets is sound.                                            |
| DKIM Record       | The DKIM records for the detected or supplied selectors.                                                       |
| DNSSEC            | Whether DNSSEC is enabled and correctly signed.                                                                |
| MTA-STS           | The MTA-STS policy, showing the mode it enforces.                                                              |
| AutoDiscover      | The AutoDiscover record and the record type it was found as.                                                   |
| HTTPS Certificate | The certificate presented by the domain and any subdomains listed. Only shown when the HTTPS check is enabled. |

## Reading the Results

Each card shows an icon in its header summarizing the outcome: a green tick where everything passed, an orange warning where there are non-fatal issues, and a red error where a check failed. The body of the card lists the individual findings with the same color coding, so you can see exactly which test produced the warning.

Two actions sit at the bottom of each card:

* The help icon opens Microsoft's or the mail provider's reference material for that check. It is only shown where the check returns a relevant link.
* The details icon opens a flyout with the full result. What it contains depends on the check. **DMARC Policy** breaks the record down into its policy, subdomain policy, percentage, alignment, reporting interval and format, along with the reporting and forensic addresses. **SPF Record** shows the raw record, any recommendations, and every IP address the record resolves to once includes are followed. **DKIM Record** lists each selector with its own record and findings. **HTTPS Certificate** shows the issuer, subject, validity dates, serial number, thumbprint and DNS names for each hostname tested. **Whois Results** shows the registration and expiry dates, registrar contact details, domain status and DNSSEC state. The remaining cards show the raw record data.

{% hint style="warning" %}
A domain that fails validation here is not necessarily misconfigured for its own purposes. Read the individual findings rather than treating the header icon as a verdict, particularly on domains that do not send mail.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
