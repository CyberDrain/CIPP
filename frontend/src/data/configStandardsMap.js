// Maps a Configuration-page setting field to the API name of the Standard that governs it - the
// Invoke-CIPPStandard<Name> suffix, i.e. the standards.json `name` minus the "standards." prefix.
// The Configuration page is read-only; this map is how it shows whether each setting is under
// management (by a Standard or Baseline) and routes you to the system that manages it.
//
// Each entry was confirmed by finding the standard whose body reads/sets that exact property.
// Expand this as more field -> standard mappings are confirmed. A field with no entry here simply
// renders without a management chip ("not covered by a standard"), which is correct - not every
// tenant setting has a governing standard. The Teams policy standards govern several fields each
// (one policy = one standard), so those fields all point at the same standard.
export const configStandardsMap = {
  // Exchange Online - Organization settings
  EwsEnabled: 'DisableEWS',
  AuditDisabled: 'EnableMailboxAuditing',
  BookingsEnabled: 'Bookings',
  MessageRecallEnabled: 'CloudMessageRecall',
  FocusedInboxOn: 'FocusedInbox',
  SendFromAliasEnabled: 'SendFromAlias',
  CustomerLockboxEnabled: 'EnableCustomerLockbox',

  // Exchange Online - OWA mailbox policy
  AdditionalStorageProvidersAvailable: 'DisableAdditionalStorageProviders',

  // SharePoint & OneDrive - Tenant settings
  isLegacyAuthProtocolsEnabled: 'DisableSharePointLegacyAuth',
  isResharingByExternalUsersEnabled: 'DisableReshare',
  deletedUserPersonalSiteRetentionPeriodInDays: 'DeletedUserRentention',

  // SharePoint - Sharing & sync
  DisallowInfectedFileDownload: 'SPDisallowInfectedFiles',
  DisableAddToOneDrive: 'DisableAddShortcutsToOneDrive',
  EnableAzureADB2BIntegration: 'SPAzureB2B',
  ShowPeoplePickerSuggestionsForGuestUsers: 'SPGuestPeoplePicker',

  // Entra - Authorization policy
  allowInvitesFrom: 'GuestInvite',
  guestUserRoleId: 'DisableGuestDirectory',
  allowedToUseSSPR: 'AdminSSPR',
  allowedToCreateApps: 'DisableAppCreation',
  allowedToCreateSecurityGroups: 'DisableSecurityGroupUsers',
  allowedToCreateTenants: 'DisableTenantCreation',
  allowedToReadBitLockerKeysForOwnedDevice: 'BitLockerKeysForOwnedDevice',

  // Entra - Cross-tenant access (inbound trust)
  isMfaAccepted: 'ExternalMFATrusted',
  isCompliantDeviceAccepted: 'ExternalComplianceTrusted',

  // Teams - Meetings (all governed by the one meeting-policy standard)
  AllowAnonymousUsersToJoinMeeting: 'TeamsGlobalMeetingPolicy',
  AllowAnonymousUsersToStartMeeting: 'TeamsGlobalMeetingPolicy',
  AllowPSTNUsersToBypassLobby: 'TeamsGlobalMeetingPolicy',
  AllowExternalParticipantGiveRequestControl: 'TeamsGlobalMeetingPolicy',
  AllowParticipantGiveRequestControl: 'TeamsGlobalMeetingPolicy',

  // Teams - Messaging (all governed by the one messaging-policy standard)
  AllowUserEditMessage: 'TeamsMessagingPolicy',
  AllowUserDeleteMessage: 'TeamsMessagingPolicy',
  AllowOwnerDeleteMessage: 'TeamsMessagingPolicy',
  AllowUserDeleteChat: 'TeamsMessagingPolicy',
  AllowSecurityEndUserReporting: 'TeamsMessagingPolicy',

  // Teams - External access
  EnableFederationAccess: 'TeamsExternalAccessPolicy',
  EnableTeamsConsumerAccess: 'TeamsExternalAccessPolicy',
  EnableTeamsConsumerInbound: 'TeamsExternalAccessPolicy',

  // Teams - Client & guest access
  AllowGuestUser: 'TeamsGuestAccess',
  AllowEmailIntoChannel: 'TeamsEmailIntegration',

  // Audit & Reports - Unified Audit Log
  UnifiedAuditLogIngestionEnabled: 'AuditLog',
}
