import { useMemo } from 'react'
import { CippIcons } from '../../../../utils/icon-registry'
import {
  Card,
  CardContent,
  CardHeader,
  Chip,
  Divider,
  LinearProgress,
  Skeleton,
  Stack,
  Typography,
} from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { Box, Container, Grid } from '@mui/system'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { TabbedLayout } from '../../../../layouts/TabbedLayout'
import { CippHead } from '../../../../components/CippComponents/CippHead'
import { CippTimeAgo } from '../../../../components/CippComponents/CippTimeAgo'
import { CippDataTable } from '../../../../components/CippTable/CippDataTable'
import {
  auditLogFeedFilters,
  auditLogFeedLogs,
  auditLogFeedOffCanvas,
} from '../../../../components/CippComponents/CippAuditLogFeedDetails'
import { CippInfoBar } from '../../../../components/CippCards/CippInfoBar'
import { Chart } from '../../../../components/chart'
import tabOptions from './tabOptions.json'
import { useSettings } from '../../../../hooks/use-settings'
import { ApiGetCall } from '../../../../api/ApiCall'

const hours = 48

// Two series per chart at most, checked for colour-blind separation and contrast on each surface.
const seriesColors = {
  light: ['#F77F00', '#635dff'],
  dark: ['#D96C00', '#7C77FF'],
}

const attentionColumns = [
  'Tenant',
  'Log',
  'Status',
  'Problem',
  'WhatToDo',
  'DelayMinutes',
  'CheckedUpToDateTime',
  'NextTryDateTime',
]

const checkColumns = [
  'StartedDateTime',
  'TookSeconds',
  'TenantsChecked',
  'RecordsRead',
  'RecordsChecked',
  'AlertsSent',
  'RepeatedActivityAlerts',
  'BatchesDownloaded',
  'BatchesFailed',
  'Workers',
  'LongestWorkerSeconds',
]

const repeatedActivityColumns = [
  'Timestamp',
  'Tenant',
  'User',
  'Operation',
  'TimesRepeated',
  'Title',
]

const sum = (rows, field) =>
  rows.reduce((total, row) => total + (Number(row[field]) || 0), 0)

const median = (values) => {
  const sorted = values.filter((v) => v != null).sort((a, b) => a - b)
  return sorted.length ? sorted[Math.floor(sorted.length / 2)] : null
}

const formatDelay = (minutes) => {
  if (minutes == null) return '—'
  if (minutes < 120) return `${minutes} minutes`
  if (minutes < 2880) return `${Math.round(minutes / 60)} hours`
  return `${Math.round(minutes / 1440)} days`
}

// A log's overall state as a chip: icon and words, never colour alone.
const logHealth = (rows) => {
  const count = (status) => rows.filter((r) => r.Status === status).length
  const errors = count('Error, retrying')
  const delayed = count('Delayed')
  const waiting = count('Waiting to start')
  if (rows.length === 0)
    return {
      label: 'Not in use',
      color: 'default',
      icon: <CippIcons.InfoOutlined />,
    }
  if (errors > 0)
    return {
      label: `${errors} with an error`,
      color: 'error',
      icon: <CippIcons.Error />,
    }
  if (delayed > 0 || waiting > 0)
    return {
      label: [
        delayed && `${delayed} delayed`,
        waiting && `${waiting} waiting to start`,
      ]
        .filter(Boolean)
        .join(', '),
      color: 'warning',
      icon: <CippIcons.Warning />,
    }
  if (count('Up to date') === 0)
    return {
      label: 'Unavailable',
      color: 'default',
      icon: <CippIcons.InfoOutlined />,
    }
  return {
    label: 'Up to date',
    color: 'success',
    icon: <CippIcons.CheckCircle />,
  }
}

const Stat = ({ label, value }) => (
  <Stack direction="row" sx={{ justifyContent: 'space-between' }}>
    <Typography variant="body2" sx={{ color: 'text.secondary' }}>
      {label}
    </Typography>
    <Typography variant="body2" sx={{ fontWeight: 600 }}>
      {value}
    </Typography>
  </Stack>
)

