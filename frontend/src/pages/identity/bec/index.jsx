import { useMemo, useState } from 'react'
import { useRouter } from 'next/router'
import { useForm } from 'react-hook-form'
import {
  Button,
  Stack,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { CippOffCanvas } from '../../../components/CippComponents/CippOffCanvas'
import CippFormComponent from '../../../components/CippComponents/CippFormComponent'
import { CippApiResults } from '../../../components/CippComponents/CippApiResults'
import { useBecEvidenceDownload } from '../../../components/CippComponents/CippBecEvidenceDownload'
import { CippIcons } from '../../../utils/icon-registry'
import { ApiGetCall, ApiPostCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'

// Quick action: pick one or more users and queue a BEC investigation for each. Runs land in the
// table below; each is its own case.
const StartInvestigationDrawer = ({ tenant }) => {
  const router = useRouter()
  const [visible, setVisible] = useState(false)
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: { users: [] },
  })
  const queue = ApiPostCall({ relatedQueryKeys: [`ListBECReports-${tenant}`] })

  const handleStart = () => {
    const users = formControl.getValues('users') || []
    const ids = users.map((u) => u?.value ?? u).filter(Boolean)
    if (ids.length === 0) return
    // One user: open its case workspace and start the run there, so you watch it run.
    if (ids.length === 1) {
      setVisible(false)
      router.push(
        `/identity/bec/case?userId=${encodeURIComponent(ids[0])}&tenantFilter=${encodeURIComponent(
          tenant
        )}&start=true`
      )
      return
    }
    // Several users: queue one run each; they appear in the table as they finish.
    queue.mutate({
      url: '/api/ExecBECBulkCheck',
      data: { tenantFilter: tenant, UserIds: ids },
    })
  }

  return (
    <>
      <Button
        variant="contained"
        startIcon={<CippIcons.TravelExplore />}
        onClick={() => setVisible(true)}
      >
        Start investigation
      </Button>
      <CippOffCanvas
        title="Start a BEC investigation"
        visible={visible}
        onClose={() => setVisible(false)}
        size="md"
        footer={
          <Stack spacing={2}>
            <CippApiResults apiObject={queue} />
            <Stack direction="row" spacing={1} justifyContent="flex-end">
              <Button
                variant="contained"
                onClick={handleStart}
                disabled={queue.isPending}
              >
                Start investigation
              </Button>
            </Stack>
          </Stack>
        }
      >
        <Stack spacing={2}>
          <Typography variant="body2" color="text.secondary">
            Pick one user to open its case workspace and watch the run, or
            several to queue a run for each (they appear in the table as they
            finish). Each run is kept as a case. Metadata only — no message
            content is read.
          </Typography>
          <CippFormComponent
            type="autoComplete"
            name="users"
            label="Users to investigate"
            formControl={formControl}
            multiple
            creatable={false}
            api={{
              url: '/api/ListUsers',
              data: { tenantFilter: tenant },
              labelField: (u) => `${u.displayName} (${u.userPrincipalName})`,
              valueField: 'id',
              queryKey: `ListUsers-${tenant}`,
            }}
          />
        </Stack>
      </CippOffCanvas>
    </>
  )
}

