# IP Database

The IP Database holds CIPP's IP allow and block list. Each entry is a single address or a CIDR range, IPv4 or IPv6, recorded as safe or as compromised (a known attacker address).

* **Audit logs:** a safe address is excluded from audit log processing. When CIPP evaluates audit logs against your alert rules, any client IP marked as safe skips geolocation and reputation enrichment entirely, so rules that key on location or on a bad-reputation IP (including `CIPPBadRepIP`) will not fire for it. Reserved and private address ranges are skipped automatically and do not need an entry.
* **Compromise investigations:** the [Business Email Compromise](../../identity/administration/bec/README.md) investigation treats safe entries as confirmed safe and compromised entries as confirmed compromised. Where several entries cover the same address, the most specific range decides it, and at the same specificity an entry for the tenant overrides one for all tenants. A single compromised address inside a safe office range therefore stays compromised.

The page pairs a lookup tool for investigating an IP address with the list of entries already recorded.

Viewing this page needs the `CIPP.IPDatabase` permission. Changing an entry's state still goes through the Application Settings permission.

## Geo IP Check

Enter an address or a CIDR range into the field and click **Check**. Both IPv4 and IPv6 are accepted, and the field validates the format before the lookup runs. For a range, the lookup uses the address written before the prefix length. Resolution uses the GeoIP database bundled with CIPP rather than an external service, so no query leaves your instance.

## Geo IP Results

The results card appears once a check has run. Alongside the details below, a map pins the approximate location, and clicking the marker reveals the time zone, the autonomous system the address belongs to, and whether the address is flagged as a proxy, as hosting, or as mobile. Those three flags are often the most useful part of the result when triaging a sign-in from an unexpected location.

| Field   | Description                                    |
| ------- | ---------------------------------------------- |
| Org     | The organisation the address is registered to. |
| City    | The city the address resolves to.              |
| Region  | The state or region the address resolves to.   |
| Country | The country the address resolves to.           |
| Zip     | The postal code the address resolves to.       |

Three buttons below the results record what you entered in the **Geo IP Check** field, address or range, against the tenant currently chosen in the tenant selector:

* **Mark Safe** records it as safe.
* **Mark Compromised** records it as compromised, a known attacker address.
* **Remove from list** deletes the entry for that tenant, so the address is neither safe nor compromised.

{% hint style="warning" %}
Check the tenant selector before using any of the buttons. Entries are written against the tenant selected at that moment, and an entry for one tenant has no effect on any other. With **All Tenants** selected, the entry applies to every tenant, and an entry for a single tenant overrides it for the same range.
{% endhint %}

## IP Allow/Block List

The table lists every entry recorded across all of your tenants, not just the tenant currently selected. Use the **Partition Key** column to see which tenant each entry belongs to.

### Table Details

| Column        | Description                                                                                                                                                 |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Partition Key | The tenant the entry applies to, shown as that tenant's default domain name, or `AllTenants` for an entry that applies to every tenant.                     |
| Verdict       | Whether the entry is recorded as `Safe` or `Compromised`. An entry made neutral before entries could be removed shows as `NotTrusted` and has no effect.     |
| Range         | The IP address or CIDR range.                                                                                                                               |
| Note          | Context recorded with the entry. Entries saved from a Business Email Compromise IP review carry the case they came from, for example `BEC case` and its ID. |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Location</td><td>Runs a Geo IP check for the selected entry and shows the result in the Geo IP Results card. For a range, the check uses the address before the prefix length.</td><td>false</td></tr><tr><td>Mark Safe</td><td>Records the selected entry as safe for the tenant shown in its <strong>Partition Key</strong>. Greyed out on entries that are already safe.</td><td>true</td></tr><tr><td>Mark Compromised</td><td>Records the selected entry as compromised, a known attacker address, for the tenant shown in its <strong>Partition Key</strong>. Greyed out on entries that are already compromised.</td><td>true</td></tr><tr><td>Remove from list</td><td>Deletes the selected entry from the list.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
The table actions change the entry for the tenant in its own **Partition Key**, whatever the tenant selector is set to. Only the buttons below the Geo IP results write against the selected tenant.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
