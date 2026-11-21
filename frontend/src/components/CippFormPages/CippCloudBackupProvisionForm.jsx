import { useEffect, useRef } from 'react'
import Link from 'next/link'
import {
  Alert,
  Box,
  Button,
  CircularProgress,
  Divider,
  List,
  ListItem,
  ListItemText,
  Stack,
  Typography,
} from '@mui/material'
import { Grid } from '@mui/system'
import { useWatch } from 'react-hook-form'
import { useQueryClient } from '@tanstack/react-query'
import CippFormComponent from '../CippComponents/CippFormComponent'
import { CippFormCondition } from '../CippComponents/CippFormCondition'
import { CippPropertyListCard } from '../CippCards/CippPropertyListCard'
import { ApiGetCall } from '../../api/ApiCall'
import { CippIcons } from '../../utils/icon-registry'
import { getCippFormatting } from '../../utils/get-cipp-formatting'
import {
  CLOUD_BACKUP_REDUNDANCY,
  cloudBackupOptionValue,
  cloudBackupProvisionJob,
  cloudBackupProvisionRunning,
  cloudBackupRegionOptions,
} from '../../utils/cloud-backup'

const HARDENED_SETTINGS = [
  'HTTPS only, with TLS 1.2 or later',
  'No anonymous (public) access to backups',
  'Account keys turned off: CIPP signs in with its own app',
  'Versioning turned on, as content backup needs it',
  'A private container for the backups',
  'CIPP’s own app gets Storage Blob Data Owner and Storage Account Contributor on the storage account',
]

const RESOURCE_GROUP_PATTERN = /^[-\w.()]{0,89}[-\w()]$/
const CONTAINER_PATTERN = /^(?!.*--)[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/

export const CippCloudBackupProvisionForm = ({ formControl, options }) => {
  const subscription = cloudBackupOptionValue(
    useWatch({ control: formControl.control, name: 'SubscriptionId' })
  )
  const previousSubscription = useRef(subscription)

  const regions = ApiGetCall({
    url: '/api/ListCloudBackupProvisioningOptions',
    data: { SubscriptionId: subscription },
    queryKey: `ListCloudBackupProvisioningOptions-regions-${subscription}`,
    waiting: Boolean(subscription),
  })

  useEffect(() => {
    if (previousSubscription.current === subscription) return
    previousSubscription.current = subscription
    formControl.setValue('Region', null)
  }, [subscription, formControl])

  const subscriptions = (options?.Subscriptions ?? []).map((item) => ({
    label: item.name ?? item.id,
    value: item.id,
  }))

  return (
    <Grid container spacing={2}>
      {typeof options?.ManagedIdentity === 'string' &&
        options.ManagedIdentity && (
          <Grid size={{ xs: 12 }}>
            <Typography variant="body2" color="text.secondary">
              CIPP creates the storage with its managed identity (
              {options.ManagedIdentity}).
            </Typography>
          </Grid>
        )}
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="textField"
          label="Destination name"
          name="Name"
          required
          formControl={formControl}
          validators={{ required: 'Destination name is required' }}
          fullWidth
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="select"
          label="Subscription"
          name="SubscriptionId"
          required
          options={subscriptions}
          formControl={formControl}
          validators={{ required: 'Choose a subscription' }}
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="textField"
          label="New resource group name"
          name="ResourceGroup"
          required
          formControl={formControl}
          validators={{
            required: 'Resource group name is required',
            pattern: {
              value: RESOURCE_GROUP_PATTERN,
              message:
                'Use up to 90 letters, numbers, hyphens, underscores, periods or brackets, not ending with a period.',
            },
          }}
          helperText="CIPP creates this resource group. Use a name that doesn't exist in the subscription yet."
          fullWidth
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }} key={`region-${subscription ?? 'none'}`}>
        <CippFormComponent
          type="select"
          label="Region"
          name="Region"
          required
          disabled={!subscription}
          isFetching={regions.isFetching}
          options={subscription ? cloudBackupRegionOptions(regions.data) : []}
          formControl={formControl}
          validators={{ required: 'Choose a region' }}
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="textField"
          label="Container name"
          name="Container"
          required
          formControl={formControl}
          validators={{
            required: 'Container name is required',
            pattern: {
              value: CONTAINER_PATTERN,
              message:
                'Use 3 to 63 lowercase letters, numbers and single hyphens, starting and ending with a letter or number.',
            },
          }}
          fullWidth
        />
      </Grid>
      <Grid size={{ xs: 12 }}>
        <CippFormComponent
          type="radio"
          label="Redundancy"
          name="Redundancy"
          options={CLOUD_BACKUP_REDUNDANCY}
          formControl={formControl}
          validators={{ required: 'Choose a redundancy' }}
        />
      </Grid>
      <Grid size={{ xs: 12 }}>
        <CippFormComponent
          type="switch"
          label="Make backups immutable"
          name="Immutability"
          formControl={formControl}
          helperText="Stored backups can't be changed or deleted until they are this many days old."
        />
      </Grid>
      <CippFormCondition
        formControl={formControl}
        field="Immutability"
        compareType="is"
        compareValue={true}
        clearOnHide={false}
      >
        <Grid size={{ md: 6, xs: 12 }}>
          <CippFormComponent
            type="number"
            label="Immutable for (days)"
            name="ImmutabilityDays"
            required
            formControl={formControl}
            validators={{
              required: 'Enter the number of days',
              min: { value: 1, message: 'Use at least 1 day' },
              max: { value: 3650, message: 'Use at most 3650 days' },
              validate: (value) =>
                Number.isInteger(Number(value)) || 'Use a whole number of days',
            }}
            fullWidth
          />
        </Grid>
        <Grid size={{ xs: 12 }}>
          <Alert severity="warning">
            <Typography variant="body2">
              Backups can't be deleted before this period ends, not even by CIPP
              or an Azure administrator. Keep it no longer than the shortest
              retention of the policies that use this destination, or CIPP can't
              remove backups when their retention ends. CIPP leaves the
              immutability policy unlocked; to lock it permanently, do that in
              the Azure portal.
            </Typography>
          </Alert>
        </Grid>
      </CippFormCondition>
      <Grid size={{ xs: 12 }}>
        <Divider />
      </Grid>
      <Grid size={{ xs: 12 }}>
        <Typography variant="subtitle2" gutterBottom>
          Security settings CIPP applies
        </Typography>
        <List dense disablePadding>
          {HARDENED_SETTINGS.map((setting) => (
            <ListItem key={setting} disableGutters>
              <ListItemText primary={setting} />
            </ListItem>
          ))}
        </List>
      </Grid>
    </Grid>
  )
}

