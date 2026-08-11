# SSO

The SSO App Registration page manages the Entra ID app registration that backs CIPP single sign-on. From here you provision the sign-on app, repair or recreate it, rotate its client secret, choose between single- and multi-tenant login, and for advanced cases store an existing app's credentials by hand.

## What CIPP-SSO Is and Why It Exists

CIPP signs users in with OpenID Connect against an app registration named **CIPP-SSO** in your own partner tenant.

Older CIPP instances ran on Azure Static Web Apps, where sign-in was handled by the platform's built-in Entra ID provider. Microsoft managed that registration, so there was no app registration of your own involved — and nothing in your tenant to scope a Conditional Access policy, MFA requirement or session control to. CIPP now runs on Azure App Service, and this is why an instance that has been upgraded prompts you to complete authentication setup: it needs its own app registration to sign in against. Once CIPP-SSO exists, CIPP sign-in behaves like any other application you own in Entra ID — it appears in your sign-in logs and your Conditional Access policies, MFA requirements, sign-in risk policies and session lifetimes apply to it.

The CIPP-SSO app **only proves who you are**. It has no access to any data in your tenant. Everything CIPP actually does against Microsoft 365 continues to run through the existing CIPP-SAM app registration and your GDAP relationships — the sign-on app is not involved in it.

Which CIPP pages a signed-in user can reach is decided entirely by [cipp-users.md](cipp-users.md "mention") and the roles assigned there. Being able to sign in is not the same as having access.

## What CIPP Creates in Your Tenant

