import { useEffect, useMemo, useState } from 'react'
import { useForm, useWatch } from 'react-hook-form'
import {
  Alert,
  Box,
  Breadcrumbs,
  Button,
  Card,
  CardContent,
  CardHeader,
  Checkbox,
  Container,
  Grid,
  Link,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Stack,
  Typography,
} from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import { CippPropertyListCard } from '../../../components/CippCards/CippPropertyListCard'
import CippFormComponent from '../../../components/CippComponents/CippFormComponent'
import { CippApiDialog } from '../../../components/CippComponents/CippApiDialog'
import { CippApiResults } from '../../../components/CippComponents/CippApiResults'
import { CippCloudBackupJobStatus } from '../../../components/CippComponents/CippCloudBackupJobStatus'
import {
  CippCloudBackupExportDownload,
  CippCloudBackupJobResults,
} from '../../../components/CippComponents/CippCloudBackupJobResults'
import { ApiGetCall, ApiPostCall } from '../../../api/ApiCall'
import { useDialog } from '../../../hooks/use-dialog'
import { usePermissions } from '../../../hooks/use-permissions'
import { useSettings } from '../../../hooks/use-settings'
import { useCloudBackupJob } from '../../../hooks/use-cloud-backup-job'
import { useCloudBackupDownload } from '../../../hooks/use-cloud-backup-download'
import { getCippFormatting } from '../../../utils/get-cipp-formatting'
import { isMultiTenant } from '../../../utils/tenant-selection'
import { formatBytes } from '../../../utils/instance-diagnostics'
import { CippIcons } from '../../../utils/icon-registry'
import {
  CLOUD_BACKUP_CONFLICT_ACTIONS,
  CLOUD_BACKUP_RESTORE_LOCATIONS,
  CLOUD_BACKUP_RESTORE_PERMISSION,
  cloudBackupCanRestore,
  cloudBackupItemTypes,
  cloudBackupJobCounts,
  cloudBackupJobSummary,
  cloudBackupOptionValue,
  cloudBackupOwnerLabel,
  cloudBackupPolicyWorkloads,
  cloudBackupRecoveryPoints,
  cloudBackupRestoreCount,
  cloudBackupSelectionSummary,
  cloudBackupWorkloadLabel,
  formatCloudBackupSelection,
  parseCloudBackupList,
  parseCloudBackupListing,
  parseCloudBackupObject,
  toCloudBackupItemRow,
} from '../../../utils/cloud-backup'

const PAGE_SIZE = 100
const FILE_WORKLOADS = ['onedrive', 'sharepoint']

const OWNER_NOUNS = {
  exchange: 'mailbox',
  onedrive: 'OneDrive',
  sharepoint: 'site',
  teams: 'team or chat user',
}

const EMPTY = []

const toTenantOption = (tenant) => ({
  label: tenant.displayName
    ? `${tenant.displayName} (${tenant.defaultDomainName})`
    : tenant.defaultDomainName,
  value: tenant.customerId,
  domain: tenant.defaultDomainName,
})

const policyCoversAllTenants = (policy) =>
  (policy?.Tenants ?? []).some(
    (tenant) => tenant?.value === 'AllTenants' || tenant?.type === 'Group'
  )

const policyTenantOptions = (policy) =>
  (policy?.Tenants ?? [])
    .filter((tenant) => tenant?.addedFields?.customerId)
    .map((tenant) => ({
      label: tenant.label,
      value: tenant.addedFields.customerId,
      domain: tenant.addedFields.defaultDomainName,
    }))

const userPicker = (tenant) => ({
  url: '/api/ListGraphRequest',
  tenantFilter: tenant,
  dataKey: 'Results',
  labelField: (user) => `${user.displayName} (${user.userPrincipalName})`,
  valueField: 'id',
  queryKey: `ListGraphRequest-cloudBackupRestore-users-${tenant}`,
  data: {
    Endpoint: 'users',
    manualPagination: true,
    $select: 'id,displayName,userPrincipalName',
    $count: true,
    $orderby: 'displayName',
    $top: 999,
  },
})

const toVersionRow = (version) => ({
  ...version,
  CloudBackupVersionAt: version.At,
  CloudBackupSize: version.Size,
  CloudBackupVersionState: version.Deleted
    ? 'Deleted in Microsoft 365'
    : 'Backed up',
})

