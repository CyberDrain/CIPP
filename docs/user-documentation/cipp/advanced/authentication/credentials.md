# Credentials

The Credentials page is where you see and manage the two app registrations CIPP depends on: **CIPP-SAM**, which CIPP uses for everything it does against Microsoft 365, and **CIPP-SSO**, which signs your users in. The CIPP-SAM card is described here. The SSO card on the same page is covered in [sso.md](sso.md "mention").

Until now the SAM credentials were only touched by the setup wizard and a weekly timer, with nothing showing what was stored, when it expired, or whether it still worked. This page shows all of that, lets you rotate and revoke credentials deliberately, and alerts you whenever anything on the application changes.

## The CIPP-SAM Card

The status chip in the card header summarises the rows beneath it:

| Status                 | Meaning                                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Healthy                | Every credential CIPP uses works and nothing expires within 30 days.                                                                                                                       |
| Unreviewed credentials | The application carries secrets or certificates this instance did not create and nobody has marked as known. See [#reviewing-credentials](credentials.md#reviewing-credentials "mention"). |
| Secret expiring        | The client secret this instance uses, or its certificate, expires within 30 days. The weekly token update renews both automatically; this shows up when that has not happened yet.        |
| Token failing          | A refresh token no longer works, the stored client secret is rejected, or certificate authentication is on but the certificate is not registered on the application.                       |
| Not configured         | The application registration has not been created yet. Run the [sam-setup-wizard.md](../../sam-setup-wizard.md "mention").                                                                |

The rows are grouped into three sections.

**Application** shows the Application (client) ID and the partner tenant, both as chips you can copy, and the authentication mode: **Client secret** or **Certificate**. The chip next to the mode tells you whether the other credential is available as a fallback.

**Credentials** shows what this instance holds:

* **Client secret**: whether the stored secret can obtain a token right now, and when it expires. **Propagating** means a secret was created in the last few minutes and Microsoft has not finished activating it. Nothing needs recreating; it clears on its own. This row is hidden on a certificate-only install that has never had a secret.
* **Certificate**: whether the SAM certificate is registered on the application, and when it expires. **Not provisioned** means no certificate exists yet; the weekly token update creates one.
* **Thumbprint**: the certificate thumbprint, as a chip you can copy.
* **On app registration**: how many secrets and certificates exist on the application in Entra, how many have expired, and how many are still unreviewed.

**Tokens** shows the refresh tokens CIPP signs in with: the partner tenant token, when it was last rotated, and one line per direct tenant. A failing token means re-authentication is needed for that tenant.

Each status row keeps its detail behind the information icon next to the chip, so the full error text from Microsoft is one hover away without cluttering the card. The refresh icon in the header re-checks everything.

{% hint style="info" %}
The checks on this page go to Microsoft directly rather than through CIPP's token cache, so a credential that stopped working shows as failing here even while cached tokens keep the rest of CIPP running for a while.
{% endhint %}

## Actions

The **Actions** menu holds everything that changes a credential. Each one opens a confirmation first, and the result is shown in the same dialog.

| Action             | Description                                                                                                                                                                                                                                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Rotate secret      | Creates a new client secret on CIPP-SAM, stores it, and switches to it straight away. The previous secret stays on the application until it expires, so other instances or integrations still using it keep working. Only shown when a secret is stored.                                                                                        |
| Renew certificate  | Generates a new SAM certificate and registers it on the application. The previous certificate stays registered until it expires.                                                                                                                                                                                                                 |
| Clear token cache  | Drops every cached Graph and Exchange token, including cached failures, so each worker fetches a fresh token on its next call. Use it if token errors persist after a rotation or re-authentication.                                                                                                                                              |
| Run token update   | Runs the weekly token update now: refresh tokens are renewed, the client secret is rotated if it is within 30 days of expiry, and the certificate is renewed if needed.                                                                                                                                                                           |
| Re-authenticate    | Opens the setup wizard at the token refresh step, for when a refresh token has stopped working.                                                                                                                                                                                                                                                    |
| Manual override    | Opens the setup wizard's manual entry step, for storing an Application ID, secret, tenant ID or refresh token by hand.                                                                                                                                                                                                                             |

{% hint style="warning" %}
Microsoft activates a new client secret for different sign-in flows at different times. After a rotation it can take several minutes, sometimes 10 to 15, before every token request accepts the new secret, and during that window requests can fail with `AADSTS7000215`. CIPP keeps retrying rather than treating it as a permanent failure. If you are about to switch authentication modes, wait for the **Client secret** row to read **Valid** first.
{% endhint %}

## Reviewing Credentials

**Manage credentials** opens a table of every secret and certificate on the CIPP-SAM application, read live from Entra. Because several CIPP instances can share one application, and because you may have minted secrets of your own for scripts or other tools, the table tells you which credential is whose:

| Owner                | Meaning                                                                                                                                                                                                                      |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This instance        | The secret or certificate this CIPP instance currently signs in with.                                                                                                                                                       |
| Other CIPP           | Named like a CIPP-created credential, but not the one this instance uses. Most often another CIPP instance, or a leftover from an earlier setup run on this one. The name is only a hint; it still needs reviewing.          |
| External             | Not created by CIPP. For example a secret you minted for an automation platform.                                                                                                                                             |
| Unknown              | Named like a CIPP credential on an instance that predates credential tracking, so it may or may not be this instance's own.                                                                                                 |
| Known · *label*      | A credential someone has reviewed and labelled, or one CIPP created itself and recorded the origin of.                                                                                                                       |

The **Provenance** column shows where a credential came from when CIPP knows: a scheduled rotation, a manual rotation and who ran it, or the initial setup.

Row actions:

| Action            | Description                                                                                                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Revoke credential | Removes the secret or certificate from the application. Anything still signing in with it stops working, and this cannot be undone. Not available for the credential this instance uses.    |
| Mark as known     | Records a label for a credential you have checked, such as the integration that uses it. It stops counting as unreviewed and the label shows wherever the credential appears.                |
| Remove known flag | Clears a label you set earlier. Credentials CIPP created itself keep their recorded origin.                                                                                                   |

Anything this instance did not create counts as unreviewed until it is marked known. Clearing that count once, after enabling this page, gives you a clean baseline: from then on a new unreviewed credential is something that appeared on your application and deserves a look.

## Alerts and Logging

Every credential change made through CIPP is written to the logbook at **Alert** severity, naming the action, the user who performed it, and the credential's key ID or thumbprint. The secret value itself is never logged. Scheduled changes are labelled as such, so a rotation the weekly timer performed reads as routine rather than as something to investigate.

Separately, an hourly monitor compares the secrets and certificates on the CIPP-SAM application against what it saw the hour before, and sends an alert for every credential that was added or removed. This is always on; it is not an alert you choose from the alert catalogue. Alerts go to the channels configured under [notifications.md](../../settings/notifications.md "mention"): e-mail, webhook and PSA. Nothing is delivered until at least one of those is set.

The wording tells you how to react:

* **Created by CIPP (scheduled rotation). No action needed.** and the manual variant naming the user: CIPP made the change itself and recorded it.
* **New credential detected. Not created by this CIPP instance; review it.**: something was added to the application outside this instance. Check the table, then mark it as known or revoke it.
* **Credential removed outside this CIPP instance; review it.**: a secret or certificate disappeared from the application and CIPP did not remove it.

The first time the monitor runs it only records what it sees, so enabling it on an existing application does not produce an alert for every credential already there.

## Switching Authentication Mode

The **Use certificate authentication** option in the [sam-setup-wizard.md](../../sam-setup-wizard.md "mention") switches CIPP-SAM between the certificate and the client secret. Both changes are logged at Alert severity like any other credential change.

Turning certificate authentication on also changes the CIPP Exemption Policy so that adding client secrets to the CIPP-SAM application is blocked. Nobody, CIPP included, can mint a new secret on it until certificate authentication is turned off again, which lifts the block.

### The CIPP Exemption Policy

Entra ID has **app management policies**: rules that control what credentials an application may carry, such as blocking new client secrets, capping their lifetime, or requiring certificates from a trusted authority. A tenant can set a default policy for every application, and individual applications can be assigned their own policy that overrides the default.

CIPP creates one such policy in your partner tenant, named **CIPP Exemption Policy**, and assigns it to the CIPP-SAM application. It exists so CIPP can keep managing its own credentials when your tenant default forbids it: without it, a tenant that blocks client secrets or restricts certificate lifetimes would also stop CIPP from rotating its secret or renewing its certificate, and CIPP would eventually lose access. CIPP creates or updates it only when it needs to, during setup, rotation and renewal, and only ever assigns it to CIPP-SAM. Other applications CIPP works with, such as the Azure MFA client, get their own separately named policies.

In certificate mode the policy does the opposite job for secrets: it is set to block adding client secrets to CIPP-SAM, whatever the tenant default says, while still allowing the certificate to be renewed. Switching back to secret mode sets it to allow secrets again.

The policy only exists in your partner tenant. In customer tenants CIPP-SAM is a service principal protected by the service principal lock that CIPP enables on the application, and CIPP never creates policies there.

App management policies are not shown in the Entra admin centre. You can inspect them with Graph, for example through the Graph Explorer in CIPP at `/policies/appManagementPolicies`, where the CIPP policy shows which restriction types are enabled or disabled for CIPP-SAM.

Turning certificate authentication off needs a working client secret to fall back to. On an install that never had one, CIPP creates a secret for you, using the certificate, and tracks it like a manual rotation. It then waits for Microsoft to activate the new secret before switching; if that takes longer than the request allows, certificate authentication stays on and you are asked to try again in a few minutes. The secret is already in place at that point, so the second attempt completes straight away.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
