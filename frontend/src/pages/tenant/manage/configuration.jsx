import { Layout as DashboardLayout } from '../../../layouts/index'
import { HeaderedTabbedLayout } from '../../../layouts/HeaderedTabbedLayout'
import { createContext, useContext, useMemo, useState } from 'react'
import { useRouter } from 'next/router'
import {
  Box,
  Button,
  Stack,
  Alert,
  Typography,
  Card,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Collapse,
  SvgIcon,
  Autocomplete,
  TextField,
  Chip,
  Divider,
} from '@mui/material'
import { Grid } from '@mui/system'
import { ApiGetCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'
import CippButtonCard from '../../../components/CippCards/CippButtonCard'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import { CippIcons } from '../../../utils/icon-registry'
import tabOptions from './tabOptions.json'
import timezoneList from '../../../data/timezoneList'
import { configStandardsMap } from '../../../data/configStandardsMap'

// This page is deliberately read-only. Configuration is changed through Standards or Baselines
// so the change is reapplied on schedule and drift is detected - a value set by hand here would
// be neither. Every leaf is one live read of one Microsoft 365 area; nothing writes.

const findOption = (options, value) =>
  options.find((o) => o.value === value) || null

const sharingCapabilityOptions = [
  {
    label: 'Only within the organization (no external sharing)',
    value: 'disabled',
  },
  {
    label: 'New and existing guests (sign-in or verification required)',
    value: 'externalUserSharingOnly',
  },
  {
    label: 'Anyone (anonymous access links allowed)',
    value: 'externalUserAndGuestSharing',
  },
  { label: 'Existing guests only', value: 'existingExternalUserSharingOnly' },
]

const domainModeOptions = [
  { label: 'Off', value: 'none' },
  { label: 'Restrict sharing to specific domains', value: 'allowList' },
  { label: 'Block sharing to specific domains', value: 'blockList' },
]

const retentionOptions = [
  30, 90, 365, 730, 1095, 1460, 1825, 2190, 2555, 2920, 3285, 3650,
].map((days) => ({
  label: days >= 365 ? `${days / 365} year(s)` : `${days} days`,
  value: String(days),
}))

const guestInviteOptions = [
  { label: 'Anyone in the organization can invite guests', value: 'everyone' },
  {
    label: 'Members and admins can invite',
    value: 'adminsGuestInvitersAndAllMembers',
  },
  { label: 'Admins and guest inviters only', value: 'adminsAndGuestInviters' },
  { label: 'No one can invite guests', value: 'none' },
]

const guestRoleOptions = [
  {
    label: 'Restricted access (most limited)',
    value: '2af84b1e-32c8-42b7-82bc-daa82404023b',
  },
  {
    label: 'Guest user (default limited access)',
    value: '10dae51f-b6af-4016-8d66-8c2a99b929b3',
  },
  {
    label: 'Same as member users (most access)',
    value: 'a0b1b346-4d3e-4e8b-98f8-753987be4970',
  },
]

// Every section reads live (staleTime 0) so config is never stale, and only the opened section's
// area of Microsoft 365 is queried.
const liveRead = (url, tenant, queryKey) => {
  const sep = url.includes('?') ? '&' : '?'
  return ApiGetCall({
    url: `${url}${sep}tenantFilter=${tenant}`,
    queryKey: `${queryKey}_${tenant}`,
    staleTime: 0,
  })
}

const boolText = (v) => (v ? 'Enabled' : 'Disabled')

// Management state is supplied through context so only rows whose field maps to a Standard (see
// configStandardsMap) render a chip. `resolve` returns one of: none (no governing standard),
// pending (data not in yet), managed (a Standard/Baseline governs this tenant), available (a
// standard exists but nothing manages it here).
const ManagementContext = createContext(null)

const MgmtChip = ({ status, label, onManage }) => {
  if (!status || status.state === 'none' || status.state === 'pending') {
    return null
  }
  const chip =
    status.state === 'managed'
      ? status.compliant === false
        ? { color: 'warning', text: 'Drift from standard' }
        : { color: 'success', text: 'Managed' }
      : { color: 'default', text: `Not enforced · add to ${label}` }
  return (
    <Chip
      size="small"
      variant="outlined"
      color={chip.color}
      label={chip.text}
      onClick={onManage}
      clickable
      sx={{ mt: 0.5, height: 22 }}
    />
  )
}

// One label/value line. The value is a neutral chip (booleans) or right-aligned text; a separate
// management chip under the label carries the "good vs bad" meaning where a standard governs it.
const Row = ({ label, value, chip, name }) => {
  const mgmt = useContext(ManagementContext)
  const status = mgmt && name ? mgmt.resolve(name) : null
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 2,
        py: 1.25,
      }}
    >
      <Box sx={{ minWidth: 0 }}>
        <Typography variant="body2">{label}</Typography>
        <MgmtChip
          status={status}
          label={mgmt?.label}
          onManage={mgmt?.onManage}
        />
      </Box>
      {chip ? (
        <Chip
          size="small"
          variant="outlined"
          label={value}
          sx={{ flexShrink: 0 }}
        />
      ) : (
        <Typography
          variant="body2"
          sx={{ color: 'text.secondary', textAlign: 'right', flexShrink: 0 }}
        >
          {value || '—'}
        </Typography>
      )}
    </Box>
  )
}

