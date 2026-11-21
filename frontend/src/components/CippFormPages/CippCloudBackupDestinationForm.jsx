import { Alert, Link, Typography } from '@mui/material'
import { Grid } from '@mui/system'
import CippFormComponent from '../CippComponents/CippFormComponent'
import { CippFormCondition } from '../CippComponents/CippFormCondition'
import { CLOUD_BACKUP_PROVIDERS } from '../../utils/cloud-backup'

const textField = (formControl, name, label, { required, helperText } = {}) => (
  <Grid size={{ md: 6, xs: 12 }} key={name}>
    <CippFormComponent
      type="textField"
      label={label}
      name={name}
      required={required}
      formControl={formControl}
      validators={required ? { required: `${label} is required` } : undefined}
      helperText={helperText}
      fullWidth
    />
  </Grid>
)

const secretField = (formControl, name, label, isEdit) => (
  <Grid size={{ md: 6, xs: 12 }}>
    <CippFormComponent
      type="password"
      label={label}
      name={name}
      required={!isEdit}
      formControl={formControl}
      validators={isEdit ? undefined : { required: `${label} is required` }}
      helperText={
        isEdit
          ? 'Leave as is to keep the stored secret, or type a new one to replace it.'
          : 'Stored in CIPP’s Key Vault, never shown again.'
      }
      fullWidth
    />
  </Grid>
)

export const CippCloudBackupDestinationForm = ({
  formControl,
  isEdit = false,
}) => (
  <Grid container spacing={2}>
    <CippFormComponent type="hidden" name="Id" formControl={formControl} />
    <CippFormComponent
      type="hidden"
      name="AuthMode"
      formControl={formControl}
    />
    {textField(formControl, 'Name', 'Destination name', { required: true })}
    <Grid size={{ md: 6, xs: 12 }}>
      <CippFormComponent
        type="select"
        label="Storage provider"
        name="Provider"
        required
        disabled={isEdit}
        options={CLOUD_BACKUP_PROVIDERS}
        formControl={formControl}
        validators={{ required: 'Choose a storage provider' }}
      />
    </Grid>

    <Grid size={{ xs: 12 }}>
      <Alert severity="warning">
        <Typography variant="body2">
          Content backup needs <strong>versioning</strong> turned on for the
          storage account or bucket. CIPP keeps earlier versions of changed and
          deleted items as storage versions, and won't save a policy to a
          destination without it. See how to turn it on for{' '}
          <Link
            href="https://learn.microsoft.com/azure/storage/blobs/versioning-enable"
            target="_blank"
            rel="noopener noreferrer"
          >
            Azure Blob Storage
          </Link>{' '}
          and{' '}
          <Link
            href="https://docs.aws.amazon.com/AmazonS3/latest/userguide/manage-versioning-examples.html"
            target="_blank"
            rel="noopener noreferrer"
          >
            Amazon S3
          </Link>
          . S3-compatible providers have their own setting for it.
        </Typography>
      </Alert>
    </Grid>

    <CippFormCondition
      formControl={formControl}
      field="Provider"
      compareType="is"
      compareValue="AzureBlob"
    >
      <CippFormCondition
        formControl={formControl}
        field="AuthMode"
        compareType="is"
        compareValue="CippApp"
        clearOnHide={false}
      >
        <Grid size={{ xs: 12 }}>
          <Alert severity="info">
            <Typography variant="body2">
              CIPP created this storage account and signs in to it with its own
              app, so there is no app registration or secret to enter. CIPP's
              app already has the roles it needs on the storage account.
            </Typography>
          </Alert>
        </Grid>
      </CippFormCondition>
      <CippFormCondition
        formControl={formControl}
        field="AuthMode"
        compareType="isNot"
        compareValue="CippApp"
        clearOnHide={false}
      >
        <Grid size={{ xs: 12 }}>
          <Alert severity="info">
            <Typography variant="body2">
              CIPP signs in with an app registration (service principal). Give
              it <strong>Storage Blob Data Owner</strong> and{' '}
              <strong>Storage Account Contributor</strong> on the storage
              account. The first lets CIPP write and read backups and remove
              earlier versions once they are past the policy's retention,
              because Azure's own lifecycle rules would remove them too early.
              The second lets it manage the lifecycle rule and check that
              versioning is on.
            </Typography>
          </Alert>
        </Grid>
      </CippFormCondition>
      {textField(formControl, 'StorageAccount', 'Storage account name', {
        required: true,
      })}
      {textField(formControl, 'Container', 'Container', { required: true })}
      {textField(formControl, 'SubscriptionId', 'Subscription ID', {
        required: true,
      })}
      {textField(formControl, 'ResourceGroup', 'Resource group', {
        required: true,
      })}
      <CippFormCondition
        formControl={formControl}
        field="AuthMode"
        compareType="isNot"
        compareValue="CippApp"
      >
        {textField(formControl, 'AzureTenantId', 'Directory (tenant) ID', {
          required: true,
          helperText: 'The Entra tenant that owns the app registration.',
        })}
        {textField(formControl, 'ClientId', 'Application (client) ID', {
          required: true,
        })}
        {secretField(formControl, 'ClientSecret', 'Client secret', isEdit)}
      </CippFormCondition>
    </CippFormCondition>

    <CippFormCondition
      formControl={formControl}
      field="Provider"
      compareType="is"
      compareValue="S3"
    >
      <Grid size={{ xs: 12 }}>
        <Alert severity="info">
          <Typography variant="body2">
            The access key needs these permissions on the bucket:{' '}
            <strong>s3:PutObject</strong>, <strong>s3:GetObject</strong>,{' '}
            <strong>s3:GetObjectVersion</strong>,{' '}
            <strong>s3:DeleteObject</strong>,{' '}
            <strong>s3:AbortMultipartUpload</strong>,{' '}
            <strong>s3:ListBucket</strong>,{' '}
            <strong>s3:ListBucketVersions</strong>,{' '}
            <strong>s3:GetLifecycleConfiguration</strong>,{' '}
            <strong>s3:PutLifecycleConfiguration</strong> and{' '}
            <strong>s3:GetBucketVersioning</strong>.
          </Typography>
        </Alert>
      </Grid>
      {textField(formControl, 'Endpoint', 'Endpoint URL', {
        helperText:
          'Leave blank for Amazon S3. For S3-compatible storage, enter the provider’s endpoint, for example https://s3.eu-central-1.wasabisys.com.',
      })}
      {textField(formControl, 'Region', 'Region', {
        helperText: 'For example us-east-1. Leave blank to use us-east-1.',
      })}
      {textField(formControl, 'Bucket', 'Bucket', { required: true })}
      {textField(formControl, 'AccessKeyId', 'Access key ID', {
        required: true,
      })}
      {secretField(formControl, 'SecretAccessKey', 'Secret access key', isEdit)}
      <CippFormCondition
        formControl={formControl}
        field="Endpoint"
        compareType="isOneOf"
        compareValue={[undefined, null, '']}
        clearOnHide={false}
      >
        <Grid size={{ md: 6, xs: 12 }}>
          <CippFormComponent
            type="switch"
            label="Use path-style addresses"
            name="ForcePathStyle"
            formControl={formControl}
            helperText="Amazon S3 only. Turn on if the bucket name contains dots or capital letters. Custom endpoints always use path-style addresses."
          />
        </Grid>
      </CippFormCondition>
    </CippFormCondition>
  </Grid>
)

export default CippCloudBackupDestinationForm
