# IP Database

IP addresses recorded here as trusted are excluded from audit log processing. When CIPP evaluates audit logs against your alert rules, any client IP marked as trusted skips geolocation and reputation enrichment entirely, so rules that key on location or on a bad-reputation IP (including `CIPPBadRepIP`) will not fire for it. Reserved and private address ranges are skipped automatically and do not need an entry.

The page pairs a lookup tool for investigating an IP address with the list of addresses already recorded.

## Geo IP Check

Enter an address into the field and click **Check**. Both IPv4 and IPv6 are accepted, and the field validates the format before the lookup runs. Resolution uses the GeoIP database bundled with CIPP rather than an external service, so no query leaves your instance.

## Geo IP Results

The results card appears once a check has run. Alongside the details below, a map pins the approximate location, and clicking the marker reveals the time zone, the autonomous system the address belongs to, and whether the address is flagged as a proxy, as hosting, or as mobile. Those three flags are often the most useful part of the result when triaging a sign-in from an unexpected location.

| Field   | Description                                    |
| ------- | ---------------------------------------------- |
| Org     | The organization the address is registered to. |
| City    | The city the address resolves to.              |
| Region  | The state or region the address resolves to.   |
| Country | The country the address resolves to.           |
| Zip     | The postal code the address resolves to.       |

Two buttons below the results record the address against the tenant currently chosen in the tenant selector:

* **Add to Whitelist** records the address as trusted, which is what actually suppresses the enrichment described above.
* **Remove from Whitelist** records it as not trusted. This does not delete the entry, it flips its state, so the address reappears in the table marked as not trusted.

{% hint style="warning" %}
Check the tenant selector before using either button. Entries are written against the tenant selected at that moment, and an address trusted for one tenant has no effect on any other.
{% endhint %}

## IP Whitelist

The table lists every address recorded across all of your tenants, not just the tenant currently selected. Use the **Partition Key** column to see which tenant each entry belongs to.

### Table Details

| Column        | Description                                                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Partition Key | The tenant the entry applies to, shown as that tenant's default domain name.                                              |
| State         | Whether the address is recorded as `Trusted` or `NotTrusted`. Only `Trusted` entries change how audit logs are processed. |
| Row Key       | The IP address.                                                                                                           |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Location</td><td>Runs a Geo IP check for the selected address and shows the result in the Geo IP Results card.</td><td>false</td></tr><tr><td>Add to Whitelist</td><td>Records the selected address as trusted for the tenant currently selected. Only shown on entries that are not already trusted.</td><td>true</td></tr><tr><td>Remove from Whitelist</td><td>Records the selected address as not trusted for the tenant currently selected. Only shown on entries that are not already marked as not trusted.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
The whitelist actions write against the tenant in the tenant selector, not the tenant shown in the entry's **Partition Key**. Acting on another tenant's row while a different tenant is selected creates a second entry rather than changing the existing one.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
