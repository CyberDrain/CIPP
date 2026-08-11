# Edit Properties Wizard

This wizard applies the same property change to many users at once. It is reached from the **Edit Properties** action on the [.](./ "mention") page, which carries the selected users across, so there is no way to pick users from within the wizard itself.

{% hint style="info" %}
The selection is handed over in session storage and cleared as soon as the wizard reads it. Reloading the page loses the list and leaves you with nothing to update, so go back to the Users page and start the action again rather than refreshing.
{% endhint %}

{% stepper %}
{% step %}
### Review Users

The users carried over from the Users page are listed with their display name, user principal name, job title and department. The **Remove from List** row action drops a user from the run, which is the moment to catch anyone caught by an over-broad selection or filter. The wizard will not continue with an empty list.
{% endstep %}

{% step %}
### Select Properties

**Properties to update** is a multi-select listing everything that can be changed, with a **Select All** entry at the top. Each property you tick adds its own input below, and the input matches the property: a text box for most, a switch for **Show in Address List**, a user picker for **Manager** and **Sponsor**, and a domain picker for **UPN Domain Suffix**.
{% endstep %}

{% step %}
### Confirmation

The properties and the values you set are listed together, followed by the users the change will be applied to. **Submit** applies everything in one operation. Once it has run the button becomes **Resubmit**, and the results appear below it.
{% endstep %}
{% endstepper %}

## Properties

| Property                | Graph property          | Notes                                                                                                                                                               |
| ----------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Business Phone          | `businessPhones`        | Holds a list in Graph, but the wizard writes the single value entered, replacing any numbers already on the account.                                                |
| City                    | `city`                  |                                                                                                                                                                     |
| Company Name            | `companyName`           |                                                                                                                                                                     |
| Country                 | `country`               | The country name held on the profile. This is not what licenses are assigned against, which is Usage Location below.                                                |
| Department              | `department`            |                                                                                                                                                                     |
| Employee Type           | `employeeType`          | Free text, commonly used for values such as Employee, Contractor or Vendor.                                                                                         |
| Fax Number              | `faxNumber`             |                                                                                                                                                                     |
| Job Title               | `jobTitle`              |                                                                                                                                                                     |
| Manager                 | `manager`               | A directory relationship rather than a property, so it is set in a separate operation from the rest of the patch and reports its own result.                        |
| Mobile Phone            | `mobilePhone`           |                                                                                                                                                                     |
| Office Location         | `officeLocation`        |                                                                                                                                                                     |
| Postal Code             | `postalCode`            |                                                                                                                                                                     |
| Preferred Data Location | `preferredDataLocation` | Only has an effect in a multi-geo tenant, where it decides which region the user's data is stored in.                                                               |
| Preferred Language      | `preferredLanguage`     | A language code such as `en-GB`, not a language name.                                                                                                               |
| Show in Address List    | `showInAddressList`     | A switch rather than a text value. See the note below on setting it to No.                                                                                          |
| Sponsor                 | `sponsor`               | A directory relationship, handled the same way as Manager.                                                                                                          |
| State/Province          | `state`                 |                                                                                                                                                                     |
| Street Address          | `streetAddress`         |                                                                                                                                                                     |
| Usage Location          | `usageLocation`         | A two-letter country code such as `GB` or `US`. This is the field license assignment depends on, so a wrong value blocks licensing rather than just looking untidy. |
| UPN Domain Suffix       | `userPrincipalName`     | Changes the part of the sign-in name after the @ symbol, keeping each user's existing prefix. Only offered when every selected user belongs to the same tenant.     |

Custom data attributes mapped for manual entry against users also appear in the list, labelled **(Custom)**, and write to the attribute they are mapped to. Attributes that hold more than one value are left out, as the wizard writes a single value to every selected user.

{% hint style="warning" %}
Usage Location, Country, Preferred Language and Preferred Data Location are plain text boxes here, unlike the Add User and Edit User forms where they are chosen from a list. Whatever is typed is sent to Graph as it stands, so a value in the wrong format is rejected for every user in the run, or worse, accepted and wrong. Copy the format from an account that is already correct if you are unsure.
{% endhint %}

{% hint style="warning" %}
A property with no value entered is skipped rather than cleared, so the wizard can set and change properties but cannot empty them. To clear a property across several users, use the edit.md page one user at a time, where emptying a field you have edited does clear it.

**Show in Address List** is the exception worth watching. The switch only contributes a value once it has been touched, so setting the property to No means toggling it on and then off again. Leaving it untouched sends nothing at all.
{% endhint %}

{% hint style="danger" %}
Changing the UPN domain suffix signs every affected user out, and they have to sign in again with the new address. Anything keyed to the old sign-in name, including saved credentials and any system that matches users by UPN, needs to be considered before running this across a group.
{% endhint %}

{% hint style="info" %}
When the selection spans tenants, the users are grouped by tenant and updated tenant by tenant. Two limits follow from that. UPN Domain Suffix is withdrawn from the property list entirely, since a domain from one tenant means nothing in another. Manager and Sponsor stay available, but their picker only lists users from the first tenant in the selection, and the assignment will only succeed where an account with that name also exists in the other tenants. The wizard warns about both on screen.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
