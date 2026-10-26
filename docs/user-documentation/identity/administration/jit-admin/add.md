# Add JIT Admin

This page grants time-limited administrative access. You choose who gets it, what they get, and when it ends, and CIPP acts on the account automatically at expiry. The result appears on the [README.md](README.md "mention") page for as long as CIPP is tracking it.

## Tenant and template

| Field                                      | Description                                                                                                                                                |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select a tenant to create the JIT Admin in | The tenant the access is granted in. Required, and it has to be chosen before the template list and the tenant's Temporary Access Pass policy can be read. |
| JIT Admin Template (optional)              | Applies a saved template, filling in the rest of the form. Templates are managed on the [README.md](templates/README.md "mention") page.     |

{% hint style="info" %}
A default template is applied on its own once a tenant is selected. A template marked as the default for that specific tenant wins; failing that, a template marked as the default across All Tenants is used. Anything a template fills in can still be changed before submitting. A template can contain `%cipptechnician%` in its name, username or reason text, or `%cipptechnicianupn%` in its reason; those are replaced with your own signed-in account name as the template is applied.
{% endhint %}

## User

**Would you like to create a new user or assign permissions to an existing user?** decides which fields follow. Creating a new account keeps the elevated access separate from someone's day-to-day account, which is usually the point of doing this. **Existing User** is greyed out until a tenant is selected.

Changing the tenant clears the selected user, groups and Conditional Access policies, since they belong to the previous tenant.

| Field                 | Description                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| First Name, Last Name | The new account's name. Shown for a new user.                                                             |
| Username              | The part before the @ symbol. Shown for a new user.                                                       |
| Domain Name           | The domain the account is created under, chosen from the tenant's verified domains. Shown for a new user. |
| Usage Location        | The country the account is licensed in. Shown for a new user.                                             |
| User                  | The existing account the access is granted to. Shown when assigning to an existing user.                  |

## Access window

| Field      | Description                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------------------- |
| Start Date | When the access begins. Required.                                                                     |
| End Date   | When the access ends and the expiration action runs. Required, and it has to be after the start date. |

## Roles and groups

**Admin Roles** and **Group Membership** are switches, and each reveals its own selector. At least one entry is required in whichever selector is turned on.

| Field                    | Description                                                                                                                      |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Apply JIT Role Template  | Picks one or more [JIT Role Templates](role-templates/README.md "mention") and adds their roles into Roles below. Selections are additive to whatever Roles already holds, and everything stays editable afterwards. |
| Roles                    | The Entra ID directory roles to assign for the duration of the access.                                                           |
| Groups                   | The groups to add the account to for the duration of the access.                                                                 |
| Reason                   | Why the access was granted. Required, and it is shown on the JIT Admin list, which is what makes the list reviewable afterwards. |

{% hint style="warning" %}
Apply least privilege here. Grant the narrowest role that covers the work rather than reaching for Global Administrator, and keep the window as short as the task allows.
{% endhint %}

{% hint style="info" %}
If your CIPP role has a [JIT Role Template](role-templates/README.md "mention") assigned, Roles only offers the roles that template allows, and Apply JIT Role Template only offers roles you are permitted to grant. Requesting a role outside your allow-list is also rejected when you submit. A role with no template assigned is unaffected.
{% endhint %}

## Temporary Access Pass

**Generate TAP** issues a Temporary Access Pass so the account can sign in and satisfy a strong authentication requirement without a registered method.

The pass lifetime is worked out from the access window rather than entered, then clamped to what the tenant's policy allows. The form states how long the pass will be valid once both dates are set, and warns before you submit if Temporary Access Pass is not enabled in the tenant, in which case generation fails.

{% hint style="info" %}
Temporary Access Pass has to be enabled in the tenant's authentication methods policy first. The **Enable Temporary Access Passes (TAP)** standard turns it on.
{% endhint %}

## Approval

If JIT Admin approval is switched on in the [application settings](../../../cipp/settings/README.md#jit-admin-settings) and the request is for a tenant and a role that need approval, submitting the form does not create anything. The request is saved on the [requests.md](requests.md "mention") tab, the approvers are notified, and the result says how many approvals it needs and from which CIPP roles. When no specific roles are set to need approval, every request needs it, including one that only adds groups.

The duration limit and the roles you are allowed to grant are checked when you submit, and again when the request is approved.

{% hint style="info" %}
When an approved request is created, no password or Temporary Access Pass is generated, even if **Generate TAP** was on, so the approver never sees the account's sign-in details. Once the request is approved, use **Create Temporary Access Pass** or **Reset Password** on the [README.md](README.md "mention") tab to sign in.
{% endhint %}

## Expiry and notification

| Field               | Description                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------- |
| Expiration Action   | What happens to the account when the window closes. Required.                               |
| Notification Action | How you are told when the JIT admin is created and when it expires: Webhook, Email, PSA or Push (a notification to your own registered devices). Several can be selected. |

The expiration action offers **Delete User** and **Disable User** for any grant. Depending on which switches are on, it also offers **Remove Roles**, **Remove Groups**, or **Remove Roles and Groups**, so the account itself survives and only the elevation is taken away. Changing the switches after choosing clears the selection, since the option may no longer apply.

{% hint style="info" %}
Notification channels only deliver if they are configured in CIPP's [notifications.md](../../../cipp/settings/notifications.md "mention") settings first. Selecting one that is not set up produces no notification rather than an error.
{% endhint %}

## Vacation Mode

Two exclusions are offered when the access is assigned to an existing user. They stop the account's elevated sign-ins being blocked or flagged for being somewhere unusual, for example when someone needs admin access while travelling. Each can be used on its own or together, and both cover the same window as the JIT access, plus a one-hour buffer after the end date.

| Field                                         | Description                                                                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Vacation Mode                          | Excludes the user from the Conditional Access policies selected below.                                                                         |
| Conditional Access Policies in _tenant_       | The Conditional Access policies to exclude the user from. Shown once Vacation Mode is on. Several can be selected, read from the selected tenant. |
| Exclude from location-based audit log alerts  | Keeps the user off location-based audit log alerts for the window, so sign-ins from an unusual location do not raise alerts. Works whether or not Vacation Mode is on. |

Once Vacation Mode is on, the form warns until at least one policy is selected. The exclusions are only scheduled after the JIT admin itself is created successfully, and their results are shown alongside the JIT admin's own. They appear on the [Vacation Mode](../vacation-mode/README.md "mention") page with the reason as their reference, where they can be reviewed or removed like any other vacation. A template can turn either exclusion on by default and pre-select the policies.

{% hint style="warning" %}
Excluding an account from a Conditional Access policy lifts that policy's protection for the whole window, on an account that holds elevated roles. Choose only the policies that would actually get in the way.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