const ItemDetails = ({ row, source, canDownload }) => {
  const { download, busy, error, progress } = useCloudBackupDownload()
  const request = ApiGetCall({
    url: '/api/ListCloudBackupItem',
    data: {
      ...source.params,
      Key: row.Key,
      AsOf: source.asOf,
    },
    queryKey: `ListCloudBackupItem-${source.params.OwnerId}-${source.asOf}-${row.Key}`,
  })
  const detail = parseCloudBackupObject(request.data)
  const entry = parseCloudBackupObject(detail.Item ?? detail)
  const extra = parseCloudBackupObject(entry.Extra ?? row.Extra)
  const versions = useMemo(
    () => parseCloudBackupList(detail.Versions).map(toVersionRow),
    [detail.Versions]
  )
  const fileName = row.CloudBackupItemName
  const downloadVersion = (versionId) =>
    download({ ...source.params, Key: row.Key, VersionId: versionId }, fileName)

  const mailItems =
    row.Type === 'message'
      ? [
          { label: 'From', value: extra.from || 'Unknown' },
          { label: 'To', value: extra.to || 'Unknown' },
          {
            label: 'Received',
            value: extra.received
              ? getCippFormatting(extra.received, 'CloudBackupModified')
              : 'Unknown',
          },
        ]
      : []

  return (
    <Stack spacing={2}>
      <CippPropertyListCard
        cardSx={{ p: 0, m: -2 }}
        title={row.CloudBackupItemName}
        isFetching={request.isFetching}
        propertyItems={[
          { label: 'Folder', value: row.CloudBackupItemFolder },
          { label: 'Type', value: row.CloudBackupItemType },
          ...mailItems,
          { label: 'Size', value: formatBytes(row.Size) },
          {
            label: 'Modified',
            value: row.Modified
              ? getCippFormatting(row.Modified, 'CloudBackupModified')
              : 'Unknown',
          },
        ]}
      />
      {canDownload ? (
        <Box>
          <Button
            variant="contained"
            startIcon={<CippIcons.Download />}
            disabled={busy || !row.VersionId}
            onClick={() => downloadVersion(row.VersionId)}
          >
            {busy
              ? progress
                ? `Downloading part ${progress.part} of ${progress.parts}…`
                : 'Downloading…'
              : 'Download'}
          </Button>
        </Box>
      ) : (
        <Alert severity="info">
          Downloading items needs the Cloud Backup restore permission.
        </Alert>
      )}
      {error && <Alert severity="error">{error}</Alert>}
      {request.isError && (
        <Alert severity="error">
          The earlier versions of this item could not be loaded.
        </Alert>
      )}
      <CippDataTable
        title="Earlier versions"
        queryKey={`CloudBackupItemVersions-${source.params.OwnerId}-${row.Key}`}
        data={versions}
        isFetching={request.isFetching}
        simpleColumns={[
          'CloudBackupVersionAt',
          'CloudBackupSize',
          'CloudBackupVersionState',
        ]}
        actions={
          canDownload
            ? [
                {
                  label: 'Download This Version',
                  icon: <CippIcons.Download />,
                  noConfirm: true,
                  customFunction: (version) =>
                    downloadVersion(version.VersionId),
                  condition: (version) =>
                    !version.Deleted && !!version.VersionId,
                },
              ]
            : undefined
        }
      />
    </Stack>
  )
}

const RestoreConfirmText = ({ targetName, counts }) => (
  <Stack spacing={2}>
    <Typography>
      Restore to <strong>{targetName}</strong>: {Number(counts.Create ?? 0)}{' '}
      new, {Number(counts.Overwrite ?? 0)} overwritten and{' '}
      {Number(counts.Copy ?? 0)} restored as copies. {Number(counts.Skip ?? 0)}{' '}
      skipped and {Number(counts.NotRestorable ?? 0)} cannot be restored.
    </Typography>
    <Typography variant="body2">
      Changes are made in Microsoft 365 straight away. CIPP does not undo them.
    </Typography>
  </Stack>
)

const FolderPath = ({ path, onOpen }) => {
  const segments = path ? path.split('/') : []
  return (
    <Breadcrumbs maxItems={6}>
      <Link
        component="button"
        type="button"
        underline="hover"
        onClick={() => onOpen('')}
      >
        All folders
      </Link>
      {segments.map((segment, index) => {
        const target = segments.slice(0, index + 1).join('/')
        return index === segments.length - 1 ? (
          <Typography key={target} color="text.primary">
            {segment}
          </Typography>
        ) : (
          <Link
            key={target}
            component="button"
            type="button"
            underline="hover"
            onClick={() => onOpen(target)}
          >
            {segment}
          </Link>
        )
      })}
    </Breadcrumbs>
  )
}