const LogCard = ({ log, rows, isFetching }) => {
  const upToDate = rows.filter((r) => r.Status === 'Up to date')
  const delays = rows.map((r) => r.DelayMinutes).filter((v) => v != null)
  const health = logHealth(rows)
  const lastCollected = rows
    .map((r) => r.LastCollectedDateTime)
    .filter(Boolean)
    .sort()
    .pop()
  return (
    <Card sx={{ height: '100%' }}>
      <CardHeader title={log} />
      <Divider />
      <CardContent>
        {isFetching ? (
          <Skeleton variant="rounded" sx={{ height: 180 }} />
        ) : (
          <Stack spacing={1}>
            <Chip
              size="small"
              variant="outlined"
              icon={health.icon}
              label={health.label}
              color={health.color}
              sx={{ alignSelf: 'flex-start' }}
            />
            <Stack spacing={0.5}>
              <Stat
                label="Tenants up to date"
                value={`${upToDate.length} of ${rows.length}`}
              />
              <LinearProgress
                variant="determinate"
                color={health.color === 'default' ? 'inherit' : health.color}
                value={rows.length ? (upToDate.length / rows.length) * 100 : 0}
                aria-label={`${upToDate.length} of ${rows.length} tenants up to date`}
              />
            </Stack>
            <Stat
              label="Usual delay"
              value={formatDelay(median(upToDate.map((r) => r.DelayMinutes)))}
            />
            <Stat
              label="Longest delay"
              value={formatDelay(delays.length ? Math.max(...delays) : null)}
            />
            <Stat
              label="With an error"
              value={rows.filter((r) => r.Status === 'Error, retrying').length}
            />
            <Stat
              label="Waiting to start"
              value={rows.filter((r) => r.Status === 'Waiting to start').length}
            />
            <Stat
              label="Audit log unavailable"
              value={rows.filter((r) => r.Status === 'Unavailable').length}
            />
            <Stat
              label="Last collected"
              value={lastCollected ? <CippTimeAgo data={lastCollected} /> : '—'}
            />
          </Stack>
        )}
      </CardContent>
    </Card>
  )
}

const TrendCard = ({ title, subheader, isFetching, empty, children }) => (
  <Card sx={{ height: '100%' }}>
    <CardHeader title={title} subheader={subheader} />
    <Divider />
    <CardContent>
      {isFetching ? (
        <Skeleton variant="rounded" sx={{ height: 260 }} />
      ) : empty ? (
        <Typography
          sx={{ color: 'text.secondary', py: 6, textAlign: 'center' }}
        >
          No checks in the last {hours} hours.
        </Typography>
      ) : (
        children
      )}
    </CardContent>
  </Card>
)