// Reads the live management system (whichever the Baselines flag selects) once for the tenant and
// resolves each mapped setting to managed / available. Degrades to no chip until the data is in.
const useConfigManagement = ({ tenant, baselinesActive, flagsReady }) => {
  const single = !!tenant && tenant !== 'AllTenants'
  const stdCompare = ApiGetCall({
    url: `/api/ListStandardsCompare?tenantFilter=${tenant}`,
    queryKey: `CfgStdCompare_${tenant}`,
    waiting: single && flagsReady && !baselinesActive,
    staleTime: 300000,
  })
  const baseAlign = ApiGetCall({
    url: `/api/ListBaselineAlignment?tenantFilter=${tenant}&byStandard=true`,
    queryKey: `CfgBaseAlign_${tenant}`,
    waiting: single && flagsReady && baselinesActive,
    staleTime: 300000,
  })

  // apiName -> { compliant }. Standards key their per-tenant object as "standards.<Name>";
  // baselines return per-standard rows keyed by a bare "<Name>" (optionally "<Name>#instance").
  const managedMap = useMemo(() => {
    const m = {}
    if (baselinesActive) {
      const data = baseAlign.data
      const rows = Array.isArray(data)
        ? data
        : data?.standards || data?.rows || data?.Results || []
      rows.forEach((r) => {
        const nm = r?.standardName || r?.StandardName
        if (!nm) return
        m[String(nm).split('#')[0]] = {
          compliant: r.compliant === true || r.status === 'Compliant',
        }
      })
    } else {
      const obj = Array.isArray(stdCompare.data)
        ? stdCompare.data.find((o) => o?.tenantFilter === tenant) ||
          stdCompare.data[0]
        : null
      if (obj) {
        Object.entries(obj).forEach(([k, v]) => {
          if (!k.startsWith('standards.')) return
          const api = k.slice('standards.'.length)
          if (api.includes('.')) return
          m[api] = {
            compliant:
              v?.Value === true ||
              (v?.CurrentValue != null &&
                JSON.stringify(v.CurrentValue) ===
                  JSON.stringify(v.ExpectedValue)),
          }
        })
      }
    }
    return m
  }, [baselinesActive, stdCompare.data, baseAlign.data, tenant])

  const ready = baselinesActive ? baseAlign.isSuccess : stdCompare.isSuccess

  return (fieldName) => {
    const api = configStandardsMap[fieldName]
    if (!api) return { state: 'none' }
    if (!ready) return { state: 'pending' }
    return managedMap[api]
      ? { state: 'managed', compliant: managedMap[api].compliant }
      : { state: 'available' }
  }
}

const Readout = ({ title, isFetching, error, errorText, children }) =>
  error ? (
    <Alert severity="warning">{errorText}</Alert>
  ) : (
    <CippButtonCard title={title} isFetching={isFetching}>
      <Stack divider={<Divider flexItem />} spacing={0}>
        {children}
      </Stack>
    </CippButtonCard>
  )

// Read-only render of a set of tenant-level boolean toggles. A field may set invert:true to show
// the opposite sense of the stored property (e.g. Exchange AuditDisabled shows as "Mailbox
// auditing enabled").
const SwitchesReadout = ({
  tenant,
  title,
  readUrl,
  queryKey,
  fields,
  description,
  errorText,
}) => {
  const settings = liveRead(readUrl, tenant, queryKey)
  const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
  const known = settings.isSuccess && !!d
  return (
    <Readout
      title={title}
      isFetching={settings.isFetching}
      error={settings.isError}
      errorText={
        errorText || 'Could not load these settings for the selected tenant.'
      }
    >
      {description && (
        <Typography variant="body2" sx={{ color: 'text.secondary', pt: 1 }}>
          {description}
        </Typography>
      )}
      {fields.map((f) => {
        const v = known ? (f.invert ? !d[f.name] : !!d[f.name]) : null
        return (
          <Row
            key={f.name}
            label={f.label}
            value={v === null ? '—' : boolText(v)}
            chip={v !== null}
            name={f.name}
          />
        )
      })}
    </Readout>
  )
}

