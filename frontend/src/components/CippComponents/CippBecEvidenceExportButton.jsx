import { Button, Tooltip } from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { useBecEvidenceDownload } from './CippBecEvidenceDownload'

/**
 * Export evidence from the case page: renders both report PDFs in the browser, posts them to the
 * backend which collates the package into a ZIP with a SHA-256 manifest, and downloads it. There is no
 * results panel — the ZIP's SHA-256 (for verifying a copy later) and any error show in the button's
 * hover tooltip, so the control stays a single button in the action row.
 */
export const CippBecEvidenceExportButton = ({
  tenantFilter,
  caseId,
  userData,
  becData,
}) => {
  const { download, busy, lastHash, lastError } = useBecEvidenceDownload()
  const hash = lastHash || becData?.Run?.EvidenceSha256 || null

  const tooltip = busy
    ? 'Building evidence package…'
    : lastError
      ? `Last export failed: ${lastError}`
      : hash
        ? `Packages the case evidence (with both report PDFs) as a ZIP. Last export SHA-256: ${hash}`
        : 'Renders both report PDFs and packages the case evidence as a ZIP'

  return (
    <Tooltip title={tooltip}>
      <span>
        <Button
          size="small"
          variant="outlined"
          color={lastError ? 'error' : 'primary'}
          startIcon={<CippIcons.Archive />}
          onClick={() =>
            download(
              {
                CaseId: caseId,
                Tenant: tenantFilter,
                UserId: userData?.id,
                UserPrincipalName: userData?.userPrincipalName,
                DisplayName: userData?.displayName,
              },
              becData
            )
          }
          disabled={busy || !caseId}
        >
          {busy ? 'Building evidence package…' : 'Export evidence (ZIP)'}
        </Button>
      </span>
    </Tooltip>
  )
}

export default CippBecEvidenceExportButton
