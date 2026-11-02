# Setup Wizard

The Setup Wizard is the component that gives CIPP access to your client tenants. It creates and maintains the **Secure Application Model (SAM)** application registration that CIPP authenticates with against Microsoft Graph, Exchange Online and the Partner Center APIs, and it is also where tenants are added to an existing deployment.

The wizard offers six setup options. Which steps you see depends entirely on the option chosen, so the flow is short for routine tasks and longer for a first-time build.

{% hint style="info" %}
Until CIPP's first setup is complete, this same wizard opens automatically as a full-screen gate in place of the rest of the app. That gate offers only **First Setup** and **Manually enter credentials**, plus **Refresh Tokens for existing application registration** once an application registration already exists but its refresh token has died.
{% endhint %}

## First Setup

Choose **First Setup** if this is your first time setting up CIPP, or if you want to redo a previous setup. This is the only option that runs the complete initial configuration in one pass, covering the application registration, tenant access, baselines, notification settings, and a closing summary of what to do next.

The Application step asks whether the new application registration should authenticate with a certificate or a client secret. Certificate is the default: CIPP generates and auto-rotates it, and there is no secret to manage. Client secret creates a traditional shared secret instead, which some newer Entra tenants block.

For the full walkthrough, see [executing-the-setup-wizard.md](../../setup/installation/executing-the-setup-wizard.md "mention"). The service account this relies on is covered in [creating-the-cipp-service-account-gdap-ready.md](../../setup/installation/creating-the-cipp-service-account-gdap-ready.md "mention").

## Add a Tenant

Choose **Add a tenant** to bring a new tenant into an existing CIPP deployment. You are then asked to pick a tenant type, and each type leads to a different path.

**Add GDAP Tenant** and **Get Reseller Invite Link** are greyed out where the tenant CIPP itself runs in is not a Microsoft Partner tenant, since both work through Partner Center. **Add Direct Tenant** is always available.

Detailed steps for the GDAP and direct paths are in [gdap-invite-wizard.md](../../setup/installation/gdap-invite-wizard.md "mention").

{% hint style="warning" %}
Adding a tenant requires a role with unrestricted tenant access, meaning **Allowed Tenants** left as `AllTenants` with nothing in **Blocked Tenants**. A role scoped to particular tenants or tenant groups can reach the wizard but is refused at the point the tenant is saved. See [roles.md](../../setup/setting-up-cipp/roles.md "mention").
{% endhint %}

### Add GDAP Tenant

For Microsoft CSP partners. This walks you through creating a GDAP relationship, selecting the admin roles to request, and generating an invite link to send to the customer.

Once the customer accepts the invite, a further **GDAP Tenant Onboarding** step becomes available in the same wizard. That step maps the requested GDAP roles to security groups and validates that CIPP can reach the tenant, and it offers the option to exclude the newly onboarded tenant from All Tenant standards. It can also add the tenant to static tenant groups, which happens once its CPV permissions have been refreshed. Onboarding progress can also be reviewed later on onboarding.md.

### Add Direct Tenant

For non-partner scenarios, or tenants that fall outside the scope of your Partner Center. You authenticate directly against the target tenant to grant CIPP access, rather than relying on a delegated relationship.

### Get Reseller Invite Link

Generates a reseller relationship invite link to send to a customer. If your service account is an indirect reseller, your indirect provider can optionally be included in the link.

A reseller relationship is a **billing** relationship. It lets you sell and issue licences to the customer and it is what the Partner Center APIs authorise against, for example Autopilot device registration: see [add-device.md](../endpoint/autopilot/add-device.md "mention"). It grants no administrative access.

{% hint style="warning" %}
This is not part of tenant onboarding and is not a prerequisite for it. GDAP is the delegated admin relationship and works with no reseller relationship in place; a reseller relationship on its own gives CIPP nothing to manage. Use this option only when you actually need the billing relationship.
{% endhint %}

This option does not add the tenant to CIPP. It only produces the Microsoft Admin Portal invitation link, and there is no automatic confirmation when the customer accepts it: verify the relationship in Partner Center.

## Create a New Application Registration

Select this option when you need to replace the application registration CIPP is using, or want to use your own custom registration. It runs the Application and Tenants steps from the First Setup flow, without the baselines, notifications or next steps screens.