const SharePointSection = ({ tenant }) => {
  const settings = liveRead(
    '/api/ListSharepointSettings',
    tenant,
    'SharepointSettings'
  )
  const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
  const known = settings.isSuccess && !!d
  const mode = d?.sharingDomainRestrictionMode || 'none'
  const domains = (
    mode === 'allowList'
      ? d?.sharingAllowedDomainList
      : mode === 'blockList'
        ? d?.sharingBlockedDomainList
        : []
  )?.join(', ')
  return (
    <Readout
      title="SharePoint & OneDrive"
      isFetching={settings.isFetching}
      error={settings.isError}
      errorText="Could not load SharePoint settings for this tenant. This usually means the tenant has no SharePoint/OneDrive licence."
    >
      <Row label="Default timezone" value={d?.tenantDefaultTimezone} />
      <Row
        label="External sharing level"
        value={
          findOption(sharingCapabilityOptions, d?.sharingCapability)?.label
        }
      />
      <Row
        label="Limit external sharing by domain"
        value={findOption(domainModeOptions, mode)?.label}
      />
      {mode !== 'none' && <Row label="Domains" value={domains} />}
      <Row
        label="Deleted user OneDrive retention"
        value={
          findOption(
            retentionOptions,
            String(d?.deletedUserPersonalSiteRetentionPeriodInDays)
          )?.label
        }
        name="deletedUserPersonalSiteRetentionPeriodInDays"
      />
      <Row
        label="Sync app excluded file extensions"
        value={(d?.excludedFileExtensionsForSyncApp || []).join(', ')}
      />
      <Row
        label="Allow external users to reshare"
        value={known ? boolText(!!d.isResharingByExternalUsersEnabled) : '—'}
        chip={known}
        name="isResharingByExternalUsersEnabled"
      />
      <Row
        label="Allow legacy authentication protocols"
        value={known ? boolText(!!d.isLegacyAuthProtocolsEnabled) : '—'}
        chip={known}
        name="isLegacyAuthProtocolsEnabled"
      />
      <Row
        label="Allow users to create sites"
        value={known ? boolText(!!d.isSiteCreationEnabled) : '—'}
        chip={known}
      />
      <Row
        label="Allow OneDrive sync on macOS"
        value={known ? boolText(!!d.isMacSyncAppEnabled) : '—'}
        chip={known}
      />
    </Readout>
  )
}

const EXCHANGE_FIELDS = [
  { name: 'BookingsEnabled', label: 'Allow Microsoft Bookings' },
  { name: 'MessageRecallEnabled', label: 'Allow cloud-based message recall' },
  { name: 'FocusedInboxOn', label: 'Focused Inbox on by default' },
  {
    name: 'SendFromAliasEnabled',
    label: 'Allow users to send from their aliases',
  },
  {
    name: 'OnlineMeetingsByDefaultEnabled',
    label: 'New meetings are Teams meetings by default',
  },
  {
    name: 'TwoClickMailPreviewEnabled',
    label: 'Require two-click preview for protected mail',
  },
  { name: 'EwsEnabled', label: 'Allow Exchange Web Services (EWS)' },
  { name: 'AuditDisabled', label: 'Mailbox auditing enabled', invert: true },
  {
    name: 'CustomerLockboxEnabled',
    label: 'Require approval for Microsoft support access (Customer Lockbox)',
  },
  {
    name: 'AppsForOfficeEnabled',
    label: 'Allow Outlook add-ins (apps for Office)',
  },
  {
    name: 'ConnectorsEnabled',
    label: 'Allow connected apps (connectors) in Outlook/Groups',
  },
  {
    name: 'LinkPreviewEnabled',
    label: 'Show link previews in Outlook on the web',
  },
  {
    name: 'ReadTrackingEnabled',
    label: 'Allow read receipts / message tracking',
  },
  {
    name: 'PublicComputersDetectionEnabled',
    label: 'Detect public computers in OWA',
  },
  {
    name: 'SmtpActionableMessagesEnabled',
    label: 'Allow actionable messages in email',
  },
  { name: 'OutlookPayEnabled', label: 'Allow Microsoft Pay in Outlook' },
]

const ExchangeOrgSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="Exchange Online — Organization settings"
    readUrl="/api/ListExchangeOrgConfig"
    queryKey="ExchangeOrgConfig"
    fields={EXCHANGE_FIELDS}
  />
)

