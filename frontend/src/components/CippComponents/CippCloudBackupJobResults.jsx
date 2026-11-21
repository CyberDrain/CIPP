import { useMemo } from 'react'
import { Alert, Box, Button, Stack, Typography } from '@mui/material'
import { CippDataTable } from '../CippTable/CippDataTable'
import { CippPropertyListCard } from '../CippCards/CippPropertyListCard'
import { getCippFormatting } from '../../utils/get-cipp-formatting'
import { CippIcons } from '../../utils/icon-registry'
import { useCloudBackupDownload } from '../../hooks/use-cloud-backup-download'
import {
  cloudBackupExportAvailable,
  cloudBackupItemTypeLabel,
  cloudBackupJobResults,
  cloudBackupRestoreActionLabel,
} from '../../utils/cloud-backup'

const toResultRow = (row) => ({
  ...row,
  CloudBackupItemName: row.Name || row.Key,
  CloudBackupItemFolder: row.Path || '/',
  CloudBackupItemType: cloudBackupItemTypeLabel(row.Type),
  CloudBackupRestoreAction: cloudBackupRestoreActionLabel(row.Action),
  CloudBackupStatus: row.Status,
  CloudBackupMessage: row.Message ?? '',
  CloudBackupTargetPath: row.TargetPath ?? '',
})

const ResultDetails = ({ row, applied }) => (
  <CippPropertyListCard
    cardSx={{ p: 0, m: -2 }}
    title={row.CloudBackupItemName}
    propertyItems={[
      { label: 'Folder', value: row.CloudBackupItemFolder },
      { label: 'Type', value: row.CloudBackupItemType },
      { label: 'What happens', value: row.CloudBackupRestoreAction },
      {
        label: 'Result',
        value: applied
          ? getCippFormatting(row.Status, 'CloudBackupStatus')
          : 'Not restored yet',
      },
      { label: 'Restored to', value: row.CloudBackupTargetPath || 'Not set' },
      { label: 'Details', value: row.CloudBackupMessage || 'None' },
    ]}
  />
)

export const CippCloudBackupJobResults = ({ job, title }) => {
  const applied = job?.Type === 'Restore'
  const { rows, total } = useMemo(
    () => cloudBackupJobResults(job?.Result),
    [job?.Result]
  )
  const data = useMemo(() => rows.map(toResultRow), [rows])
  if (job?.Type === 'Export') return null
  return (
    <Stack spacing={1}>
      {total > rows.length && (
        <Alert severity="info">
          Showing the first {rows.length} of {total} items.
        </Alert>
      )}
      <CippDataTable
        title={title}
        queryKey={`CloudBackupJobResults-${job?.Id}`}
        data={data}
        simpleColumns={[
          'CloudBackupItemName',
          'CloudBackupItemFolder',
          'CloudBackupItemType',
          'CloudBackupRestoreAction',
          ...(applied ? ['CloudBackupStatus'] : []),
          'CloudBackupMessage',
        ]}
        filters={[
          {
            filterName: 'Cannot be restored',
            value: [
              {
                id: 'CloudBackupRestoreAction',
                value: cloudBackupRestoreActionLabel('NotRestorable'),
              },
            ],
            type: 'column',
          },
          ...(applied
            ? [
                {
                  filterName: 'Failed',
                  value: [{ id: 'CloudBackupStatus', value: 'Failed' }],
                  type: 'column',
                },
              ]
            : []),
        ]}
        offCanvas={{
          title: 'Item Result',
          children: (row) => <ResultDetails row={row} applied={applied} />,
        }}
        offCanvasOnRowClick={true}
      />
    </Stack>
  )
}

export const CippCloudBackupExportDownload = ({ job }) => {
  const { download, busy, error, progress } = useCloudBackupDownload()
  if (job?.Type !== 'Export' || job.Status !== 'Completed') return null
  if (!cloudBackupExportAvailable(job)) {
    return (
      <Alert severity="info">
        This export has expired and was deleted. Start a new export from Browse
        & Restore.
      </Alert>
    )
  }
  return (
    <Stack spacing={1}>
      <Box>
        <Button
          variant="contained"
          startIcon={<CippIcons.Download />}
          disabled={busy}
          onClick={() => download({ JobId: job.Id }, `export-${job.Id}.zip`)}
        >
          {busy
            ? progress
              ? `Downloading part ${progress.part} of ${progress.parts}…`
              : 'Downloading…'
            : 'Download export'}
        </Button>
      </Box>
      {job.ExpiresAt && (
        <Typography variant="body2">
          Available until{' '}
          {getCippFormatting(job.ExpiresAt, 'CloudBackupExpiresAt')}.
        </Typography>
      )}
      {error && <Alert severity="error">{error}</Alert>}
    </Stack>
  )
}
