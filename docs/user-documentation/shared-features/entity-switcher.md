# Entity Switcher

On a page that shows a single record, the page title is a control rather than plain text. It carries a small chevron, and selecting it opens a searchable list of the other records of the same kind, so you can move from one to the next without going back to the table you came from.

## Where It Appears

| Page                                                                                                          | The list holds                                    | Shown beneath each name                             |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- |
| [View Individual User](../identity/administration/users/user/ "mention"), on every tab                        | Every user in the tenant                          | User principal name                                 |
| [View Group](../identity/administration/groups/group.md "mention")                                            | Every group in the tenant                         | Mail address                                        |
| [View Device](../endpoint/mem/devices/device/README.md "mention")                                                    | Every Intune managed device in the tenant         | The user principal name recorded against the device |
| [View App Registration](../tenant/administration/applications/app-registrations/appid.md "mention"), on both tabs | Every app registration in the tenant              | Application (client) ID                             |
| [View Enterprise Application](../tenant/administration/applications/enterprise-apps/spid.md "mention"), on both tabs | Every enterprise application in the tenant        | Application ID                                      |
| [Relationship Summary](../tenant/gdap-management/relationships/relationship/ "mention"), on both tabs          | Every GDAP relationship, across all your customers | The relationship name                               |

On the GDAP relationship pages each entry is named for the customer rather than the relationship, matching the page header, with the relationship name on the second line. A relationship that has no customer recorded against it is listed as **No Customer Set**.

## Using It

Selecting the title opens the list, ordered alphabetically by name. The box at the top filters as you type and matches on both lines of an entry, so a user can be found by display name or by user principal name. A tick marks the record you are already viewing.

Choosing a record loads it in place. You stay on the tab you were on, so moving from one user's Exchange settings to another's takes a single selection rather than a trip back through the users list, and the tenant you are working in does not change.

{% hint style="info" %}
The list is fetched the first time you open it rather than with the page, so there can be a short pause on a large tenant while it loads. Opening it again is immediate for the next five minutes, after which the following opening fetches it afresh.
{% endhint %}

{% hint style="warning" %}
The list is not affected by any filter, search or preset applied to the table you arrived from. It holds every record of that kind, so an account hidden from your table view still appears here.
{% endhint %}

{% hint style="warning" %}
The GDAP relationship list is the one exception to being scoped to a single tenant. It covers your customers as a whole, so selecting an entry can move you to a relationship belonging to a different customer.
{% endhint %}

## On Narrow Screens

On a phone the list opens as a sheet from the bottom of the screen, headed with the record type, and works the same way. See [mobile-layout.md](mobile-layout.md "mention").

{% include "../../../.gitbook/includes/feature-request.md" %}
