import { useState } from 'react'
import { CippIcons } from '../utils/icon-registry'
import {
  Button,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Box,
  Typography,
  IconButton,
} from '@mui/material'
import { useSettings } from '../hooks/use-settings'
import { ServerPdfPane, useServerPdf } from './CippPdf/useServerPdf'

// The report PDF is rendered server-side (ExecGetBecReportPdf) by the shared CIPPSharp component kit,
// which reads the cached BEC run; the button fetches the finished PDF as a blob for preview and download.
export const BECRemediationReportButton = ({ userData, becData, tenantName }) => {
  const [dialogOpen, setDialogOpen] = useState(false)
  const tenantFilter = useSettings().currentTenant

  // Only offer the report once the BEC analysis has completed (its result is what the server reads).
  const hasData = userData && becData && !becData.Waiting

  const params = new URLSearchParams({
    tenantFilter: tenantFilter ?? '',
    userId: userData?.id ?? userData?.userId ?? '',
    userName: userData?.userPrincipalName ?? '',
    userDisplayName: userData?.displayName ?? '',
  })
  const pdf = useServerPdf({ url: `/api/ExecGetBecReportPdf?${params}`, enabled: dialogOpen })
  const handleOpenDialog = () => setDialogOpen(true)
  const handleCloseDialog = () => setDialogOpen(false)
  const fileName = `BEC_Report_${(userData?.userPrincipalName || 'user').replace(/[^a-zA-Z0-9]/g, '_')}_${new Date().toISOString().split('T')[0]}.pdf`

  if (!hasData) {
    return null // Don't show button if data isn't ready
  }

  return (
    <>
      <Tooltip title="Generate BEC Remediation Report PDF">
        <Button
          variant="contained"
          startIcon={<CippIcons.PictureAsPdf />}
          onClick={handleOpenDialog}
          disabled={!hasData}
          color="primary"
        >
          Generate PDF Report
        </Button>
      </Tooltip>

      <Dialog
        open={dialogOpen}
        onClose={handleCloseDialog}
        maxWidth="lg"
        fullWidth
        slotProps={{
          paper: {
            sx: {
              height: '90vh',
            },
          }
        }}
      >
        <DialogTitle>
          <Box
            sx={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center"
            }}>
            <Typography variant="h6" component="div">
              BEC Remediation Report Preview
            </Typography>
            <IconButton onClick={handleCloseDialog} size="small">
              <CippIcons.Close />
            </IconButton>
          </Box>
        </DialogTitle>
        <DialogContent dividers sx={{ p: 0 }}>
          <ServerPdfPane
            {...pdf}
            title={`BEC Remediation Report - ${tenantName}`}
            errorText="The report could not be generated. Ensure the BEC check has completed for this user."
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={handleCloseDialog}>Close</Button>
          <Button
            variant="contained"
            startIcon={<CippIcons.Download />}
            onClick={() => pdf.download(fileName)}
            disabled={!pdf.pdfUrl}
          >
            Download PDF
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}