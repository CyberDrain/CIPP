import { useState } from 'react'
import { Button, CircularProgress, IconButton, Tooltip } from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { ApiPostCall } from '../../api/ApiCall'
import { useBrandingSettings } from '../CippPdf/useBrandingSettings'
import { useReportVariables } from '../CippPdf/useReportVariables'
import { BECRemediationReportDocument } from '../BECRemediationReportButton'

const blobToBase64 = (blob) =>
  new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onloadend = () => resolve(String(reader.result).split(',')[1] || '')
    reader.onerror = reject
    reader.readAsDataURL(blob)
  })

const base64ToBlob = (base64, type) => {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return new Blob([bytes], { type })
}

const safe = (value) =>
  String(value || 'case')
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80)

const caseOf = (row) => row?.CaseId ?? row?.caseId
const tenantOf = (row) => row?.Tenant ?? row?.tenantFilter
const upnOf = (row) => row?.UserPrincipalName ?? row?.userPrincipalName

/**
 * Downloads a case's evidence package WITH the report PDFs, without opening the case: it fetches the
 * case results, renders the full report and the C-suite summary in-memory (no browser tab), posts them
 * to the export endpoint, and saves the ZIP under a name carrying the user and case.
 *
 * Returned as a hook so one owner (the runs hub) drives it for every row and can show one status,
 * while the button below is the self-contained form for a single place.
 */
export const useBecEvidenceDownload = () => {
  const brandingSettings = useBrandingSettings()
  const variables = useReportVariables()
  const [pendingCaseId, setPendingCaseId] = useState(null)
  const exportCall = ApiPostCall({})

  const download = async (row, providedBecData) => {
    const caseId = caseOf(row)
    const tenantFilter = tenantOf(row)
    if (!caseId || !tenantFilter || pendingCaseId) return
    setPendingCaseId(caseId)
    try {
      let becData = providedBecData
      if (!becData) {
        const response = await fetch(
          `/api/execBECCheck?GUID=${encodeURIComponent(caseId)}&tenantFilter=${encodeURIComponent(tenantFilter)}`
        )
        if (!response.ok) throw new Error(`Could not load case ${caseId}`)
        becData = await response.json()
      }
      if (becData?.Waiting || becData?.Error) {
        throw new Error('The case is not a completed run')
      }
      const userData = {
        id: row?.UserId ?? row?.userId,
        userPrincipalName: upnOf(row),
        displayName: row?.DisplayName ?? row?.displayName ?? upnOf(row),
      }

      let pdfBase64 = ''
      let pdfSummaryBase64 = ''
      try {
        const { pdf } = await import('@react-pdf/renderer')
        const render = async (reportVariant) => {
          const blob = await pdf(
            <BECRemediationReportDocument
              userData={userData}
              becData={becData}
              brandingSettings={brandingSettings}
              tenantName={tenantFilter}
              variables={variables}
              variant={reportVariant}
            />
          ).toBlob()
          return blobToBase64(blob)
        }
        pdfBase64 = await render('full')
        pdfSummaryBase64 = await render('summary')
      } catch (renderError) {
        console.error(
          'BEC evidence: PDF render failed, exporting without it',
          renderError
        )
      }

      await new Promise((resolve) => {
        exportCall.mutate(
          {
            url: '/api/ExecBECEvidenceExport',
            data: { tenantFilter, caseId, pdfBase64, pdfSummaryBase64 },
          },
          {
            onSuccess: (result) => {
              const zip = result?.data?.Evidence?.ZipBase64
              if (zip) {
                const blob = base64ToBlob(zip, 'application/zip')
                const url = URL.createObjectURL(blob)
                const link = document.createElement('a')
                link.href = url
                link.download = `BEC_Evidence_${safe(upnOf(row) || userData.id)}_${safe(caseId)}.zip`
                document.body.appendChild(link)
                link.click()
                document.body.removeChild(link)
                URL.revokeObjectURL(url)
              }
              resolve()
            },
            onError: () => resolve(),
          }
        )
      })
    } catch (error) {
      console.error('BEC evidence download failed', error)
    } finally {
      setPendingCaseId(null)
    }
  }

  return { download, pendingCaseId, exportCall }
}

/**
 * Self-contained download control for a single case (its own hook instance). `variant='icon'` for a
 * compact per-row button, otherwise a labelled button.
 */
export const CippBecEvidenceDownloadButton = ({
  row,
  becData,
  variant = 'button',
  label = 'Download evidence (ZIP)',
}) => {
  const { download, pendingCaseId } = useBecEvidenceDownload()
  const busy = pendingCaseId != null
  const disabled = busy || !caseOf(row)

  if (variant === 'icon') {
    return (
      <Tooltip title={busy ? 'Building evidence package…' : label}>
        <span>
          <IconButton
            size="small"
            onClick={() => download(row, becData)}
            disabled={disabled}
          >
            {busy ? (
              <CircularProgress size={18} />
            ) : (
              <CippIcons.Archive fontSize="small" />
            )}
          </IconButton>
        </span>
      </Tooltip>
    )
  }

  return (
    <Button
      size="small"
      variant="outlined"
      startIcon={busy ? <CircularProgress size={16} /> : <CippIcons.Archive />}
      onClick={() => download(row, becData)}
      disabled={disabled}
    >
      {busy ? 'Building…' : label}
    </Button>
  )
}

export default CippBecEvidenceDownloadButton
