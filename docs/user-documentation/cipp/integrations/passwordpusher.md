# Password Pusher

The Password Pusher integration replaces plain text passwords in CIPP with single-use links. When it is enabled, any password CIPP generates (for a new user, a password reset, a JIT admin account, or a bulk user import) is pushed to Password Pusher and the resulting link is returned in place of the password itself. The expiry, passphrase and retrieval settings configured here apply to every link CIPP creates.

Both the hosted service at [pwpush.com](https://pwpush.com) and self-hosted instances are supported.

If [One-Time Secret](onetimesecret.md) is also enabled, Password Pusher takes priority for generated password links, preserving existing behavior. Disable Password Pusher to use One-Time Secret. The Password Pusher Test button still tests Password Pusher directly.

{% hint style="info" %}
If your Password Pusher instance sits behind a Cloudflare Zero Trust tunnel, set up the [cloudflare.md](cloudflare.md "mention") integration as well and enable **Behind a CF-ZTNA Tunnel**. That toggle only appears on this page once the Cloudflare integration is enabled.
{% endhint %}

## Settings

| Setting                                                                                 | Description                                                                                                                                                                            |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                                                      | Turns the integration on. Every other setting and the **Test** button remain unavailable until this is enabled and saved.                                                              |
| Use Bearer Authentication (Hosted only)                                                 | Authenticates with a bearer token rather than an email address and API key. Only available on the hosted service; self-hosted instances must use the email address and API key method. |
| PWPush URL                                                                              | The base URL of your Password Pusher instance. Leave blank to use the hosted service at `https://pwpush.com`.                                                                          |
| PWPush API Key                                                                          | The API key or bearer token for your account. Optional: leaving it blank creates anonymous pushes. Stored securely and masked once saved.                                             |
| PWPush email address                                                                    | The email address of your Password Pusher account, used together with the API key. Hidden when bearer authentication is enabled.                                                       |
| Select your PWPush Account for branding (Pro/Premium only, optional with Custom Domain) | The Password Pusher account whose branding is applied to generated links. Only appears when bearer authentication is enabled, and requires a Pro or Premium subscription on the hosted service. When no accounts can be retrieved the list shows a single explanatory row instead, which cannot be selected.              |
| Expiration in Days                                                                      | The number of days before a link expires, from 1 to 90. Leave blank to use the Password Pusher default. A value outside that range is ignored and the default is used instead.                                                                                              |
| Expiration after views                                                                  | The number of views before a link expires, from 1 to 100. Leave blank to use the Password Pusher default. A value outside that range is ignored and the default is used instead.                                                                                             |
| Default Passphrase                                                                      | A passphrase the recipient must enter before the password is revealed. Applied to every link CIPP creates, so it needs to be something you can communicate out of band.                |
| Click to retrieve password (recommended if passphrase is not set)                       | Adds an interstitial page requiring a deliberate click before the password is shown, which prevents link preview scanners in mail and chat clients from consuming a view.              |
| Allow deletion of passwords                                                             | Allows the recipient to delete the push once they have retrieved it.                                                                                                                   |
| Behind a CF-ZTNA Tunnel                                                                 | Sends the Cloudflare Access service token with every request to Password Pusher. Only appears when the Cloudflare integration is enabled.                                              |

{% hint style="warning" %}
Enable **Click to retrieve password** whenever no default passphrase is set. Without one of the two, a mail security product that follows links in a message can consume the view before the recipient ever opens it, and the password is then gone.
{% endhint %}

## Authentication

Password Pusher accepts three levels of authentication, and CIPP supports all of them.

| Method                    | Description                                                                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Anonymous                 | Leave the API key blank. Links are created without an account, so they cannot be branded or tracked.                                   |
| Email address and API key | Enter both **PWPush email address** and **PWPush API Key**. This is the only authenticated option available to self-hosted instances.  |
| Bearer token              | Enable **Use Bearer Authentication (Hosted only)** and enter the token as the API key. This unlocks the account selector for branding. |

## Configuring the Integration

{% stepper %}
{% step %}
### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
### Set the instance and authentication

Enter your **PWPush URL** if you are self-hosting, and configure whichever authentication method applies. For bearer authentication, enable the toggle first so that the account selector appears.
{% endstep %}

{% step %}
### Choose branding

Hosted Pro and Premium customers can select an account under **Select your PWPush Account for branding**. Save the configuration first, because the account list is retrieved using the credentials you have stored. Until they are saved, and whenever the token is not a valid Pro or Premium bearer token for the hosted service, the list shows a single explanatory row. That row is there to be read and cannot be selected.
{% endstep %}

{% step %}
### Set expiry and protection

Set **Expiration in Days**, **Expiration after views**, and either a **Default Passphrase** or **Click to retrieve password**. Decide whether recipients may delete their own pushes.
{% endstep %}

{% step %}
### Save and test

Select **Submit**, then select **Test**. A successful test creates a real push containing a test payload and offers a copy button, so you can open the link and confirm the expiry, passphrase and branding behave as you expect. A failed test reports the reason it failed, so a wrong URL, a rejected token or an unreachable instance shows up here rather than later as plain text passwords.
{% endstep %}
{% endstepper %}

## Where Password Links Appear

Once enabled, the integration applies automatically wherever CIPP produces a password. This includes creating a user, resetting a user's password, bulk user creation, JIT admin account provisioning, and restore tasks that generate credentials. No per-action setting is required, and there is nothing to map.

{% hint style="info" %}
If a link cannot be created, for example because the instance is unreachable or the credentials are wrong, CIPP falls back to returning the plain text password and records a warning in the logbook. Passwords are never lost because of an integration failure, but it does mean a silent misconfiguration shows up as plain passwords rather than an obvious error.
{% endhint %}

{% hint style="danger" %}
Do not enable the **Force the default value?** option on a Password Pusher website policy. It applies the default to all account members and cannot be overridden by them, and it has been observed to produce broken push URLs.
{% endhint %}

{% hint style="info" %}
Password Pusher's own password generator policy applies only to the generator on its website, which is a convenience tool. It has no bearing on the passwords CIPP generates, which are controlled by CIPP's own password configuration.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
