# Edit Room

Opened from **Edit Room** on the [README.md](./ "mention") page, this page covers everything about a single room: its name, how it handles bookings, when it is available, what facilities it has, and where it is. **Submit** applies every change on the page at once.

{% hint style="info" %}
A refresh button sits next to the **Basic Information** heading. It reloads the form with the room's current settings, which is worth doing after a change made elsewhere, for example in the Exchange admin center.
{% endhint %}

{% hint style="warning" %}
Emptying a text box does not clear the setting. The previous value stays in place, so a value such as a building or a phone number has to be removed from the Exchange admin center rather than from here.
{% endhint %}

**Basic Information**

| Field                     | Description                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| Display Name              | The name shown in the address list and in booking dialogs. Required.                               |
| Hidden From Address Lists | When on, the room is hidden from the global address list and no longer appears in the room finder. |

**Booking Settings**

| Field                              | Description                                                                                                                                                                                                                                                                                         |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Room Capacity                      | The number of people the room seats. Cannot be negative.                                                                                                                                                                                                                                            |
| Maximum Booking Duration (Minutes) | The longest meeting the room accepts. Accepts 1 to 1440 minutes (24 hours).                                                                                                                                                                                                                         |
| Booking Window (Days)              | How far ahead a meeting can be scheduled. Accepts 0 to 1080 days (3 years).                                                                                                                                                                                                                         |
| Booking Process                    | How the room handles incoming invitations. `None - No processing` leaves requests for a delegate to answer, `AutoUpdate - Accept/Decline but not delete` records the request and leaves the message in the mailbox, and `AutoAccept - Accept and delete` books the meeting and removes the message. |
| Allow Recurring Meetings           | When on, the room accepts recurring meeting requests.                                                                                                                                                                                                                                               |
| Allow Double-Booking               | When on, the room accepts requests that conflict with a meeting already booked.                                                                                                                                                                                                                     |
| Process External Meetings          | When on, the room processes requests from senders outside the organization.                                                                                                                                                                                                                         |
| Enforce Room Capacity              | When on, the room declines meetings with more attendees than the capacity set above.                                                                                                                                                                                                                |
| Forward to Delegates               | When on, meeting requests are forwarded to the room's resource delegates.                                                                                                                                                                                                                           |
| Add Organizer to Subject           | When on, the name of the person who booked the meeting is added to the subject shown on the room's calendar.                                                                                                                                                                                        |
| Default Calendar Permission        | The access everyone in the organization has to the room's calendar, from `Owner` down to `Availability Only` and `None`.                                                                                                                                                                            |
| Delete Subject                     | When on, the meeting subject is removed from the copy kept on the room's calendar.                                                                                                                                                                                                                  |
| Delete Comments                    | When on, the body of the meeting request is removed from the copy kept on the room's calendar.                                                                                                                                                                                                      |
| Remove Private Property            | When on, the private flag is cleared from bookings, so they are visible to anyone who can see the room's calendar.                                                                                                                                                                                  |
| Remove Canceled Meetings           | When on, canceled meetings are removed from the room's calendar instead of being left in place.                                                                                                                                                                                                    |
| Remove Old Meeting Messages        | When on, superseded meeting messages are removed from the room mailbox.                                                                                                                                                                                                                             |

{% hint style="info" %}
Turning on **Add Organizer to Subject** while **Default Calendar Permission** is set to `Availability Only` or `None` raises a warning on the page. Those two permission levels hide the subject, so the organizer's name is added but nobody can read it. Set the permission to at least `Limited Details` for the name to be visible.
{% endhint %}

**Working Hours**

| Field                           | Description                                                                                                                |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Schedule Only During Work Hours | When on, the room declines meetings that fall outside the working hours set below.                                         |
| Working Days                    | The days the room is available. Individual days can be picked, as can the `Weekdays`, `Weekend`, and `All Days` shortcuts. |
| Timezone                        | The time zone the working hours are expressed in.                                                                          |
| Work Hours Start                | The time the room becomes available on a working day.                                                                      |
| Work Hours End                  | The time the room stops being available on a working day.                                                                  |

**Room Facilities & Equipment**

| Field                 | Description                                                                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Wheelchair Accessible | When on, the room is marked as wheelchair accessible so users can filter for it in the room finder.                                              |
| Phone                 | The phone number in the room.                                                                                                                    |
| Audio Device          | The audio device available in the room.                                                                                                          |
| Video Device          | The video device available in the room.                                                                                                          |
| Display Device        | The display device available in the room.                                                                                                        |
| Tags                  | Free-text labels describing the room's features. To add a tag, type it in the box and choose the **Add option: \<tag text>** entry that appears. |

**Location Information**

| Field          | Description                                                                                        |
| -------------- | -------------------------------------------------------------------------------------------------- |
| Building       | The building the room is in.                                                                       |
| Floor          | The floor number the room is on.                                                                   |
| Floor Label    | A label for the floor, for when a number alone is not enough, for example `Ground` or `Mezzanine`. |
| Street Address | The street address of the building.                                                                |
| City           | The city the building is in.                                                                       |
| State/Province | The state or province the building is in.                                                          |
| Postal Code    | The postal code of the building.                                                                   |
| Country/Region | The country or region the building is in, chosen from a list.                                      |

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
