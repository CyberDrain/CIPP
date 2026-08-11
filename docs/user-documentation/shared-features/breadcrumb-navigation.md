# Breadcrumb Navigation

Breadcrumb navigation appears at the top of CIPP, just beneath the top menu bar, and shows how you reached the page you are on. The bar has three parts: a mode toggle at the far left, the trail itself, and a bookmark button immediately after the last entry in the trail.

## Display Modes

The icon at the far left of the breadcrumb bar switches between the two display modes. Hovering over it tells you which mode you will switch to. Your choice is saved to your preferences and applies the next time you sign in.

### Hierarchy Mode

Hierarchy mode shows where the current page sits in the menu structure, exactly as if you had drilled down through the left-hand navigation to reach it. On pages with tabs, the tab you are viewing is included as the final entry.

Each entry is clickable and takes you to that level. Grouping headers that have no page of their own are shown as plain text rather than links.

### History Mode

History mode shows the pages you actually visited on the way to the current one, in the order you visited them. Clicking an earlier entry returns you to that page and discards everything you visited after it, so the trail always reflects a single path rather than a growing list.

CIPP keeps the last twenty pages and displays the five most recent. The history is held for the current session only, so refreshing the browser or signing in again starts it over.

{% hint style="info" %}
Both modes ignore the tenant selection when building the trail, so switching tenants does not add duplicate entries or leave the tenant name embedded in a breadcrumb label.
{% endhint %}

## Bookmark Button

The bookmark button sits at the end of the breadcrumb trail and adds or removes the current page from your bookmarks. An outlined bookmark means the page is not yet saved, and a solid, colored bookmark means it is.

The bookmark takes its name from the last entry in the breadcrumb trail and is filed under the top-level menu heading that page belongs to, so renaming or restructuring the menu is reflected in new bookmarks automatically.

{% hint style="info" %}
The button is hidden on pages whose address identifies a specific record, such as an individual user or group, because bookmarks store only the page address and saving one of these would reopen an empty page.
{% endhint %}

For managing your saved bookmarks, see [bookmarks.md](menu-bar/bookmarks.md "mention").

{% include "../../../.gitbook/includes/feature-request.md" %}
