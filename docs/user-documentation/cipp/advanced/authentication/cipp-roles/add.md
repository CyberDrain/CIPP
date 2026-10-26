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