const Page = () => {
  const currentTenant = useSettings().currentTenant
  const selectedTenant = isMultiTenant(currentTenant) ? null : currentTenant
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: {
      PolicyId: null,
      TenantId: null,
      Workload: null,
      OwnerId: null,
      AsOf: null,
      Type: null,
      Search: '',
      SearchInFolder: false,
      DateFrom: null,
      DateTo: null,
      TargetMode: 'Original',
      TargetUser: null,
      Location: 'RestoredFolder',
      ConflictAction: 'Skip',
    },
  })
  const [
    policyField,
    tenantField,
    workloadField,
    ownerField,
    asOfField,
    typeField,
    searchInFolder,
    dateFrom,
    dateTo,
    targetMode,
    targetUser,
    location,
    conflictAction,
  ] = useWatch({
    control: formControl.control,
    name: [
      'PolicyId',
      'TenantId',
      'Workload',
      'OwnerId',
      'AsOf',
      'Type',
      'SearchInFolder',
      'DateFrom',
      'DateTo',
      'TargetMode',
      'TargetUser',
      'Location',
      'ConflictAction',
    ],
  })
  const policyId = cloudBackupOptionValue(policyField)
  const tenantId = cloudBackupOptionValue(tenantField)
  const workload = cloudBackupOptionValue(workloadField)
  const ownerId = cloudBackupOptionValue(ownerField)
  const asOf = cloudBackupOptionValue(asOfField)
  const itemType = cloudBackupOptionValue(typeField)

  const [path, setPath] = useState('')
  const [skip, setSkip] = useState(0)
  const [search, setSearch] = useState('')
  const [selectedItems, setSelectedItems] = useState(EMPTY)
  const [selectedFolders, setSelectedFolders] = useState(EMPTY)
  const [restoreOpen, setRestoreOpen] = useState(false)
  const [preview, setPreview] = useState(null)
  const [applyJobId, setApplyJobId] = useState(null)
  const [exportJobId, setExportJobId] = useState(null)
  const restoreDialog = useDialog()
  const exportDialog = useDialog()
  const { checkPermissions } = usePermissions()
  const canRestore = checkPermissions(CLOUD_BACKUP_RESTORE_PERMISSION)

  const clearSelection = () => {
    setSelectedItems(EMPTY)
    setSelectedFolders(EMPTY)
  }
  const resetBrowse = () => {
    setPath('')
    setSkip(0)
    setSearch('')
    formControl.setValue('Search', '')
    formControl.setValue('DateFrom', null)
    formControl.setValue('DateTo', null)
    clearSelection()
    setRestoreOpen(false)
    setPreview(null)
    setApplyJobId(null)
    setExportJobId(null)
  }

  useEffect(() => {
    formControl.setValue('PolicyId', null)
  }, [currentTenant, formControl])

  useEffect(() => {
    formControl.setValue(
      'TenantId',
      selectedTenant ? { label: selectedTenant, value: selectedTenant } : null
    )
    formControl.setValue('Workload', null)
  }, [policyId, selectedTenant, formControl])

  useEffect(() => {
    formControl.setValue('OwnerId', null)
    formControl.setValue('Type', null)
  }, [tenantId, workload, formControl])

  useEffect(() => {
    formControl.setValue('AsOf', null)
    formControl.setValue('TargetUser', null)
  }, [ownerId, formControl])

  useEffect(() => {
    resetBrowse()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ownerId, asOf])

  useEffect(() => {
    setSkip(0)
    setSelectedItems(EMPTY)
  }, [itemType, dateFrom, dateTo, searchInFolder])

  const policies = ApiGetCall({
    url: '/api/ListCloudBackupPolicies',
    data: { tenantFilter: currentTenant, InvalidateCIPPCache: true },
    queryKey: `ListCloudBackupPolicies-picker-${currentTenant}`,
  })
  const policyRows = Array.isArray(policies.data) ? policies.data : EMPTY
  const policy = policyRows.find((row) => row.Id === policyId)
  const allTenants = policyCoversAllTenants(policy)

  const tenantList = ApiGetCall({
    url: '/api/ListTenants',
    queryKey: 'ListTenants-cloudBackupRestore',
    waiting: allTenants && !selectedTenant,
  })
  const tenantOptions = useMemo(
    () =>
      allTenants
        ? (Array.isArray(tenantList.data) ? tenantList.data : []).map(
            toTenantOption
          )
        : policyTenantOptions(policy),
    [allTenants, tenantList.data, policy]
  )
  const tenantDomain =
    tenantOptions.find((option) => option.value === tenantId)?.domain ??
    tenantId

  const sourceParams = {
    PolicyId: policyId,
    TenantId: tenantId,
    Workload: workload,
  }
  const owners = ApiGetCall({
    url: '/api/ListCloudBackupOwners',
    data: sourceParams,
    queryKey: `ListCloudBackupOwners-${policyId}-${tenantId}-${workload}`,
    waiting: !!(policyId && tenantId && workload),
  })
  const ownerRows = useMemo(
    () => (Array.isArray(owners.data) ? owners.data : EMPTY),
    [owners.data]
  )
  const owner = ownerRows.find((row) => row.OwnerId === ownerId)
  const ownerParams = { ...sourceParams, OwnerId: ownerId }

  const points = ApiGetCall({
    url: '/api/ListCloudBackupRecoveryPoints',
    data: ownerParams,
    queryKey: `ListCloudBackupRecoveryPoints-${policyId}-${tenantId}-${workload}-${ownerId}`,
    waiting: !!(policyId && tenantId && workload && ownerId),
  })
  const pointOptions = useMemo(
    () => cloudBackupRecoveryPoints(points.data),
    [points.data]
  )
  useEffect(() => {
    if (ownerId && !asOf && pointOptions.length > 0) {
      formControl.setValue('AsOf', pointOptions[0])
    }
  }, [ownerId, asOf, pointOptions, formControl])

  const filtering = !!(search || dateFrom || dateTo)
  const filterInFolder = filtering && !!searchInFolder && !!path
  const itemQuery = {
    ...ownerParams,
    AsOf: asOf,
    ...(!filtering && { Path: path }),
    ...(filterInFolder && { Path: path }),
    ...(search && { Search: search }),
    ...(dateFrom && { DateFrom: new Date(dateFrom * 1000).toISOString() }),
    ...(dateTo && { DateTo: new Date(dateTo * 1000).toISOString() }),
    ...(itemType && { Type: itemType }),
    Skip: skip,
    Take: PAGE_SIZE,
  }
  const itemQueryId = JSON.stringify(itemQuery)
  const items = ApiGetCall({
    url: '/api/ListCloudBackupItems',
    data: itemQuery,
    queryKey: `ListCloudBackupItems-${itemQueryId}`,
    waiting: !!(ownerId && asOf),
  })
  const listing = useMemo(
    () => parseCloudBackupListing(items.data),
    [items.data]
  )
  const itemRows = useMemo(
    () =>
      listing.Items.filter((item) => item.Type !== 'folder').map(
        toCloudBackupItemRow
      ),
    [listing.Items]
  )
  const folders = useMemo(
    () =>
      filtering
        ? []
        : listing.Folders.map((folder) => ({
            name: folder.Name,
            path: folder.Path || folder.Name,
          })),
    [listing.Folders, filtering]
  )

  const openFolder = (target) => {
    setPath(target)
    setSkip(0)
    setSelectedItems(EMPTY)
  }
  const toggleFolder = (target) =>
    setSelectedFolders((current) =>
      current.includes(target)
        ? current.filter((entry) => entry !== target)
        : [...current, target]
    )
  const runSearch = () => {
    setSearch(String(formControl.getValues('Search') ?? '').trim())
    setSkip(0)
    setSelectedItems(EMPTY)
  }
  const clearSearch = () => {
    formControl.setValue('Search', '')
    formControl.setValue('DateFrom', null)
    formControl.setValue('DateTo', null)
    setSearch('')
    setSkip(0)
    setSelectedItems(EMPTY)
  }

  const selection = {
    keys: selectedItems.map((row) => row.Key),
    paths: selectedFolders,
    path: filtering ? '' : path,
  }
  const selectionText = cloudBackupSelectionSummary(selection)
  const restorable = cloudBackupCanRestore(workload)
  const ownerRemoved = owner?.Removed === true
  const otherTarget = ownerRemoved || targetMode === 'Other'
  const targetUserId = cloudBackupOptionValue(targetUser)
  const fileWorkload = FILE_WORKLOADS.includes(workload)
  const restoreLocation =
    fileWorkload && otherTarget ? 'RestoredFolder' : location
  const ownerNoun = OWNER_NOUNS[workload] ?? 'source'
  const ownerName = cloudBackupOwnerLabel(owner) || ownerId
  const asOfLabel = asOfField?.label ?? asOf

  const restoreBody = {
    ...ownerParams,
    AsOf: asOf,
    ...formatCloudBackupSelection(selection),
    ...(otherTarget && { TargetOwnerId: targetUserId }),
    Location: restoreLocation,
    ConflictAction: conflictAction,
    Mode: 'Preview',
  }
  const exportBody = {
    ...ownerParams,
    AsOf: asOf,
    ...formatCloudBackupSelection(selection),
  }
  const previewStale =
    !!preview && JSON.stringify(preview.body) !== JSON.stringify(restoreBody)

  const previewPost = ApiPostCall({
    relatedQueryKeys: ['ListCloudBackupJobs*'],
  })
  const previewJob = useCloudBackupJob(preview?.jobId)
  const applyJob = useCloudBackupJob(applyJobId)
  const exportJob = useCloudBackupJob(exportJobId)

  const startPreview = () => {
    const body = restoreBody
    setApplyJobId(null)
    previewPost.mutate(
      { url: '/api/ExecCloudBackupRestore', data: body },
      {
        onSuccess: (response) => {
          const jobId = response?.data?.JobId
          if (jobId) {
            setPreview({
              jobId,
              body,
              targetName: otherTarget ? targetUser?.label : ownerName,
            })
          }
        },
      }
    )
  }

  const previewCounts = cloudBackupJobCounts(previewJob.job)
  const restoreCount = cloudBackupRestoreCount(previewCounts)
  const previewDone = previewJob.job?.Status === 'Completed'

  const pickerGrid = { xs: 12, md: 4 }
  const sourceGrid = { xs: 12, md: selectedTenant ? 6 : 4 }

  return (
    <>
      <CippHead title="Browse & Restore" noTenant />
      <Container maxWidth={false}>
        <Stack spacing={2}>
          <Card>
            <CardHeader
              title="Choose a backup"
              subheader={`Pick the policy, ${selectedTenant ? '' : 'tenant, '}service and the mailbox, OneDrive, site or team to browse.`}
            />
            <CardContent>
              <Grid container spacing={2}>
                <Grid size={sourceGrid}>
                  <CippFormComponent
                    type="autoComplete"
                    label="Policy"
                    name="PolicyId"
                    formControl={formControl}
                    multiple={false}
                    creatable={false}
                    isFetching={policies.isFetching}
                    options={policyRows.map((row) => ({
                      label: row.Name,
                      value: row.Id,
                    }))}
                  />
                </Grid>
                {!selectedTenant && (
                  <Grid size={pickerGrid}>
                    <CippFormComponent
                      key={`tenant-${policyId}`}
                      type="autoComplete"
                      label="Tenant"
                      name="TenantId"
                      formControl={formControl}
                      multiple={false}
                      creatable={false}
                      disabled={!policyId}
                      isFetching={allTenants && tenantList.isFetching}
                      options={tenantOptions.map(({ label, value }) => ({
                        label,
                        value,
                      }))}
                    />
                  </Grid>
                )}
                <Grid size={sourceGrid}>
                  <CippFormComponent
                    key={`workload-${policyId}`}
                    type="autoComplete"
                    label="Service"
                    name="Workload"
                    formControl={formControl}
                    multiple={false}
                    creatable={false}
                    disabled={!policyId}
                    options={cloudBackupPolicyWorkloads(policy).map(
                      (value) => ({
                        label: cloudBackupWorkloadLabel(value),
                        value,
                      })
                    )}
                  />
                </Grid>
                <Grid size={{ xs: 12, md: 8 }}>
                  <CippFormComponent
                    key={`owner-${policyId}-${tenantId}-${workload}`}
                    type="autoComplete"
                    label={
                      workload
                        ? `Backed up ${ownerNoun}`
                        : 'Backed up mailbox, OneDrive, site or team'
                    }
                    name="OwnerId"
                    formControl={formControl}
                    multiple={false}
                    creatable={false}
                    disabled={!(policyId && tenantId && workload)}
                    isFetching={owners.isFetching}
                    options={ownerRows.map((row) => ({
                      label: cloudBackupOwnerLabel(row),
                      value: row.OwnerId,
                    }))}
                  />
                </Grid>
                <Grid size={pickerGrid}>
                  <CippFormComponent
                    key={`asof-${ownerId}`}
                    type="autoComplete"
                    label="Point in time"
                    name="AsOf"
                    formControl={formControl}
                    multiple={false}
                    creatable={false}
                    disableClearable={true}
                    disabled={!ownerId}
                    isFetching={points.isFetching}
                    options={pointOptions}
                  />
                </Grid>
              </Grid>
              {owners.isError && (
                <Alert severity="error" sx={{ mt: 2 }}>
                  The backed up {ownerNoun}s could not be loaded. Check that the
                  destination is reachable on the Destinations page.
                </Alert>
              )}
              {owners.isSuccess &&
                tenantId &&
                workload &&
                ownerRows.length === 0 && (
                  <Alert severity="info" sx={{ mt: 2 }}>
                    Nothing has been backed up for this tenant and service yet.
                  </Alert>
                )}
              {ownerId && points.isSuccess && pointOptions.length === 0 && (
                <Alert severity="info" sx={{ mt: 2 }}>
                  There is no completed backup of this {ownerNoun} yet.
                </Alert>
              )}
            </CardContent>
          </Card>

          {ownerRemoved && (
            <Alert severity="warning">
              {owner.RemovedReason === 'Excluded'
                ? `This ${ownerNoun} is no longer backed up because the policy excludes it.`
                : `This ${ownerNoun} is no longer in the tenant.`}{' '}
              {owner.RemovedAt
                ? `CIPP noticed on ${new Date(owner.RemovedAt).toLocaleDateString()}. `
                : ''}
              Its backups are kept until the policy's retention period ends. It
              can only be restored to another user.
            </Alert>
          )}

          {!canRestore && ownerId && (
            <Alert severity="info">
              You can browse this backup, but restoring, exporting and
              downloading need the Cloud Backup restore permission. Ask a CIPP
              administrator if you need it.
            </Alert>
          )}

          {ownerId && asOf && (
            <>
              <Card>
                <CardContent>
                  <Stack spacing={2}>
                    <Stack
                      direction={{ xs: 'column', md: 'row' }}
                      spacing={2}
                      alignItems={{ md: 'center' }}
                    >
                      <Box sx={{ flexGrow: 1 }}>
                        <CippFormComponent
                          type="textField"
                          label="Search this backup"
                          name="Search"
                          formControl={formControl}
                          placeholder="Subject, sender, file name or folder"
                          onKeyDown={(event) => {
                            if (event.key === 'Enter') {
                              event.preventDefault()
                              runSearch()
                            }
                          }}
                        />
                      </Box>
                      <Box sx={{ minWidth: 220 }}>
                        <CippFormComponent
                          key={`type-${workload}`}
                          type="autoComplete"
                          label="Type"
                          name="Type"
                          formControl={formControl}
                          multiple={false}
                          creatable={false}
                          placeholder="All types"
                          options={cloudBackupItemTypes(workload)}
                        />
                      </Box>
                      <Stack direction="row" spacing={1}>
                        <Button
                          variant="contained"
                          startIcon={<CippIcons.Search />}
                          onClick={runSearch}
                        >
                          Search
                        </Button>
                        {filtering && (
                          <Button onClick={clearSearch}>Clear search</Button>
                        )}
                      </Stack>
                    </Stack>
                    <Stack
                      direction={{ xs: 'column', md: 'row' }}
                      spacing={2}
                      alignItems={{ md: 'center' }}
                    >
                      <CippFormComponent
                        type="datePicker"
                        dateTimeType="date"
                        label="Modified from"
                        name="DateFrom"
                        formControl={formControl}
                      />
                      <CippFormComponent
                        type="datePicker"
                        dateTimeType="date"
                        label="Modified to"
                        name="DateTo"
                        formControl={formControl}
                      />
                      {path && (
                        <CippFormComponent
                          type="switch"
                          label="Only search the open folder"
                          name="SearchInFolder"
                          formControl={formControl}
                        />
                      )}
                    </Stack>
                    {filtering ? (
                      <Typography variant="body2">
                        {filterInFolder
                          ? `Showing matching items in ${path} and its subfolders.`
                          : `Showing matching items in the whole ${ownerNoun}.`}
                      </Typography>
                    ) : (
                      <FolderPath path={path} onOpen={openFolder} />
                    )}
                    {folders.length > 0 && (
                      <List dense disablePadding>
                        {folders.map((folder) => (
                          <ListItem
                            key={folder.path}
                            disablePadding
                            secondaryAction={
                              canRestore ? (
                                <Checkbox
                                  edge="end"
                                  checked={selectedFolders.includes(
                                    folder.path
                                  )}
                                  onChange={() => toggleFolder(folder.path)}
                                  slotProps={{
                                    input: {
                                      'aria-label': `Select folder ${folder.name}`,
                                    },
                                  }}
                                />
                              ) : null
                            }
                          >
                            <ListItemButton
                              onClick={() => openFolder(folder.path)}
                            >
                              <ListItemIcon>
                                <CippIcons.Folder />
                              </ListItemIcon>
                              <ListItemText primary={folder.name} />
                            </ListItemButton>
                          </ListItem>
                        ))}
                      </List>
                    )}
                    {items.isError && items.error?.response?.status === 404 && (
                      <Alert severity="info">
                        There is no backup of this {ownerNoun} at this point in
                        time. Pick another point in time.
                      </Alert>
                    )}
                    {items.isError && items.error?.response?.status !== 404 && (
                      <Alert severity="error">
                        This backup could not be read from the destination.
                        Check that the destination is reachable on the
                        Destinations page.
                      </Alert>
                    )}
                  </Stack>
                </CardContent>
              </Card>

              <CippDataTable
                key={itemQueryId}
                title={filtering ? 'Search results' : 'Items in this folder'}
                queryKey={`CloudBackupItems-${itemQueryId}`}
                data={itemRows}
                isFetching={items.isFetching}
                refreshFunction={items.refetch}
                simpleColumns={[
                  'CloudBackupItemName',
                  ...(filtering ? ['CloudBackupItemFolder'] : []),
                  'CloudBackupItemType',
                  ...(workload === 'exchange' ? ['CloudBackupFrom'] : []),
                  'CloudBackupModified',
                  'CloudBackupSize',
                ]}
                onChange={canRestore ? setSelectedItems : undefined}
                offCanvas={{
                  title: 'Backed Up Item',
                  size: 'lg',
                  children: (row) => (
                    <ItemDetails
                      row={row}
                      source={{ params: ownerParams, asOf }}
                      canDownload={canRestore}
                    />
                  ),
                }}
                offCanvasOnRowClick={true}
              />

              {listing.Total > PAGE_SIZE && (
                <Stack direction="row" spacing={2} alignItems="center">
                  <Typography variant="body2">
                    {`Items ${skip + 1}–${Math.min(skip + PAGE_SIZE, listing.Total)} of ${listing.Total}`}
                  </Typography>
                  <Button
                    disabled={skip === 0}
                    onClick={() => {
                      setSkip(Math.max(0, skip - PAGE_SIZE))
                      setSelectedItems(EMPTY)
                    }}
                  >
                    Previous
                  </Button>
                  <Button
                    disabled={skip + PAGE_SIZE >= listing.Total}
                    onClick={() => {
                      setSkip(skip + PAGE_SIZE)
                      setSelectedItems(EMPTY)
                    }}
                  >
                    Next
                  </Button>
                </Stack>
              )}

              {canRestore && (
                <Card>
                  <CardContent>
                    <Stack
                      direction={{ xs: 'column', md: 'row' }}
                      spacing={2}
                      alignItems={{ md: 'center' }}
                    >
                      <Typography sx={{ flexGrow: 1 }}>
                        {`Selected: ${selectionText}`}
                      </Typography>
                      {(selectedItems.length > 0 ||
                        selectedFolders.length > 0) && (
                        <Button onClick={clearSelection}>
                          Clear selection
                        </Button>
                      )}
                      {restorable && (
                        <Button
                          variant="contained"
                          startIcon={<CippIcons.Restore />}
                          onClick={() => setRestoreOpen(true)}
                        >
                          Restore
                        </Button>
                      )}
                      <Button
                        variant="outlined"
                        startIcon={<CippIcons.FileDownload />}
                        onClick={() => exportDialog.handleOpen()}
                      >
                        Export
                      </Button>
                    </Stack>
                    {!restorable && (
                      <Typography variant="body2" sx={{ mt: 1 }}>
                        Teams messages cannot be restored into Teams. Export
                        them to download a copy.
                      </Typography>
                    )}
                  </CardContent>
                </Card>
              )}

              {canRestore && restorable && restoreOpen && (
                <Card>
                  <CardHeader
                    title="Restore options"
                    subheader={`Restoring ${selectionText} from ${ownerName} as it was on ${asOfLabel}.`}
                  />
                  <CardContent>
                    <Stack spacing={3}>
                      {ownerRemoved ? (
                        <Typography variant="body2">
                          Restore to another user in this tenant.
                        </Typography>
                      ) : (
                        <CippFormComponent
                          type="radio"
                          label="Restore to"
                          name="TargetMode"
                          formControl={formControl}
                          options={[
                            {
                              label: `The original ${ownerNoun}`,
                              value: 'Original',
                            },
                            {
                              label:
                                workload === 'exchange'
                                  ? "Another user's mailbox in this tenant"
                                  : "Another user's OneDrive in this tenant",
                              value: 'Other',
                            },
                          ]}
                        />
                      )}
                      {otherTarget && (
                        <CippFormComponent
                          key={`target-${tenantDomain}`}
                          type="autoComplete"
                          label="User to restore to"
                          name="TargetUser"
                          formControl={formControl}
                          multiple={false}
                          creatable={false}
                          api={userPicker(tenantDomain)}
                        />
                      )}
                      {fileWorkload && otherTarget ? (
                        <Typography variant="body2">
                          Files are restored to a new folder named
                          &quot;Restored&quot; with the date and time, at the
                          top of the user&apos;s OneDrive.
                        </Typography>
                      ) : (
                        <CippFormComponent
                          type="radio"
                          label="Restore into"
                          name="Location"
                          formControl={formControl}
                          options={CLOUD_BACKUP_RESTORE_LOCATIONS}
                        />
                      )}
                      <CippFormComponent
                        type="radio"
                        label="When an item already exists"
                        name="ConflictAction"
                        formControl={formControl}
                        options={CLOUD_BACKUP_CONFLICT_ACTIONS}
                      />
                      <Typography variant="body2">
                        The preview checks what a restore would do. Nothing is
                        changed until you confirm the restore.
                      </Typography>
                      <Box>
                        <Button
                          variant="contained"
                          onClick={startPreview}
                          disabled={
                            (otherTarget && !targetUserId) ||
                            previewPost.isPending ||
                            previewJob.isActive
                          }
                          startIcon={<CippIcons.Visibility />}
                        >
                          Preview restore
                        </Button>
                      </Box>
                      <CippApiResults apiObject={previewPost} errorsOnly />
                    </Stack>
                  </CardContent>
                </Card>
              )}

              {preview && (
                <Card>
                  <CardHeader
                    title="Preview"
                    subheader="Nothing has been changed yet. Review what a restore would do."
                  />
                  <CardContent>
                    <Stack spacing={2}>
                      <CippCloudBackupJobStatus
                        jobState={previewJob}
                        runningText="Checking the backup against what is in Microsoft 365 now."
                      />
                      {previewDone && (
                        <>
                          <Typography variant="body2">
                            {cloudBackupJobSummary(previewJob.job)}
                          </Typography>
                          <CippCloudBackupJobResults
                            job={previewJob.job}
                            title="Restore preview"
                          />
                          {previewStale ? (
                            <Alert severity="warning">
                              The options or the selection changed after this
                              preview. Preview again before restoring.
                            </Alert>
                          ) : (
                            !applyJobId && (
                              <Box>
                                <Button
                                  variant="contained"
                                  color="warning"
                                  onClick={() => restoreDialog.handleOpen()}
                                  disabled={restoreCount === 0}
                                  startIcon={<CippIcons.Restore />}
                                >
                                  {`Restore ${restoreCount} ${restoreCount === 1 ? 'item' : 'items'}`}
                                </Button>
                              </Box>
                            )
                          )}
                        </>
                      )}
                    </Stack>
                  </CardContent>
                </Card>
              )}

              {applyJobId && (
                <Card>
                  <CardHeader title="Restore" />
                  <CardContent>
                    <Stack spacing={2}>
                      <CippCloudBackupJobStatus
                        jobState={applyJob}
                        runningText="Restoring. This page updates by itself, and the result is also kept in Restore History."
                      />
                      {applyJob.job?.Status === 'Completed' && (
                        <>
                          <Typography variant="body2">
                            {cloudBackupJobSummary(applyJob.job)}
                          </Typography>
                          <CippCloudBackupJobResults
                            job={applyJob.job}
                            title="Restore results"
                          />
                        </>
                      )}
                    </Stack>
                  </CardContent>
                </Card>
              )}

              {exportJobId && (
                <Card>
                  <CardHeader title="Export" />
                  <CardContent>
                    <Stack spacing={2}>
                      <CippCloudBackupJobStatus
                        jobState={exportJob}
                        runningText="Building the export. This page updates by itself, and the download is also kept in Restore History."
                      />
                      {exportJob.job?.Status === 'Completed' && (
                        <Typography variant="body2">
                          {cloudBackupJobSummary(exportJob.job)}
                        </Typography>
                      )}
                      <CippCloudBackupExportDownload job={exportJob.job} />
                    </Stack>
                  </CardContent>
                </Card>
              )}

              {preview && (
                <CippApiDialog
                  createDialog={restoreDialog}
                  title="Restore"
                  relatedQueryKeys={['ListCloudBackupJobs*']}
                  api={{
                    type: 'POST',
                    url: '/api/ExecCloudBackupRestore',
                    customDataformatter: () => ({
                      ...preview.body,
                      Mode: 'Apply',
                      PreviewJobId: preview.jobId,
                    }),
                    confirmText: (
                      <RestoreConfirmText
                        targetName={preview.targetName}
                        counts={previewCounts}
                      />
                    ),
                  }}
                  dialogAfterEffect={(data) => {
                    if (data?.JobId) setApplyJobId(data.JobId)
                  }}
                />
              )}

              <CippApiDialog
                createDialog={exportDialog}
                title="Export"
                relatedQueryKeys={['ListCloudBackupJobs*']}
                api={{
                  type: 'POST',
                  url: '/api/ExecCloudBackupExport',
                  customDataformatter: () => exportBody,
                  confirmText: `Export ${selectionText} from ${ownerName} as it was on ${asOfLabel}? CIPP builds a .zip file you can download for 7 days.`,
                }}
                dialogAfterEffect={(data) => {
                  if (data?.JobId) setExportJobId(data.JobId)
                }}
              />
            </>
          )}
        </Stack>
      </Container>
    </>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