const SPO_CSOM_FIELDS = [
  {
    name: 'DisableAddToOneDrive',
    label: 'Disable "Add shortcut to OneDrive" button',
  },
  {
    name: 'EnableAzureADB2BIntegration',
    label: 'Enable SharePoint/OneDrive B2B integration',
  },
  { name: 'CustomScriptsRestrictMode', label: 'Block custom scripts' },
  {
    name: 'DisableSharePointStoreAccess',
    label: 'Disable SharePoint Store app access',
  },
  {
    name: 'DisallowInfectedFileDownload',
    label: 'Block downloading malware-infected files',
  },
  {
    name: 'ShowPeoplePickerSuggestionsForGuestUsers',
    label: 'Show guests in the People Picker',
  },
  { name: 'HideSyncButtonOnDocLib', label: 'Hide the SharePoint Sync button' },
]

const SpoSharingSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="SharePoint — Sharing & sync"
    readUrl="/api/ListSpoTenantSettings"
    queryKey="SpoTenantSettings"
    fields={SPO_CSOM_FIELDS}
    description="Read from the SharePoint admin (CSOM) API. Requires SharePoint app-only consent for the tenant."
  />
)

const ENTRA_SWITCHES = [
  {
    name: 'allowedToUseSSPR',
    label: 'Admins can use Self-Service Password Reset',
  },
  { name: 'allowedToCreateApps', label: 'Users can register applications' },
  {
    name: 'allowedToCreateSecurityGroups',
    label: 'Users can create security groups',
  },
  { name: 'allowedToCreateTenants', label: 'Users can create tenants' },
  {
    name: 'allowedToReadBitLockerKeysForOwnedDevice',
    label: 'Users can read their own BitLocker keys',
  },
  {
    name: 'allowedToReadOtherUsers',
    label: 'Users can read other users in the directory',
  },
]

const EntraAuthSection = ({ tenant }) => {
  const settings = liveRead(
    '/api/ListEntraAuthPolicy',
    tenant,
    'EntraAuthPolicy'
  )
  const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
  const known = settings.isSuccess && !!d
  return (
    <Readout
      title="Entra — Authorization policy"
      isFetching={settings.isFetching}
      error={settings.isError}
      errorText="Could not load the authorization policy for this tenant."
    >
      <Row
        label="Who can invite guests"
        value={findOption(guestInviteOptions, d?.allowInvitesFrom)?.label}
        name="allowInvitesFrom"
      />
      <Row
        label="Guest access level in the directory"
        value={findOption(guestRoleOptions, d?.guestUserRoleId)?.label}
        name="guestUserRoleId"
      />
      {ENTRA_SWITCHES.map((f) => (
        <Row
          key={f.name}
          label={f.label}
          value={known ? boolText(!!d[f.name]) : '—'}
          chip={known}
          name={f.name}
        />
      ))}
    </Readout>
  )
}

const TEAMS_MEETING_FIELDS = [
  {
    name: 'AllowAnonymousUsersToJoinMeeting',
    label: 'Allow anonymous users to join meetings',
  },
  {
    name: 'AllowAnonymousUsersToStartMeeting',
    label: 'Allow anonymous users to start meetings',
  },
  {
    name: 'AllowPSTNUsersToBypassLobby',
    label: 'Dial-in users bypass the lobby',
  },
  {
    name: 'AllowExternalParticipantGiveRequestControl',
    label: 'External participants can give/request control',
  },
  {
    name: 'AllowParticipantGiveRequestControl',
    label: 'Participants can give/request control',
  },
]

const TEAMS_MESSAGING_FIELDS = [
  { name: 'AllowUserEditMessage', label: 'Users can edit their messages' },
  { name: 'AllowUserDeleteMessage', label: 'Users can delete their messages' },
  { name: 'AllowOwnerDeleteMessage', label: 'Owners can delete any message' },
  { name: 'AllowUserDeleteChat', label: 'Users can delete chats' },
  {
    name: 'AllowSecurityEndUserReporting',
    label: 'Users can report messages as a security concern',
  },
]

const TEAMS_CLIENT_FIELDS = [
  { name: 'AllowGuestUser', label: 'Allow guest users in Teams' },
  {
    name: 'AllowEmailIntoChannel',
    label: 'Allow email into a channel address',
  },
]

const TEAMS_EXTERNAL_FIELDS = [
  {
    name: 'EnableFederationAccess',
    label: 'Allow federation with other organizations',
  },
  {
    name: 'EnableTeamsConsumerAccess',
    label: 'Allow communication with unmanaged (consumer) Teams',
  },
  {
    name: 'EnableTeamsConsumerInbound',
    label: 'Unmanaged Teams users can initiate contact',
  },
]

// Factory for a Teams Global-policy leaf (each is one policy type = one read).
const teamsLeaf = (title, policyType, fields) =>
  function TeamsSection({ tenant }) {
    return (
      <SwitchesReadout
        tenant={tenant}
        title={`Teams — ${title}`}
        readUrl={`/api/ListTeamsConfig?policyType=${policyType}`}
        queryKey={`Teams_${policyType}`}
        fields={fields}
      />
    )
  }

