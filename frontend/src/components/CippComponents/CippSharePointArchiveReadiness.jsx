import PropTypes from 'prop-types'
import { Alert, AlertTitle, Link } from '@mui/material'
import { ARCHIVE_WAIT_NOTE } from '../../utils/sharepoint-archive'
import { getCippError } from '../../utils/get-cipp-error'
import { formatCleanupBytes } from '../../utils/storage-cleanup-opportunities'

const SETUP_URL =
  'https://learn.microsoft.com/microsoft-365/archive/archive-overview'

/**
 * Says whether a tenant is ready to archive SharePoint content, from the tenant's cached
 * Microsoft 365 Archive settings, and always carries the wait to get archived content back.
 */
export const CippSharePointArchiveReadiness = ({
  settings,
  sitesBlocked = 0,
  hasArchiveUsage = false,
  error = null,
}) => {
  if (!settings) {
    if (!error) return null
    const notCollected = error.response?.status === 404
    return (
      <Alert severity="info" sx={{ mb: 1 }}>
        <AlertTitle>
          {notCollected
            ? "This tenant's SharePoint settings have not been collected yet"
            : "This tenant's SharePoint settings could not be read"}
        </AlertTitle>
        {notCollected
          ? getCippError(error)
          : `${getCippError(error)} Reload the page to try again.`}{' '}
        Until then this page cannot say whether Microsoft 365 Archive is turned
        on for the tenant.
      </Alert>
    )
  }

  const archivedBytes = Number(settings.archivedFileStorageInBytes) || 0
  // Archive usage is proof it is on, whatever the switch reads.
  const enabled =
    settings.archiveEnabled || archivedBytes > 0 || hasArchiveUsage

  if (!enabled) {
    return (
      <Alert severity="warning" sx={{ mb: 1 }}>
        <AlertTitle>
          Microsoft 365 Archive does not appear to be turned on
        </AlertTitle>
        Files and sites cannot be archived until it is turned on for this tenant
        in the Microsoft 365 admin center, under pay-as-you-go services, with an
        Azure subscription for billing.{' '}
        <Link href={SETUP_URL} target="_blank" rel="noreferrer">
          How Microsoft 365 Archive works
        </Link>
      </Alert>
    )
  }

  if (!settings.allowFileArchive) {
    return (
      <Alert severity="warning" sx={{ mb: 1 }}>
        <AlertTitle>File archiving is switched off for this tenant</AlertTitle>
        Whole sites can still be archived, but users cannot archive individual
        files, and archiving a file from CIPP may be refused. Turn it on with
        the Set SharePoint file archiving baseline. {ARCHIVE_WAIT_NOTE}
      </Alert>
    )
  }

  return (
    <Alert severity="info" sx={{ mb: 1 }}>
      <AlertTitle>Microsoft 365 Archive is turned on</AlertTitle>
      {formatCleanupBytes(archivedBytes)} is archived at file level.
      {sitesBlocked > 0
        ? ` ${sitesBlocked} ${sitesBlocked === 1 ? 'site does' : 'sites do'} not allow file archiving: use File archiving… on a site to change it.`
        : ''}
      {settings.allowFileArchiveOnNewSites
        ? ''
        : ' New sites do not allow file archiving by default.'}{' '}
      {ARCHIVE_WAIT_NOTE}
    </Alert>
  )
}

CippSharePointArchiveReadiness.propTypes = {
  settings: PropTypes.object,
  sitesBlocked: PropTypes.number,
  hasArchiveUsage: PropTypes.bool,
  error: PropTypes.object,
}
