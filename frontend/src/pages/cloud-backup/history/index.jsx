import { Stack, Typography } from '@mui/material'
import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippPropertyListCard } from '../../../components/CippCards/CippPropertyListCard'
import { CippCloudBackupJobStatus } from '../../../components/CippComponents/CippCloudBackupJobStatus'
import {
  CippCloudBackupExportDownload,
  CippCloudBackupJobResults,
} from '../../../components/CippComponents/CippCloudBackupJobResults'
import { useCloudBackupJob } from '../../../hooks/use-cloud-backup-job'
import { usePermissions } from '../../../hooks/use-permissions'
import { useSettings } from '../../../hooks/use-settings'
import { getCippFormatting } from '../../../utils/get-cipp-formatting'
import {
  CLOUD_BACKUP_CONFLICT_ACTIONS,
  CLOUD_BACKUP_HISTORY_JOB_TYPES,
  CLOUD_BACKUP_RESTORE_LOCATIONS,
  CLOUD_BACKUP_RESTORE_PERMISSION,
  cloudBackupJobSummary,
  cloudBackupJobTypeLabel,
  cloudBackupWorkloadLabel,
  parseCloudBackupObject,
} from '../../../utils/cloud-backup'

const optionLabel = (options, value) =>
  options.find((option) => option.value === value)?.label ??
  value ??
  'Not recorded'

const toCloudBackupJobRow = (row) => {
  const parameters = parseCloudBackupObject(row.Parameters)
  const target = parseCloudBackupObject(row.Target)
  const owner =
    row.SourceOwner ??
    row.OwnerDisplayName ??
    row.OwnerName ??
    parameters.OwnerId ??
    row.OwnerId
  const targetName =
    row.Type === 'Export'
      ? 'Download'
      : (row.TargetOwner ??
        target.UserPrincipalName ??
        parameters.TargetOwnerId ??
        owner)
  return {
    ...row,
    CloudBackupJobType: cloudBackupJobTypeLabel(row.Type),
    CloudBackupStatus: row.Status,
    CloudBackupWorkload: cloudBackupWorkloadLabel(
      row.Workload ?? parameters.Workload
    ),
    CloudBackupOwner: owner,
    CloudBackupTarget: targetName,
    CloudBackupRequestedBy: row.RequestedBy,
    CloudBackupCreatedAt: row.CreatedAt,
    CloudBackupCompletedAt: row.CompletedAt,
    CloudBackupJobSummary: cloudBackupJobSummary(row),
    Parameters: parameters,
  }
}

const dateOr = (value, cellName, fallback) =>
  value ? getCippFormatting(value, cellName) : fallback

const JobDetails = ({ row, canDownload }) => {
  const jobState = useCloudBackupJob(row.Id)
  const job = jobState.job ? toCloudBackupJobRow(jobState.job) : row
  const parameters = job.Parameters ?? {}
  return (
    <Stack spacing={2}>
      <CippPropertyListCard
        cardSx={{ p: 0, m: -2 }}
        title={`${job.CloudBackupJobType} of ${job.CloudBackupOwner ?? 'a backup'}`}
        propertyItems={[
          {
            label: 'Status',
            value: getCippFormatting(job.Status, 'CloudBackupStatus'),
          },
          { label: 'Tenant', value: job.Tenant ?? job.SourceTenant },
          { label: 'Service', value: job.CloudBackupWorkload },
          { label: 'Backup of', value: job.CloudBackupOwner },
          ...(job.Type === 'Export'
            ? []
            : [
                { label: 'Restored to', value: job.CloudBackupTarget },
                {
                  label: 'Restored into',
                  value: optionLabel(
                    CLOUD_BACKUP_RESTORE_LOCATIONS,
                    parameters.Location
                  ),
                },
                {
                  label: 'When an item already exists',
                  value: optionLabel(
                    CLOUD_BACKUP_CONFLICT_ACTIONS,
                    parameters.ConflictAction
                  ),
                },
              ]),
          { label: 'Requested by', value: job.RequestedBy },
          {
            label: 'Requested',
            value: dateOr(job.CreatedAt, 'CloudBackupCreatedAt', 'Unknown'),
          },
          {
            label: 'Finished',
            value: dateOr(
              job.CompletedAt,
              'CloudBackupCompletedAt',
              'Not finished'
            ),
          },
          { label: 'Result', value: job.CloudBackupJobSummary },
        ]}
      />
      <CippCloudBackupJobStatus
        jobState={jobState}
        runningText="This job is still running. The details update by themselves."
      />
      {job.Type === 'RestorePreview' && job.Status === 'Completed' && (
        <Typography variant="body2">
          This is a saved preview. To restore, open Browse & Restore, pick the
          same backup and run a new preview.
        </Typography>
      )}
      {job.Type === 'Export' &&
        (canDownload ? (
          <CippCloudBackupExportDownload job={jobState.job} />
        ) : (
          <Typography variant="body2">
            Downloading exports needs the Cloud Backup restore permission.
          </Typography>
        ))}
      {jobState.job && job.Status !== 'Queued' && (
        <CippCloudBackupJobResults
          job={jobState.job}
          title={job.Type === 'Restore' ? 'Restore results' : 'Restore preview'}
        />
      )}
    </Stack>
  )
}

const Page = () => {
  const { checkPermissions } = usePermissions()
  const canDownload = checkPermissions(CLOUD_BACKUP_RESTORE_PERMISSION)
  const tenant = useSettings().currentTenant
  return (
    <CippTablePage
      title="Restore History"
      apiUrl="/api/ListCloudBackupJobs"
      apiData={{ InvalidateCIPPCache: true }}
      queryKey={`ListCloudBackupJobs-history-${tenant}`}
      dataFilter={(row) => CLOUD_BACKUP_HISTORY_JOB_TYPES.includes(row.Type)}
      dataMap={toCloudBackupJobRow}
      offCanvas={{
        title: 'Restore or Export Details',
        size: 'xl',
        children: (row) => <JobDetails row={row} canDownload={canDownload} />,
      }}
      offCanvasOnRowClick={true}
      simpleColumns={[
        'CloudBackupCreatedAt',
        'CloudBackupJobType',
        'CloudBackupStatus',
        'CloudBackupWorkload',
        'CloudBackupOwner',
        'CloudBackupTarget',
        'CloudBackupRequestedBy',
        'CloudBackupCompletedAt',
        'CloudBackupJobSummary',
      ]}
      filters={[
        {
          filterName: 'Restores',
          value: [{ id: 'CloudBackupJobType', value: 'Restore' }],
          type: 'column',
        },
        {
          filterName: 'Exports',
          value: [{ id: 'CloudBackupJobType', value: 'Export' }],
          type: 'column',
        },
        {
          filterName: 'Failed',
          value: [{ id: 'CloudBackupStatus', value: 'Failed' }],
          type: 'column',
        },
      ]}
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
