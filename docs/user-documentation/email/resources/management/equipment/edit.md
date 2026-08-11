# Edit Equipment Mailbox

This page changes the details and booking behavior of an equipment mailbox. It is reached from the **Edit Equipment** action on [README.md](README.md "mention"), and opens with the mailbox's current settings filled in.

**Basic Information**

| Field                      | Description                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------- |
| Display Name               | The name the equipment is listed under in the address list. Required.                           |
| Hidden From Address Lists  | Keeps the equipment out of the address list, so it can still be booked directly but not browsed. |

**Booking Information**

| Field                             | Description                                                                                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Maximum Booking Duration (Minutes) | The longest single booking allowed. Set it to `0` for no limit.                                                                                                   |
| Booking Window (Days)             | How far ahead the equipment can be booked, up to 1080 days.                                                                                                       |
| Booking Process                   | How requests are handled: **None** leaves them for a delegate to answer, **AutoUpdate** accepts or declines without deleting, and **AutoAccept** accepts and deletes the request. |
| Allow Recurring Meetings          | Whether the equipment can be booked on a repeating basis.                                                                                                         |
| Allow Double-Booking              | Whether two bookings may overlap. Off means a clashing request is declined.                                                                                       |
| Process External Meetings         | Whether requests from outside the organization are handled automatically rather than declined.                                                                    |
| Forward to Delegates              | Whether requests are passed on to the mailbox's delegates.                                                                                                        |

**Working Hours**

| Field                          | Description                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------------- |
| Schedule Only During Work Hours | Restricts bookings to the working hours set below, so a request outside them is declined.       |
| Working Days                   | The days the equipment can be booked. Individual days can be chosen, or Weekdays, Weekend, or All Days. |
| Timezone                       | The timezone the working hours are read in.                                                     |
| Work Hours Start Time          | When the working day begins.                                                                    |
| Work Hours End Time            | When the working day ends.                                                                      |

**Equipment & Location Details**

| Field          | Description                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------------- |
| Department     | The department the equipment belongs to.                                                     |
| Company        | The company the equipment belongs to.                                                        |
| Phone          | A contact number recorded against the equipment.                                             |
| Street         | The street part of the equipment's address.                                                  |
| City           | The city the equipment is in.                                                                |
| State          | The state or province the equipment is in.                                                   |
| Postal Code    | The postal code for the equipment.                                                           |
| Country/Region | The country or region the equipment is in, chosen from the list.                             |
| Tags           | Free-form labels for grouping equipment, for example by floor or by type. New tags can be typed in. |

**Save** applies the changes and returns you to the equipment list.

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
