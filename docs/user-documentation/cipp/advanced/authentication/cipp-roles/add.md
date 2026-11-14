# Add Role

Create a new custom CIPP role from scratch, choosing who it applies to, which tenants it can reach, and which CIPP API permissions it grants.

{% stepper %}
{% step %}
### Name

Enter a unique name for the role.
{% endstep %}

{% step %}
### (Optional) Group Assignment

Select an Entra ID group to assign to this role. This will automatically assign the CIPP role permissions to anyone added to this group.
{% endstep %}

{% step %}
### (Optional) JIT Role Template

Select a [JIT Role Template](../../../../identity/administration/jit-admin/role-templates/README.md) to restrict which Entra ID directory roles members of this role can grant when creating a JIT Admin. Members will also only see existing JIT Admins whose roles fall entirely within the template. Leave blank to apply no restriction from this role. A template on any other role a user holds still applies, because restrictions combine rather than cancel out.
{% endstep %}

{% step %}
### (Optional) Allowed Tenants

Select the tenants that you want this role to have access to. If you select `AllTenants` you will be given the option to select any blocked tenants if a restrictive list is easier to manage.

{% hint style="info" %}
Templates are shared across every tenant, so a role limited to particular tenants, through a list of allowed tenants or any blocked tenants, can create new templates but cannot change or remove existing ones. Only a role that reaches every tenant can.
{% endhint %}
{% endstep %}

{% step %}
### (Optional) Block the All Tenants view

Switch on **Block the All Tenants view** to stop members of this role selecting **\*All Tenants** in the tenant selector or running cross-tenant views. A user who also holds a role without this setting, or a built-in admin role, still gets the All Tenants view.
{% endstep %}

{% step %}
### (Optional) Block tenant groups in the tenant selector

Switch on **Block tenant groups in the tenant selector** to stop members of this role picking a tenant group in the tenant selector to view pages. They can still assign standards, alerts and other settings to tenant groups, and a user who also holds a role without this setting still gets tenant groups in the selector.

The switch is unavailable until **Tenant Groups in Tenant Selector** is turned on under [features.md](../../../settings/features.md "mention"). See [tenant-select.md](../../../../shared-features/menu-bar/tenant-select.md "mention").
{% endstep %}

{% step %}
### (Optional) Blocked Endpoints

You can get more granular with your permissions to block specific CIPP API endpoints, such as `ExecJITAdmin` if you don't want this custom role to have access to creating JIT admin accounts in your clients' tenants.
{% endstep %}

{% step %}
### (Optional) Allowed IP Range

Enter the IP addresses, as single hosts or in CIDR notation, that members of this role can use CIPP from. Leave it empty to allow all IP addresses.
{% endstep %}

{% step %}
### (Optional) App Role Tenants

Enter the Entra tenant IDs whose users can be given this role through an app role on the CIPP SSO enterprise app, pressing Enter after each one. A user from a listed tenant who is assigned the role's app role on that enterprise app receives this CIPP role when they sign in. Include your own tenant ID to grant the role this way in your own tenant. Anything that is not a tenant ID is ignored when you save.

When you save, CIPP adds an app role named after this role to the CIPP-SSO app registration if one is not there yet. If it cannot, the result message asks you to add an app role with the role's name as its value yourself.

Users from any tenant other than your own can only sign in when the SSO app is in multi-tenant mode and an administrator in their tenant has consented to it. If sign-in is restricted to a list of tenants, the result message names any listed tenant that is missing from it. See [#single-tenant-vs-multi-tenant-login](../sso.md#single-tenant-vs-multi-tenant-login "mention").
{% endstep %}

{% step %}
### Set API Permissions

Permissions are defined in one of two modes, chosen with the **Simple (patterns)** and **Advanced (per-category)** toggle. A new role opens in Simple mode.

**Simple (patterns)** takes an **Include** list of patterns that grant access and an **Exclude** list that denies anything matching, with exclusions always winning, the same arrangement the built-in roles use. Patterns match permission names in the form `Category.Object.Level` and `*` matches anything, so `Identity.*.Read` grants read access to everything under Identity. **Start from a built-in role** fills both lists with an existing role's patterns as a starting point, and the **Live result** panel shows how many permissions each pattern matches so an ineffective pattern is easy to spot.

**Advanced (per-category)** lists the categories individually, where you select whether the custom role will have `None`, `Read`, or `Read/Write` access to each. Use the Information icon next to each category to display the CIPP API endpoints included in each category.

`CIPP.Core.Read` is the minimum needed to sign in and is added to every role automatically. It covers the dashboard and the lookups shared by every page, and nothing more: the Logbook, Report Builder, breach lookups and IP Database each have their own permission under `CIPP`, as does the Template Library, which also covers the **Catalog** page. This means a role that should only sign in and work in one area can leave those out.

{% hint style="warning" %}
Note that when creating a custom role to layer with the base role, any permission that you do not define will be evaluated as if you had selected `None`. If you want to preserve the functionality of the base role, be sure to select an option for every category.

Saving in Simple mode replaces the role's permissions with the patterns on screen, so the two modes are not combined.
{% endhint %}
{% endstep %}
{% endstepper %}

## Additional Information Regarding API Permissions

The `i` icon next to each API permissions category will open a flyout listing the CIPP API endpoints included in each category. This flyout also shows the `i` icon next to API endpoints where developers can add details regarding the function of the API. This will help clarify the endpoint's purpose if the name of the API endpoint is not clear.

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
