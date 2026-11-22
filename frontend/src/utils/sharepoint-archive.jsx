import { CippIcons } from './icon-registry'

// Microsoft's US list prices per GB per month; technicians can overwrite them with their own.
export const ARCHIVE_RATE_DEFAULT = 0.05
export const EXTRA_STORAGE_RATE_DEFAULT = 0.2
export const ARCHIVE_CANDIDATE_MONTHS = 12

export const ARCHIVE_WAIT_NOTE =
  'Archived content is not available straight away: bringing it back is instant for the first 7 days, then can take up to 24 hours, and it cannot be opened until that finishes.'

// The backend sends exactly one of these values; a folder has none.
export const ARCHIVE_STATUS_LABELS = {
  active: 'Active',
  archived: 'Archived',
  reactivating: 'Reactivating',
  unknown: 'Unknown',
}

export const archiveStatusLabel = (status) =>
  typeof status === 'string' && Object.hasOwn(ARCHIVE_STATUS_LABELS, status)
    ? ARCHIVE_STATUS_LABELS[status]
    : status

const UNARCHIVABLE_EXTENSIONS = ['.one', '.onetoc2', '.aspx']

/**
 * False for content Microsoft 365 Archive cannot archive: OneNote files, SharePoint pages and
 * anything in the site's Site Assets library. Rows carry `name`, `isFolder`, `libraryName`,
 * `siteUrl` and `webUrl`. A folder merely named SiteAssets in another library can be archived.
 */
export const canBeArchived = (row) => {
  if (String(row?.libraryName ?? '').toLowerCase() === 'site assets') return false
  const siteUrl = String(row?.siteUrl ?? '').replace(/\/+$/, '')
  if (
    siteUrl &&
    String(row?.webUrl ?? '')
      .toLowerCase()
      .startsWith(`${siteUrl}/SiteAssets/`.toLowerCase())
  ) {
    return false
  }
  if (row?.isFolder) return true
  const name = String(row?.name ?? '').toLowerCase()
  return !UNARCHIVABLE_EXTENSIONS.some((extension) => name.endsWith(extension))
}

/** A file that is still active, can be archived, and has not been changed for `months` months. */
export const isArchiveCandidate = (
  row,
  months = ARCHIVE_CANDIDATE_MONTHS,
  now = new Date()
) => {
  if (row?.archiveStatus !== 'active' || !canBeArchived(row)) return false
  const changed = Date.parse(row?.lastModifiedDateTime)
  if (!Number.isFinite(changed)) return false
  const cutoff = new Date(now)
  cutoff.setMonth(cutoff.getMonth() - months)
  return changed < cutoff.getTime()
}

const toGb = (bytes) => bytes / 1024 ** 3

/**
 * What archiving `candidateBytes` costs a month, against buying that much extra storage.
 * Microsoft only bills archived storage for the amount by which active plus archived storage
 * exceeds the tenant quota, so with the tenant figures the archive cost is exact, and without
 * them it is the most it could be.
 */
export const estimateArchiveCost = ({
  candidateBytes,
  activeBytes,
  archivedBytes = 0,
  quotaBytes,
  archiveRate = ARCHIVE_RATE_DEFAULT,
  storageRate = EXTRA_STORAGE_RATE_DEFAULT,
}) => {
  const candidate = Math.max(0, Number(candidateBytes) || 0)
  const archived = Math.max(0, Number(archivedBytes) || 0)
  const active = Number(activeBytes)
  const quota = Number(quotaBytes)
  const exact =
    Number.isFinite(active) && active > 0 && Number.isFinite(quota) && quota > 0
  const extraStorageCost = toGb(candidate) * storageRate
  if (!exact) {
    return {
      exact,
      withinQuota: null,
      archiveCost: toGb(candidate) * archiveRate,
      extraStorageCost,
    }
  }
  const overQuota = Math.max(0, active + archived - quota)
  const billedNow = Math.min(archived, overQuota)
  const billedAfter = Math.min(archived + candidate, overQuota)
  return {
    exact,
    withinQuota: overQuota === 0,
    archiveCost: toGb(billedAfter - billedNow) * archiveRate,
    extraStorageCost,
  }
}

/**
 * Archive and Reactivate row actions for a table of SharePoint files and folders.
 * Rows carry driveId, name, isFolder and the item's id in `itemIdField`.
 */
export const getArchiveFileActions = ({
  canWrite,
  relatedQueryKeys,
  onSuccess,
  itemIdField = 'id',
}) => [
  {
    label: 'Archive',
    type: 'POST',
    icon: <CippIcons.Archive />,
    url: '/api/ExecSharePointFileArchive',
    data: {
      DriveId: 'driveId',
      ItemId: itemIdField,
      ItemName: 'name',
      IsFolder: 'isFolder',
      Action: '!Archive',
    },
    confirmText:
      'Archive [name]? Archived files move to Microsoft 365 Archive and stop counting towards SharePoint storage. They stay listed in the library, but nobody can open them until they are reactivated, which is instant for the first 7 days and can take up to 24 hours after that. Archiving a folder archives the eligible files inside it: OneNote files and SharePoint pages stay active.',
    relatedQueryKeys,
    onSuccess,
    multiPost: false,
    condition: (row) =>
      canWrite &&
      (row?.isFolder || row?.archiveStatus === 'active') &&
      canBeArchived(row),
  },
  {
    label: 'Reactivate',
    type: 'POST',
    icon: <CippIcons.Unarchive />,
    url: '/api/ExecSharePointFileArchive',
    data: {
      DriveId: 'driveId',
      ItemId: itemIdField,
      ItemName: 'name',
      IsFolder: 'isFolder',
      Action: '!Reactivate',
    },
    confirmText:
      'Reactivate [name]? Reactivated files count towards SharePoint storage again and cannot be archived again for 120 days. Files archived in the last 7 days come back straight away, older files can take up to 24 hours.',
    relatedQueryKeys,
    onSuccess,
    multiPost: false,
    condition: (row) =>
      canWrite && (row?.isFolder || row?.archiveStatus === 'archived'),
  },
]