When you run the setup, CIPP creates the following in your partner tenant. All of it is created by CIPP itself, using permissions your tenant already consented to when CIPP was installed — see [#permissions-cipp-uses-to-create-the-app](sso.md#permissions-cipp-uses-to-create-the-app "mention").

| Object                            | Details                                                                                                                                                                    |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App registration `CIPP-SSO`       | Single-tenant by default (`AzureADMyOrg`). ID token issuance enabled. Redirect URI `https://<your-cipp-hostname>/.auth/login/aad/callback` for every hostname bound to the instance. |
| Service principal (enterprise app) | The enterprise app entry for `CIPP-SSO`, so the app can be assigned Conditional Access policies and appear in sign-in logs.                                                  |
| Client secret                     | A single secret named `CIPP-SSO-Secret`, stored in your instance's Key Vault. Its lifetime honors a tenant `passwordLifetime` restriction if you enforce one.                |
| Tenant-wide consent grant         | An `AllPrincipals` OAuth2 permission grant for the three delegated scopes below, so your users are not each prompted to consent at first sign-in. Best-effort — see [#troubleshooting](sso.md#troubleshooting "mention"). |
| App management policy exemption   | Only created if your tenant's default app management policy blocks adding client secrets. Named `CIPP Exemption Policy` and scoped to the CIPP-SAM app.                       |

## Permissions the CIPP-SSO App Requests

The app requests exactly three delegated Microsoft Graph permissions and **no application (app-only) permissions at all**. Because they are delegated only, the app cannot do anything unless a user is actively signed in, and it can never act on its own.

| Permission | Type      | What it grants                                                       | Why CIPP needs it                                                                                                                           |
| ---------- | --------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `openid`   | Delegated | Sign the user in and receive an ID token.                            | The base OpenID Connect scope. Without it there is no sign-in at all.                                                                        |
| `profile`  | Delegated | Read the signed-in user's basic profile — display name, object ID, tenant ID. | Identifies which account signed in, and which tenant it came from.                                                                           |
| `email`    | Delegated | Read the signed-in user's email address / UPN.                       | CIPP matches the UPN against the [cipp-users.md](cipp-users.md "mention") list to decide which CIPP roles and permissions the user gets. |

What these permissions do **not** grant: no access to mailboxes, files, Teams, directory objects, groups, devices, policies, or any other tenant data. Microsoft classifies all three as low impact, and they are consentable by an ordinary user by default. They are the same three scopes used by essentially every OpenID Connect sign-in integration.

{% hint style="info" %}
User assignment is not required on the enterprise app. Any account in the tenant can complete the sign-in, and CIPP then denies access to anyone who is not on the CIPP Users list. If your security team prefers a hard gate at the Entra layer, you can set **Assignment required** on the `CIPP-SSO` enterprise app and assign only the intended users or a group — CIPP does not depend on that setting either way.
{% endhint %}

## Permissions CIPP Uses to Create the App

The setup runs as the **CIPP-SAM** app registration, using application permissions your tenant consented to when CIPP was first installed. Nothing new is requested and no new consent screen is presented during setup, provided your CIPP-SAM consent is current.

| Permission on CIPP-SAM                       | Type        | Why it is used during SSO setup                                                                                                                                   |
| -------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Application.ReadWrite.All`                  | Application | Create the `CIPP-SSO` app registration and its service principal, set its redirect URIs and sign-in audience, and add its client secret.                            |
| `Directory.ReadWrite.All`                    | Application | Write the tenant-wide admin consent grant for `openid`, `profile` and `email`, so your users do not each see a consent prompt at first sign-in.                     |
| `Policy.ReadWrite.ApplicationConfiguration`  | Application | Add an app management policy exemption for CIPP-SAM, but only when the tenant default policy blocks adding client secrets. Without it, secret creation fails.       |

These three permissions are part of the standard CIPP-SAM permission set and were granted at install time — they are not specific to SSO. If your instance predates one of them, the consent is out of date and setup will fail on the corresponding step; re-consent CIPP-SAM from the [sam-app-permissions.md](sam-app-permissions.md "mention") page or by re-running the SAM setup wizard.

## Who Needs to Do What

This is the part most people get stuck on. In the normal path, **nobody needs Entra ID Global Administrator, and no separate enterprise app approval is required.**

| Task                                   | Who has to do it                                                                                                              |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Run the SSO setup                      | A CIPP user with the **superadmin** or **admin** CIPP role (the `CIPP.AppSettings.ReadWrite` permission). This is a CIPP role, not an Entra role. |
| Approve an enterprise app in Entra     | Nobody, in the normal path. CIPP writes the consent grant itself using the permissions above.                                   |
| Grant Entra permissions                | Nobody, in the normal path. The permissions were consented when CIPP was installed.                                             |
| Fix a tenant policy that blocks setup  | An Entra administrator — but only if setup fails. See [#troubleshooting](sso.md#troubleshooting "mention").                        |

An Entra administrator is only needed when a tenant-level policy in your own tenant deliberately blocks part of what CIPP is doing — most commonly an app management policy that forbids adding client secrets, or a tenant setting that disables user consent. Those cases are covered in [#troubleshooting](sso.md#troubleshooting "mention") and [#creating-the-app-registration-manually](sso.md#creating-the-app-registration-manually "mention").

## Setting Up SSO

{% stepper %}
{% step %}
### Open the SSO page

Sign in to CIPP as a user with the superadmin or admin role and go to **CIPP** > **Advanced** > **Authentication** > **SSO**. If your instance is prompting you to complete authentication setup, the dialog it shows runs the same process and you can complete it from there instead.
{% endstep %}

{% step %}
### Choose single- or multi-tenant

Leave **Multi-tenant mode** off unless the people who sign in to CIPP have accounts in a tenant other than your partner tenant. See [#single-tenant-vs-multi-tenant-login](sso.md#single-tenant-vs-multi-tenant-login "mention").
{% endstep %}

{% step %}
### Create the app

Select **Create SSO App**. CIPP creates the app registration, its service principal and its client secret, stores the credentials in Key Vault, and grants tenant-wide consent for the three sign-in scopes. This usually takes a few seconds; secret creation can retry for up to a minute while Entra replicates the new app.
{% endstep %}

{% step %}
### Check the result

The status chip should read **Secrets Stored** or **Complete**, and **Admin Consent** should read **Granted**. If either shows a problem, the card explains what failed and which button resolves it — see [#troubleshooting](sso.md#troubleshooting "mention").
{% endstep %}

{% step %}
### Confirm your CIPP users

On the [cipp-users.md](cipp-users.md "mention") page, make sure the accounts that should have access are listed with the right roles. Sign-in succeeding is not the same as having access.
{% endstep %}
{% endstepper %}

## App Registration Status

The top of the card shows the current state of the SSO app registration.

| Status                         | Meaning                                                                                         |
| ------------------------------ | ----------------------------------------------------------------------------------------------- |
| Not Configured                 | No SSO app registration has been set up yet.                                                    |
| App Created — Secret Pending   | The app registration was created, but its client secret has not yet been generated.             |
| App ID Stored — Secret Pending | The app's ID has been stored, but its client secret is still pending.                           |
| Secrets Stored                 | The app ID and client secret have both been stored.                                             |
| Complete                       | Single sign-on is fully configured.                                                             |
| Error                          | The last setup attempt failed. The error is shown, along with the appropriate recovery buttons. |

Once an app exists, the card also shows:

* **Admin Consent** — whether the tenant-wide consent grant is in place. **Not Granted** is not fatal: sign-in still works, users are simply prompted to consent the first time. **Not Checked** means the grant has not been attempted yet; it is retried on every startup.
* **App ID** — the Application (client) ID of the CIPP-SSO app, and the date it was created.
* **Sign-in URLs** — every hostname bound to this instance. A hostname shown in orange is bound to the instance but has no matching redirect URI on the app registration, so sign-in on that hostname fails with `AADSTS50011`. **Refresh Sign-in URLs** adds the missing ones.

If a setup attempt failed, an alert explains what went wrong and points to the right next step — Repair or Recreate when the app was created but the secret failed, or Create when no App ID was ever saved and an orphaned CIPP-SSO app may need deleting from Entra by hand.

## Managing the SSO App

The buttons on the card change depending on the current status. The available actions are:

| Action                | Description                                                                                                                                           |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Create SSO App        | Provisions the CIPP-SSO app registration in your tenant. Shown when no working app exists.                                                            |
| Repair                | Retries generating the client secret on the existing app registration. Used when the app was created but its secret could not be generated.           |
| Recreate              | Clears the current SSO record and provisions a brand-new app registration. The previous app is left in your Entra tenant for you to delete manually.  |
| Refresh Sign-in URLs  | Adds a redirect URI for every hostname currently bound to this instance. Use it after adding a custom domain. Additive — it never removes a URI.       |
| Rotate Secret         | Generates a new client secret for the existing SSO app.                                                                                               |
| Save Changes          | Applies changes to the SSO settings, such as toggling multi-tenant mode. This restarts CIPP, and the change can take up to 60 seconds to take effect. |

## Single-Tenant vs Multi-Tenant Login

By default, CIPP sign-on is single-tenant: it trusts sign-ins only from your partner tenant. This is the right choice when the people who log in to CIPP have accounts in the partner tenant.

Multi-tenant mode allows users from more than one Entra ID tenant to sign in. Use it for split-tenant deployments where your MSP's staff sign in from a tenant other than the partner tenant. Multi-tenant mode is currently the supported way to handle that scenario.

One important caveat: multi-tenant mode currently accepts sign-ins from any Entra ID tenant. Whether a user can actually reach CIPP is still governed by the [cipp-users.md](cipp-users.md "mention") list and the roles assigned there, so only the intended users should be added.

## Configuring Multi-Tenant Mode

To enable multi-tenant login:

1. Turn on the **Multi-tenant mode (allow users from multiple Entra ID tenants)** switch on the SSO App Registration card. You can also set it while creating the app, or from the Manual Configuration section.
2. Select **Save Changes** to apply it. CIPP restarts, and the change can take up to 60 seconds.
3. On the [cipp-users.md](cipp-users.md "mention") page, add the users who should have access and assign them appropriate roles.

{% hint style="warning" %}
**Restricting to specific tenants:** multi-tenant mode is currently all-or-nothing and cannot yet be limited to a chosen list of tenant IDs from this page. The ability to restrict multi-tenant sign-in to specific tenant IDs is a planned addition to the SSO settings; until it is available, scope who can actually sign in through the CIPP Users list. This section will be updated with the configuration steps once the feature ships.
{% endhint %}

{% hint style="info" %}
Tenant-wide admin consent can only be written in your own partner tenant. In multi-tenant mode, users signing in from a different tenant will still see a consent prompt for `openid`, `profile` and `email` unless an administrator in that tenant grants consent for the CIPP-SSO app.
{% endhint %}

## Troubleshooting

| Symptom                                                                                        | Cause                                                                                                                                                      | Fix                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status **App Created — Secret Pending**, error mentions `Credential type not allowed as per assigned policy` | A tenant app management policy forbids adding client secrets, and CIPP could not create an exemption for itself.                                            | Select **Repair** first — CIPP retries the exemption and the secret. If it fails again, an Entra administrator needs to either exempt the app from the policy, or create the secret by hand and store it through [#manual-configuration](sso.md#manual-configuration "mention"). |
| Status **App Created — Secret Pending**, error mentions the application does not exist          | Entra had not finished replicating the new app when the secret was requested.                                                                              | Select **Repair**. This is a transient condition and normally succeeds on the retry.                                                                                                                                    |
| Status **Error** with no App ID                                                                | An earlier attempt failed before the App ID was saved, so there is nothing to repair. An orphaned `CIPP-SSO` app may exist in Entra.                        | Delete the orphaned `CIPP-SSO` app registration in Entra if one exists, then select **Create SSO App**.                                                                                                                 |
| Admin Consent shows **Not Granted**                                                            | The consent grant could not be written — most often because the tenant's CIPP-SAM consent predates `Directory.ReadWrite.All`.                               | Not fatal; users are prompted to consent once at sign-in and can accept it themselves. To remove the prompt, re-consent CIPP-SAM, or have an Entra administrator select **Grant admin consent** on the `CIPP-SSO` enterprise app. |
| Users see a consent prompt they cannot accept                                                  | Your tenant disables user consent to applications.                                                                                                         | An Entra administrator grants admin consent once on the `CIPP-SSO` enterprise app — Entra admin center > Enterprise applications > CIPP-SSO > Permissions > **Grant admin consent**.                                    |
| `AADSTS50011: The redirect URI ... does not match`                                              | A hostname is bound to the instance but has no matching redirect URI on the app registration — typically after adding a custom domain.                       | Select **Refresh Sign-in URLs**. If the card warns that the domain list could not be read, add the callback URI manually as described below.                                                                            |
| Sign-in stopped working with an invalid client secret error                                    | The client secret expired, or a tenant `passwordLifetime` restriction shortened it.                                                                        | Select **Rotate Secret**, then restart the instance. See [#recovering-login-credentials](sso.md#recovering-login-credentials "mention") if you can no longer sign in at all.                                             |
| You cannot sign in to CIPP at all, or the authentication setup prompt keeps failing and cannot be dismissed | Sign-in is broken, so none of the actions on this page are reachable.                                                                                      | Reset SSO from the management portal to return the instance to its setup wizard — see [#resetting-sso-when-you-cannot-sign-in](sso.md#resetting-sso-when-you-cannot-sign-in "mention").                                   |

## Creating the App Registration Manually

If a tenant policy blocks CIPP from creating the app or its secret, an Entra administrator can create the app registration by hand and you can then point CIPP at it. The result is identical to what CIPP would have created.

{% stepper %}
{% step %}
### Register the application

In the Entra admin center, go to **Identity** > **Applications** > **App registrations** > **New registration**.

* **Name:** `CIPP-SSO`
* **Supported account types:** *Accounts in this organizational directory only* for a normal deployment, or *Accounts in any organizational directory* if you need multi-tenant mode.
* **Redirect URI:** platform **Web**, value `https://<your-cipp-hostname>/.auth/login/aad/callback`

Select **Register**.
{% endstep %}

{% step %}
### Add a redirect URI for every hostname

Under **Authentication**, add a Web redirect URI of `https://<hostname>/.auth/login/aad/callback` for **every** hostname the instance answers on — the default `*.azurewebsites.net` address as well as any custom domain. The SSO page lists them under **Sign-in URLs**. A hostname without its own redirect URI fails sign-in with `AADSTS50011`.

Still under **Authentication**, tick **ID tokens (used for implicit and hybrid flows)**.
{% endstep %}

{% step %}
### Add the API permissions

Under **API permissions**, select **Add a permission** > **Microsoft Graph** > **Delegated permissions**, and add `openid`, `profile` and `email`. Do not add any application permissions.

Optionally select **Grant admin consent** so your users are not prompted at first sign-in. This is required if your tenant disables user consent.
{% endstep %}

{% step %}
### Create a client secret

Under **Certificates & secrets** > **Client secrets** > **New client secret**, create a secret and copy its **Value** immediately — Entra will not show it again. Note the expiry date; sign-in breaks when the secret expires.
{% endstep %}

{% step %}
### Store the credentials in CIPP

Copy the **Application (client) ID** from the app's Overview page. In CIPP, open **Advanced** > **Authentication** > **SSO**, expand **Manual configuration (advanced)**, paste the App ID and secret, set multi-tenant mode if needed, and select **Save Manual Configuration**.
{% endstep %}

{% step %}
### Restart the instance

Restart CIPP so it reads the new credentials. Self-hosted instances restart from the [container.md](container.md "mention") page; CyberDrain-hosted instances restart from the [management portal](https://management.cipp.app/).
{% endstep %}
{% endstepper %}

## Manual Configuration

The Manual configuration (advanced) section lets you store an existing Application (client) ID and client secret directly in Key Vault; for example, to rotate the secret by hand or to point SSO at a different app registration. Enter the App ID (a GUID) and client secret, optionally set multi-tenant mode, and select **Save Manual Configuration**. This overwrites the stored values, so an incorrect App ID or secret will break single sign-on. The instance must then be restarted (from Container Management > Status & Updates on a self-hosted instance) for the change to take effect.

## Resetting SSO When You Cannot Sign In

Everything above assumes you can still reach the CIPP interface. If SSO is broken badly enough that you cannot sign in at all — an expired or incorrect client secret, a deleted app registration, or a setup attempt that failed and left the instance unusable — you do not need to reach this page to fix it.

For CyberDrain-hosted instances, the [management portal](https://management.cipp.app/) has a **Reset SSO** page. Resetting tells the instance to disregard its stored sign-in configuration and restart into its setup wizard, which is reachable without signing in. From there you walk back through SSO setup and either let CIPP create a fresh CIPP-SSO app registration, or supply an Application (client) ID and client secret that an Entra administrator created for you. Once new credentials are stored, the reset clears itself automatically and normal sign-in resumes.

A reset only affects sign-in. Your CIPP-SAM app registration, GDAP relationships, tenants, standards and all other CIPP data are untouched.

{% hint style="info" %}
This is also the way out of a forced authentication setup prompt you cannot get past. If the **Complete Authentication Setup** dialog keeps failing — because a tenant policy blocks the client secret, for example — reset SSO from the management portal to return the instance to its setup wizard, then complete setup with an app registration created by hand as described in [#creating-the-app-registration-manually](sso.md#creating-the-app-registration-manually "mention").
{% endhint %}

**Self-hosted instances** achieve the same thing by adding the application setting `CIPP_SSO_RESET` with a value of `true` to the App Service hosting CIPP, then restarting it. CIPP removes the setting itself once new sign-in credentials have been stored.

## Recovering Login Credentials

If the SSO client secret expires, single sign-on stops working and users may be unable to log in.

If you can still reach this page, use **Rotate Secret** to issue and store a new secret, or use **Manual Configuration** to write a known-good App ID and secret, then restart the instance.

If you cannot sign in at all, use the reset described in [#resetting-sso-when-you-cannot-sign-in](sso.md#resetting-sso-when-you-cannot-sign-in "mention"). On a self-hosted instance, an administrator with access to the underlying Azure resources can alternatively retrieve or replace the stored SSO values directly in the instance's Key Vault and restart the container to restore access.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
