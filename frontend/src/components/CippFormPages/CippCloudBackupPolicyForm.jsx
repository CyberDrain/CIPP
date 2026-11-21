import { Alert, Button, Typography } from '@mui/material'
import { Grid } from '@mui/system'
import Link from 'next/link'
import { useEffect } from 'react'
import { useWatch } from 'react-hook-form'
import CippFormComponent from '../CippComponents/CippFormComponent'
import { CippFormTenantSelector } from '../CippComponents/CippFormTenantSelector'
import { ApiGetCall } from '../../api/ApiCall'
import {
  CLOUD_BACKUP_WORKLOADS,
  cloudBackupContentReady,
  cloudBackupOptionValue,
  cloudBackupSchedulesFor,
} from '../../utils/cloud-backup'

const singleTenantOf = (tenants) => {
  if (!Array.isArray(tenants) || tenants.length !== 1) return null
  const [tenant] = tenants
  if (tenant?.type === 'Group' || !tenant?.value) return null
  if (tenant.value === 'AllTenants') return null
  return tenant.value
}

const graphPicker = (tenant, endpoint, select, labelField) => ({
  url: '/api/ListGraphRequest',
  tenantFilter: tenant,
  dataKey: 'Results',
  labelField,
  valueField: 'id',
  queryKey: `ListGraphRequest-cloudBackup-${endpoint}-${tenant}`,
  data: {
    Endpoint: endpoint,
    manualPagination: true,
    $select: select,
    $count: true,
    $orderby: 'displayName',
    $top: 999,
  },
})

const isSiteUrl = (value) => {
  const url = String(cloudBackupOptionValue(value) ?? '').trim()
  return /^https:\/\/[^/\s]+\.sharepoint\.(com|us|cn|de)(\/\S*)?$/i.test(url)
}

