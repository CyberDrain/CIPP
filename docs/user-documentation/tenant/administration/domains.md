# Domains

This page lists the domains registered in the selected tenant and lets you add, verify, and remove them, along with showing the DNS records Microsoft expects for each one.

## Page Actions

**Add Domain** opens a drawer asking only for a **Domain Name**. Adding a domain registers it with the tenant in an unverified state; it becomes usable once ownership has been proven. The drawer stays open after a successful add so several domains can be registered in one sitting.

### Proving domain ownership

A domain is unverified until Microsoft can see a record it asked for in that domain's public DNS, which demonstrates that whoever added it controls the domain. You will need access to wherever the domain's DNS is hosted, usually the registrar or a DNS provider such as Cloudflare or Route 53. Until this is done the domain cannot be used for mail, sign-in or anything else.

{% stepper %}
{% step %}
#### Add the domain

Enter the domain name in the **Add Domain** drawer and add it. It appears in the table straight away with **Is Verified** unticked.
{% endstep %}

{% step %}
#### Collect the verification record

Open the row's **More Info** flyout and look at **Verification Records**, or start **Verify Domain**, which shows the same records in its confirmation dialog. Microsoft usually asks for a TXT record whose value begins `MS=ms`, and sometimes offers an MX record as an alternative. Where more than one record is offered, any one of them is enough. Each value has a copy button next to it.
{% endstep %}

{% step %}
#### Publish the record in DNS

Create the record at the root of the domain, using the host or name your DNS provider uses for the domain itself, often written as `@` or left blank. Copy the value exactly as shown. The TTL given alongside the record is a suggestion rather than a requirement; a low value such as 300 seconds makes the record visible sooner.
{% endstep %}

{% step %}
#### Verify in CIPP

Once the record has propagated, run **Verify Domain** on the row. Propagation is usually a few minutes but can take longer, and verification fails rather than retrying if the record is not yet visible, so simply run it again after waiting.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Verification proves ownership only. It does not configure the domain for any service. Once verified, use **Service Configuration Records** in the row's flyout to see the MX, SPF, autodiscover and other records Microsoft expects for the services the domain will be used with.
{% endhint %}

## Table Details

The properties returned are for the Graph resource type `domain`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/domain?view=graph-rest-1.0#properties).

The domain name itself appears in the Id column, since that is the identifier Microsoft uses for a domain.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Verify Domain</td><td>Asks Microsoft to check for the ownership record and marks the domain verified once it is found. The confirmation shows the records that satisfy verification, so they can be copied without leaving the dialog. Only offered for domains that are not yet verified.</td><td>true</td></tr><tr><td>Set as Default</td><td>Makes the selected domain the tenant's default, which is the domain used when no other is specified for new mailboxes and accounts. Only offered for verified domains that are not already the default.</td><td>false</td></tr><tr><td>Delete Domain</td><td>Removes the domain from the tenant. Only offered for domains that are neither the default nor the tenant's initial <code>onmicrosoft.com</code> domain, neither of which can be removed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Verification only succeeds once the record has been published and has propagated. Running **Verify Domain** before then returns an error rather than queuing a retry, so publish the record first and verify afterwards.
{% endhint %}

## Extended Info Flyout

The flyout for this table is built specifically for domains and shows three sections:

* **Supported Services**, the Microsoft services the domain is enabled for, such as Email or OfficeCommunicationsOnline.
* **Verification Records**, the DNS records that prove ownership. Each is headed by its name and record type, with its TTL and whether it is optional, and every value carries a copy button.
* **Service Configuration Records**, the DNS records Microsoft expects for the services the domain is used with, such as MX, autodiscover and SPF. These are shown the same way, with an additional label naming the service each record belongs to.

Both record sets are read live from Microsoft when the flyout is opened, so they reflect what Microsoft is currently asking for rather than a cached copy.

{% include "../../../../.gitbook/includes/feature-request.md" %}
