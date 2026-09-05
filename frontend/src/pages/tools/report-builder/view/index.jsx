import { useState, useEffect, useMemo } from 'react'
import { CippIcons } from '../../../../utils/icon-registry'
import {
  Button,
  Typography,
  IconButton,
  Container,
  Divider,
  Skeleton,
  Card,
  CardContent,
} from '@mui/material'
import { Stack, Box } from '@mui/system'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { useSettings } from '../../../../hooks/use-settings'
import { ApiGetCall } from '../../../../api/ApiCall.jsx'
import { useRouter } from 'next/router'

// The PDF is rendered server-side now (CIPPSharp/OfficeIMO) and fetched as a finished file, so this
// page no longer builds it in the browser — it lists the report for its name/status, then streams the
// stored PDF from ExecGetReportBuilderPdf into an iframe for preview and an anchor for download.
const Page = () => {
  const router = useRouter()
  const [reportId, setReportId] = useState(null)
  const [isReady, setIsReady] = useState(false)
  const [pdfUrl, setPdfUrl] = useState(null)
  const [pdfError, setPdfError] = useState(false)
  const settings = useSettings()

  useEffect(() => {
    if (router.isReady) {
      setReportId(router.query.id || null)
      setIsReady(true)
    }
  }, [router.isReady, router.query.id])

  const reportApi = ApiGetCall({
    url: '/api/ListGeneratedReports?tenantFilter=' + settings.currentTenant,
    data: { ReportGUID: reportId },
    queryKey: `ListGeneratedReports-${reportId}`,
    waiting: !!reportId,
  })

  const report = useMemo(() => {
    if (!reportApi.data) return null
    const list = Array.isArray(reportApi.data) ? reportApi.data : []
    return list.length > 0 ? list[0] : null
  }, [reportApi.data])

  const reportName = report?.TemplateName || 'Generated Report'
  const tenantName = report?.TenantFilter || 'Organization'
  const hasPdf = report?.HasPdf === true

  // Fetch the finished PDF once and keep the object URL for both the iframe and the download.
  useEffect(() => {
    if (!reportId || !hasPdf) return undefined
    let objectUrl
    let cancelled = false
    setPdfError(false)
    fetch(`/api/ExecGetReportBuilderPdf?id=${encodeURIComponent(reportId)}`, {
      credentials: 'same-origin',
    })
      .then((res) =>
        res.ok ? res.blob() : Promise.reject(new Error('Failed to load PDF'))
      )
      .then((blob) => {
        if (cancelled) return
        objectUrl = URL.createObjectURL(blob)
        setPdfUrl(objectUrl)
      })
      .catch(() => {
        if (!cancelled) setPdfError(true)
      })
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [reportId, hasPdf])

  const handleDownload = () => {
    if (!pdfUrl) return
    const link = document.createElement('a')
    link.href = pdfUrl
    link.download = `Report_${(tenantName || 'report').replace(/[^a-zA-Z0-9]/g, '_')}_${new Date().toISOString().split('T')[0]}.pdf`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  const handleBackClick = () => {
    router.push('/tools/report-builder/generated')
  }

  if (!isReady || reportApi.isFetching) {
    return (
      <Box sx={{ flexGrow: 1 }}>
        <Container maxWidth={false}>
          <Stack spacing={2}>
            <Stack
              direction="row"
              sx={{ justifyContent: 'space-between', alignItems: 'center' }}
            >
              <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                <Skeleton variant="circular" width={32} height={32} />
                <Skeleton variant="text" width={250} height={40} />
              </Stack>
              <Skeleton variant="rounded" width={140} height={36} />
            </Stack>
            <Divider />
            <Box sx={{ height: 'calc(100vh - 220px)', minHeight: 500 }}>
              <Card sx={{ height: '100%' }}>
                <CardContent>
                  <Stack spacing={2}>
                    <Skeleton variant="text" width="60%" height={32} />
                    <Skeleton variant="text" width="40%" height={24} />
                    <Skeleton variant="rounded" width="100%" height={200} />
                    <Skeleton variant="text" width="80%" />
                    <Skeleton variant="text" width="90%" />
                    <Skeleton variant="rounded" width="100%" height={150} />
                  </Stack>
                </CardContent>
              </Card>
            </Box>
          </Stack>
        </Container>
      </Box>
    )
  }

  if (!reportId) {
    return <div>Report ID is required</div>
  }

  return (
    <Box sx={{ flexGrow: 1 }}>
      <Container maxWidth={false}>
        <Stack spacing={2}>
          <Stack
            direction="row"
            sx={{ justifyContent: 'space-between', alignItems: 'center' }}
          >
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
              <IconButton size="small" onClick={handleBackClick}>
                <CippIcons.ArrowBack />
              </IconButton>
              <Typography variant="h4">{reportName}</Typography>
            </Stack>
            <Button
              variant="contained"
              startIcon={<CippIcons.Download />}
              onClick={handleDownload}
              disabled={!pdfUrl}
            >
              Download PDF
            </Button>
          </Stack>
          <Divider />
          <Box sx={{ height: 'calc(100vh - 220px)', minHeight: 500 }}>
            {!report ? (
              <Typography sx={{ color: 'text.secondary' }}>
                Report not found. It may have been deleted.
              </Typography>
            ) : !hasPdf ? (
              <Typography sx={{ color: 'text.secondary' }}>
                This report has no rendered PDF. Regenerate it to produce one.
              </Typography>
            ) : pdfError ? (
              <Typography sx={{ color: 'error.main' }}>
                The report PDF could not be loaded.
              </Typography>
            ) : pdfUrl ? (
              <iframe
                src={pdfUrl}
                title="Report preview"
                style={{ width: '100%', height: '100%', border: 'none' }}
              />
            ) : (
              <Skeleton variant="rounded" width="100%" height="100%" />
            )}
          </Box>
        </Stack>
      </Container>
    </Box>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
