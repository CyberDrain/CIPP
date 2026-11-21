export const CLOUD_BACKUP_WORKLOADS = [
  {
    label: 'Exchange Online',
    value: 'exchange',
    description: 'User and shared mailboxes: mail, calendar and contacts.',
    sources: 'Mailboxes',
  },
  {
    label: 'OneDrive',
    value: 'onedrive',
    description: 'Every user’s OneDrive files.',
    sources: 'OneDrives',
  },
  {
    label: 'SharePoint',
    value: 'sharepoint',
    description:
      'All document libraries of every site, including the sites behind Teams.',
    sources: 'Sites',
  },
  {
    label: 'Teams',
    value: 'teams',
    description:
      'Chats and channel messages. These can be backed up but not restored into Teams.',
    sources: 'Teams and chat users',
  },
]

export const CLOUD_BACKUP_SCHEDULES = [
  { label: 'Every 4 hours', value: '4h' },
  { label: 'Every 6 hours', value: '6h' },
  { label: 'Every 12 hours', value: '12h' },
  { label: 'Every day', value: '1d' },
]

export const CLOUD_BACKUP_DEFAULT_SCHEDULES = {
  exchange: '4h',
  onedrive: '6h',
  sharepoint: '6h',
  teams: '4h',
}

const FILE_WORKLOADS = ['onedrive', 'sharepoint']

export const cloudBackupSchedulesFor = (workload) =>
  FILE_WORKLOADS.includes(workload)
    ? CLOUD_BACKUP_SCHEDULES.filter((schedule) => schedule.value !== '4h')
    : CLOUD_BACKUP_SCHEDULES

export const CLOUD_BACKUP_PROVIDERS = [
  { label: 'Azure Blob Storage', value: 'AzureBlob' },
  { label: 'Amazon S3 or S3-compatible storage', value: 'S3' },
]

export const CLOUD_BACKUP_SECRET_SENTINEL = 'SentToKeyVault'

const labelFor = (options, value) =>
  options.find((option) => option.value === value)?.label ?? value

export const cloudBackupWorkloadLabel = (value) =>
  labelFor(CLOUD_BACKUP_WORKLOADS, String(value ?? '').toLowerCase())

export const cloudBackupWorkloadSources = (value) =>
  CLOUD_BACKUP_WORKLOADS.find(
    (workload) => workload.value === String(value ?? '').toLowerCase()
  )?.sources ?? 'Sources'

export const cloudBackupScheduleLabel = (value) =>
  labelFor(CLOUD_BACKUP_SCHEDULES, value)

export const cloudBackupProviderLabel = (value) =>
  labelFor(CLOUD_BACKUP_PROVIDERS, value)

const optionValue = (item) =>
  item && typeof item === 'object' ? item.value : item

export const cloudBackupOptionValue = optionValue

