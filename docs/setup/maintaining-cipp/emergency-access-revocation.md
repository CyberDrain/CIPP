# Revoking CIPP Access in an Emergency

Use this page when you suspect CIPP, the CIPP service account, or the CIPP-SAM application has been compromised and you need to cut CIPP off from your client tenants immediately. All actions are performed in your partner tenant. Nothing needs to be changed in any client tenant.

{% hint style="danger" %}
These actions stop CIPP from managing every client tenant at once, including scheduled standards, alerts, and automation. Use them for incident response only.

They do not remove access an attacker may already have established inside client tenants. See [What These Actions Do Not Cover](#what-these-actions-do-not-cover).
{% endhint %}

## Choosing an Action

| Action                                                                                          | What it stops                                       | Recovery                                                  |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| [Remove the service account from the GDAP groups](#remove-the-service-account-from-the-gdap-groups) | Delegated access to every client tenant             | Add the service account back to the groups                |
| [Revoke the CIPP-SAM secrets and certificates](#revoke-the-cipp-sam-secrets-and-certificates)  | CIPP authenticating as the CIPP-SAM application     | Issue new credentials and give them to CIPP               |
| [Delete the CIPP-SAM application](#delete-the-cipp-sam-application)                             | The CIPP-SAM application itself                     | Create a new application registration and re-onboard all tenants |

The first two actions are fully recoverable without touching your client tenants. They can be combined, and the order does not matter.

## Remove the Service Account From the GDAP Groups

Client tenants grant access to the security groups in your partner tenant, not to CIPP directly. Removing the CIPP service account from those groups ends its delegated access to every client tenant.

{% stepper %}
{% step %}

#### Open the groups

Sign in to the Microsoft Entra admin center of your partner tenant and go to **Groups** > **All groups**. Groups created by CIPP are named `M365 GDAP <RoleName>`, with an optional ` - <suffix>`.

{% hint style="info" %}
If you onboarded your tenants without CIPP, your GDAP groups have different names. Use the groups assigned to your GDAP relationships.
{% endhint %}
{% endstep %}

{% step %}

#### Remove the service account

Open each group, select **Members**, and remove the CIPP service account. CIPP maps one role to one security group by default, so expect to repeat this for every `M365 GDAP` group the account belongs to.
{% endstep %}

{% step %}

#### Check the result

Open the CIPP service account in Microsoft Entra and review **Groups**. The account should no longer be a member of any GDAP group.
{% endstep %}
{% endstepper %}

To recover, add the service account back to the same groups. The groups and the roles they carry are listed under [mappings.md](../../user-documentation/tenant/gdap-management/role-templates/mappings/README.md "mention").

## Revoke the CIPP-SAM Secrets and Certificates

CIPP authenticates against Microsoft Graph, Exchange Online, and the Partner Center APIs with the CIPP-SAM application registration, using either a certificate or a client secret. Removing every credential from the application stops CIPP from authenticating as the application.

{% stepper %}
{% step %}

#### Open the application

In the Microsoft Entra admin center of your partner tenant, go to **App registrations** > **All applications** and open **CIPP-SAM**.
{% endstep %}

{% step %}

#### Delete the credentials

Select **Certificates & secrets**. Delete every entry on both the **Certificates** and **Client secrets** tabs.
{% endstep %}
{% endstepper %}

To recover, create a new client secret on the application and give it to CIPP through the Setup Wizard. See [sam-setup-wizard.md](../../user-documentation/cipp/sam-setup-wizard.md "mention") for the **Manually enter credentials** and **Use certificate authentication** options. CIPP cannot re-register its own certificate while the application has no credentials, so start with a client secret.

## Delete the CIPP-SAM Application

Deleting the application registration is the hardest stop. It removes the application CIPP authenticates with.

{% hint style="danger" %}
Recovery after deleting the application requires re-onboarding all tenants into CIPP. If you only need to stop CIPP temporarily, use the two actions above instead.
{% endhint %}

{% stepper %}
{% step %}

#### Delete the application registration

In the Microsoft Entra admin center of your partner tenant, go to **App registrations** > **All applications**, open **CIPP-SAM**, and select **Delete**.
{% endstep %}
{% endstepper %}

To recover, run the **Create a new application registration for me and connect to my tenants** option in the Setup Wizard, then add your tenants again through [gdap-invite-wizard.md](../installation/gdap-invite-wizard.md "mention").

Entra keeps a deleted application registration for 30 days. You can restore it from **Deleted applications** in **App registrations**, which avoids re-onboarding. Remove any credentials still on the restored application before you reconnect CIPP.


## What These Actions Do Not Cover

Cutting CIPP off from your client tenants does not remove anything an attacker has already done inside them. Review each affected client tenant for indicators of compromise and persistent access, for example:

* New or modified users, groups, and role assignments.
* Newly registered applications and consented enterprise applications.
* Mailbox rules and forwarding.
* Changes to Conditional Access policies and authentication methods.

CIPP features that review these items, such as [case.md](../../user-documentation/identity/administration/bec/case.md "mention") and [audit-logs.md](../../user-documentation/tenant/administration/audit-logs/README.md "mention"), are unavailable while CIPP has no access. Use the Microsoft Entra, Microsoft Defender, and Microsoft Purview portals of each client tenant until access is restored.

## Related Documentation

{% content-ref url="../installation/creating-the-cipp-service-account-gdap-ready.md" %}
[creating-the-cipp-service-account-gdap-ready.md](../installation/creating-the-cipp-service-account-gdap-ready.md)
{% endcontent-ref %}

{% content-ref url="../../user-documentation/cipp/sam-setup-wizard.md" %}
[sam-setup-wizard.md](../../user-documentation/cipp/sam-setup-wizard.md)
{% endcontent-ref %}

{% content-ref url="../installation/gdap-invite-wizard.md" %}
[gdap-invite-wizard.md](../installation/gdap-invite-wizard.md)
{% endcontent-ref %}