export const CippCloudBackupProvisionProgress = ({
  jobId,
  onManual,
  onRetry,
}) => {
  const queryClient = useQueryClient()
  const job = ApiGetCall({
    url: '/api/ListCloudBackupJobs',
    data: { Id: jobId },
    queryKey: `ListCloudBackupJobs-provision-${jobId}`,
    waiting: Boolean(jobId),
    staleTime: 0,
    refetchOnWindowFocus: false,
    refetchInterval: (query) =>
      cloudBackupProvisionRunning(cloudBackupProvisionJob(query?.state?.data))
        ? 3000
        : false,
  })
  const current = cloudBackupProvisionJob(job.data)
  const status = current?.Status
  const steps = Array.isArray(current?.Steps) ? current.Steps : []
  const result = current?.Result ?? {}
  const failedStep = steps.find((step) => step.Status === 'Failed')

  useEffect(() => {
    if (status !== 'Completed') return
    queryClient.invalidateQueries({
      predicate: (query) =>
        ['ListCloudBackupDestinations', 'ListCloudBackupOverview'].some(
          (prefix) => String(query.queryKey?.[0] ?? '').startsWith(prefix)
        ),
    })
  }, [status, queryClient])

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} sx={{ alignItems: 'center' }}>
        {cloudBackupProvisionRunning(current) && <CircularProgress size={20} />}
        <Typography variant="h6">
          {status === 'Completed'
            ? 'Your storage account is ready'
            : status === 'Failed'
              ? 'CIPP couldn’t finish creating the storage'
              : 'Creating your storage account'}
        </Typography>
        {status && getCippFormatting(status, 'CloudBackupStepStatus')}
      </Stack>

      {steps.length === 0 ? (
        <Typography variant="body2" color="text.secondary">
          Waiting for CIPP to start. This page updates on its own.
        </Typography>
      ) : (
        <List dense disablePadding>
          {steps.map((step, index) => (
            <ListItem
              key={`${step.Name}-${index}`}
              disableGutters
              secondaryAction={
                step.Status
                  ? getCippFormatting(step.Status, 'CloudBackupStepStatus')
                  : null
              }
            >
              <ListItemText primary={step.Name} secondary={step.Message} />
            </ListItem>
          ))}
        </List>
      )}

      {status === 'Completed' && (
        <>
          {result.TestPassed === false && (
            <Alert severity="warning">
              The storage is ready, but CIPP&apos;s access can take up to 10
              minutes to apply. Test the destination again from Destinations
              before adding a policy.
            </Alert>
          )}
          <CippPropertyListCard
            cardSx={{ p: 0 }}
            title="What CIPP created"
            showDivider={false}
            propertyItems={[
              { label: 'Storage account', value: result.StorageAccount },
              { label: 'Container', value: result.Container },
              { label: 'Resource group', value: result.ResourceGroup },
              { label: 'Region', value: result.Region },
            ]}
          />
          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
            <Button
              variant="contained"
              component={Link}
              href="/cloud-backup/destinations"
              startIcon={<CippIcons.Storage />}
            >
              View destination
            </Button>
            <Button
              variant="outlined"
              component={Link}
              href="/cloud-backup/policies/add"
              startIcon={<CippIcons.AddBox />}
            >
              Add a backup policy
            </Button>
          </Stack>
        </>
      )}

      {status === 'Failed' && (
        <>
          <Alert severity="error">
            {failedStep ? (
              <>
                <strong>{failedStep.Name}</strong> failed
                {failedStep.Message ? `: ${failedStep.Message}` : '.'}
              </>
            ) : (
              current?.Error || 'Something went wrong.'
            )}
            {failedStep &&
              current?.Error &&
              current.Error !== failedStep.Message && (
                <Box sx={{ mt: 1 }}>{current.Error}</Box>
              )}
          </Alert>
          <Typography variant="body2">
            You can set the destination up yourself instead. CIPP fills in what
            it already knows, and you add the app registration that signs in to
            the storage account.
          </Typography>
          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
            <Button
              variant="contained"
              onClick={() => onManual(result)}
              startIcon={<CippIcons.Edit />}
            >
              Set up manually instead
            </Button>
            <Button
              variant="outlined"
              onClick={onRetry}
              startIcon={<CippIcons.Undo />}
            >
              Change the details and try again
            </Button>
          </Stack>
        </>
      )}
    </Stack>
  )
}

export default CippCloudBackupProvisionForm
