# Deploy Safe Links Template

Creates Safe Links policies in one or more tenants from templates you have already saved. Both fields accept several values, so you can push a set of templates across a set of customers in a single submission.

{% hint style="info" %}
The page itself needs a single tenant selected in the tenant selector and does not support All Tenants there, separately from the **Select Tenants** field below, which still lets you target several tenants or All Tenants for the deployment itself.
{% endhint %}

| Field | Description |
| ----- | ----------- |
| Select Tenants | Required. The tenants to create the policies in. Pick one or several, or All Tenants to cover everything you manage. |
| Select a template | Required. The Safe Links policy templates to deploy. More than one can be selected, and each produces its own policy and rule in every tenant chosen above. |

Submit the form to deploy. Each tenant gets the policy and its matching rule created together, with the settings stored in the template.

{% hint style="warning" %}
A template deploys under the policy name it was saved with. Where a tenant already has a policy or rule of that name, the deployment is skipped for that tenant and the result says so, rather than overwriting what is there. Redeploying a template is therefore not a way to push changed settings to a tenant that already has the policy: edit that tenant's policy on [README.md](../safelinks/README.md "mention") instead.
{% endhint %}

{% hint style="info" %}
Changes to Safe Links policies and rules may take up to 6 hours to propagate throughout your organisation.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
