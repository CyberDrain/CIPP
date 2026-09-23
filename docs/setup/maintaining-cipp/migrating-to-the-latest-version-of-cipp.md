# Migrating CyberDrain Hosted to the New Infrastructure

{% hint style="success" %}
The hosted migration process was completed in late August. All new deployments had been on the new infrastructure from the start of the migration. Your instance is on the new infrastructure at this point. This documentation will remain for reference purposes.
{% endhint %}

In July of 2026, we were pleased to announce new infrastructure for CIPP. Migrating to the new infrastructure gains speed and controlled cost. Newly deployed CIPP instances are already on the new infrastructure.

## CyberDrain Hosted Clients

{% stepper %}
{% step %}
### Open the Management Portal

Navigate to [management.cipp.app](https://management.cipp.app/).
{% endstep %}

{% step %}
### Go to Early Opt-In

Select **Early Opt-In** from the navigation on the left. The page summarises what the migration does and confirms whether your instance is eligible.

Two messages mean there is nothing for you to do here:

* **Your instance is already running CIPP-NG.** The migration has already happened.
* **No classic instance was found to migrate.** Newly deployed instances are built on the new infrastructure, so there is nothing to opt into.
{% endstep %}

{% step %}
### Complete the Form

| Field                 | Description                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| First Name            | Required.                                                                                                                       |
| Email                 | Required.                                                                                                                       |
| Your Company's Domain | Required. Asked separately from your email address, because some MSPs sign up on a different domain from the one they trade as. |
| Discord Username      | Optional. Used to add you to the early opt-in role automatically, so you can reach the **#early-opt-in** channel.               |

{% hint style="info" %}
The Discord username is the one shown beneath your display name on your profile, not the display name itself. You also need to be a member of the [CyberDrain Discord server](https://discord.gg/cyberdrain) for the role to be applied.
{% endhint %}

{% hint style="warning" %}
The migration is one way. There is no rollback to the old platform.
{% endhint %}
{% endstep %}

{% step %}
### Submit

Selecting **Submit** starts the migration straight away, and it can take several minutes. You are redirected to the dashboard to follow its progress, and the Overview tab shows when the migration is complete.

If a migration fails, the Early Opt-In page reports the reason and you can select **Submit** again to retry it.

{% hint style="info" %}
If you receive an error during migration rest assured that the helpdesk has been alerted and will work to resolve the error quickly.
{% endhint %}
{% endstep %}

{% step %}
### SSO Setup

If you have not already completed SSO setup, you are prompted to when you next open CIPP.

Your instance answers on a new hostname after the migration, and sign-in needs a redirect URI of `https://<hostname>/.auth/login/aad/callback` to match it. Creating the app from the SSO page adds that for you. A hostname without one fails sign-in with `AADSTS50011`.

See [sso.md](../../user-documentation/cipp/advanced/authentication/sso.md "mention") for the full process, including what CIPP creates in your tenant and what to do if you cannot sign in at all, or [roles.md](../setting-up-cipp/roles.md "mention") if you are setting up your first user at the same time.
{% endstep %}

{% step %}
### Custom Domain

If you had a custom domain on your old version of CIPP, you'll need to migrate it too. To migrate a domain to the new generation of CIPP, point its existing CNAME record at CIPPXXXX.azurewebsites.net, then add the domain here. It will move over automatically. If a TXT record named `asuid.<your domain>` exists from your previous setup, remove it — domain-verification TXT records are no longer used, and a leftover one blocks validation. This step must be performed in the [management portal](https://management.cipp.app/).

{% hint style="warning" %}
Add the custom domain **after** completing SSO setup and the new hostname has no redirect URI of its own yet, so sign-in on it fails with `AADSTS50011`. Select **Refresh Sign-in URLs** on the CIPP SSO page to add one. The action is additive and never removes an existing URI.
{% endhint %}

{% hint style="warning" %}
Users who load your pre-existing custom domain prior to the certificate being provisioned will be redirected to the new Azure URL. After the certificate is provisioned they may still experience this behavior as their local DNS cache will remember the redirect. Please direct those users to clear their cache.
{% endhint %}
{% endstep %}
{% endstepper %}

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/d3kcpzf2efuj" linkValue="d3kcpzf2efuj" %}

## Self-Hosted Clients

Please see this document for the migration script and instructions:

{% content-ref url="migrating-to-the-new-infrastructure.md" %}
[migrating-to-the-new-infrastructure.md](migrating-to-the-new-infrastructure.md)
{% endcontent-ref %}
