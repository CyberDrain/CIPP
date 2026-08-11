# Bookmarks

Bookmarks give you quick access to the CIPP pages you use most, without navigating the menu each time. They are saved against your CIPP user account rather than your browser, so the same list follows you to any device you sign in from. You can hold up to fifty bookmarks.

## Adding a Bookmark

There are two ways to bookmark a page.

* Hover over the page's entry in the left-hand menu. A bookmark icon appears at the end of the row, and clicking it adds the page.
* Open the page and click the bookmark button at the end of the breadcrumb trail. See breadcrumb-navigation.md.

In both places an outlined bookmark means the page is not saved and a solid, colored bookmark means it is. Clicking again removes it.

The bookmark takes its name from the page's menu entry, and is filed under the top-level menu heading it belongs to, which is shown above the name in the list.

{% hint style="info" %}
Some pages cannot be bookmarked, and show no bookmark icon. Bookmarks store only the page address, so pages that identify a specific record in their address, such as an individual user or group, are excluded because the saved address would reopen an empty page.
{% endhint %}

Once you reach fifty bookmarks the button is disabled until you remove one, and hovering over it explains why.

## Where Bookmarks Appear

Bookmarks are shown in a collapsible **Bookmarks** section in the left-hand menu, and can also be opened from a bookmark button in the top menu bar. The list and its controls behave identically in both places, and the section remembers whether you left it expanded or collapsed.

Both locations are controlled by the **Show Sidebar Bookmarks** and **Show Popover Bookmarks** settings described in user-settings.md. The sidebar section is shown by default. With nothing saved, the list reads **No bookmarks added yet**.

## Managing Your Bookmarks

Each entry shows the page name with its menu heading above it in smaller text. Clicking the name opens the page. Hovering over an entry reveals its controls at the right-hand end.

| Control            | Description                                                                                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Padlock            | Locks or unlocks the list. While locked, the reorder and remove controls are hidden so bookmarks cannot be moved or deleted by accident as you click through the menu. |
| Sort               | Cycles the display order between **Custom order**, **A > Z** and **Z > A**. The icon reflects the order currently applied.                                             |
| Up and down arrows | Move an entry one position up or down. Shown when **Bookmark Reorder Mode** is set to Arrow Buttons.                                                                   |
| Drag handle        | Drag an entry to a new position. Shown when **Bookmark Reorder Mode** is set to Drag and Drop, and works with both a mouse and touch.                                  |
| Cross              | Removes the bookmark from your list.                                                                                                                                   |

{% hint style="warning" %}
Reordering only takes effect while the list is in **Custom order**. If you try to move an entry while an alphabetical sort is applied, the sort icon flashes instead of the entry moving. Switch back to custom order first.
{% endhint %}

The list is locked by default. If you attempt to move or remove a bookmark while it is locked, the padlock flashes to show why nothing happened.

Your custom order, sort choice and lock state are all remembered between sessions.

{% include "../../../../.gitbook/includes/feature-request.md" %}