## Refresh Tokens for Existing Application

Re-authenticates your existing CIPP-SAM application. It refreshes the Graph API token and updates the stored refresh token, leaving the application registration itself untouched.

This is the option to use when an authentication problem has stopped CIPP refreshing its own token, or when someone has authenticated CIPP with a personal account instead of the CIPP service account.

## Manually Enter Credentials

Enter or update the credentials for an existing application by hand.

| Field              | Description                                    |
| ------------------ | ---------------------------------------------- |
| Tenant ID          | Your partner or primary tenant GUID.           |
| Application ID     | The client ID of the application registration. |
| Application Secret | The client secret value, not the secret ID.    |
| Refresh Token      | A valid refresh token for the service account. |

Leave any field blank to retain its currently stored value.

{% hint style="info" %}
This is most useful when migrating CIPP to a new Azure resource group and carrying an existing setup across. It is recommended for advanced users only, since an incorrect value here will break CIPP's access to every tenant.
{% endhint %}

## Use Certificate Authentication

Switches an existing installation between authenticating with the SAM certificate and the client secret, without recreating the application registration. The toggle starts set to the option's current state, and works in either direction.

Turning it on makes sure a SAM certificate exists and is registered on the application - generating and registering one first if needed - before authentication switches over. If that step fails, the error is reported and the client secret stays in use, so nothing breaks. Turning it off needs a working client secret to fall back to: an install that has none gets one created for it, using the certificate, and the switch waits until Microsoft has activated it. If that takes longer than the request allows, certificate authentication stays on and you are asked to try again in a few minutes. Turning it on also sets the CIPP Exemption Policy, the Entra app management policy CIPP keeps on the CIPP-SAM application (explained on the [credentials.md](advanced/authentication/credentials.md "mention") page), to block adding client secrets, and turning it off lifts that block. Both switches are logged at Alert severity and the credentials involved appear on the [credentials.md](advanced/authentication/credentials.md "mention") page.

{% hint style="info" %}
The certificate is renewed automatically on the same schedule either way, so leaving certificate authentication off does not stop it being kept current for whenever it is turned on.
{% endhint %}

## Wizard Steps

The steps shown depend on the option chosen, and every path finishes with a confirmation screen.

| Option                                               | Steps                                                                                                                          |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| First Setup                                          | Application, Tenants, Baselines, Notifications, Next Steps                                                                     |
| Add a tenant                                         | Tenant Type, followed by Direct Tenant, GDAP Setup or Reseller Link. GDAP Onboarding appears once the invite has been accepted |
| Create a new application registration                | Application, Tenants                                                                                                           |
| Refresh Tokens for existing application registration | Refresh Tokens                                                                                                                 |
| Manually enter credentials                           | Manually enter credentials                                                                                                     |
| Use certificate authentication                       | Certificate Authentication                                                                                                     |

## Deep Linking

The wizard accepts two query parameters, which preselect an option and skip the corresponding selection screens.

| Parameter        | Description                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `selectedOption` | Preselects a setup option and skips the option list. Accepts `FirstSetup`, `AddTenant`, `CreateApp`, `UpdateTokens`, `Manual` or `CertificateAuth`. |
| `tenantType`     | Used alongside `selectedOption=AddTenant` to preselect the tenant type and skip the type selection. Accepts `GDAP`, `Direct` or `IndirectReseller`. |

This is how links elsewhere in CIPP drop you straight into the right place, such as re-authenticating a direct tenant from the tenants list. It is equally useful in your own runbooks.

## Related Documentation

{% content-ref url="../../setup/installation/creating-the-cipp-service-account-gdap-ready.md" %}
[creating-the-cipp-service-account-gdap-ready.md](../../setup/installation/creating-the-cipp-service-account-gdap-ready.md)
{% endcontent-ref %}

{% content-ref url="../../setup/installation/executing-the-setup-wizard.md" %}
[executing-the-setup-wizard.md](../../setup/installation/executing-the-setup-wizard.md)
{% endcontent-ref %}

{% content-ref url="../../setup/installation/gdap-invite-wizard.md" %}
[gdap-invite-wizard.md](../../setup/installation/gdap-invite-wizard.md)
{% endcontent-ref %}

{% include "../../../.gitbook/includes/feature-request.md" %}