export const parseCloudBackupList = (value) => {
  if (Array.isArray(value)) return value
  if (typeof value === 'string' && value.trim().startsWith('[')) {
    try {
      const parsed = JSON.parse(value)
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }
  return []
}

export const parseCloudBackupObject = (value) => {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value
  if (typeof value === 'string' && value.trim().startsWith('{')) {
    try {
      const parsed = JSON.parse(value)
      return parsed && typeof parsed === 'object' ? parsed : {}
    } catch {
      return {}
    }
  }
  return {}
}

export const cloudBackupPolicyWorkloads = (row) => {
  const selected = parseCloudBackupList(row?.Workloads).map((workload) =>
    String(workload).toLowerCase()
  )
  return CLOUD_BACKUP_WORKLOADS.map((workload) => workload.value).filter(
    (value) => selected.includes(value)
  )
}

export const cloudBackupPolicyExclusions = (row) => {
  const exclusions = parseCloudBackupObject(row?.Exclusions)
  return {
    Users: parseCloudBackupList(exclusions.Users),
    Groups: parseCloudBackupList(exclusions.Groups),
    Sites: parseCloudBackupList(exclusions.Sites),
  }
}

const toOption = (value) => ({ label: String(value), value: String(value) })

export const toCloudBackupPolicyForm = (row) => {
  const workloads = cloudBackupPolicyWorkloads(row)
  const schedules = parseCloudBackupObject(row.Schedules)
  const exclusions = cloudBackupPolicyExclusions(row)
  return {
    Id: row.Id,
    Name: row.Name,
    Enabled: row.Enabled === true,
    DestinationId: row.DestinationId
      ? {
          label: row.DestinationName ?? row.DestinationId,
          value: row.DestinationId,
        }
      : null,
    Tenants: row.Tenants ?? [],
    Workloads: Object.fromEntries(
      CLOUD_BACKUP_WORKLOADS.map(({ value }) => [
        value,
        workloads.includes(value),
      ])
    ),
    Schedules: Object.fromEntries(
      CLOUD_BACKUP_WORKLOADS.map(({ value }) => {
        const schedule =
          schedules[value] ?? CLOUD_BACKUP_DEFAULT_SCHEDULES[value]
        return [
          value,
          { label: cloudBackupScheduleLabel(schedule), value: schedule },
        ]
      })
    ),
    ExcludedUsers: exclusions.Users.map(toOption),
    ExcludedGroups: exclusions.Groups.map(toOption),
    ExcludedSites: exclusions.Sites.map(toOption),
    RetentionDays: row.RetentionDays,
    Encryption: row.Encryption === true,
  }
}

export const cloudBackupPolicyDefaults = () => ({
  Enabled: true,
  Tenants: [],
  Workloads: Object.fromEntries(
    CLOUD_BACKUP_WORKLOADS.map(({ value }) => [value, true])
  ),
  Schedules: Object.fromEntries(
    Object.entries(CLOUD_BACKUP_DEFAULT_SCHEDULES).map(([workload, value]) => [
      workload,
      { label: cloudBackupScheduleLabel(value), value },
    ])
  ),
  ExcludedUsers: [],
  ExcludedGroups: [],
  ExcludedSites: [],
  RetentionDays: 90,
  Encryption: false,
})

const optionValues = (items) =>
  (items ?? [])
    .map(optionValue)
    .map((value) => (typeof value === 'string' ? value.trim() : value))
    .filter(Boolean)

export const formatCloudBackupPolicy = (values, action) => {
  const workloads = CLOUD_BACKUP_WORKLOADS.map(({ value }) => value).filter(
    (workload) => values.Workloads?.[workload]
  )
  return {
    Action: action,
    Id: values.Id,
    Name: values.Name,
    Enabled: Boolean(values.Enabled),
    DestinationId: optionValue(values.DestinationId),
    Tenants: values.Tenants ?? [],
    Workloads: workloads,
    Schedules: Object.fromEntries(
      workloads.map((workload) => [
        workload,
        optionValue(values.Schedules?.[workload]) ??
          CLOUD_BACKUP_DEFAULT_SCHEDULES[workload],
      ])
    ),
    Exclusions: {
      Users: optionValues(values.ExcludedUsers),
      Groups: optionValues(values.ExcludedGroups),
      Sites: optionValues(values.ExcludedSites),
    },
    RetentionDays: Number(values.RetentionDays),
    Encryption: Boolean(values.Encryption),
  }
}

export const cloudBackupPermissionRows = (row) => {
  const status = parseCloudBackupObject(row?.PermissionStatus)
  return Object.entries(status).map(([customerId, entry]) => ({
    customerId,
    Status: entry?.Status ?? 'Pending',
    Message: entry?.Message ?? '',
    CheckedAt: entry?.CheckedAt ?? null,
  }))
}

export const cloudBackupPermissionSummary = (row) => {
  const rows = cloudBackupPermissionRows(row)
  if (rows.length === 0) return 'Not checked yet'
  const failed = rows.filter((entry) => entry.Status === 'Failed').length
  const pending = rows.filter((entry) => entry.Status === 'Pending').length
  if (failed) {
    return `${failed} of ${rows.length} ${rows.length === 1 ? 'tenant' : 'tenants'} failed`
  }
  if (pending) return `${pending} pending`
  return 'All granted'
}

export const cloudBackupContentReady = (lastTest) => {
  if (!lastTest) return null
  if (typeof lastTest.ContentReady === 'boolean') return lastTest.ContentReady
  if (!lastTest.Versioning || lastTest.Versioning === 'Unknown') return null
  return lastTest.Versioning === 'Enabled'
}

const AZURE_FIELDS = [
  'StorageAccount',
  'Container',
  'SubscriptionId',
  'ResourceGroup',
  'AzureTenantId',
  'ClientId',
  'ClientSecret',
]
const AZURE_APP_FIELDS = ['AzureTenantId', 'ClientId', 'ClientSecret']
const S3_FIELDS = [
  'Endpoint',
  'Region',
  'Bucket',
  'AccessKeyId',
  'SecretAccessKey',
]

export const formatCloudBackupDestination = (values, action) => {
  const provider = optionValue(values.Provider)
  const fields =
    provider !== 'AzureBlob'
      ? S3_FIELDS
      : values.AuthMode === 'CippApp'
        ? AZURE_FIELDS.filter((field) => !AZURE_APP_FIELDS.includes(field))
        : AZURE_FIELDS
  const body = {
    Action: action,
    Id: values.Id,
    Name: values.Name,
    Provider: provider,
  }
  fields.forEach((field) => {
    body[field] =
      typeof values[field] === 'string' ? values[field].trim() : values[field]
  })
  if (provider === 'S3') {
    body.ForcePathStyle = Boolean(values.ForcePathStyle)
  }
  return body
}

export const toCloudBackupRunRow = (row) => ({
  ...row,
  CloudBackupWorkload: row.Workload
    ? cloudBackupWorkloadLabel(row.Workload)
    : undefined,
  CloudBackupStatus: row.Status,
  CloudBackupStartedAt: row.StartedAt,
  CloudBackupCompletedAt: row.CompletedAt,
  CloudBackupSize: row.Bytes,
})

export const CLOUD_BACKUP_PROVISION_DEFAULTS = {
  ResourceGroup: 'rg-cipp-cloudbackup',
  Container: 'cipp-backups',
  Redundancy: 'Standard_LRS',
  Immutability: false,
  ImmutabilityDays: 30,
}

export const CLOUD_BACKUP_REDUNDANCY = [
  {
    label:
      'Locally redundant (LRS): three copies in one datacenter. Lowest cost.',
    value: 'Standard_LRS',
  },
  {
    label:
      'Zone redundant (ZRS): copies in three datacenters in the same region. Not offered in every region.',
    value: 'Standard_ZRS',
  },
  {
    label:
      'Geo-redundant (GRS): also copied to a second region far away. Highest cost.',
    value: 'Standard_GRS',
  },
]

export const formatCloudBackupProvision = (values) => {
  const text = (value) => (typeof value === 'string' ? value.trim() : value)
  const body = {
    Name: text(values.Name),
    SubscriptionId: optionValue(values.SubscriptionId),
    ResourceGroup: text(values.ResourceGroup),
    Region: optionValue(values.Region),
    Redundancy:
      optionValue(values.Redundancy) ||
      CLOUD_BACKUP_PROVISION_DEFAULTS.Redundancy,
    Container: text(values.Container),
  }
  if (values.Immutability) {
    body.ImmutabilityDays = Number(values.ImmutabilityDays)
  }
  return body
}

export const cloudBackupRegionOptions = (data) => {
  const regions = Array.isArray(data) ? data : (data?.Regions ?? [])
  return regions.map((region) => ({
    label: region.displayName ?? region.name,
    value: region.name,
  }))
}

export const cloudBackupProvisionJob = (data) =>
  Array.isArray(data) ? data[0] : data

export const cloudBackupProvisionRunning = (job) =>
  !job || job.Status === 'Queued' || job.Status === 'Running'

export const cloudBackupManualPrefill = (result, name) => ({
  Provider: 'AzureBlob',
  ForcePathStyle: false,
  Name: name ?? '',
  SubscriptionId: result?.SubscriptionId ?? '',
  ResourceGroup: result?.ResourceGroup ?? '',
  StorageAccount: result?.StorageAccount ?? '',
  Container: result?.Container ?? '',
})

export const cloudBackupSignInLabel = (row) => {
  if (row?.Provider === 'S3') return 'Access key'
  return row?.AuthMode === 'CippApp' ? 'CIPP’s own app' : 'App registration'
}

export const CLOUD_BACKUP_RESTORE_PERMISSION = [
  'CIPP.CloudBackupRestore.ReadWrite',
]

const ITEM_TYPES = {
  exchange: [
    { label: 'Email', value: 'message' },
    { label: 'Calendar event', value: 'event' },
    { label: 'Contact', value: 'contact' },
  ],
  onedrive: [{ label: 'File', value: 'file' }],
  sharepoint: [{ label: 'File', value: 'file' }],
  teams: [
    { label: 'Chat message', value: 'chatMessage' },
    { label: 'Channel message', value: 'channelMessage' },
  ],
}

export const cloudBackupItemTypes = (workload) =>
  ITEM_TYPES[String(workload ?? '').toLowerCase()] ?? []

export const cloudBackupItemTypeLabel = (value) => {
  if (value === 'folder') return 'Folder'
  const match = Object.values(ITEM_TYPES)
    .flat()
    .find((type) => type.value === value)
  return match?.label ?? value
}

export const cloudBackupCanRestore = (workload) =>
  String(workload ?? '').toLowerCase() !== 'teams'

export const CLOUD_BACKUP_RESTORE_LOCATIONS = [
  {
    label:
      'A new folder named "Restored" with the date and time, keeping the original folder structure',
    value: 'RestoredFolder',
  },
  { label: 'The original folders', value: 'Original' },
]

export const CLOUD_BACKUP_CONFLICT_ACTIONS = [
  { label: 'Skip items that already exist', value: 'Skip' },
  { label: 'Overwrite items that already exist', value: 'Overwrite' },
  {
    label: 'Keep both: restore a copy with "(restored date)" added to its name',
    value: 'Copy',
  },
]

const RESTORE_ACTION_LABELS = {
  Create: 'Restore',
  Overwrite: 'Overwrite',
  Copy: 'Restore as a copy',
  Skip: 'Skip, already exists',
  NotRestorable: 'Cannot be restored',
}

export const cloudBackupRestoreActionLabel = (value) =>
  RESTORE_ACTION_LABELS[value] ?? value

const JOB_TYPE_LABELS = {
  RestorePreview: 'Restore preview',
  Restore: 'Restore',
  Export: 'Export',
}

export const CLOUD_BACKUP_HISTORY_JOB_TYPES = Object.keys(JOB_TYPE_LABELS)

export const cloudBackupJobTypeLabel = (value) =>
  JOB_TYPE_LABELS[value] ?? value

export const isCloudBackupJobActive = (status) =>
  status === 'Queued' || status === 'Running'

export const cloudBackupOwnerLabel = (owner) => {
  if (!owner) return ''
  const name =
    owner.DisplayName ??
    owner.UserPrincipalName ??
    owner.SiteUrl ??
    owner.OwnerId
  const detail = owner.UserPrincipalName ?? owner.SiteUrl
  const base = detail && detail !== name ? `${name} (${detail})` : name
  if (!owner.Removed) return base
  return owner.RemovedReason === 'Excluded'
    ? `${base}, excluded from the policy`
    : `${base}, removed from the tenant`
}

export const cloudBackupRecoveryPoints = (data) =>
  (Array.isArray(data) ? data : parseCloudBackupList(data))
    .filter((point) => point?.RunStamp)
    .map((point) => ({
      label: point.At
        ? new Date(point.At).toLocaleString()
        : String(point.RunStamp),
      value: String(point.RunStamp),
    }))

const toExtra = (value) => parseCloudBackupObject(value)

export const toCloudBackupItemRow = (item) => {
  const extra = toExtra(item.Extra)
  return {
    ...item,
    Extra: extra,
    CloudBackupItemName: item.Name || extra.subject || item.Key,
    CloudBackupItemType: cloudBackupItemTypeLabel(item.Type),
    CloudBackupItemFolder: item.Path || '/',
    CloudBackupModified: item.Modified,
    CloudBackupSize: item.Size,
    CloudBackupFrom: extra.from,
  }
}

export const parseCloudBackupListing = (data) => {
  const listing = parseCloudBackupObject(data)
  return {
    RunStamp: listing.RunStamp,
    Total: Number(listing.Total ?? 0),
    Items: parseCloudBackupList(listing.Items),
    Folders: parseCloudBackupList(listing.Folders),
  }
}

const countOf = (counts, key) => Number(counts?.[key] ?? 0)

export const cloudBackupJobResults = (result) => {
  if (Array.isArray(result) || typeof result === 'string') {
    const rows = parseCloudBackupList(result)
    return { rows, total: rows.length }
  }
  const page = parseCloudBackupObject(result)
  const rows = parseCloudBackupList(page.Items ?? page.Results)
  return { rows, total: Number(page.Total ?? rows.length) }
}

export const cloudBackupJobCounts = (job) => {
  const summary = parseCloudBackupObject(job?.Summary)
  if (Object.keys(summary).length > 0) return summary
  const counts = {}
  cloudBackupJobResults(job?.Result).rows.forEach((row) => {
    const key = job?.Type === 'RestorePreview' ? row.Action : row.Status
    if (key) counts[key] = (counts[key] ?? 0) + 1
  })
  return counts
}

export const cloudBackupRestoreCount = (counts) =>
  countOf(counts, 'Create') +
  countOf(counts, 'Overwrite') +
  countOf(counts, 'Copy')

const plural = (count, one, many) => `${count} ${count === 1 ? one : many}`

export const cloudBackupJobSummary = (job) => {
  const counts = cloudBackupJobCounts(job)
  const phrase = (key, text) =>
    countOf(counts, key) ? `${countOf(counts, key)} ${text}` : null
  let parts
  if (job?.Type === 'RestorePreview') {
    parts = [
      phrase('Create', 'to restore'),
      phrase('Overwrite', 'to overwrite'),
      phrase('Copy', 'to restore as copies'),
      phrase('Skip', 'already exist'),
      phrase('NotRestorable', 'cannot be restored'),
    ]
  } else if (job?.Type === 'Export') {
    const items = countOf(counts, 'Items')
    parts = [
      items ? plural(items, 'item exported', 'items exported') : null,
      phrase('Failed', 'failed'),
    ]
  } else {
    parts = [
      phrase('Succeeded', 'restored'),
      phrase('Failed', 'failed'),
      phrase('Skipped', 'skipped'),
      phrase('NotRestorable', 'cannot be restored'),
    ]
  }
  return parts.filter(Boolean).join(', ') || 'Nothing to do'
}

export const cloudBackupSelectionSummary = ({ keys, paths, path }) => {
  if (keys.length || paths.length) {
    return [
      keys.length ? plural(keys.length, 'item', 'items') : null,
      paths.length ? plural(paths.length, 'folder', 'folders') : null,
    ]
      .filter(Boolean)
      .join(' and ')
  }
  return path ? `everything in ${path}` : 'everything in this backup'
}

export const formatCloudBackupSelection = ({ keys, paths, path }) => {
  if (keys.length || paths.length) {
    return {
      ...(keys.length > 0 && { Keys: keys }),
      ...(paths.length > 0 && { Paths: paths }),
    }
  }
  return path ? { Paths: [path] } : {}
}

export const cloudBackupExportAvailable = (job, now = Date.now()) => {
  if (job?.Type !== 'Export' || job.Status !== 'Completed') return false
  if (job.DownloadAvailable === false) return false
  if (job.ExpiresAt && new Date(job.ExpiresAt).getTime() <= now) return false
  return true
}

export const cloudBackupDownloadFileName = (header, fallback) => {
  const value = String(header ?? '')
  const encoded = /filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)/.exec(value)
  if (encoded) {
    try {
      return decodeURIComponent(encoded[1].trim().replace(/^"|"$/g, ''))
    } catch {
      return fallback
    }
  }
  const plain = /filename\s*=\s*"?([^";]+)"?/i.exec(value)
  return plain ? plain[1].trim() : fallback
}
