# Edit Room List

Opened from **Edit Room List** on the [README.md](./ "mention") page, this page renames a room list, changes which rooms and owners it holds, and controls whether it accepts external mail. The heading reads **Room List:** followed by the list's display name, and **Submit** applies every change on the page at once.

A **View members** button sits beside the heading. It swaps the form for a read-only table of the list's current contents, with a **Type** column marking each row as `Owner` or `Room` alongside the user principal name and display name. The button changes to **Edit Membership** to switch back.

{% hint style="warning" %}
Emptying **Display Name**, **Description**, or **Mail Nickname** leaves the previous value in place. These cannot be cleared from this page.
{% endhint %}

**Room List Properties**

| Field         | Description                                                                                                  |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| Display Name  | The name shown in the address list and in the room finder.                                                   |
| Description   | A free-text description of the room list.                                                                    |
| Mail Nickname | The alias of the room list. Changing this also renames the room list object, so it is not a cosmetic change. |

**Add Members**

| Field              | Description                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------- |
| Add Room Mailboxes | The rooms to add to the list, chosen from the rooms in the tenant. Rooms already in the list are not offered. |
| Add Owners         | The users to add as owners of the list. Users who are already owners are not offered.                         |

**Remove Members**

| Field                 | Description                                                                |
| --------------------- | -------------------------------------------------------------------------- |
| Remove Room Mailboxes | The rooms to take out of the list, chosen from its current members.        |
| Remove Owners         | The users to remove as owners of the list, chosen from its current owners. |

**Room List Settings**

| Field                                                   | Description                                                                                             |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Let people outside the organization email the room list | When on, senders outside the organization can email the room list. When off, only internal senders can. |

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
