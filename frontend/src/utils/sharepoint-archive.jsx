export const ARCHIVE_WAIT_NOTE =
  'Archived content is not available straight away: bringing it back is instant for the first 7 days, then can take up to 24 hours, and it cannot be opened until that finishes.'

// The backend sends exactly one of these values for each site.
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
