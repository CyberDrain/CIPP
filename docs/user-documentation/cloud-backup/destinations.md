# Destinations

A destination is the Azure storage account or S3 bucket where Cloud Backup writes backups. Destinations are shared by all policies, and only users with access to CIPP's application settings can manage them.

## Adding a destination

When you add a destination, choose how to set it up:

* **Create a storage account for me (recommended)**: CIPP creates and secures an Azure storage account for you. There are no credentials to enter.
* **Use an existing Azure storage account or S3 bucket**: you enter the details of storage you already have. S3 storage is always set up this way.

### Create a storage account for me

CIPP uses its managed identity to create:

* a new resource group (default `rg-cipp-cloudbackup`), which must not already exist,
* a storage account in the region and redundancy you choose, with HTTPS only (TLS 1.2 or later), no public access, account keys turned off and versioning turned on,
* a private container for the backups (default `cipp-backups`),
* the **Storage Blob Data Owner** and **Storage Account Contributor** roles for CIPP's own app on the storage account, so CIPP signs in without a secret.

The page shows each step as it runs. When it finishes, the destination is ready and you can add a backup policy.

This option is only available when CIPP's managed identity has the **Contributor** and **User Access Administrator** roles on at least one Azure subscription. If it doesn't, the option is greyed out with the reason, and you can set the destination up manually instead.

| Redundancy | What it means |
| --- | --- |
| Locally redundant (LRS) | Three copies in one datacenter. Lowest cost. |
| Zone redundant (ZRS) | Copies in three datacenters in the same region. Not offered in every region. |
| Geo-redundant (GRS) | Also copied to a second region far away. Highest cost. |

**Immutability** (optional) stops anyone, including CIPP and Azure administrators, from changing or deleting a backup until it is the chosen number of days old (1 to 3650).

* Keep the period no longer than the shortest retention of the policies that use this destination, or CIPP can't remove backups when their retention ends.
* CIPP leaves the immutability policy unlocked. To lock it permanently, do that in the Azure portal. A locked policy can't be shortened or removed.

If a step fails, CIPP shows which one and why. Choose **Set up manually instead** to switch to the manual form with the storage account, container, subscription and resource group already filled in, then add an app registration as described below.

Destinations created this way show **Created by CIPP** and the sign-in method **CIPP's own app** in their details. Editing one doesn't ask for an app registration or secret.

### Use an existing storage account or bucket

Choose a storage provider and fill in its details. Secrets (the client secret or secret access key) are stored in CIPP's Key Vault and are never shown again. When editing a destination, leave the secret as is to keep it, or type a new one to replace it.

When you save, CIPP tests the destination straight away and shows any check that failed.

## Versioning is required

Content backup keeps earlier versions of changed and deleted items as storage versions, so **versioning must be turned on** for the storage account or bucket. A policy can't be saved to a destination without it.

* Azure Blob Storage: turn on [blob versioning](https://learn.microsoft.com/azure/storage/blobs/versioning-enable) for the storage account.
* Amazon S3: turn on [bucket versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/manage-versioning-examples.html) for the bucket.
* S3-compatible storage: turn on versioning in your provider's portal (Wasabi, Backblaze B2 and MinIO all support it).

After turning it on, use **Test Connection** again. The **Versioning** column shows **On** once the destination is ready for content backup.

### Azure Blob Storage

CIPP signs in to the storage account with an app registration (service principal) you create in your own Entra tenant.

| Field | Description |
| --- | --- |
| Storage account name | The storage account's name. |
| Container | The blob container backups are written to. Create it before adding the destination. |
| Subscription ID and Resource group | Where the storage account lives. CIPP needs these to manage the retention rule. |
| Directory (tenant) ID | The Entra tenant that owns the app registration. |
| Application (client) ID and Client secret | The app registration's credentials. |

Give the app registration these roles on the storage account:

* **Storage Blob Data Owner**, to write and read backups and to remove earlier versions once they are past the policy's retention. CIPP removes them itself because Azure's lifecycle rules would remove them too early.
* **Storage Account Contributor**, to manage the lifecycle rule and to check that versioning is on.

### Amazon S3 and S3-compatible storage

| Field | Description |
| --- | --- |
| Endpoint URL | Leave blank for Amazon S3. For S3-compatible storage (for example Wasabi, Backblaze B2 or MinIO), enter the provider's endpoint. |
| Region | The bucket's region. Leave blank to use us-east-1. |
| Bucket | The bucket backups are written to. Create it before adding the destination. |
| Access key ID and Secret access key | The credentials CIPP uses. |
| Use path-style addresses | Turn on if your provider doesn't support the bucket name in the host name. |

The access key needs these permissions on the bucket: `s3:PutObject`, `s3:GetObject`, `s3:GetObjectVersion`, `s3:DeleteObject`, `s3:AbortMultipartUpload`, `s3:ListBucket`, `s3:ListBucketVersions`, `s3:GetLifecycleConfiguration`, `s3:PutLifecycleConfiguration` and `s3:GetBucketVersioning`.

## Table Actions

| Action | Description |
| --- | --- |
| Test Connection | Writes, reads and deletes a small test file, checks CIPP can read the retention rules, checks that versioning is on and, for Azure, that CIPP can remove expired versions. The result is shown in the destination's details. |
| Edit Destination | Changes the destination's details or replaces its secret. The provider can't be changed. |
| Delete Destination | Removes the destination and its stored secret. Backups already stored are not deleted. A destination used by a policy can't be deleted. |

{% include "../../../.gitbook/includes/feature-request.md" %}
