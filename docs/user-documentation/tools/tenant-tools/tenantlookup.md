# Tenant Lookup

Tenant Lookup returns the publicly available identity information for any Entra ID tenant. Enter a domain name or tenant ID, and CIPP resolves it to the tenant's ID, default domain and region, along with the branding shown on that tenant's sign-in page. This is useful for identifying the owner of a domain seen in a guest invitation, a forwarding rule or a cross-tenant access request.

{% hint style="info" %}
The lookup queries endpoints that Microsoft exposes publicly, so it works against any tenant. You do not need a GDAP relationship with the tenant, and the tenant does not need to exist in CIPP. Nothing on this page uses the tenant selector.
{% endhint %}

## Looking Up a Tenant

Enter the tenant into the **Tenant** field. Either a domain name (for example `contoso.com`, whether or not it is the tenant's default `onmicrosoft.com` domain) or a tenant ID will resolve. Click **Check**, or press Enter, to run the lookup. The button is unavailable while the field is empty or a lookup is already running.

If the value does not resolve to a Microsoft 365 tenant, no tenant information is returned. Check the spelling of the domain and try again.

## Tenant Information

| Field               | Description                                                                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Name         | The domain name or tenant ID you searched for, repeated back for reference.                                                                                                                              |
| Default Domain Name | The tenant's default domain, normally its `onmicrosoft.com` address. This identifies the tenant even where the domain you searched for is one of several attached to it.                                 |
| Tenant ID           | The tenant's directory (tenant) ID.                                                                                                                                                                      |
| Tenant Region       | The region scope Microsoft reports for the tenant, shown as a color-coded chip. This indicates the broad geography the tenant is homed in rather than the precise data residency of any given workload. |

Each of the first three values has a copy button next to it for pasting into a ticket or another tool. Any value the lookup could not resolve is shown as **Not Available**.

## Tenant Branding

Where the tenant has customized its sign-in experience, that branding is reproduced around the results:

* The sign-in page illustration is used as the background behind the results. If the tenant has not set one, a repeating **NotFound** watermark is shown in its place. This refers only to the missing illustration and does not mean the tenant itself was not found.
* The tenant's tile logo is shown in a **Tenant Logo** panel beside the tenant details. CIPP picks the light or dark variant to match your current display mode and falls back to whichever one the tenant has published. The panel is only rendered when the tenant has a logo, and shows a placeholder while the image loads.

{% hint style="warning" %}
Branding is retrieved from the tenant's own sign-in service and is a helpful signal, not proof of identity. Treat a familiar-looking logo as a starting point for verification rather than confirmation that a domain belongs to who you expect.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