export const CippCloudBackupPolicyForm = ({ formControl }) => {
  const destinations = ApiGetCall({
    url: '/api/ListCloudBackupDestinations',
    queryKey: 'ListCloudBackupDestinations-picker',
  })
  const destinationRows = Array.isArray(destinations.data)
    ? destinations.data
    : []
  const destinationOptions = destinationRows.map((destination) => ({
    label: destination.Location
      ? `${destination.Name} (${destination.Location})`
      : destination.Name,
    value: destination.Id,
  }))
  const noDestinations = destinations.isSuccess && destinationRows.length === 0

  const selectedDestination = useWatch({
    control: formControl.control,
    name: 'DestinationId',
  })
  const destinationId = cloudBackupOptionValue(selectedDestination)
  const destinationRow = destinationRows.find(
    (destination) => destination.Id === destinationId
  )
  const contentReady = destinationRow
    ? cloudBackupContentReady(destinationRow.LastTest)
    : undefined

  const workloads = useWatch({
    control: formControl.control,
    name: 'Workloads',
  })
  const workloadKey = CLOUD_BACKUP_WORKLOADS.map(
    ({ value }) => !!workloads?.[value]
  ).join()
  useEffect(() => {
    formControl.trigger(`Workloads.${CLOUD_BACKUP_WORKLOADS[0].value}`)
  }, [workloadKey, formControl])
  const tenants = useWatch({ control: formControl.control, name: 'Tenants' })
  const pickerTenant = singleTenantOf(tenants)

  return (
    <Grid container spacing={2}>
      <CippFormComponent type="hidden" name="Id" formControl={formControl} />
      <Grid size={{ md: 8, xs: 12 }}>
        <CippFormComponent
          type="textField"
          label="Policy name"
          name="Name"
          required
          formControl={formControl}
          validators={{ required: 'Give the policy a name' }}
          fullWidth
        />
      </Grid>
      <Grid size={{ md: 4, xs: 12 }}>
        <CippFormComponent
          type="switch"
          label="Enabled"
          name="Enabled"
          formControl={formControl}
          helperText="Disabled policies keep their settings but don't run on schedule."
        />
      </Grid>
      <Grid size={{ xs: 12 }}>
        {noDestinations ? (
          <Alert
            severity="warning"
            action={
              <Button
                component={Link}
                href="/cloud-backup/destinations/add"
                color="inherit"
                size="small"
              >
                Add destination
              </Button>
            }
          >
            Add a destination first. A policy needs somewhere to store its
            backups.
          </Alert>
        ) : (
          <CippFormComponent
            type="select"
            label="Destination"
            name="DestinationId"
            required
            formControl={formControl}
            options={destinationOptions}
            isFetching={destinations.isFetching}
            validators={{ required: 'Choose where backups are stored' }}
          />
        )}
      </Grid>
      {contentReady === false && (
        <Grid size={{ xs: 12 }}>
          <Alert severity="warning">
            Versioning is off on this destination. Turn on blob versioning
            (Azure) or bucket versioning (S3), then test the destination again.
            The policy can't be saved until versioning is on.
          </Alert>
        </Grid>
      )}
      {destinationRow && contentReady === null && (
        <Grid size={{ xs: 12 }}>
          <Alert severity="info">
            CIPP hasn't confirmed that versioning is on for this destination.
            Use Test Connection on the Destinations page to check it. The policy
            can only be saved when versioning is on.
          </Alert>
        </Grid>
      )}
      <Grid size={{ xs: 12 }}>
        <CippFormTenantSelector
          formControl={formControl}
          name="Tenants"
          label="Tenants"
          allTenants={true}
          includeGroups={true}
          required={true}
        />
      </Grid>

      <Grid size={{ xs: 12 }}>
        <Typography variant="h6">What to back up</Typography>
        <Typography variant="body2" color="text.secondary">
          Everything in each service is backed up, including users and sites
          added later. Use the exclusions below to leave some out.
        </Typography>
      </Grid>
      {CLOUD_BACKUP_WORKLOADS.map((workload) => (
        <Grid container size={{ xs: 12 }} spacing={2} key={workload.value}>
          <Grid size={{ md: 6, xs: 12 }}>
            <CippFormComponent
              type="switch"
              label={workload.label}
              name={`Workloads.${workload.value}`}
              formControl={formControl}
              helperText={workload.description}
              validators={
                workload.value === CLOUD_BACKUP_WORKLOADS[0].value
                  ? {
                      validate: (_, values) =>
                        CLOUD_BACKUP_WORKLOADS.some(
                          ({ value }) => values?.Workloads?.[value]
                        ) || 'Choose at least one service to back up',
                    }
                  : undefined
              }
            />
          </Grid>
          {workloads?.[workload.value] && (
            <Grid size={{ md: 6, xs: 12 }}>
              <CippFormComponent
                type="select"
                label={`${workload.label} schedule`}
                name={`Schedules.${workload.value}`}
                required
                options={cloudBackupSchedulesFor(workload.value)}
                formControl={formControl}
                validators={{ required: 'Choose how often to back up' }}
              />
            </Grid>
          )}
        </Grid>
      ))}

      <Grid size={{ xs: 12 }}>
        <Typography variant="h6">Exclusions</Typography>
        <Typography variant="body2" color="text.secondary">
          {pickerTenant
            ? 'Pick users and groups from the selected tenant, or type a user principal name or object ID.'
            : 'Type user principal names or object IDs. To pick from a list, select a single tenant above.'}
        </Typography>
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          key={`users-${pickerTenant ?? 'typed'}`}
          type="autoComplete"
          label="Excluded users"
          name="ExcludedUsers"
          multiple
          creatable={true}
          options={[]}
          api={
            pickerTenant
              ? graphPicker(
                  pickerTenant,
                  'users',
                  'id,userPrincipalName,displayName',
                  (option) =>
                    `${option.displayName} (${option.userPrincipalName})`
                )
              : undefined
          }
          formControl={formControl}
          helperText="Their mailbox, OneDrive and chats are not backed up."
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          key={`groups-${pickerTenant ?? 'typed'}`}
          type="autoComplete"
          label="Excluded groups"
          name="ExcludedGroups"
          multiple
          creatable={!pickerTenant}
          options={[]}
          api={
            pickerTenant
              ? graphPicker(
                  pickerTenant,
                  'groups',
                  'id,displayName,mail',
                  (option) => option.displayName
                )
              : undefined
          }
          formControl={formControl}
          helperText={
            pickerTenant
              ? 'Members of these groups are left out.'
              : 'Members of these groups are left out. Enter each group’s object ID.'
          }
        />
      </Grid>
      <Grid size={{ xs: 12 }}>
        <CippFormComponent
          type="autoComplete"
          label="Excluded sites"
          name="ExcludedSites"
          multiple
          creatable={true}
          options={[]}
          formControl={formControl}
          validators={{
            validate: (value) =>
              !Array.isArray(value) ||
              value.every(isSiteUrl) ||
              'Enter full site addresses, for example https://contoso.sharepoint.com/sites/archive',
          }}
          helperText="Full site addresses, for example https://contoso.sharepoint.com/sites/archive. Type an address and press Enter."
        />
      </Grid>

      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="number"
          label="Keep deleted and changed items for (days)"
          name="RetentionDays"
          formControl={formControl}
          validators={{
            required: 'Enter how many days to keep earlier versions',
            min: {
              value: 7,
              message: 'Keep earlier versions for at least 7 days',
            },
            max: {
              value: 3650,
              message: 'Keep earlier versions for at most 3650 days (10 years)',
            },
          }}
          helperText="The latest copy of every item is always kept. Earlier versions and items deleted in Microsoft 365 are removed from the destination after this many days."
          fullWidth
        />
      </Grid>
      <Grid size={{ md: 6, xs: 12 }}>
        <CippFormComponent
          type="switch"
          label="Encrypt backups"
          name="Encryption"
          formControl={formControl}
          helperText="Backups are encrypted before upload with a key kept in CIPP's Key Vault. If that key is lost, encrypted backups can't be read."
        />
      </Grid>
      <Grid size={{ xs: 12 }}>
        <Alert severity="info">
          When you save, CIPP gives its own app the Microsoft Graph permissions
          these services need in every tenant of the policy. The result for each
          tenant is shown in the policy's details.
        </Alert>
      </Grid>
    </Grid>
  )
}

export default CippCloudBackupPolicyForm
