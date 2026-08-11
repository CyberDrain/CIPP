# Business Voice

The Business Voice page gives an overview of all the phone numbers in the selected tenant, showing who each number is assigned to, its emergency location, its activation state, when it was acquired, and what it can be assigned to. From here you can assign a number to a user or resource account, remove an assignment, and set the emergency location a number is registered against.

{% hint style="info" %}
A user needs a Teams Phone license before a number can be assigned to them. Phone numbers themselves are not included with Teams Phone licensing: they come from whichever provider gives the tenant its PSTN connectivity.
{% endhint %}

## Filters

| Filter                   | Shows                                                                          |
| ------------------------ | ------------------------------------------------------------------------------ |
| Unassigned User Numbers  | Only numbers that are unassigned and can be assigned to a user.                |

## Table Details

| Column                            | Description                                                                                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Assigned To - User Principal Name | The user principal name of the user or resource account the number is assigned to.                                                         |
| Telephone Number                  | The phone number.                                                                                                                          |
| Assignment Status                 | Whether the number is currently assigned to a user or resource account, or unassigned.                                                     |
| Number Type                       | The type of phone number, such as Calling Plan, Direct Routing, or Operator Connect.                                                       |
| Emergency Location                | The emergency location associated with the number, shown as its description, place name, or street address. Blank when no location is set. |
| Acquired Capabilities             | What the number can be assigned to, such as a user, a conference bridge, or a voice application.                                           |
| Iso Country Code                  | The country of the phone number.                                                                                                           |
| Place Name                        | The location of the phone number.                                                                                                          |
| Activation State                  | The activation state of the phone number.                                                                                                  |
| Is Operator Connect               | Whether the phone number is an Operator Connect number.                                                                                    |
| Acquisition Date                  | The date the number was acquired. Shows "Unknown" where the tenant holds no acquisition date for it.                                       |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign User</td><td>Assigns a user or resource account to the phone number. The assignment is submitted for processing and may take a moment to complete; re-sync the report to see the updated status.</td><td>true</td></tr><tr><td>Unassign User</td><td>Removes the assignment from the phone number. The change is submitted for processing and may take a moment to complete; re-sync the report to see the updated status.</td><td>true</td></tr><tr><td>Set Emergency Location</td><td>Sets the emergency location for the number. Locations are listed by description, place name, or street address.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
