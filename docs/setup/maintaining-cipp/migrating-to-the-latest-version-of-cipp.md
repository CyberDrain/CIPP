# Migrating to the Latest Version of CIPP

In July of 2026, we were pleased to announce new infrastructure for CIPP. Migrating to the new infrastructure gains speed and controlled cost. Newly deployed CIPP instances are already on the new infrastructure.

## CyberDrain Hosted Clients

{% stepper %}
{% step %}
### Open the Management Portal

Navigate to [management.cipp.app](https://management.cipp.app/).
{% endstep %}

{% step %}
### Go to Early Opt-In


{% endstep %}

{% step %}
### Complete the Form


{% endstep %}

{% step %}
### Submit

The Overview tab will show when your migration is complete.&#x20;

{% hint style="info" %}
If you receive an error during migration rest assured that the helpdesk has been alerted and will work to resolve the error quickly.
{% endhint %}
{% endstep %}

{% step %}
### SSO Setup

If you haven't already completed the SSO set up steps you will be prompted to complete that setup when you first open CIPP again. See [roles.md](../setting-up-cipp/roles.md "mention")
{% endstep %}

{% step %}
### Custom Domain

If you had a custom domain on your old version of CIPP, you'll need to migrate it too. To migrate a domain to the new generation of CIPP, point its existing CNAME record at CIPPXXXX.azurewebsites.net, then add the domain here. It will move over automatically. If a TXT record named `asuid.<your domain>` exists from your previous setup, remove it — domain-verification TXT records are no longer used, and a leftover one blocks validation. This step must be performed in the [management portal](https://management.cipp.app/).

{% hint style="warning" %}
Users who load your pre-existing custom domain prior to the certificate being provisioned will be redirected to the new Azure URL. After the certificate is provisioned they may still experience this behavior as their local DNS cache will remember the redirect. Please direct those users to clear their cache.
{% endhint %}
{% endstep %}
{% endstepper %}

{% @storylane/embed subdomain="app" linkValue="d3kcpzf2efuj" url="https://app.storylane.io/share/d3kcpzf2efuj" %}

## Self-Hosted Clients

Self-hosted instances migrate with the PowerShell script in `deployment/Invoke-CippMigration.ps1`. It moves the instance to the containerized web app, preserves your SAM credentials and API auth settings, migrates SWA users into `allowedUsers`, and removes the old Function Apps, App Service Plans, Application Insights resources, and Static Web App.

{% stepper %}
{% step %}
### Back up your instance

In CIPP, go to **Application Settings** → **Manage Backups** and run a fresh backup. Download the JSON file before you start; it protects the instance configuration even though authentication material is not included.
{% endstep %}

{% step %}
### Confirm prerequisites

Use **PowerShell 7+** with the Azure PowerShell modules available, and sign in to Azure with access to the resource group that contains CIPP. The migration needs **Owner** on that resource group, or **Contributor + User Access Administrator**.

If Az is not installed yet, run:

```powershell
Install-Module Az -Scope CurrentUser -Repository PSGallery -Force
Import-Module Az
```

Sign in and select the right subscription:

```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId '<your-subscription-id>'
```
{% endstep %}

{% step %}
### Complete SSO migration first

Make sure the SSO setup in CIPP has reached **secrets_stored** or **complete** before cutting over. If the container app already exists and is using Easy Auth, the script will treat SSO as complete.
{% endstep %}

{% step %}
### Test the migration

From the repo root, run:

```powershell
.\deployment\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -TestOnly
```

If you use a custom domain, pass `-CippUrl 'cipp.contoso.com'` so the script can include the DNS records in its summary.

If the script says the resource group is not found even though it exists, pass the subscription explicitly:

```powershell
$subId = (Get-AzContext).Subscription.Id
.\deployment\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -SubscriptionId $subId -CippUrl 'cipp.contoso.com' -TestOnly
```

On first run you may see a PowerShell script trust prompt; choose **Run once** for this script if you trust your local repository.
{% endstep %}

{% step %}
### Run the live migration

If the test run looks good, rerun the same command without `-TestOnly`.

```powershell
$subId = (Get-AzContext).Subscription.Id
.\deployment\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -SubscriptionId $subId -CippUrl 'cipp.contoso.com'
```

If you see a `WebAppName ... does not match the existing Key Vault name` error and you did not set `-WebAppName`, check for any stray trailing characters or extra arguments in the command line. The script treats a third positional argument as `WebAppName`.

Successful runs end with `=== Migration Complete ===` and print the new hostname (for example `https://<name>.azurewebsites.net`) plus custom-domain DNS next steps.
{% endstep %}

{% step %}
### Update DNS

After the cutover, point any custom domain CNAME records at the new Azure Web App hostname the script prints, then add the domain in App Service. Remove any old `asuid.<domain>` TXT record first — those are no longer used and will block validation.

The migration script removes custom domains from Static Web App before deleting it, but it does **not** add them to the new App Service automatically.

To add the domain manually in Azure:

1. Open **App Service** → your CIPP app (for example `cippslebi`)
2. Go to **Custom domains**
3. Select **Add custom domain**
4. In the dialog, set:
   * **Domain provider**: **All other domain services** (not App Service Domain)
   * **TLS/SSL certificate**: **App Service Managed Certificate**
   * **TLS/SSL type**: **SNI SSL**
5. Enter your hostname (for example `partner.allixo.com`) and complete validation
6. Confirm the managed certificate is issued and bound for that hostname

You do **not** need to create or buy an **App Service Domain** for this. That panel is only for purchasing a domain through Azure. If your domain is already hosted elsewhere, just create the required DNS record at your DNS provider and then validate/bind the hostname in App Service.

If you see `ERR_CERT_COMMON_NAME_INVALID` and a certificate for `*.azurewebsites.net`, the custom domain has not finished certificate provisioning yet (or has not been bound correctly). Wait for the custom domain to show as secured in App Service, then retry. If needed, clear browser DNS/SSL cache after provisioning completes.
{% endstep %}

{% step %}
### Verify the cutover

Open the new CIPP URL, confirm sign-in works, then validate:

1. your custom domain resolves to the new `azurewebsites.net` hostname and is added in App Service
2. expected users and roles can access CIPP
3. backups, integrations, and custom roles are present and working
{% endstep %}
{% endstepper %}
