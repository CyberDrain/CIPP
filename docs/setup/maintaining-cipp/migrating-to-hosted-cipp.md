# Migrating to Hosted CIPP

When you start a **CIPP sponsorship**, you can either:

* Continue self-hosting and receive support for that setup, **or**
* Use the **version hosted by CyberDrain** (fully managed).

If you decide to **migrate** from a self-hosted instance to our **hosted** environment, follow these steps:

***

### 1. Back Up Your Self-Hosted Instance

{% hint style="warning" %}
NOTE: Please ensure your function app is set to run on PowerShell 7.4, otherwise the backups may be corrupted.
{% endhint %}

{% stepper %}
{% step %}
**Log In** to your **self-hosted** CIPP instance.
{% endstep %}

{% step %}
Go to **Application Settings** → click **Run Backup**.
{% endstep %}

{% step %}
**Download** the generated backup file.

* Store this file in a safe location (it contains all your CIPP config).
{% endstep %}
{% endstepper %}

***

### 2. Deploy Your Hosted Instance

{% stepper %}
{% step %}
**Go to** CIPP's [Management Portal](https://management.cipp.app/) and log in using the email address you signed up with if you subscribed through Stripe, or your GitHub account if you are still using GitHub Sponsors before October 1, 2026.

{% hint style="warning" %}
NOTE: If you are still using GitHub Sponsors and signed up with an organisation account, please send a message to helpdesk@cyberdrain.com with your personal GitHub username so we can help you access the portal. If you have any other trouble accessing the management portal after subscribing, please contact helpdesk@cyberdrain.com.
{% endhint %}
{% endstep %}

{% step %}
**Deploy** your hosted CIPP instance by filling out the required information.
{% endstep %}

{% step %}
**Accept** the initial invite and log into the newly created hosted environment.
{% endstep %}
{% endstepper %}

***

### 3. Transfer Your Key Vault Secrets

The CIPP Key Vault holds four secrets you'll need to enter into the hosted setup wizard:

{% stepper %}
{% step %}
Return to your **self-hosted** instance → **Application Settings** → **Backend**.
{% endstep %}

{% step %}
Click **Go to Keyvault**. This opens the Azure portal on your Key Vault's **Overview** blade. Keep this tab open.
{% endstep %}

{% step %}
**Grant yourself permission to read the secrets.**

By default, even the user who deployed CIPP does not have data plane access to the secret values; only management plane access to the vault itself. Add yourself under **Access policies**, not under **Access control (IAM)**.

1. In the Key Vault's left navigation, click **Access policies**.
2. Click **+ Create**.
3. On the **Permissions** tab, under **Secret permissions**, tick: **List**, **Get**, **Set**, **Delete**, **Recover**, **Backup**, and **Restore**. Leave Key and Certificate permissions unticked. Click **Next**.
4. On the **Principal** tab, search for your own account, select it, then click **Next**.
5. Skip the **Application** tab by clicking **Next**.
6. On the **Review + create** tab, click **Create**.

{% hint style="info" %}
If **Access policies** is missing from the left navigation, your Key Vault is using the Azure RBAC permission model rather than the vault access policy model. Switch it under **Settings** → **Access configuration**, or grant yourself the **Key Vault Secrets Officer** role under **Access control (IAM)** instead.
{% endhint %}

{% hint style="info" %}
The policy usually takes effect within 30–60 seconds. If you get a "Caller is not authorized" error in the next step, wait a moment and refresh.
{% endhint %}
{% endstep %}

{% step %}
**Open the secrets list.**

In the Key Vault's left navigation, expand **Objects** and click **Secrets**. You should see the four secrets listed above.
{% endstep %}

{% step %}
**Reveal and copy each secret value.**

For each of the four secrets:

1. Click the secret name (for example `ApplicationID`).
2. Click the row for the **current version** (the GUID shown under "Current Version").
3. At the bottom of the version page, click **Show Secret Value**.
4. Click the **copy** icon to the right of the revealed value.
5. Switch to your hosted CIPP tab and paste the value into the matching field in the setup wizard (see the table at the top of this section).
6. Use the browser back button twice to return to the secrets list, and repeat for the next secret.

