import { useState } from 'react'
import { CippIcons } from '../../utils/icon-registry'
import {
  Autocomplete,
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material'
import { ServerPdfPane, useServerPdf } from '../CippPdf/useServerPdf'

const operatorLabels = {
  eq: 'equals',
  ne: 'does not equal',
  startsWith: 'starts with',
  notStartsWith: 'does not start with',
}

// Human-readable summary of a stage's graduation conditions. Shared with the alignment and
// templates pages; the server-rendered report words them the same way.
export const describeStageConditions = (stage) => {
  if (!stage?.conditions?.length) return 'no conditions configured'
  const parts = stage.conditions.map((condition) => {
    switch (condition.type) {
      case 'time':
        return `${condition.days} ${condition.unit ?? 'days'} in the previous stage`
      case 'variable':
        return `${condition.variable} ${operatorLabels[condition.operator] ?? condition.operator} '${condition.value}'`
      case 'success':
        return 'all previous stage items applied successfully'
      case 'manual':
        return 'manual approval by an operator'
      default:
        return condition.type
    }
  })
  return parts.join(stage.logic === 'or' ? ' OR ' : ' AND ')
}

// Button + preview dialog in the style of the Executive Report button. The PDF is rendered
// server-side (ExecGetBaselineWhatIfReportPdf) by the shared CIPPSharp component kit from the same
// alignment payload this page shows, and re-rendered while the dialog is open whenever the
// simulated baseline changes.
export const CippBaselineWhatIfReport = ({
  tenant,
  stageStates,
  baselines = [],
}) => {
  const [open, setOpen] = useState(false)
  const [simulatedTemplate, setSimulatedTemplate] = useState(null)

  // Baselines not currently rolled out to this tenant can be simulated in the report.
  const availableTemplates = baselines.filter(
    (template) =>
      !stageStates.some((state) => state.templateId === template.GUID)
  )

  const pdf = useServerPdf({
    url: '/api/ExecGetBaselineWhatIfReportPdf',
    body: {
      tenantFilter: tenant.tenantFilter,
      simulatedTemplateId: simulatedTemplate?.GUID ?? '',
    },
    enabled: open,
  })

  const fileName = `WhatIf_Report_${String(tenant.displayName).replace(/[^a-zA-Z0-9]/g, '_')}.pdf`

  return (
    <>
      <Tooltip title="Preview what applying the configured standards would change for this tenant, including upcoming stages">
        <Button
          variant="contained"
          startIcon={<CippIcons.PictureAsPdf />}
          onClick={() => setOpen(true)}
        >
          What-If Report
        </Button>
      </Tooltip>
      <Dialog
        open={open}
        onClose={() => setOpen(false)}
        maxWidth="xl"
        fullWidth
      >
        <DialogTitle>What-If Report - {tenant.displayName}</DialogTitle>
        <DialogContent
          sx={{
            p: 0,
            height: '75vh',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <Box sx={{ p: 2, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Autocomplete
              size="small"
              options={availableTemplates}
              getOptionLabel={(option) => option.templateName}
              value={simulatedTemplate}
              onChange={(event, value) => setSimulatedTemplate(value)}
              renderInput={(params) => (
                <TextField
                  {...params}
                  label="Simulate assigning an additional baseline"
                />
              )}
              sx={{ maxWidth: 460 }}
            />
          </Box>
          <Box sx={{ flex: 1, minHeight: 0 }}>
            <ServerPdfPane
              {...pdf}
              title="Baseline what-if report"
              errorText="The report could not be generated. Run the baseline for this tenant and try again."
            />
          </Box>
        </DialogContent>
        <DialogActions
          sx={{ p: 2, borderTop: '1px solid', borderColor: 'divider', gap: 1 }}
        >
          <Box sx={{ flex: 1 }}>
            <Typography variant="caption" sx={{ color: 'text.secondary' }}>
              Exec-friendly preview - safe to send to customers. No changes are
              made.
            </Typography>
          </Box>
          <Button
            variant="contained"
            startIcon={<CippIcons.Download />}
            onClick={() => pdf.download(fileName)}
            disabled={!pdf.pdfUrl}
          >
            Download PDF
          </Button>
          <Button variant="outlined" onClick={() => setOpen(false)}>
            Close
          </Button>
        </DialogActions>
      </Dialog>
    </>
  )
}

export default CippBaselineWhatIfReport
