import { Layout as DashboardLayout } from '../../../layouts/index'
import { HeaderedTabbedLayout } from '../../../layouts/HeaderedTabbedLayout'
import { useForm, useWatch } from 'react-hook-form'
import { useEffect, useState } from 'react'
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
} from '@mui/material'
import { Grid } from '@mui/system'
import { ApiGetCall, ApiPostCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'
import CippButtonCard from '../../../components/CippCards/CippButtonCard'
import CippFormComponent from '../../../components/CippComponents/CippFormComponent'
import { CippFormCondition } from '../../../components/CippComponents/CippFormCondition'
import { CippApiResults } from '../../../components/CippComponents/CippApiResults'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import { CippIcons } from '../../../utils/icon-registry'
import tabOptions from './tabOptions.json'
import timezoneList from '../../../data/timezoneList'

const splitList = (value) =>
  (value || '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean)

const timezoneOptions = timezoneList.map((tz) => ({
  label: tz.timezone,
  value: tz.timezone,
}))

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

const findOption = (options, value) =>
  options.find((o) => o.value === value) || null

// Every section reads live (staleTime 0) so config is never stale, and only the opened
// section's area of Microsoft 365 is queried. Saves do not invalidate the read, so the form
// keeps the values just submitted rather than briefly showing the pre-replication value.
const liveRead = (url, tenant, queryKey) => {
  const sep = url.includes('?') ? '&' : '?'
  return ApiGetCall({
    url: `${url}${sep}tenantFilter=${tenant}`,
    queryKey: `${queryKey}_${tenant}`,
    staleTime: 0,
  })
}

const SaveButton = ({ save, settings, onClick }) => (
  <Button
    variant="contained"
    startIcon={
      <SvgIcon fontSize="small">
        <CippIcons.Save />
      </SvgIcon>
    }
    onClick={onClick}
    disabled={save.isPending || settings.isFetching || settings.isError}
  >
    {save.isPending ? 'Saving...' : 'Save Changes'}
  </Button>
)

// A boolean setting that may only move toward its secure state: locked (read-only) once secure,
// one-way when not. The note points to the standard that can enforce it continuously. The
// backend also refuses insecure values for these, so this is defence in depth, not the only gate.
const SecuredSwitch = ({ field, formControl }) => {
  const value = useWatch({ control: formControl.control, name: field.name })
  const atSecure = !!value === field.secured.value
  return (
    <Box>
      <CippFormComponent
        type="switch"
        name={field.name}
        label={field.label}
        formControl={formControl}
        disabled={atSecure}
      />
      <Typography
        variant="caption"
        sx={{ color: 'text.secondary', display: 'block', ml: 1 }}
      >
        {atSecure
          ? 'Secured — locked at its secure state.'
          : 'Secured — can only be set to its secure state.'}
        {field.secured.standard
          ? ` Enforce continuously with the “${field.secured.standard}” standard.`
          : ''}
      </Typography>
    </Box>
  )
}

const SharePointSection = ({ tenant }) => {
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead(
    '/api/ListSharepointSettings',
    tenant,
    'SharepointSettings'
  )
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    const mode = d.sharingDomainRestrictionMode || 'none'
    formControl.reset({
      tenantDefaultTimezone: d.tenantDefaultTimezone
        ? { label: d.tenantDefaultTimezone, value: d.tenantDefaultTimezone }
        : null,
      sharingCapability: findOption(
        sharingCapabilityOptions,
        d.sharingCapability
      ),
      sharingDomainRestrictionMode: findOption(domainModeOptions, mode),
      domains: (mode === 'allowList'
        ? d.sharingAllowedDomainList
        : mode === 'blockList'
          ? d.sharingBlockedDomainList
          : []
      )?.join(', '),
      isResharingByExternalUsersEnabled: !!d.isResharingByExternalUsersEnabled,
      isLegacyAuthProtocolsEnabled: !!d.isLegacyAuthProtocolsEnabled,
      isSiteCreationEnabled: !!d.isSiteCreationEnabled,
      isMacSyncAppEnabled: !!d.isMacSyncAppEnabled,
      excludedFileExtensionsForSyncApp: (
        d.excludedFileExtensionsForSyncApp || []
      ).join(', '),
      deletedUserPersonalSiteRetentionPeriodInDays: findOption(
        retentionOptions,
        String(d.deletedUserPersonalSiteRetentionPeriodInDays)
      ),
    })
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    const mode = v.sharingDomainRestrictionMode?.value
    const s = {
      tenantDefaultTimezone: v.tenantDefaultTimezone?.value,
      sharingCapability: v.sharingCapability?.value,
      sharingDomainRestrictionMode: mode,
      isResharingByExternalUsersEnabled: v.isResharingByExternalUsersEnabled,
      isLegacyAuthProtocolsEnabled: v.isLegacyAuthProtocolsEnabled,
      isSiteCreationEnabled: v.isSiteCreationEnabled,
      isSiteCreationUIEnabled: v.isSiteCreationEnabled,
      isMacSyncAppEnabled: v.isMacSyncAppEnabled,
      excludedFileExtensionsForSyncApp: splitList(
        v.excludedFileExtensionsForSyncApp
      ),
      deletedUserPersonalSiteRetentionPeriodInDays: v
        .deletedUserPersonalSiteRetentionPeriodInDays?.value
        ? Number(v.deletedUserPersonalSiteRetentionPeriodInDays.value)
        : undefined,
    }
    if (mode === 'allowList') s.sharingAllowedDomainList = splitList(v.domains)
    if (mode === 'blockList') s.sharingBlockedDomainList = splitList(v.domains)
    save.mutate({
      url: '/api/ExecSetSharepointSettings',
      data: { tenantFilter: tenant, settings: s },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load SharePoint settings for this tenant. This usually means
        the tenant has no SharePoint/OneDrive licence.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title="SharePoint & OneDrive"
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        <CippFormComponent
          type="autoComplete"
          name="tenantDefaultTimezone"
          label="Default timezone"
          formControl={formControl}
          options={timezoneOptions}
          multiple={false}
          creatable={false}
        />
        <CippFormComponent
          type="autoComplete"
          name="sharingCapability"
          label="External sharing level"
          formControl={formControl}
          options={sharingCapabilityOptions}
          multiple={false}
          creatable={false}
        />
        <CippFormComponent
          type="autoComplete"
          name="sharingDomainRestrictionMode"
          label="Limit external sharing by domain"
          formControl={formControl}
          options={domainModeOptions}
          multiple={false}
          creatable={false}
        />
        <CippFormCondition
          field="sharingDomainRestrictionMode"
          compareType="valueNotEq"
          compareValue="none"
          formControl={formControl}
        >
          <CippFormComponent
            type="textField"
            name="domains"
            label="Domains (comma separated)"
            formControl={formControl}
          />
        </CippFormCondition>
        <CippFormComponent
          type="autoComplete"
          name="deletedUserPersonalSiteRetentionPeriodInDays"
          label="Deleted user OneDrive retention"
          formControl={formControl}
          options={retentionOptions}
          multiple={false}
          creatable={false}
        />
        <CippFormComponent
          type="textField"
          name="excludedFileExtensionsForSyncApp"
          label="Sync app excluded file extensions (comma separated)"
          formControl={formControl}
        />
        <CippFormComponent
          type="switch"
          name="isResharingByExternalUsersEnabled"
          label="Allow external users to reshare"
          formControl={formControl}
        />
        <SecuredSwitch
          field={{
            name: 'isLegacyAuthProtocolsEnabled',
            label: 'Allow legacy authentication protocols',
            secured: {
              value: false,
              standard: 'Disable SharePoint Legacy Authentication',
            },
          }}
          formControl={formControl}
        />
        <CippFormComponent
          type="switch"
          name="isSiteCreationEnabled"
          label="Allow users to create sites"
          formControl={formControl}
        />
        <CippFormComponent
          type="switch"
          name="isMacSyncAppEnabled"
          label="Allow OneDrive sync on macOS"
          formControl={formControl}
        />
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
  )
}

// Shared section for a single tenant-level boolean setting.
const BooleanSection = ({
  tenant,
  title,
  label,
  description,
  name,
  readUrl,
  saveUrl,
  queryKey,
  secured,
}) => {
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead(readUrl, tenant, queryKey)
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    formControl.reset({ [name]: !!d[name] })
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    save.mutate({
      url: saveUrl,
      data: { tenantFilter: tenant, [name]: !!v[name] },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load this setting for the selected tenant.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title={title}
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        {description && (
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            {description}
          </Typography>
        )}
        {secured ? (
          <SecuredSwitch
            field={{ name, label, secured }}
            formControl={formControl}
          />
        ) : (
          <CippFormComponent
            type="switch"
            name={name}
            label={label}
            formControl={formControl}
          />
        )}
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
  )
}

// Section rendering a set of tenant-level boolean toggles that POST as { tenantFilter, settings }.
// A field may set invert:true to display the opposite sense of the stored property (e.g. Exchange
// AuditDisabled is shown as "Mailbox auditing enabled").
const SwitchesSection = ({
  tenant,
  title,
  readUrl,
  saveUrl,
  queryKey,
  fields,
  description,
  saveExtra,
}) => {
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead(readUrl, tenant, queryKey)
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    const values = {}
    fields.forEach((f) => {
      values[f.name] = f.invert ? !d[f.name] : !!d[f.name]
    })
    formControl.reset(values)
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    const s = {}
    fields.forEach((f) => {
      s[f.name] = f.invert ? !v[f.name] : !!v[f.name]
    })
    save.mutate({
      url: saveUrl,
      data: { tenantFilter: tenant, settings: s, ...(saveExtra || {}) },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load these settings for the selected tenant.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title={title}
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        {description && (
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            {description}
          </Typography>
        )}
        {fields.map((f) =>
          f.secured ? (
            <SecuredSwitch key={f.name} field={f} formControl={formControl} />
          ) : (
            <CippFormComponent
              key={f.name}
              type="switch"
              name={f.name}
              label={f.label}
              formControl={formControl}
            />
          )
        )}
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
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
  {
    name: 'EwsEnabled',
    label: 'Allow Exchange Web Services (EWS)',
    secured: { value: false, standard: 'Disable Exchange Web Services' },
  },
  {
    name: 'AuditDisabled',
    label: 'Mailbox auditing enabled',
    invert: true,
    secured: { value: true, standard: 'Enable Mailbox Auditing' },
  },
  {
    name: 'CustomerLockboxEnabled',
    label: 'Require approval for Microsoft support access (Customer Lockbox)',
  },
  {
    name: 'AppsForOfficeEnabled',
    label: 'Allow Outlook add-ins (apps for Office)',
  },
  {
    name: 'OAuth2ClientProfileEnabled',
    label: 'Enable modern authentication (OAuth2) for OWA/EAS',
    secured: { value: true, standard: 'Enable Modern Authentication' },
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
  <SwitchesSection
    tenant={tenant}
    title="Exchange Online — Organization settings"
    readUrl="/api/ListExchangeOrgConfig"
    saveUrl="/api/ExecSetExchangeOrgConfig"
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
    secured: { value: true, standard: 'Disallow Infected File Download' },
  },
  {
    name: 'ShowPeoplePickerSuggestionsForGuestUsers',
    label: 'Show guests in the People Picker',
  },
  { name: 'HideSyncButtonOnDocLib', label: 'Hide the SharePoint Sync button' },
]

const SpoSharingSection = ({ tenant }) => (
  <SwitchesSection
    tenant={tenant}
    title="SharePoint — Sharing & sync"
    readUrl="/api/ListSpoTenantSettings"
    saveUrl="/api/ExecSetSpoTenantSettings"
    queryKey="SpoTenantSettings"
    fields={SPO_CSOM_FIELDS}
    description="Set through the SharePoint admin (CSOM) API. Requires SharePoint app-only consent for the tenant."
  />
)

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

const ENTRA_SWITCHES = [
  {
    name: 'allowedToUseSSPR',
    label: 'Admins can use Self-Service Password Reset',
  },
  {
    name: 'blockMsolPowerShell',
    label: 'Block legacy MSOnline PowerShell access',
    secured: { value: true, standard: null },
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
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead(
    '/api/ListEntraAuthPolicy',
    tenant,
    'EntraAuthPolicy'
  )
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    const values = {
      allowInvitesFrom: findOption(guestInviteOptions, d.allowInvitesFrom),
      guestUserRoleId: findOption(guestRoleOptions, d.guestUserRoleId),
    }
    ENTRA_SWITCHES.forEach((f) => {
      values[f.name] = !!d[f.name]
    })
    formControl.reset(values)
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    const s = {
      allowInvitesFrom: v.allowInvitesFrom?.value,
      guestUserRoleId: v.guestUserRoleId?.value,
    }
    ENTRA_SWITCHES.forEach((f) => {
      s[f.name] = !!v[f.name]
    })
    save.mutate({
      url: '/api/ExecSetEntraAuthPolicy',
      data: { tenantFilter: tenant, settings: s },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load the authorization policy for this tenant.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title="Entra — Authorization policy"
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        <CippFormComponent
          type="autoComplete"
          name="allowInvitesFrom"
          label="Who can invite guests"
          formControl={formControl}
          options={guestInviteOptions}
          multiple={false}
          creatable={false}
        />
        <CippFormComponent
          type="autoComplete"
          name="guestUserRoleId"
          label="Guest access level in the directory"
          formControl={formControl}
          options={guestRoleOptions}
          multiple={false}
          creatable={false}
        />
        {ENTRA_SWITCHES.map((f) => (
          <CippFormComponent
            key={f.name}
            type="switch"
            name={f.name}
            label={f.label}
            formControl={formControl}
          />
        ))}
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
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

// Factory for a Teams Global-policy leaf (each is one policy type = one read + one write).
const teamsLeaf = (title, policyType, fields) =>
  function TeamsSection({ tenant }) {
    return (
      <SwitchesSection
        tenant={tenant}
        title={`Teams — ${title}`}
        readUrl={`/api/ListTeamsConfig?policyType=${policyType}`}
        saveUrl="/api/ExecSetTeamsConfig"
        saveExtra={{ policyType }}
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
  <SwitchesSection
    tenant={tenant}
    title="Entra — Cross-tenant access (inbound trust)"
    readUrl="/api/ListCrossTenantAccess"
    saveUrl="/api/ExecSetCrossTenantAccess"
    queryKey="CrossTenantAccess"
    fields={XTAP_FIELDS}
    description="Trust MFA and device-compliance claims from a guest's home tenant so your Conditional Access can honour them."
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
  <SwitchesSection
    tenant={tenant}
    title="Exchange Online — OWA mailbox policy"
    readUrl="/api/ListOwaMailboxPolicy"
    saveUrl="/api/ExecSetOwaMailboxPolicy"
    queryKey="OwaMailboxPolicy"
    fields={OWA_FIELDS}
  />
)

const ORG_CONTACT_FIELDS = [
  {
    name: 'technicalNotificationMails',
    label: 'Technical notification emails (comma separated)',
  },
  {
    name: 'securityComplianceNotificationMails',
    label: 'Security & compliance notification emails (comma separated)',
  },
  {
    name: 'marketingNotificationEmails',
    label: 'Marketing notification emails (comma separated)',
  },
]

const OrgContactsSection = ({ tenant }) => {
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead('/api/ListOrgContacts', tenant, 'OrgContacts')
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    formControl.reset({
      technicalNotificationMails: (d.technicalNotificationMails || []).join(
        ', '
      ),
      securityComplianceNotificationMails: (
        d.securityComplianceNotificationMails || []
      ).join(', '),
      marketingNotificationEmails: (d.marketingNotificationEmails || []).join(
        ', '
      ),
    })
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    save.mutate({
      url: '/api/ExecSetOrgContacts',
      data: {
        tenantFilter: tenant,
        settings: {
          technicalNotificationMails: splitList(v.technicalNotificationMails),
          securityComplianceNotificationMails: splitList(
            v.securityComplianceNotificationMails
          ),
          marketingNotificationEmails: splitList(v.marketingNotificationEmails),
        },
      },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load organization contacts for this tenant.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title="Organization — Notification contacts"
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        {ORG_CONTACT_FIELDS.map((f) => (
          <CippFormComponent
            key={f.name}
            type="textField"
            name={f.name}
            label={f.label}
            formControl={formControl}
          />
        ))}
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
  )
}

const DeviceRegSection = ({ tenant }) => {
  const formControl = useForm({ mode: 'onChange' })
  const settings = liveRead(
    '/api/ListDeviceRegistrationPolicy',
    tenant,
    'DeviceRegPolicy'
  )
  const save = ApiPostCall({})

  useEffect(() => {
    const d = Array.isArray(settings.data) ? settings.data[0] : settings.data
    if (!settings.isSuccess || !d) return
    formControl.reset({
      lapsEnabled: !!d.lapsEnabled,
      userDeviceQuota: d.userDeviceQuota,
    })
  }, [settings.isSuccess, settings.data])

  const onSave = (v) => {
    save.mutate({
      url: '/api/ExecSetDeviceRegistrationPolicy',
      data: {
        tenantFilter: tenant,
        settings: {
          lapsEnabled: !!v.lapsEnabled,
          userDeviceQuota:
            v.userDeviceQuota !== '' && v.userDeviceQuota != null
              ? Number(v.userDeviceQuota)
              : undefined,
        },
      },
    })
  }

  if (settings.isError) {
    return (
      <Alert severity="warning">
        Could not load the device registration policy.
      </Alert>
    )
  }

  return (
    <CippButtonCard
      title="Entra — Device registration"
      CardButton={
        <SaveButton
          save={save}
          settings={settings}
          onClick={formControl.handleSubmit(onSave)}
        />
      }
      isFetching={settings.isFetching}
    >
      <Stack spacing={2}>
        <CippFormComponent
          type="switch"
          name="lapsEnabled"
          label="Enable Windows LAPS"
          formControl={formControl}
        />
        <CippFormComponent
          type="number"
          name="userDeviceQuota"
          label="Maximum devices per user"
          formControl={formControl}
        />
        <CippApiResults apiObject={save} />
      </Stack>
    </CippButtonCard>
  )
}

const AuditLogSection = ({ tenant }) => (
  <BooleanSection
    tenant={tenant}
    title="Audit Log"
    label="Enable the Unified Audit Log"
    description="Enables the Unified Audit Log for tracking and auditing activity across the tenant."
    name="UnifiedAuditLogIngestionEnabled"
    readUrl="/api/ListAdminAuditLogConfig"
    saveUrl="/api/ExecSetAdminAuditLogConfig"
    queryKey="AdminAuditLogConfig"
    secured={{ value: true, standard: 'Enable the Unified Audit Log' }}
  />
)

const UsageReportsSection = ({ tenant }) => (
  <BooleanSection
    tenant={tenant}
    title="Usage Reports"
    label="Conceal user, group, and site names in usage reports"
    description="When enabled, Microsoft 365 usage reports show de-identified names instead of real user, group, and site names."
    name="displayConcealedNames"
    readUrl="/api/ListAdminReportSettings"
    saveUrl="/api/ExecSetAdminReportSettings"
    queryKey="AdminReportSettings"
  />
)

// Each leaf = one Microsoft 365 resource = one live read + one write (single-tenant) and one
// cached fleet type (all-tenants). Leaves are grouped into categories for the nav tree.
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
    // CSOM values are cached in a separate table, not the reporting DB, so no fleet view yet.
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
        Cached values across all tenants. Select a specific tenant to change a
        value live.
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
              Select a tenant to view and set its configuration, or choose All
              Tenants for a fleet overview.
            </Typography>
          </Box>
        ) : (
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
                      Select a specific tenant to view and change its settings.
                    </Alert>
                  </CippButtonCard>
                )
              ) : (
                <ActiveComponent
                  key={activeSection.key}
                  tenant={currentTenant}
                />
              )}
            </Grid>
          </Grid>
        )}
      </Box>
    </HeaderedTabbedLayout>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
