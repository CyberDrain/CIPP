# View Audit Log

Opening a saved log gives you the complete picture of a single captured event: what CIPP matched on, what it did in response, and the raw audit record straight from Microsoft. The heading at the top of the page is the entry's title, the same one shown in the Saved Logs table. **Back** returns you to wherever you came from, which keeps your place in the table and its filters.

## Log Information

A summary of the event and how CIPP handled it.

| Field         | Description                                                                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Timestamp     | When the event occurred in the tenant, taken from the raw audit record.                                                                                 |
| Tenant        | The tenant the entry was captured from.                                                                                                                 |
| User          | The account the event relates to. CIPP resolves this from the audit record, preferring a readable user name where the record only carried an object ID. |
| IP Address    | The client IP address recorded against the event, where one was present.                                                                                |
| Actions Taken | The response actions CIPP ran when the alert matched, such as disabling the user or raising a ticket. Shows `N/A` when the rule was notification only.  |
| Webhook Rule  | The alert condition that matched this entry, written out in the same plain language used on the alert itself.                                           |

Some entries also carry a button in the top right of this card, which jumps straight to the most useful follow-up in CIPP. A BEC alert, for example, links through to the compromise review for the affected user. The button only appears when the alert supplied one.

## Location Information

Shown when an IP address could be determined for the event, either from the audit record or from location data captured at the time. The card is headed with the IP address being looked up.

A map pins the approximate location, and the panel beside it lists the organization, city, region, country and postcode returned by the lookup. Selecting the map marker reveals further detail, including the time zone, the autonomous system, and whether the address is known to be a proxy, a hosting provider or a mobile network.

{% hint style="info" %}
Geolocation is an estimate based on IP registration data. Treat it as a signal rather than proof of where someone was, particularly for mobile and hosting addresses.
{% endhint %}

## Audit Data

Everything else from the raw audit record, laid out as a property list. The exact set of properties varies with the type of event, since this is Microsoft's own record rather than something CIPP shapes.

Values are translated into readable text wherever CIPP has a mapping for them, so numeric result codes and internal identifiers appear as their meanings rather than their raw values. Properties that CIPP added while processing the alert are left out here, as they are already presented above.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
