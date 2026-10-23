import { useMemo } from 'react'
import { CippIcons } from '../../../../utils/icon-registry'
import {
  Card,
  CardContent,
  CardHeader,
  Divider,
  Skeleton,
  Stack,
  Typography,
} from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { Box, Container } from '@mui/system'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { TabbedLayout } from '../../../../layouts/TabbedLayout'
import { CippHead } from '../../../../components/CippComponents/CippHead'
import { CippDataTable } from '../../../../components/CippTable/CippDataTable'
import { CippInfoBar } from '../../../../components/CippCards/CippInfoBar'
import { Chart } from '../../../../components/chart'
import tabOptions from './tabOptions.json'
import { useSettings } from '../../../../hooks/use-settings'
import { ApiGetCall } from '../../../../api/ApiCall'

const statusColumns = [
  'Tenant',
  'ContentType',
  'Status',
  'CoveredUntil',
  'LagMinutes',
  'LastSuccessUtc',
  'NextAttemptUtc',
  'Records',
  'Stored',
  'LastError',
]

const cycleColumns = [
  'StartedUtc',
  'FeedSeconds',
  'ProcessingSeconds',
  'Tenants',
  'Records',
  'Stored',
  'Alerts',
  'Failed',
  'Parked',
]

const TenantFeedDetail = ({ row }) => {
  const windowsQuery = ApiGetCall({
    url: '/api/ListAuditLogCoverage',
    data: { tenantFilter: row.Tenant, RelativeTime: '7d' },
    queryKey: `AuditLogFeedWindows-${row.Tenant}`,
  })
  const windows = (windowsQuery.data?.Results ?? []).filter(
    (w) => w.Type === 'Feed'
  )

  return (
    <Stack spacing={2} sx={{ mt: 2 }}>
      <CippDataTable
        title="Feed windows (7 days)"
        data={windows}
        simpleColumns={[
          'WindowStart',
          'WindowEnd',
          'State',
          'RecordCount',
          'MatchedCount',
          'DownloadedUtc',
          'ProcessedUtc',
          'LastError',
        ]}
        isFetching={windowsQuery.isFetching}
        refreshFunction={windowsQuery.refetch}
      />
      <CippDataTable
        title="Feed logs (7 days)"
        api={{
          url: `/api/ListLogs?Filter=true&API=AuditLogFeedV3&Tenant=${row.Tenant}&Days=7`,
        }}
        simpleColumns={['DateTime', 'Severity', 'Message']}
        queryKey={`AuditLogFeedLogs-${row.Tenant}`}
      />
    </Stack>
  )
}

const offCanvas = {
  size: 'lg',
  extendedInfoFields: [
    'Tenant',
    'ContentType',
    'Status',
    'CoveredUntil',
    'LagMinutes',
    'LastPolledUtc',
    'LastSuccessUtc',
    'NextAttemptUtc',
    'Attempts',
    'LastErrorCode',
    'LastError',
    'LastErrorUtc',
    'SubscriptionStartedUtc',
    'Blobs',
    'Records',
    'Stored',
  ],
  children: (row) => <TenantFeedDetail row={row} />,
}

const median = (values) => {
  const sorted = values.filter((v) => v != null).sort((a, b) => a - b)
  return sorted.length ? sorted[Math.floor(sorted.length / 2)] : null
}