const Page = () => {
  const { currentTenant } = useSettings()
  const [viewMode, setViewMode] = useState('flat')
  const isByUser = viewMode === 'byUser'
  // Renders the report PDFs in-memory and exports, without opening the case.
  const { download } = useBecEvidenceDownload()

  // Grouped mode: the same runs reduced to one row per user (their worst recent level, run count and
  // latest run) and fed to the table via `data` with no apiUrl — the Standards page's grouping pattern.
  const groupedCall = ApiGetCall({
    url: '/api/ListBECReports',
    data: { tenantFilter: currentTenant },
    queryKey: `ListBECReports-${currentTenant}`,
    waiting: isByUser,
  })
  const groupedByUser = useMemo(() => {
    const runs = Array.isArray(groupedCall.data) ? groupedCall.data : []
    const rank = { High: 3, Medium: 2, Low: 1 }
    const when = (row) =>
      new Date(row?.ExtractedAt || row?.RequestedAt || 0).getTime() || 0
    const byUser = new Map()
    runs.forEach((run) => {
      const key = run.UserPrincipalName || run.UserId || 'unknown'
      if (!byUser.has(key)) byUser.set(key, [])
      byUser.get(key).push(run)
    })
    return [...byUser.values()]
      .map((list) => {
        const latest = [...list].sort((a, b) => when(b) - when(a))[0]
        const worst = [...list].sort(
          (a, b) => (rank[b.Level] || 0) - (rank[a.Level] || 0)
        )[0]
        return {
          ...latest,
          Level: worst?.Level ?? latest?.Level,
          RunCount: list.length,
        }
      })
      .sort(
        (a, b) =>
          (rank[b.Level] || 0) - (rank[a.Level] || 0) || when(b) - when(a)
      )
  }, [groupedCall.data])

  const modeToggle = (
    <ToggleButtonGroup
      key="mode"
      size="small"
      exclusive
      value={viewMode}
      onChange={(event, value) => value && setViewMode(value)}
    >
      <ToggleButton value="flat">All runs</ToggleButton>
      <ToggleButton value="byUser">By user</ToggleButton>
    </ToggleButtonGroup>
  )

  const actions = [
    {
      // Open in any state — a queued or running case shows live progress, a failed one its error.
      label: isByUser ? 'Open latest case' : 'Open case',
      icon: <CippIcons.Visibility />,
      link: '/identity/bec/case?userId=[UserId]&caseId=[CaseId]&tenantFilter=[Tenant]',
      multiPost: false,
    },
    {
      // Renders both report PDFs in the browser and bundles them into the package, then downloads it
      // with a case-named file. The server GET path cannot include the PDFs, so this is client-driven.
      label: 'Download evidence (ZIP, with PDFs)',
      icon: <CippIcons.Archive />,
      noConfirm: true,
      customFunction: (row) => download(row),
      condition: (row) => row.Status === 'Completed',
    },
    // Deleting one run only makes sense on an actual run, not a per-user rollup.
    ...(isByUser
      ? []
      : [
          {
            label: 'Delete run',
            icon: <CippIcons.DeleteForever />,
            type: 'POST',
            url: '/api/ExecBECReport',
            data: {
              Action: '!Delete',
              caseId: 'CaseId',
              tenantFilter: 'Tenant',
            },
            confirmText:
              'Delete run [CaseId] for [UserPrincipalName] permanently, including its results and evidence package?',
            multiPost: false,
          },
        ]),
  ]

  const offCanvas = {
    extendedInfoFields: [
      'CaseId',
      'Tenant',
      'UserPrincipalName',
      'DisplayName',
      'Status',
      'Level',
      'Score',
      ...(isByUser ? ['RunCount'] : ['IncompleteCount']),
      'ExtractedAt',
      'RequestedAt',
      'RequestedBy',
      'ContainmentRuns',
      'HasEvidence',
      'EvidenceSha256',
      'EvidenceCreatedAt',
      'ErrorMessage',
    ],
    actions: actions,
  }

  return (
    <CippTablePage
      key={viewMode}
      title="Business Email Compromise"
      apiUrl={isByUser ? undefined : '/api/ListBECReports'}
      data={isByUser ? groupedByUser : undefined}
      queryKey={`ListBECReports-${currentTenant}`}
      actions={actions}
      offCanvas={offCanvas}
      cardButton={[
        modeToggle,
        <StartInvestigationDrawer key="start" tenant={currentTenant} />,
      ]}
      simpleColumns={
        isByUser
          ? [
              'Tenant',
              'UserPrincipalName',
              'Level',
              'Score',
              'RunCount',
              'Status',
              'ExtractedAt',
              'CaseId',
            ]
          : [
              'Tenant',
              'UserPrincipalName',
              'Level',
              'Score',
              'Status',
              'ExtractedAt',
              'RequestedBy',
              'ContainmentRuns',
              'HasEvidence',
              'CaseId',
            ]
      }
      filters={
        isByUser
          ? []
          : [
              {
                filterName: 'High threat level',
                value: [{ id: 'Level', value: 'High' }],
                type: 'column',
              },
              {
                filterName: 'Completed runs',
                value: [{ id: 'Status', value: 'Completed' }],
                type: 'column',
              },
            ]
      }
    />
  )
}

Page.getLayout = (page) => (
  <DashboardLayout allTenantsSupport={true}>{page}</DashboardLayout>
)

export default Page
