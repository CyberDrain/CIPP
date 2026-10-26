# I Want to Manage My Own Tenant

If you want to manage your own tenant or if you are not a Microsoft Partner but still want to use CIPP you can perform the setup and either enable access to the partner tenant or enable Single Tenant Mode. The CIPP Service Account should be granted at least the [recommended-roles.md](../maintaining-cipp/recommended-roles.md "mention") within the tenant being managed.

{% hint style="warning" %}
To manage the tenant mode, a user with the CIPP `superadmin` role will need to access the [tenant-mode.md](../../user-documentation/cipp/advanced/super-admin/tenant-mode.md "mention") page of the Super Admin settings.
{% endhint %}

### There are 3 different modes in CIPP to choose from:

* **Multi Tenant - GDAP mode**
  * This is the default mode in CIPP, it does not allow access to the partner tenant.
* **Multi Tenant - Add Partner Tenant**
  * This mode allows direct access to the partner tenant in addition to your customer tenants via GDAP. See the Limitations below for more details.
* **Single Tenant - Own Tenant Mode**
  * This mode is for if you would like to manage your own tenant and/or are not a Microsoft Partner. CIPP manages the tenant it is deployed in, and you can still add other tenants as direct tenants. See the limitations below for more details.

## Limitations of Single Tenant Mode

When using Single Tenant Mode, CIPP does not use GDAP. The tenant CIPP is deployed in is the only tenant listed by default, and you cannot add tenants through a GDAP relationship because there is no partner relationship to read them from.

You can still add other tenants as direct tenants, using **Add Direct Tenant** in the Setup Wizard. A direct tenant connects with its own service account instead of GDAP, so the [limitations of direct tenants](gdap-invite-wizard.md#limitations-of-direct-tenants) apply to it.

GDAP permissions will not apply to any tenant in this mode. You must directly assign roles such as Global Administrator to the service account in each tenant you manage.

## Limitations of Partner Tenant Enabled

When using Partner Tenant Enabled mode you can see your partner tenant inside of CIPP. There will be no permissions applied to who can see this tenant and control it.

{% hint style="danger" %}
It is highly recommended to use a custom role if multiple users have access to your CIPP instances. This can help ensure not all users have access to manage your partner tenant. If you do not, it's important to note that all your users will have access to edit/configure your partner tenant. Information on custom roles can be found [here](https://docs.cipp.app/setup/installation/roles#custom-roles).
{% endhint %}

GDAP permissions will not apply, and you must directly assign roles to the service account in the Entra portal (for example User Administrator and Exchange Administrator).

## To set the tenant mode, follow these steps

1. Log in to CIPP with an account with the role `superadmin`. This role will allow you access to the menu to change this setting.
2. Click CIPP at the bottom of the left-hand menu
3. Click Advanced
4. Click Super Admin
5. The default tab is the Tenant Mode tab
6. Select one of the three modes. The default mode is "Multi Tenant - GDAP Mode"
7. Clear the tenant cache. Users of CIPP now have access to the CSP Partner tenant, or to the single tenant it's been configured for.

{% include "../../../.gitbook/includes/feature-request.md" %}
