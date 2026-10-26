# Edit JIT Admin Template

This page changes a saved JIT Admin template. It is reached from the **Edit Template** action on the [.](./ "mention") page, and opens the template's stored values in the same form used to create one. The fields and the settings that appear for each choice are described on [add.md](add.md "mention").

Saving overwrites the existing template in place rather than creating a second one, because the template keeps its identifier through the edit. Who created the template and when is preserved, and CIPP additionally records who last modified it.

{% hint style="info" %}
The template stays with the tenant it was created for. Unlike the Add page, which takes its tenant from the top menu, this page uses the tenant stored on the template, so an All Tenants template shows the All Tenants restrictions even while a specific customer is selected. A template cannot be moved between tenants by editing it.
{% endhint %}

{% hint style="info" %}
Turning on **Default for Tenant** clears the flag from whichever template previously held it for that tenant, so there is no need to unset the old default first.
{% endhint %}

{% hint style="warning" %}
Template names have to be unique within a tenant. Saving a name already used by another template for the same tenant is rejected, and the reason is reported in the result.
{% endhint %}

{% hint style="warning" %}
Only the fields belonging to the selected **Default User Action** are kept. Switching a template from creating a new user to using an existing one discards the stored name, username, domain and usage location, and switching the other way discards the stored user and turns off the Vacation Mode defaults. Change this setting only when you intend to rebuild that part of the template.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