const Page = () => {
  const theme = useTheme()
  const tenant = useSettings().currentTenant
  const colors = seriesColors[theme.palette.mode] ?? seriesColors.light

  const statusQuery = ApiGetCall({
    url: '/api/ListAuditLogFeedStatus',
    data: { tenantFilter: tenant },
    queryKey: `AuditLogFeedStatus-${tenant}`,
    waiting: !!tenant,
  })
  const checksQuery = ApiGetCall({
    url: '/api/ListAuditLogFeedCycles',
    data: { Hours: hours },
    queryKey: `AuditLogFeedCycles-${hours}`,
  })

  const rows = useMemo(
    () => (Array.isArray(statusQuery.data) ? statusQuery.data : []),
    [statusQuery.data]
  )
  const checks = useMemo(
    () => (Array.isArray(checksQuery.data) ? checksQuery.data : []),
    [checksQuery.data]
  )
  const attention = useMemo(
    () =>
      rows.filter(
        (r) =>
          !['Up to date', 'Unavailable'].includes(r.Status) ||
          Number(r.BatchesFailing) > 0
      ),
    [rows]
  )
  const problems = useMemo(() => {
    const counts = {}
    attention.forEach((r) => {
      if (r.Problem) counts[r.Problem] = (counts[r.Problem] ?? 0) + 1
    })
    return Object.entries(counts).sort((a, b) => b[1] - a[1])
  }, [attention])

  const kpis = useMemo(() => {
    const upToDate = rows.filter((r) => r.Status === 'Up to date').length
    const last = checks[0]
    return [
      {
        icon: <CippIcons.CheckCircle />,
        data: `${upToDate} of ${rows.length}`,
        name: 'Logs up to date',
        color: rows.length && upToDate === rows.length ? 'success' : 'warning',
        toolTip:
          'Each tenant has up to four logs (Entra ID, Exchange, SharePoint and OneDrive, General). Up to date means alerts are no more than an hour behind.',
      },
      {
        icon: <CippIcons.Warning />,
        data: attention.length,
        name: 'Need attention',
        color: attention.length > 0 ? 'warning' : 'success',
        toolTip:
          'Logs with an error, running behind or waiting to start. Listed below with what to do.',
        link: '/tenant/administration/audit-logs/collection',
      },
      {
        icon: <CippIcons.Schedule />,
        data: last ? <CippTimeAgo data={last.StartedDateTime} /> : '—',
        name: 'Last check',
        color: 'secondary',
        toolTip: last
          ? `Took ${Math.round(last.TookSeconds)} seconds and read ${last.RecordsRead} records from ${last.TenantsChecked} tenants. CIPP checks every 30 minutes.`
          : `No check in the last ${hours} hours`,
      },
      {
        icon: <CippIcons.BoltIcon />,
        data: sum(checks, 'AlertsSent'),
        name: `Alerts sent, last ${hours} hours`,
        color: 'secondary',
        toolTip: `${sum(checks, 'RecordsRead')} audit records read, ${sum(checks, 'RepeatedActivityAlerts')} repeated activity alerts`,
      },
    ]
  }, [rows, checks, attention])

  // Oldest first, as [time, value] points on a time axis shown in the browser's own time zone.
  const points = (field) =>
    [...checks]
      .reverse()
      .map((c) => [
        new Date(c.StartedDateTime).getTime(),
        Number(c[field]) || 0,
      ])

  const chartOptions = (
    unit,
    type,
    { stacked = false, legend = false } = {}
  ) => ({
    chart: {
      type,
      stacked,
      background: 'transparent',
      toolbar: { show: false },
      zoom: { enabled: false },
    },
    theme: { mode: theme.palette.mode },
    colors,
    dataLabels: { enabled: false },
    stroke: { curve: 'straight', width: type === 'area' ? 2 : 0 },
    fill:
      type === 'area'
        ? { type: 'gradient', gradient: { opacityFrom: 0.35, opacityTo: 0.05 } }
        : { opacity: 1 },
    plotOptions: { bar: { columnWidth: '70%', borderRadius: 2 } },
    legend: { show: legend, position: 'top', horizontalAlign: 'left' },
    grid: { borderColor: theme.palette.divider, strokeDashArray: 3 },
    xaxis: {
      type: 'datetime',
      labels: {
        datetimeUTC: false,
        style: { colors: theme.palette.text.secondary },
      },
      axisTicks: { show: false },
    },
    yaxis: {
      min: 0,
      forceNiceScale: true,
      labels: {
        formatter: (v) => Math.round(v).toLocaleString(),
        style: { colors: theme.palette.text.secondary },
      },
    },
    tooltip: {
      shared: true,
      intersect: false,
      x: { format: 'dd MMM HH:mm' },
      y: { formatter: (v) => `${Math.round(v).toLocaleString()} ${unit}` },
    },
  })

  return (
    <>
      <CippHead title="Audit Log Diagnostics" />
      <Box sx={{ p: 3 }}>
        <Container maxWidth={false}>
          <Stack spacing={3}>
            <Typography variant="body2" sx={{ color: 'text.secondary' }}>
              Every 30 minutes CIPP collects each tenant&apos;s audit logs from
              Microsoft and checks them against your audit log alerts. This page
              shows whether that is keeping up, and what to fix when it is not.
            </Typography>

            <CippInfoBar
              data={kpis}
              isFetching={statusQuery.isFetching || checksQuery.isFetching}
            />

            <Grid container spacing={3}>
              {auditLogFeedLogs.map((log) => (
                <Grid key={log} size={{ xs: 12, sm: 6, lg: 3 }}>
                  <LogCard
                    log={log}
                    rows={rows.filter((r) => r.Log === log)}
                    isFetching={statusQuery.isFetching}
                  />
                </Grid>
              ))}
            </Grid>

            <CippDataTable
              title="Logs needing attention"
              data={attention}
              simpleColumns={attentionColumns}
              offCanvas={auditLogFeedOffCanvas}
              filters={auditLogFeedFilters}
              defaultSorting={[{ id: 'DelayMinutes', desc: true }]}
              isFetching={statusQuery.isFetching}
              refreshFunction={statusQuery.refetch}
              cardButton={
                problems.length > 0 && (
                  <Stack
                    direction="row"
                    spacing={1}
                    useFlexGap
                    sx={{ flexWrap: 'wrap' }}
                  >
                    {problems.map(([problem, count]) => (
                      <Chip
                        key={problem}
                        size="small"
                        variant="outlined"
                        color="warning"
                        icon={<CippIcons.Warning />}
                        label={`${problem}: ${count}`}
                      />
                    ))}
                  </Stack>
                )
              }
            />

            <Grid container spacing={3}>
              <Grid size={{ xs: 12, lg: 4 }}>
                <TrendCard
                  title="Audit records read"
                  subheader="Records collected from Microsoft at each check"
                  isFetching={checksQuery.isFetching}
                  empty={checks.length === 0}
                >
                  <Chart
                    type="area"
                    height={260}
                    series={[
                      { name: 'Records read', data: points('RecordsRead') },
                    ]}
                    options={chartOptions('records', 'area')}
                  />
                </TrendCard>
              </Grid>
              <Grid size={{ xs: 12, lg: 4 }}>
                <TrendCard
                  title="Alerts sent"
                  subheader="By single event, or by repeated activity from one user or app"
                  isFetching={checksQuery.isFetching}
                  empty={checks.length === 0}
                >
                  <Chart
                    type="bar"
                    height={260}
                    series={[
                      {
                        name: 'Single event',
                        data: points('AlertsSent').map(([t, v], i) => [
                          t,
                          Math.max(
                            0,
                            v - points('RepeatedActivityAlerts')[i][1]
                          ),
                        ]),
                      },
                      {
                        name: 'Repeated activity',
                        data: points('RepeatedActivityAlerts'),
                      },
                    ]}
                    options={chartOptions('alerts', 'bar', {
                      stacked: true,
                      legend: true,
                    })}
                  />
                </TrendCard>
              </Grid>
              <Grid size={{ xs: 12, lg: 4 }}>
                <TrendCard
                  title="Time each check took"
                  subheader="A check must finish within 10 minutes"
                  isFetching={checksQuery.isFetching}
                  empty={checks.length === 0}
                >
                  <Chart
                    type="area"
                    height={260}
                    series={[{ name: 'Took', data: points('TookSeconds') }]}
                    options={chartOptions('seconds', 'area')}
                  />
                </TrendCard>
              </Grid>
            </Grid>

            <CippDataTable
              title={`Repeated activity alerts, last ${hours} hours`}
              defaultSorting={[{ id: 'Timestamp', desc: true }]}
              api={{
                url: '/api/ListAuditLogs',
                data: {
                  tenantFilter: tenant,
                  Kind: 'Threshold',
                  RelativeTime: `${hours}h`,
                },
                dataKey: 'Results',
              }}
              simpleColumns={repeatedActivityColumns}
              queryKey={`AuditLogRepeatedActivity-${tenant}-${hours}`}
            />

            {!checksQuery.isError && (
              <CippDataTable
                title={`Checks, last ${hours} hours`}
                data={checks}
                simpleColumns={checkColumns}
                defaultSorting={[{ id: 'StartedDateTime', desc: true }]}
                isFetching={checksQuery.isFetching}
                refreshFunction={checksQuery.refetch}
              />
            )}
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
