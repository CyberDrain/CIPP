import { useMemo } from 'react'
import PropTypes from 'prop-types'
import {
  Alert,
  Card,
  CardContent,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { CippDataTable } from '../CippTable/CippDataTable'
import { usePermissions } from '../../hooks/use-permissions'
import { getCippError } from '../../utils/get-cipp-error'
import { formatCleanupBytes } from '../../utils/storage-cleanup-opportunities'
import {
  ARCHIVE_CANDIDATE_MONTHS,
  ARCHIVE_RATE_DEFAULT,
  ARCHIVE_WAIT_NOTE,
  EXTRA_STORAGE_RATE_DEFAULT,
  estimateArchiveCost,
  getArchiveFileActions,
  isArchiveCandidate,
} from '../../utils/sharepoint-archive'

const EMPTY_ROWS = []
const COLUMNS = [
  'name',
  'siteName',
  'libraryName',
  'folderPath',
  'sizeInBytes',
  'archiveStatus',
  'archiveCandidate',
  'lastModifiedDateTime',
  'lastModifiedBy',
]
const DEFAULT_SORTING = [{ id: 'sizeInBytes', desc: true }]
const FILTERS = [
  {
    filterName: `Archive candidates (not changed in ${ARCHIVE_CANDIDATE_MONTHS} months)`,
    value: [{ id: 'archiveCandidate', value: 'Yes' }],
    type: 'column',
  },
  {
    filterName: 'Archived',
    value: [{ id: 'archiveStatus', value: 'Archived', filterFn: 'equals' }],
    type: 'column',
  },
]

const DEFAULT_PRICES = {
  archiveRate: ARCHIVE_RATE_DEFAULT,
  storageRate: EXTRA_STORAGE_RATE_DEFAULT,
}

const money = (value) =>
  value.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

/**
 * The tenant-wide largest files from the last large file scan, the ones worth archiving,
 * and what archiving them costs against buying extra storage.
 */
export const CippSharePointLargeFiles = ({
  files,
  queryKey,
  archiveSettings,
  activeBytes,
  prices = DEFAULT_PRICES,
  onPricesChange,
  scan = null,
}) => {
  const { checkPermissions } = usePermissions()
  const canWriteSite = checkPermissions(['Sharepoint.Site.ReadWrite'])

  const rows = useMemo(() => {
    if (!Array.isArray(files.data)) return EMPTY_ROWS
    return files.data.map((row) => ({
      ...row,
      isFolder: false,
      archiveCandidate: isArchiveCandidate(row) ? 'Yes' : 'No',
    }))
  }, [files.data])

  const candidates = useMemo(
    () => rows.filter((row) => row.archiveCandidate === 'Yes'),
    [rows]
  )
  const candidateBytes = useMemo(
    () =>
      candidates.reduce((sum, row) => sum + (Number(row.sizeInBytes) || 0), 0),
    [candidates]
  )
  const searchIncomplete = rows.some((row) => row.searchComplete === false)
  const lastScan = useMemo(() => {
    const latest = rows.reduce(
      (max, row) => Math.max(max, Date.parse(row.collectedAt) || 0),
      0
    )
    return latest ? new Date(latest) : null
  }, [rows])

  const estimate = estimateArchiveCost({
    candidateBytes,
    activeBytes,
    archivedBytes: archiveSettings?.archivedFileStorageInBytes,
    quotaBytes: archiveSettings?.storageQuotaInBytes,
    archiveRate: Number(prices.archiveRate) || 0,
    storageRate: Number(prices.storageRate) || 0,
  })

  const actions = useMemo(
    () => [
      ...getArchiveFileActions({
        canWrite: canWriteSite,
        relatedQueryKeys: [queryKey],
        itemIdField: 'itemId',
      }),
      {
        label: 'Open in SharePoint',
        link: '[webUrl]',
        external: true,
        target: '_blank',
        icon: <CippIcons.Launch />,
        multiPost: false,
        condition: (row) => Boolean(row?.webUrl),
      },
    ],
    [canWriteSite, queryKey]
  )

  const notScanned = files.isError && files.error?.response?.status === 404
  const nothingStored =
    notScanned || (Array.isArray(files.data) && files.data.length === 0)
  const listFailed = files.isError && !notScanned
  const hasNewRows = Boolean(
    scan && lastScan && lastScan.getTime() > scan.listedAt
  )
  // The first read of the list after the scan ends still counts as the scan running.
  const lastRead = Math.max(files.dataUpdatedAt || 0, files.errorUpdatedAt || 0)
  const running =
    Boolean(scan?.queueId) &&
    (!scan.endState || (files.isFetching && lastRead < scan.endedAt))
  const completed = scan?.endState === 'Completed'
  const retry =
    'Check the logbook for the reason, then use Scan large files to try again.'

  let notice = null
  if (running) {
    if (rows.length === 0) {
      notice = [
        'info',
        'The large file scan has started. The files show here when it finishes, which can take a while for a large tenant. Its progress shows next to Scan large files.',
      ]
    }
  } else if (scan && !scan.queueId) {
    if (!hasNewRows) {
      notice = [
        'info',
        'A large file scan for this tenant was already running when you asked, so a second one was not started. Use Refresh to check for its results.',
      ]
    }
  } else if (scan?.endState) {
    if (rows.length > 0 && !hasNewRows && !listFailed) {
      notice = [
        'warning',
        `The large file scan did not store new results, so the files listed are from the previous scan. ${retry}`,
      ]
    } else if (!completed || notScanned) {
      notice = [
        'warning',
        rows.length > 0 && !listFailed
          ? 'Some sites could not be read by the large file scan, so their files may be missing or from the previous scan. Check the logbook for the detail.'
          : `The large file scan did not finish${nothingStored ? ', so there are no files to show' : ''}. ${retry}`,
      ]
    } else if (nothingStored) {
      notice = [
        'info',
        'The large file scan finished and no large files were stored. Only sites holding 1 GB or more are scanned. If you expected files here, the logbook has the detail.',
      ]
    }
  } else if (notScanned) {
    notice = [
      'info',
      'No large file scan has run for this tenant yet. Use Scan large files to list the largest files in every site holding 1 GB or more.',
    ]
  }

  return (
    <Stack spacing={1}>
      {listFailed && (
        <Alert severity="error">
          {getCippError(files.error)} Use Scan large files to run the scan
          again.
        </Alert>
      )}
      {notice && <Alert severity={notice[0]}>{notice[1]}</Alert>}

      {searchIncomplete && (
        <Alert severity="info">
          Some sites hold more folders than the scan reads in one go, so not
          every folder in them was searched. These are the largest files found,
          and a larger file may still be in a folder the scan did not reach. Use
          View folders and files on a library to look inside it.
        </Alert>
      )}

      {rows.length > 0 && (
        <Card variant="outlined">
          <CardContent>
            <Stack
              direction={{ xs: 'column', md: 'row' }}
              spacing={2}
              sx={{ alignItems: { md: 'center' } }}
            >
              <Stack spacing={0.5} sx={{ flex: 1 }}>
                <Typography variant="subtitle2">
                  What archiving would save
                </Typography>
                <Typography variant="body2">
                  {candidates.length === 0
                    ? `No eligible active files last changed more than ${ARCHIVE_CANDIDATE_MONTHS} months ago were found.`
                    : `${candidates.length} ${candidates.length === 1 ? 'file has' : 'files have'} not changed in ${ARCHIVE_CANDIDATE_MONTHS} months and ${candidates.length === 1 ? 'is' : 'are'} not archived yet. Archiving ${candidates.length === 1 ? 'it' : 'them'} would free ${formatCleanupBytes(candidateBytes)} of SharePoint storage.`}
                </Typography>
                {candidates.length > 0 && (
                  <Typography variant="body2">
                    {estimate.withinQuota
                      ? 'When CIPP last collected its storage figures, this tenant was within its storage quota, so the archived storage would not be charged.'
                      : estimate.exact
                        ? estimate.archiveCost > 0
                          ? `Archive storage for them would cost ${money(estimate.archiveCost)} a month.`
                          : "Archiving them would not add to the tenant's Archive charge."
                        : `Archive storage for them would cost at most ${money(estimate.archiveCost)} a month, and nothing while the tenant stays within its storage quota.`}{' '}
                    {estimate.exact &&
                      'This estimate uses the SharePoint storage figures CIPP last collected for the tenant, not a live reading. '}
                    Buying the same space as extra SharePoint storage would cost{' '}
                    {money(estimate.extraStorageCost)} a month.
                  </Typography>
                )}
                <Typography variant="caption" sx={{ color: 'text.secondary' }}>
                  {ARCHIVE_WAIT_NOTE}
                </Typography>
              </Stack>
              <Stack direction="row" spacing={1}>
                <TextField
                  size="small"
                  type="number"
                  label="Archive price per GB a month"
                  value={prices.archiveRate}
                  onChange={(event) =>
                    onPricesChange?.({
                      ...prices,
                      archiveRate: event.target.value,
                    })
                  }
                  slotProps={{ htmlInput: { min: 0, step: 0.01 } }}
                  sx={{ width: 210 }}
                />
                <TextField
                  size="small"
                  type="number"
                  label="Extra storage price per GB a month"
                  value={prices.storageRate}
                  onChange={(event) =>
                    onPricesChange?.({
                      ...prices,
                      storageRate: event.target.value,
                    })
                  }
                  helperText="The defaults are Microsoft's US list prices. Change them to your own."
                  slotProps={{ htmlInput: { min: 0, step: 0.01 } }}
                  sx={{ width: 250 }}
                />
              </Stack>
            </Stack>
          </CardContent>
        </Card>
      )}

      <CippDataTable
        title="Large Files"
        queryKey={`${queryKey}-table`}
        data={rows}
        isFetching={files.isFetching}
        refreshFunction={files}
        actions={actions}
        filters={FILTERS}
        simpleColumns={COLUMNS}
        defaultSorting={DEFAULT_SORTING}
      />
      <Typography variant="caption" sx={{ color: 'text.secondary' }}>
        {lastScan ? `Scanned ${lastScan.toLocaleString()}. ` : ''}
        The scan keeps up to 25 of the largest files found in each site holding
        1 GB or more. Sizes and archive status are as they were when it ran, so
        scan again after archiving.
      </Typography>
    </Stack>
  )
}

CippSharePointLargeFiles.propTypes = {
  files: PropTypes.object.isRequired,
  queryKey: PropTypes.string.isRequired,
  archiveSettings: PropTypes.object,
  activeBytes: PropTypes.number,
  prices: PropTypes.shape({
    archiveRate: PropTypes.oneOfType([PropTypes.number, PropTypes.string]),
    storageRate: PropTypes.oneOfType([PropTypes.number, PropTypes.string]),
  }),
  onPricesChange: PropTypes.func,
  scan: PropTypes.shape({
    listedAt: PropTypes.number.isRequired,
    queueId: PropTypes.string,
    endState: PropTypes.string,
    endedAt: PropTypes.number,
  }),
}