const TeamsMeetingSection = teamsLeaf(
  'Meetings',
  'TeamsMeetingPolicy',
  TEAMS_MEETING_FIELDS
)
const TeamsMessagingSection = teamsLeaf(
  'Messaging',
  'TeamsMessagingPolicy',
  TEAMS_MESSAGING_FIELDS
)
const TeamsExternalSection = teamsLeaf(
  'External access',
  'ExternalAccessPolicy',
  TEAMS_EXTERNAL_FIELDS
)
const TeamsClientSection = teamsLeaf(
  'Client & guest access',
  'TeamsClientConfiguration',
  TEAMS_CLIENT_FIELDS
)

const XTAP_FIELDS = [
  { name: 'isMfaAccepted', label: 'Trust MFA claims from other Entra tenants' },
  {
    name: 'isCompliantDeviceAccepted',
    label: 'Trust compliant-device claims from other tenants',
  },
  {
    name: 'isHybridAzureADJoinedDeviceAccepted',
    label: 'Trust hybrid-joined-device claims from other tenants',
  },
]

const CrossTenantAccessSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="Entra — Cross-tenant access (inbound trust)"
    readUrl="/api/ListCrossTenantAccess"
    queryKey="CrossTenantAccess"
    fields={XTAP_FIELDS}
    description="Whether your Conditional Access honours MFA and device-compliance claims from a guest's home tenant."
  />
)

const OWA_FIELDS = [
  {
    name: 'AdditionalStorageProvidersAvailable',
    label: 'Allow third-party storage providers in OWA',
  },
  {
    name: 'DirectFileAccessOnPublicComputersEnabled',
    label: 'Direct file access on public computers',
  },
  {
    name: 'DirectFileAccessOnPrivateComputersEnabled',
    label: 'Direct file access on private computers',
  },
]

const OwaMailboxSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="Exchange Online — OWA mailbox policy"
    readUrl="/api/ListOwaMailboxPolicy"
    queryKey="OwaMailboxPolicy"
    fields={OWA_FIELDS}
  />
)

const ORG_CONTACT_FIELDS = [
  {
    name: 'technicalNotificationMails',
    label: 'Technical notification emails',
  },
  {
    name: 'securityComplianceNotificationMails',
    label: 'Security & compliance notification emails',
  },
  {
    name: 'marketingNotificationEmails',
    label: 'Marketing notification emails',
  },
]

const OrgContactsSection = ({ tenant }) => {
  const settings = liveRead('/api/ListOrgContacts', tenant, 'OrgContacts')
  const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
  return (
    <Readout
      title="Organization — Notification contacts"
      isFetching={settings.isFetching}
      error={settings.isError}
      errorText="Could not load organization contacts for this tenant."
    >
      {ORG_CONTACT_FIELDS.map((f) => (
        <Row
          key={f.name}
          label={f.label}
          value={(d?.[f.name] || []).join(', ')}
        />
      ))}
    </Readout>
  )
}

const DeviceRegSection = ({ tenant }) => {
  const settings = liveRead(
    '/api/ListDeviceRegistrationPolicy',
    tenant,
    'DeviceRegPolicy'
  )
  const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
  const known = settings.isSuccess && !!d
  return (
    <Readout
      title="Entra — Device registration"
      isFetching={settings.isFetching}
      error={settings.isError}
      errorText="Could not load the device registration policy."
    >
      <Row
        label="Enable Windows LAPS"
        value={known ? boolText(!!d.lapsEnabled) : '—'}
        chip={known}
      />
      <Row
        label="Maximum devices per user"
        value={
          d?.userDeviceQuota != null ? String(d.userDeviceQuota) : undefined
        }
      />
    </Readout>
  )
}

const AuditLogSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="Audit Log"
    readUrl="/api/ListAdminAuditLogConfig"
    queryKey="AdminAuditLogConfig"
    description="Whether the Unified Audit Log is ingesting activity across the tenant."
    fields={[
      {
        name: 'UnifiedAuditLogIngestionEnabled',
        label: 'Unified Audit Log enabled',
      },
    ]}
    errorText="Could not load the audit log configuration for this tenant."
  />
)

const UsageReportsSection = ({ tenant }) => (
  <SwitchesReadout
    tenant={tenant}
    title="Usage Reports"
    readUrl="/api/ListAdminReportSettings"
    queryKey="AdminReportSettings"
    description="When enabled, Microsoft 365 usage reports show de-identified names instead of real user, group, and site names."
    fields={[
      {
        name: 'displayConcealedNames',
        label: 'Conceal names in usage reports',
      },
    ]}
    errorText="Could not load the usage report settings for this tenant."
  />
)