const Page = () => {
  const theme = useTheme()
  const tenant = useSettings().currentTenant
  const hours = 48

  const statusQuery = ApiGetCall({
    url: '/api/ListAuditLogFeedStatus',
    data: { tenantFilter: tenant },
    queryKey: `AuditLogFeedStatus-${tenant}`,
    waiting: !!tenant,
  })
  const cyclesQuery = ApiGetCall({
    url: '/api/ListAuditLogFeedCycles',
    data: { Hours: hours },
    queryKey: `AuditLogFeedCycles-${hours}`,
  })

  const rows = useMemo(
    () => (Array.isArray(statusQuery.data) ? statusQuery.data : []),
    [statusQuery.data]
  )
  const cycles = useMemo(
    () => (Array.isArray(cyclesQuery.data) ? cyclesQuery.data : []),
    [cyclesQuery.data]
  )

  const kpis = useMemo(() => {
    const count = (status) => rows.filter((r) => r.Status === status).length
    const healthy = count('Healthy')
    const attention = count('Behind') + count('Backing off')
    const lag = median(
      rows.filter((r) => r.Status === 'Healthy').map((r) => r.LagMinutes)
    )
    return [
      {
        icon: <CippIcons.ShieldCheckIcon />,
        data: `${healthy}/${rows.length}`,
        name: 'Healthy feeds',
        color: rows.length && healthy === rows.length ? 'success' : 'warning',
        toolTip: 'Tenant and content type pairs read within the last hour',
      },
      {
        icon: <CippIcons.ClockIcon />,
        data: lag != null ? `${lag}m` : '—',
        name: 'Median lag',
        color: 'secondary',
        toolTip:
          'Median minutes between now and the end of what healthy feeds have read',
      },
      {
        icon: <CippIcons.ExclamationTriangleIcon />,
        data: attention,
        name: 'Behind or backing off',
        color: attention > 0 ? 'error' : 'success',
        toolTip: `${count('Behind')} behind · ${count('Backing off')} backing off after an error · ${count('Not started')} not started`,
      },
      {
        icon: <CippIcons.BoltIcon />,
        data: count('Parked'),
        name: 'Parked',
        color: 'secondary',
        toolTip:
          'No audit log to read (audit logging off or no licence); checked once a day',
      },
    ]
  }, [rows])

  const cycleChart = useMemo(() => {
    if (cycles.length === 0) return null
    const ordered = [...cycles].reverse()
    return {
      series: [
        { name: 'Feed', data: ordered.map((c) => c.FeedSeconds ?? 0) },
        {
          name: 'Processing',
          data: ordered.map((c) => c.ProcessingSeconds ?? 0),
        },
      ],
      options: {
        chart: {
          type: 'bar',
          stacked: true,
          background: 'transparent',
          toolbar: { show: false },
        },
        theme: { mode: theme.palette.mode },
        colors: [theme.palette.primary.main, theme.palette.success.main],
        dataLabels: { enabled: false },
        xaxis: {
          categories: ordered.map((c) =>
            new Date(c.StartedUtc).toLocaleString([], {
              month: '2-digit',
              day: '2-digit',
              hour: '2-digit',
              minute: '2-digit',
            })
          ),
          tickAmount: Math.min(12, ordered.length),
          labels: {
            rotate: -45,
            hideOverlappingLabels: true,
            style: { fontSize: '10px' },
          },
        },
        yaxis: {
          min: 0,
          title: { text: 'Seconds' },
          labels: { formatter: (v) => Math.round(v) },
        },
        legend: { show: true, position: 'top' },
        grid: { borderColor: theme.palette.divider },
        tooltip: { y: { formatter: (v) => `${v}s` } },
      },
    }
  }, [cycles, theme])

  return (
    <>
      <CippHead title="Feed Status" />
      <Box sx={{ p: 3 }}>
        <Container maxWidth={false}>
          <Stack spacing={2}>
            <CippInfoBar data={kpis} isFetching={statusQuery.isFetching} />

            {!cyclesQuery.isError && (
              <Card>
                <CardHeader
                  title="Polling cycles"
                  subheader={`Feed and processing time per timer tick, last ${hours} hours`}
                />
                <Divider />
                <CardContent>
                  {cyclesQuery.isFetching ? (
                    <Skeleton variant="rounded" sx={{ height: 300 }} />
                  ) : cycleChart ? (
                    <Chart
                      options={cycleChart.options}
                      series={cycleChart.series}
                      type="bar"
                      height={300}
                    />
                  ) : (
                    <Typography
                      sx={{
                        color: 'text.secondary',
                        py: 6,
                        textAlign: 'center',
                      }}
                    >
                      No polling cycles in this period.
                    </Typography>
                  )}
                </CardContent>
              </Card>
            )}

            {!cyclesQuery.isError && (
              <CippDataTable
                title="Cycles"
                data={cycles}
                simpleColumns={cycleColumns}
                isFetching={cyclesQuery.isFetching}
                refreshFunction={cyclesQuery.refetch}
              />
            )}

            <CippDataTable
              title={tenant ? `Feed Status - ${tenant}` : 'Feed Status'}
              data={rows}
              simpleColumns={statusColumns}
              offCanvas={offCanvas}
              isFetching={statusQuery.isFetching}
              refreshFunction={statusQuery.refetch}
              filters={[
                'Healthy',
                'Behind',
                'Backing off',
                'Parked',
                'Not started',
              ].map((s) => ({
                filterName: s,
                value: [{ id: 'Status', value: s }],
                type: 'column',
              }))}
            />
          </Stack>
        </Container>
      </Box>
    </>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
)

export default Page
