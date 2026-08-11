# Custom Data

Custom Data extends Microsoft Entra directory objects with attributes you define, then keeps those attributes populated either from data CIPP already collects or from fields your technicians fill in. Because the values are written to the directory object itself, anything that reads Microsoft Graph can consume them: CIPP, dynamic group membership rules in Entra, your PSA, reporting tools, or your own scripts.

The extensions are owned by the CIPP application registration in your partner tenant, so a single definition is available across every tenant where CIPP is consented. You define an attribute once and map it per tenant.

## How Custom Data Fits Together

{% stepper %}
{% step %}
### Define the attribute

Create either a directory extension or a schema extension. This registers the property against the CIPP application and makes it available on the directory object types you choose.
{% endstep %}

{% step %}
### Map it to a source

Create a mapping that tells CIPP where the value comes from and which tenants it applies to. Reporting DB mappings populate the attribute automatically on a daily schedule. Manual Entry mappings turn the attribute into a form field for your technicians.
{% endstep %}

{% step %}
### Use the values

Manual Entry attributes appear on the user forms and in the bulk patch wizard. All custom data values are readable from Microsoft Graph, so they can drive dynamic groups, licensing rules, reporting, and downstream automation.
{% endstep %}
{% endstepper %}

## Directory Extensions or Schema Extensions?

Both add custom properties to directory objects, but they behave differently once created. Choose based on how permanent the attribute is and whether you need multi-valued storage.

|                | Directory Extensions                                                 | Schema Extensions                                                                                  |
| -------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Structure      | One standalone property per extension.                               | A named group of properties under a single schema.                                                 |
| Data types     | Binary, Boolean, DateTime, Integer, LargeInteger, String.            | Binary, Boolean, DateTime, Integer, String.                                                        |
| Multi-valued   | Supported.                                                           | Not supported.                                                                                     |
| Target objects | User, Group, Administrative Unit, Application, Device, Organization. | User, Group, Administrative Unit, Contact, Device, Event, Message, Organization, Post.             |
| Removal        | Can be deleted at any time.                                          | Properties can never be deleted. The schema itself can only be deleted while it is In Development. |
| Limits         | 100 extension values per resource instance.                          | 100 extension values per resource instance, and 5 schema extensions in total.                      |

{% hint style="info" %}
Use a directory extension when you want a single, disposable attribute or need to store a collection of values. Use a schema extension when you want a coherent, related set of properties that you intend to keep permanently.
{% endhint %}

## Where Custom Data Appears

Defining an attribute is only the first half. The value becomes useful once something reads it. These are the places custom data surfaces today.

| Surface                | What you get                                                                                                                                                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Add User and Edit User | Manual Entry mappings targeting users render as a Custom Data section on the form. The field type follows the attribute's data type, so Boolean attributes become a toggle, DateTime attributes become a date picker, and everything else becomes a text field. In edit mode the current value is pre-filled. |
| User Patch Wizard      | Manual Entry attributes are offered alongside the standard patchable properties, labelled with the field label followed by `(Custom)`, so you can set them across many users at once. Multi-valued and collection attributes are excluded.                                                                    |
| Users list             | Manual Entry attributes mapped to users for the selected tenant are added to the Graph query, so their values are returned on the user object and can be shown as columns.                                                                                                                                    |
| JIT Admin              | CIPP's built-in schema stores JIT administrator state on the user object itself, which is why JIT status survives independently of CIPP's own tables.                                                                                                                                                         |
| Microsoft Graph        | Values live on the Entra object, so they are readable by Graph Explorer, PowerShell, Entra dynamic group rules, and any third-party tool with directory read permissions.                                                                                                                                     |
| CIPP Backup            | Extension and schema definitions are captured in the CIPP backup.                                                                                                                                                                                                                                             |

## The Built-In CIPP Schema

CIPP ships with a schema extension called `cippUser`, described as CIPP User Schema and set to Available. It targets users and holds the properties CIPP uses internally, including the JIT administrator fields, mailbox type, archive settings, and per-user MFA state.

{% hint style="warning" %}
Do not deprecate or attempt to remove the `cippUser` schema. CIPP recreates it automatically, and features that depend on it will behave unpredictably while it is missing.
{% endhint %}

You can add your own properties to it but consider creating a separate schema for organization-specific attributes so that yours stay clearly distinguishable from CIPP's.

## Putting It to Work

Custom Data is most valuable when the attribute feeds something downstream rather than sitting on the object unread. These patterns are a good starting point.

| Goal                                          | Approach                                                                                                                                                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Drive Entra dynamic groups from business data | Create a Manual Entry mapping for something like Department Code or Cost Center, then write an Entra dynamic membership rule against the extension property. Licensing and Conditional Access follow the group automatically. |
| Surface mailbox facts on the user object      | Map properties from the Mailboxes or CAS Mailbox dataset so mailbox type, quotas, forwarding, or protocol settings are readable directly from the user in Graph, without an Exchange Online session.                          |
| Report on storage without a second query      | Map the Mailbox Usage or One Drive Usage datasets to capture size and activity figures on the user.                                                                                                                           |
| Keep an audit trail of mailbox delegation     | Map the Mailbox Permissions dataset to a multi-valued directory extension. Each permission entry is stored as a JSON string.                                                                                                  |
| Record data CIPP does not hold                | Use Manual Entry mappings for employee numbers, start dates, badge identifiers, or asset references so they are captured during onboarding rather than chased afterwards.                                                     |
| Feed your PSA or documentation platform       | Because the values are standard Graph properties, existing integrations and scripts can read them without any CIPP-specific code.                                                                                             |

{% hint style="info" %}
Plan the attribute name before you create it. Directory extensions are given a fixed prefix and schema properties can never be deleted, so renaming later means creating a replacement and migrating values.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