{% hint style="warning" %}
Treat these values like passwords. The Application Secret and Refresh Token together grant unattended access to every customer tenant connected through your CIPP-SAM application. Don't paste them into anything other than the hosted setup wizard.
{% endhint %}
{% endstep %}

{% step %}
In your **hosted** instance, open the CIPP **Setup Wizard** (if you haven't already) and select **"I have an existing application and would like to manually enter my tokens."**
{% endstep %}

{% step %}
Confirm all four fields are populated, then click \*\*Next\*\* to finish the wizard.
{% endstep %}
{% endstepper %}

***

### 4. Restore Your Backup

{% stepper %}
{% step %}
In your **hosted** CIPP instance, navigate to **Application Settings** → **Restore Backup**.
{% endstep %}

{% step %}
**Upload** the backup file you downloaded in Step 1.
{% endstep %}

{% step %}
Wait for the restore to complete. CIPP will import your original configuration and data.
{% endstep %}
{% endstepper %}

***

### 5. (Optional) Custom Domain Cleanup

* If you used a **custom domain** on your self-hosted instance, remove it there first so you can reuse it in the hosted environment.
* In the **Management Portal**, add your custom domain to the hosted CIPP instance following the on-screen instructions.

***

### 6. Set Up Single Sign-On

Single sign-on does not come across with the migration. The sign-in app's credentials live in the instance's Key Vault rather than in the backup, and the four secrets copied in Step 3 belong to the CIPP-SAM application, which handles tenant management rather than sign-in. Your hosted instance therefore starts with no sign-in configuration and prompts you to complete authentication setup.

The hosted instance also answers on a new hostname, and the sign-in app needs a redirect URI of `https://<hostname>/.auth/login/aad/callback` that matches it. A hostname without one fails sign-in with `AADSTS50011`.

There are two ways to finish this. Creating a new app registration is simpler and is what most migrations should do.

#### Option A: Let CIPP create a new app registration

{% stepper %}
{% step %}
In your **hosted** instance, go to **CIPP** → **Advanced** → **Authentication** → **SSO**, or work through the **Complete Authentication Setup** prompt if the instance is showing one.
{% endstep %}

{% step %}
Select **Create SSO App**. CIPP creates a fresh `CIPP-SSO` app registration in your partner tenant, gives it a redirect URI for the hosted hostname, and stores the credentials.
{% endstep %}

{% step %}
Once the hosted instance signs in successfully, delete the old `CIPP-SSO` app registration left behind by the self-hosted instance from Entra. Two registrations of the same name are otherwise easy to confuse later.
{% endstep %}
{% endstepper %}

#### Option B: Reuse the self-hosted app registration

Worth doing if you have scoped Conditional Access policies to the existing `CIPP-SSO` enterprise app and would rather not reapply them.

{% stepper %}
{% step %}
While you are still in the Key Vault in Step 3, copy the values of the `SSOAppId` and `SSOAppSecret` secrets as well. The client secret cannot be read back from Entra afterwards, so collecting it here saves generating a new one.
{% endstep %}

{% step %}
In Entra, open the `CIPP-SSO` app registration → **Authentication**, and add a **Web** redirect URI of `https://<hosted-hostname>/.auth/login/aad/callback`. Leave the existing URIs in place until the migration is finished.
{% endstep %}

{% step %}
In your **hosted** instance, go to **CIPP** → **Advanced** → **Authentication** → **SSO**, expand **Manual configuration (advanced)**, paste the App ID and secret, and select **Save Manual Configuration**. The instance restarts, which can take up to 60 seconds.
{% endstep %}
{% endstepper %}

{% hint style="warning" %}
If you add a custom domain in Step 5 **after** setting up single sign-on, the new hostname has no redirect URI yet and sign-in on it fails. Select **Refresh Sign-in URLs** on the SSO page to add one. The action is additive and never removes a URI.
{% endhint %}

{% hint style="info" %}
Being able to sign in is not the same as having access. Confirm the accounts that should reach CIPP are listed with the right roles on the [cipp-users.md](../../user-documentation/cipp/advanced/authentication/cipp-users.md "mention") page.
{% endhint %}

For the full picture, including what CIPP creates in your tenant, multi-tenant sign-in, and what to do if you cannot sign in at all, see [sso.md](../../user-documentation/cipp/advanced/authentication/sso.md "mention").

***

### 7. Decommission the Old Self-Hosted Instance

The migration is one way, and until the hosted instance is proven the old resource group is your only way back. Your hosted instance also sits in a different Azure subscription, so nothing about the old one is tidied up for you. Run on the hosted instance for a few days first and confirm all of the following before deleting anything.

{% stepper %}
{% step %}
**You can sign in to the hosted instance** with single sign-on, and the accounts that need access are on the CIPP Users list.
{% endstep %}

{% step %}
**Your configuration came across.** Check that your tenants, standards templates, scheduled tasks and integrations are all present after the restore.
{% endstep %}

{% step %}
**A scheduled task has actually run.** A restored schedule that has not fired yet has not proved anything.
{% endstep %}

{% step %}
**Your custom domain resolves to the hosted instance**, if you moved one across in Step 5.
{% endstep %}
{% endstepper %}

#### Your logs do not come across

{% hint style="warning" %}
The backup covers configuration, not history. Your CIPP logs live in a table called `CippLogs` in the old instance's storage account, and restoring a backup does not bring them with it. Deleting the old resource group deletes them permanently, and there is no way to import them into a hosted instance afterwards.
{% endhint %}

Decide what you need before you delete anything. Log entries are kept for the retention period set on [README.md](../../user-documentation/cipp/settings/README.md "mention"), 90 days by default, so anything older than that has already been cleaned up.

There are two ways to keep what remains.

| Approach | What to do |
| -------- | ---------- |
| Copy the logs out | On the **old** instance, use [siem.md](../../user-documentation/cipp/settings/siem.md "mention") to generate a read-only SAS URL for the `CippLogs` table, then pull the table into your SIEM or an archive. The URL stops working when the storage account is deleted, so copy the data itself rather than filing the URL away for later. |
| Keep the storage account | Delete every other resource in the resource group and leave the storage account in place. The logs stay queryable through a SAS URL, at a fraction of the cost of running the old instance. |

{% hint style="success" %}
Keep the backup file you downloaded in Step 1, whatever you decide about the resource group. It is the one thing that survives the old instance being deleted, and it costs nothing to file away.
{% endhint %}

#### Delete the resource group

{% stepper %}
{% step %}
Remove the custom domain from the old instance first, if you have not already done so in Step 5. A domain left bound there cannot be used on the hosted instance.
{% endstep %}

{% step %}
In the Azure portal, open the resource group holding the old CIPP instance and check what is in it. A CIPP deployment creates a Web App or Function App, an App Service Plan, an Application Insights component, a storage account and a Key Vault. If anything unrelated to CIPP was deployed into the same resource group, delete the CIPP resources individually instead of deleting the whole group.
{% endstep %}

{% step %}
Delete the resource group, or the individual resources you identified.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Deleting the resource group puts the Key Vault into a soft-deleted state rather than removing it, and its name stays reserved for the retention period, 90 days by default. CIPP deployments do not turn on purge protection, so if you need that name back sooner you can purge the vault from **Key Vaults** > **Manage deleted vaults** in the Azure portal. A soft-deleted standard vault does not incur charges.
{% endhint %}

{% hint style="info" %}
If you let the hosted instance create a new sign-in app registration in Step 6, the old `CIPP-SSO` app registration is still sitting in your Entra tenant. It is not part of the resource group, so deleting the group leaves it behind.
{% endhint %}

***

### That’s It!

Your instance and settings now live in the fully managed, **CyberDrain-hosted** version of CIPP.

Congratulations on a smooth migration! Enjoy your new, hosted CIPP with automatic updates and support.