// Each leaf = one Microsoft 365 resource = one live read (single-tenant) and one cached fleet
// type (all-tenants). Leaves are grouped into categories for the nav tree.
const SECTIONS = [
  {
    key: 'sharepoint',
    category: 'SharePoint & OneDrive',
    title: 'Tenant settings',
    icon: <CippIcons.CloudIcon />,
    Component: SharePointSection,
    cacheType: 'SharePointAdminSettings',
    columns: [
      'tenantDefaultTimezone',
      'sharingCapability',
      'sharingDomainRestrictionMode',
    ],
  },
  {
    key: 'spo-sharing',
    category: 'SharePoint & OneDrive',
    title: 'Sharing & sync',
    icon: <CippIcons.Share />,
    Component: SpoSharingSection,
    cacheType: null,
    columns: [],
  },
  {
    key: 'exchange',
    category: 'Exchange Online',
    title: 'Organization settings',
    icon: <CippIcons.EnvelopeIcon />,
    Component: ExchangeOrgSection,
    cacheType: 'ExoOrganizationConfig',
    columns: [
      'BookingsEnabled',
      'FocusedInboxOn',
      'EwsEnabled',
      'AuditDisabled',
    ],
  },
  {
    key: 'exchange-owa',
    category: 'Exchange Online',
    title: 'OWA mailbox policy',
    icon: <CippIcons.EnvelopeIcon />,
    Component: OwaMailboxSection,
    cacheType: null,
    columns: [],
  },
  {
    key: 'entra-auth',
    category: 'Entra (Identity)',
    title: 'Authorization policy',
    icon: <CippIcons.UserGroupIcon />,
    Component: EntraAuthSection,
    cacheType: 'AuthorizationPolicy',
    columns: ['allowInvitesFrom', 'guestUserRoleId'],
  },
  {
    key: 'entra-xtap',
    category: 'Entra (Identity)',
    title: 'Cross-tenant access',
    icon: <CippIcons.UserGroupIcon />,
    Component: CrossTenantAccessSection,
    cacheType: 'CrossTenantAccessPolicy',
    columns: ['isMfaAccepted', 'isCompliantDeviceAccepted'],
  },
  {
    key: 'entra-devicereg',
    category: 'Entra (Identity)',
    title: 'Device registration',
    icon: <CippIcons.UserGroupIcon />,
    Component: DeviceRegSection,
    cacheType: null,
    columns: [],
  },
  {
    key: 'teams-meetings',
    category: 'Teams',
    title: 'Meetings',
    icon: <CippIcons.UsersIcon />,
    Component: TeamsMeetingSection,
    cacheType: 'CsTeamsMeetingPolicy',
    columns: [
      'AllowAnonymousUsersToJoinMeeting',
      'AllowExternalParticipantGiveRequestControl',
    ],
  },
  {
    key: 'teams-messaging',
    category: 'Teams',
    title: 'Messaging',
    icon: <CippIcons.UsersIcon />,
    Component: TeamsMessagingSection,
    cacheType: 'CsTeamsMessagingPolicy',
    columns: ['AllowUserDeleteMessage', 'AllowSecurityEndUserReporting'],
  },
  {
    key: 'teams-external',
    category: 'Teams',
    title: 'External access',
    icon: <CippIcons.UsersIcon />,
    Component: TeamsExternalSection,
    cacheType: 'CsExternalAccessPolicy',
    columns: ['EnableFederationAccess', 'EnableTeamsConsumerAccess'],
  },
  {
    key: 'teams-client',
    category: 'Teams',
    title: 'Client & guest access',
    icon: <CippIcons.UsersIcon />,
    Component: TeamsClientSection,
    cacheType: 'CsTeamsClientConfiguration',
    columns: ['AllowGuestUser', 'AllowEmailIntoChannel'],
  },
  {
    key: 'org-contacts',
    category: 'Organization',
    title: 'Notification contacts',
    icon: <CippIcons.EnvelopeIcon />,
    Component: OrgContactsSection,
    cacheType: null,
    columns: [],
  },
  {
    key: 'audit',
    category: 'Audit & Reports',
    title: 'Unified Audit Log',
    icon: <CippIcons.ShieldCheckIcon />,
    Component: AuditLogSection,
    cacheType: 'ExoAdminAuditLogConfig',
    columns: ['UnifiedAuditLogIngestionEnabled'],
  },
  {
    key: 'reports',
    category: 'Audit & Reports',
    title: 'Usage report privacy',
    icon: <CippIcons.ChartBarIcon />,
    Component: UsageReportsSection,
    cacheType: 'AdminReportSettings',
    columns: ['displayConcealedNames'],
  },
]

