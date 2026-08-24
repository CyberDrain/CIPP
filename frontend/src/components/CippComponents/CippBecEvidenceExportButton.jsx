import { useState } from 'react'
import { Button, Tooltip } from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { ApiPostCall } from '../../api/ApiCall'
import { BECRemediationReportDocument } from '../BECRemediationReportButton'
import { useBrandingSettings } from '../CippPdf/useBrandingSettings'
import { useReportVariables } from '../CippPdf/useReportVariables'

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

/**
 * Export evidence: renders the full report and the C-suite summary in the browser, posts them to the
 * backend which collates the package into a ZIP with a SHA-256 manifest, and downloads it. There is no
 * results panel — the ZIP's SHA-256 (for verifying a copy later) and any error show in the button's
 * hover tooltip, so the control stays a single button in the action row.
 */
export const CippBecEvidenceExportButton = ({
  tenantFilter,
  caseId,
  userData,
  becData,
  tenantName,
}) => {
  const brandingSettings = useBrandingSettings()
  const variables = useReportVariables()
  const [busy, setBusy] = useState(false)
  const [lastHash, setLastHash] = useState(becData?.Run?.EvidenceSha256 || null)
  const [lastError, setLastError] = useState(null)
  const exportCall = ApiPostCall({})

  const triggerDownload = (blob) => {
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `BEC_Evidence_${caseId}.zip`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  }

  const handleExport = async () => {
    if (!caseId) return
    setBusy(true)
    setLastError(null)
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
            tenantName={tenantName}
            variables={variables}
            variant={reportVariant}
          />
        ).toBlob()
        return blobToBase64(blob)
      }
      pdfBase64 = await render('full')
      pdfSummaryBase64 = await render('summary')
    } catch (error) {
      console.error(
        'BEC evidence: PDF render failed, exporting without it',
        error
      )
    }
    exportCall.mutate(
      {
        url: '/api/ExecBECEvidenceExport',
        data: { tenantFilter, caseId, pdfBase64, pdfSummaryBase64 },
      },
      {
        onSuccess: (response) => {
          const evidence = response?.data?.Evidence
          if (evidence?.ZipBase64) {
            triggerDownload(base64ToBlob(evidence.ZipBase64, 'application/zip'))
          }
          setLastHash(evidence?.ZipSha256 || null)
          setBusy(false)
        },
        onError: (error) => {
          setLastError(
            error?.response?.data?.Results || 'the export failed; see the logbook'
          )
          setBusy(false)
        },
      }
    )
  }

  const tooltip = busy
    ? 'Building evidence package…'
    : lastError
      ? `Last export failed: ${lastError}`
      : lastHash
        ? `Packages the case evidence (with both report PDFs) as a ZIP. Last export SHA-256: ${lastHash}`
        : 'Renders both report PDFs and packages the case evidence as a ZIP'

  return (
    <Tooltip title={tooltip}>
      <span>
        <Button
          size="small"
          variant="outlined"
          color={lastError ? 'error' : 'primary'}
          startIcon={<CippIcons.Archive />}
          onClick={handleExport}
          disabled={busy || !caseId}
        >
          {busy ? 'Building evidence package…' : 'Export evidence (ZIP)'}
        </Button>
      </span>
    </Tooltip>
  )
}

export default CippBecEvidenceExportButton
