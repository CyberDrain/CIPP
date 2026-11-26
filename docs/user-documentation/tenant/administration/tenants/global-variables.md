# Global Variables

Global variables are key-value pairs that can be used to store additional information for All Tenants. These are applied to templates in standards using the format %variablename%. If a tenant group the tenant belongs to, or the tenant itself, has a variable with the same name, that value takes precedence: tenant first, then tenant group, then global.

These variables can be used in any type of template and will be replaced automatically.

Tenant custom variables can be set in the [#custom-variables](../../manage/edit.md#custom-variables "mention") box, shown while editing a Tenant. Tenant group variables are set on the group's edit page, see [#group-variables](groups/edit.md#group-variables "mention").

{% hint style="danger" %}
Given the differences in how various systems treat the variable name, we recommend using all lowercase when naming variables, for example variablename.
{% endhint %}

## Variable Types

The type decides how a value is written into a template.

| Type    | Behaviour                                                                                                                                                                                                                                  |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| String  | Substituted as text. The default, and how every variable behaved before types existed.                                                                                                                                                      |
| Integer | Written as a number, so a numeric setting receives `300` rather than `"300"`.                                                                                                                                                              |
| Boolean | Written as `true` or `false`.                                                                                                                                                                                                              |
| JSON    | Written as the JSON value it holds, where the variable fills a whole field.                                                                                                                                                                |
| List    | Several values, entered one per line. Used as an entry in a list, such as a Conditional Access policy's excluded users, groups or locations, it expands into one entry per value. An empty list, entered as `[]`, removes the entry. Inside other text the values are joined with commas. |
| Collection | A List that also repeats the list entry holding it, once per value. Use it in Intune list settings, such as the OneDrive allowed tenant IDs or excluded file types: add a single entry containing `%variable%` and each tenant gets one entry per value. An empty collection removes the entry. |

A List lets one variable carry a different number of values per tenant, for example `%breakglassaccounts%` holding two accounts for one client and three for another, without a variable per entry.

While you add or edit a variable, the dialog previews the value as it will be written in a field, a list entry, an Intune list entry and inside text, so you can see which type fits before saving. A value that does not match its type shows the error saving would give. On a tenant the preview fills in tenant variables such as `%tenantid%`; on global and tenant group variables they are left as typed, because they differ per tenant.

A List can also be empty, which makes an entry optional. Set the global value to `[]` and override it only on the tenants that need something there: everywhere else the entry is removed rather than left unresolved. The Value box cannot be left blank, so type `[]` to save an empty list. See the optional exclusions example under Custom Variables on [create-ca-template.md](../../conditional/list-template/create-ca-template.md "mention").

A List or Collection set on a tenant group or a tenant replaces the inherited value by default. Turn on **Add to the inherited list instead of replacing it** to keep the inherited values and add these to them, for example a global list of trusted IP ranges plus one extra range for a single tenant. Values already in the inherited list are not repeated. Tenant groups that all add to the same list are combined rather than treated as a conflict.

## Automatically Replaced Variables

The following variables will be automatically replaced by CIPP:

* `%deviceadminsid%`
* `%globaladminsid%`
* `%initialdomain%`
* `%initialdomainprefix%` (the initial domain without `.onmicrosoft.com`)
* `%tenantfilter%`
* `%tenantid%`
* `%tenantname%`

`%globaladminsid%` and `%deviceadminsid%` resolve to the tenant's own Global Administrator and Microsoft Entra Joined Device Local Administrator role SIDs, which differ from tenant to tenant. They are read from the tenant's synchronised directory roles, so a deployment that uses one fails for a tenant whose roles have not been synchronised yet.

## Reserved Variables

The following variables are reserved and will not be used:

* `%cippurl%`
* `%cippuserschema%`
* `%defaultdomain%`
* `%partnertenantid%`
* `%programdata%`
* `%programfiles%`
* `%programfiles(x86)%`
* `%samappid%`
* `%serial%`
* `%systemdrive%`
* `%systemroot%`
* `%temp%`
* `%userdomain%`
* `%username%`
* `%userprofile%`
* `%windir%`

## Unresolved Variables

CIPP replaces only the variables that exist for the tenant being processed, which is the global set combined with the variables of the tenant's groups and the tenant's own variables. A variable that has neither a global value nor a tenant value is not resolved, and nothing blocks or validates the template beforehand. The token is left in place as the literal text `%variablename%` and is sent to Microsoft Graph exactly as written.

Graph rejects the malformed value, so the standard fails for that tenant and the failure is recorded in the Standards logs for that tenant only. Tenants that do have a value for the variable continue to deploy normally, which is why this typically shows up as a template that works everywhere except for a handful of tenants. When you see an unexpected Graph error on a Standards deployment, check that every tenant in scope has a value for each variable the template uses.

Conditional Access policies are checked before anything is written: a policy whose users, groups, locations or applications, or whose named locations' names, IP ranges or countries, still hold an unresolved variable stops with an error naming the variable and the tenant, instead of reaching Graph.

A user template's **Manager** and **Sponsor** are also checked before anything is sent: when the variable has no value for the tenant the user is created in, the user is still created, and the results report that the manager or sponsor could not be set, naming the variable and the tenant.

{% hint style="warning" %}
Always give a variable a global value when it is used in a template deployed through Standards, even if you intend every tenant to override it. The global value acts as a fallback, so a tenant that has not been given its own value still deploys a valid value instead of failing. Choose a global default that is safe to apply to any tenant, because it is used wherever a tenant-specific value is missing.
{% endhint %}

The reserved variables listed above behave differently: they are deliberately passed through untouched so the target system can resolve them, and they are not a sign of a missing value.

{% hint style="info" %}
If you want to see how to combine Custom Variables and Tenant Groups to provide a way to "graduate" tenants through standards, see Using Custom Variables to Manage Standards Templates.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
