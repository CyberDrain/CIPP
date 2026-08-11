# User Defaults

User default templates hold the settings applied to new users at creation time, so an operator filling in the Add User form starts from a filled-in page rather than a blank one. Templates belong to the tenant selected in CIPP, and one template per tenant can be marked as the default.

## Add Template

Opens a dialog to create a template. Enter a name, set the attributes you want applied, and optionally mark the template as the tenant's default. The dialog stays open with your entries after saving, which makes it quick to create several similar templates in succession.

### Template Settings

The same fields are used when creating a template and when editing an existing one. Everything except the template name is optional, and any field left empty is simply not pre-filled on the Add User form.

| Field                                                        | Description                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name                                                | The name the template is listed under. Required.                                                                                                                                                                                                                            |
| Default for Tenant                                           | Marks this template as the one applied automatically for the tenant.                                                                                                                                                                                                        |
| Display Name Suffix (e.g., ' - Contractor' or ' (External)') | Text appended to the user's display name, useful for marking contractors or external staff.                                                                                                                                                                                 |
| Username Format                                              | The pattern used to build the username from the user's name, for example `%FirstName%.%LastName%`. A number in brackets takes that many characters, so `%FirstName[1]%%LastName%` produces `jdoe`. A pattern of your own can be typed in if none of the listed formats fit. |
| Username Space Handling                                      | What to do with spaces in the generated username: keep them, remove them, or replace them.                                                                                                                                                                                  |
| Username Space Replacement                                   | The character used when space handling is set to Replace spaces, for example an underscore or a full stop.                                                                                                                                                                  |
| Primary Domain                                               | The domain the account is created under. Only verified domains are listed.                                                                                                                                                                                                  |
| Add Aliases                                                  | Additional email aliases to add to the account, one per line.                                                                                                                                                                                                               |
| Usage Location                                               | The country used for license assignment.                                                                                                                                                                                                                                    |
| Licenses                                                     | The licenses assigned at creation. Each option shows how many units are currently available.                                                                                                                                                                                |
| Add to Groups                                                | Groups the user is added to at creation.                                                                                                                                                                                                                                    |
| Shared Mailboxes                                             | The tenant's shared mailboxes the user should be granted access to.                                                                                                                                                                                                         |
| Shared Mailbox Permissions                                   | The access level granted on those mailboxes: `Full Access`, `Send As`, and `Send on Behalf`. Several can be selected together. Defaults to `Full Access`.                                                                                                                   |
| Shared Calendars                                             | The shared mailboxes whose calendar the user should be granted access to.                                                                                                                                                                                                   |
| Shared Calendar Permission                                   | The access level granted on those calendars: `Editor`, `Reviewer`, `Limited Details`, `Availability Only`. Defaults to `Editor`.                                                                                                                                            |
| Job Title                                                    | The user's job title.                                                                                                                                                                                                                                                       |
| Street                                                       | The street part of the user's address.                                                                                                                                                                                                                                      |
| City                                                         | The user's city.                                                                                                                                                                                                                                                            |
| State/Province                                               | The user's state or province.                                                                                                                                                                                                                                               |
| Postal Code                                                  | The user's postal code.                                                                                                                                                                                                                                                     |
| Country                                                      | The user's country.                                                                                                                                                                                                                                                         |
| Company Name                                                 | The company recorded on the account.                                                                                                                                                                                                                                        |
| Department                                                   | The user's department.                                                                                                                                                                                                                                                      |
| Mobile #                                                     | The user's mobile number.                                                                                                                                                                                                                                                   |
| Business #                                                   | The user's business number.                                                                                                                                                                                                                                                 |

Any custom user attributes configured in CIPP appear at the end of the form and can be given default values in the same way.

### Shared Mailboxes and Calendars

A template can list the tenant's shared mailboxes that every new user should get access to, and separately the shared mailboxes whose **calendar** they should get access to, each with the level to grant (`Shared Mailbox Permissions`, one or more of `Full Access`, `Send As` and `Send on Behalf`, defaults to `Full Access`; `Shared Calendar Permission`, defaults to `Editor`). Both lists are pre-filled on the **Add User** form and can still be changed per user.

{% hint style="info" %}
Mailbox access with `Full Access` is automapped, so Outlook adds the mailbox on its own. Calendar access cannot work that way: it is granted with a sharing invitation, and the user adds the calendar by clicking the link in the email they receive.

Since a brand-new user is not a usable Exchange recipient right away, both grants are queued as scheduled tasks that run **15 minutes after the user is created**, visible under [scheduler](../../tools/scheduler/ "mention"). For calendars, only the access levels Exchange sends an invitation for are offered: `Editor`, `Reviewer`, `Limited Details` and `Availability Only`.
{% endhint %}

Each permission level is granted by its own task, so a mailbox with both `Full Access` and `Send As` produces two entries in the Scheduler. Only mailboxes that are genuinely shared mailboxes in the tenant are granted: anything else in the list is skipped and reported on the user creation results, and if the tenant's shared mailboxes cannot be read at all, no shared access is granted.

## Table Details

| Column                  | Description                                         |
| ----------------------- | --------------------------------------------------- |
| Template Name           | The name the template was saved under.              |
| Default For Tenant      | Whether this template is the tenant's default.      |
| Display Name            | The display name suffix configured on the template. |
| Username Format         | The username pattern the template applies.          |
| Username Space Handling | How spaces in the generated username are handled.   |
| Usage Location          | The usage location the template applies.            |
| Department              | The department the template applies.                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the selected template to allow you to change the attributes that were previously set.</td><td>false</td></tr><tr><td>Delete Template</td><td>Opens a modal to confirm deletion of the selected template(s)</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