const CATEGORIES = SECTIONS.reduce(
  (acc, s) => (acc.includes(s.category) ? acc : [...acc, s.category]),
  []
)

// Flat search index: every leaf plus its individual settings, each pointing at the leaf to open.
const fieldEntries = (leafKey, category, fields) =>
  fields.map((f) => ({ label: `${category} · ${f.label}`, key: leafKey }))

const SEARCH_INDEX = [
  ...SECTIONS.map((s) => ({ label: `${s.category} · ${s.title}`, key: s.key })),
  ...fieldEntries('exchange', 'Exchange', EXCHANGE_FIELDS),
  ...fieldEntries('spo-sharing', 'SharePoint', SPO_CSOM_FIELDS),
  ...fieldEntries('entra-auth', 'Entra', ENTRA_SWITCHES),
  ...fieldEntries('entra-xtap', 'Cross-tenant access', XTAP_FIELDS),
  ...fieldEntries('exchange-owa', 'OWA', OWA_FIELDS),
  ...fieldEntries('org-contacts', 'Organization', ORG_CONTACT_FIELDS),
  { label: 'Entra · Windows LAPS', key: 'entra-devicereg' },
  { label: 'Entra · Max devices per user', key: 'entra-devicereg' },
  ...fieldEntries('teams-meetings', 'Teams Meetings', TEAMS_MEETING_FIELDS),
  ...fieldEntries('teams-messaging', 'Teams Messaging', TEAMS_MESSAGING_FIELDS),
  ...fieldEntries('teams-external', 'Teams External', TEAMS_EXTERNAL_FIELDS),
  ...fieldEntries('teams-client', 'Teams Client', TEAMS_CLIENT_FIELDS),
  // Bespoke leaves (their fields are not in a shared array) - a few high-value search terms.
  { label: 'SharePoint · Default timezone', key: 'sharepoint' },
  { label: 'SharePoint · External sharing level', key: 'sharepoint' },
  { label: 'SharePoint · Domain sharing restriction', key: 'sharepoint' },
  { label: 'SharePoint · Allow legacy authentication', key: 'sharepoint' },
  { label: 'Entra · Guest invite scope', key: 'entra-auth' },
  { label: 'Entra · Guest access level', key: 'entra-auth' },
]

// All-tenants (fleet) view: cached values across every tenant for the leaf's type.
const FleetTable = ({ section }) => {
  const fleet = ApiGetCall({
    url: `/api/ListTenantConfigFleet?type=${section.cacheType}`,
    queryKey: `Fleet_${section.cacheType}`,
    staleTime: 0,
  })
  return (
    <CippButtonCard
      title={`${section.title} — All Tenants`}
      isFetching={fleet.isFetching}
    >
      <Typography variant="body2" sx={{ color: 'text.secondary', mb: 2 }}>
        Cached values across all tenants. Select a specific tenant to view it
        live.
      </Typography>
      <CippDataTable
        noCard={true}
        data={Array.isArray(fleet.data) ? fleet.data : []}
        simpleColumns={['Tenant', ...section.columns]}
        isFetching={fleet.isFetching}
      />
    </CippButtonCard>
  )
}

const Page = () => {
  const router = useRouter()
  const settings = useSettings()
  const currentTenant = router.query.tenantFilter || settings.currentTenant
  const title = 'Manage Tenant'

  // Baselines and classic Standards are mutually exclusive - the Baselines feature flag switches
  // the estate from one to the other. Point the "manage this properly" call-to-action at whichever
  // one is live.
  const featureFlags = ApiGetCall({
    url: '/api/ListFeatureFlags',
    queryKey: 'featureFlags',
    staleTime: 600000,
  })
  const baselinesActive =
    Array.isArray(featureFlags.data) &&
    featureFlags.data.some(
      (f) =>
        (f.Id === 'Baselines' || f.Name === 'Baselines') &&
        (f.Enabled === true || f.enabled === true)
    )
  const mgmtLabel = baselinesActive ? 'Baselines' : 'Standards'
  const mgmtNoun = baselinesActive ? 'Baseline' : 'Standard'
  const mgmtPath = baselinesActive
    ? '/tenant/baselines/templates'
    : '/tenant/standards/templates'

  const resolveManagement = useConfigManagement({
    tenant: currentTenant,
    baselinesActive,
    flagsReady: featureFlags.isSuccess,
  })
  const mgmt = {
    resolve: resolveManagement,
    label: mgmtLabel,
    onManage: () => router.push(mgmtPath),
  }

  // The selected leaf lives in the URL (?section=) so sections are deep-linkable.
  const sectionKey =
    SECTIONS.find((s) => s.key === router.query.section)?.key || SECTIONS[0].key
  const activeSection =
    SECTIONS.find((s) => s.key === sectionKey) || SECTIONS[0]
  const ActiveComponent = activeSection.Component
  const isAllTenants = currentTenant === 'AllTenants'
  const [openCategory, setOpenCategory] = useState(activeSection.category)

  const goToSection = (key) => {
    const sec = SECTIONS.find((s) => s.key === key)
    if (sec) setOpenCategory(sec.category)
    router.replace(
      { pathname: router.pathname, query: { ...router.query, section: key } },
      undefined,
      { shallow: true }
    )
  }

  return (
    <HeaderedTabbedLayout
      tabOptions={tabOptions}
      title={title}
      actions={[]}
      actionsData={{}}
    >
      <CippHead title="Configuration" />
      <Box sx={{ p: 1 }}>
        {!currentTenant ? (
          <Box sx={{ py: 4 }}>
            <Typography variant="body1" sx={{ color: 'text.secondary' }}>
              Select a tenant to view its configuration, or choose All Tenants
              for a fleet overview.
            </Typography>
          </Box>
        ) : (
          <>
            <Alert
              severity="info"
              icon={
                <SvgIcon fontSize="inherit">
                  <CippIcons.ShieldCheckIcon />
                </SvgIcon>
              }
              action={
                <Button
                  color="inherit"
                  size="small"
                  onClick={() => router.push(mgmtPath)}
                >
                  Open {mgmtLabel} templates
                </Button>
              }
              sx={{ mb: 2 }}
            >
              This is a read-only view of tenant configuration. To change any of
              these settings, enforce it through a {mgmtNoun} so it stays
              applied and configuration drift is detected.
            </Alert>
            <Grid container spacing={3}>
              {/* Left: search + category tree. Right: single-tenant live config, or all-tenants fleet table. */}
              <Grid size={{ md: 3, xs: 12 }}>
                <Autocomplete
                  size="small"
                  sx={{ mb: 2 }}
                  options={SEARCH_INDEX}
                  getOptionLabel={(o) => o.label}
                  onChange={(e, value) => value && goToSection(value.key)}
                  renderInput={(params) => (
                    <TextField {...params} label="Search settings" />
                  )}
                  isOptionEqualToValue={(o, v) => o.label === v.label}
                  clearOnBlur
                  blurOnSelect
                />
                <Card variant="outlined">
                  <List disablePadding>
                    {CATEGORIES.map((category) => {
                      const leaves = SECTIONS.filter(
                        (s) => s.category === category
                      )
                      const open = openCategory === category
                      return (
                        <Box key={category}>
                          <ListItemButton
                            onClick={() =>
                              setOpenCategory(open ? null : category)
                            }
                          >
                            <ListItemText primary={category} />
                            <SvgIcon
                              fontSize="small"
                              sx={{
                                transition: 'transform 0.2s',
                                transform: open ? 'rotate(90deg)' : 'none',
                              }}
                            >
                              <CippIcons.ChevronRightIcon />
                            </SvgIcon>
                          </ListItemButton>
                          <Collapse in={open} unmountOnExit>
                            <List disablePadding>
                              {leaves.map((section) => (
                                <ListItemButton
                                  key={section.key}
                                  selected={section.key === sectionKey}
                                  sx={{ pl: 4 }}
                                  onClick={() => goToSection(section.key)}
                                >
                                  <ListItemIcon sx={{ minWidth: 36 }}>
                                    <SvgIcon fontSize="small">
                                      {section.icon}
                                    </SvgIcon>
                                  </ListItemIcon>
                                  <ListItemText primary={section.title} />
                                </ListItemButton>
                              ))}
                            </List>
                          </Collapse>
                        </Box>
                      )
                    })}
                  </List>
                </Card>
              </Grid>
              <Grid size={{ md: 9, xs: 12 }}>
                {isAllTenants ? (
                  activeSection.cacheType ? (
                    <FleetTable
                      key={`fleet-${activeSection.key}`}
                      section={activeSection}
                    />
                  ) : (
                    <CippButtonCard
                      title={`${activeSection.title} — All Tenants`}
                    >
                      <Alert severity="info">
                        A fleet overview is not available for this area yet.
                        Select a specific tenant to view its settings.
                      </Alert>
                    </CippButtonCard>
                  )
                ) : (
                  <ManagementContext.Provider value={mgmt}>
                    <ActiveComponent
                      key={activeSection.key}
                      tenant={currentTenant}
                    />
                  </ManagementContext.Provider>
                )}
              </Grid>
            </Grid>
          </>
        )}
      </Box>
    </HeaderedTabbedLayout>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
