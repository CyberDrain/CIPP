// The attacker-objective model for the BEC case workspace. One place decides which finding and
// which score signal belongs to which objective, so the triage header (score spine) and the
// evidence groups stay in lock-step: click a fired signal, land on the group that explains it.
//
// A finding is { key, title, columns, rows?, sections?, summary?, alert?, empty?, note?, custom? }:
//  - `key` is the becData field the finding is about (and the flag/coverage lookup key);
//  - `rows(becData, ctx)` projects the table rows (defaults to becData[key]); `columns` are the
//    CippDataTable simpleColumns; `actions` names a component-provided row-action set;
//  - `sections` are extra titled tables below the main one, each { title, rows, columns };
//  - `summary` is a sentence shown above the tables, `alert` a warning banner, `empty` the prose when
//    there is nothing to show;
//  - `custom` names one of the few renderers whose shape is not tables (component-owned).
// ctx is { windowDays, windowStart }. What is flagged and why comes from becFindingFlags (below), and
// whether a check could run from BEC_FINDING_MARKERS - never from the finding object.

const arr = (value) => (Array.isArray(value) ? value : [])
export const joinList = (value) =>
  Array.isArray(value) ? value.join(', ') : (value ?? '')

export const BEC_GROUPS = [
  {
    id: 'access',
    title: 'Access & identity',
    icon: 'Login',
    blurb: 'How the account was reached and who can sign in as it now.',
    findings: [
      {
        key: 'SuspectUserSignIns',
        title: 'Interactive sign-ins',
        columns: [
          'CreatedDateTime',
          'AppDisplayName',
          'Status',
          'IPAddress',
          'Country',
          'City',
          'ForeignLocation',
        ],
      },
      {
        key: 'NonInteractiveSignIns',
        title: 'Non-interactive sign-ins (token use)',
        columns: [
          'CreatedDateTime',
          'AppDisplayName',
          'ResourceDisplayName',
          'Status',
          'IPAddress',
          'Country',
          'City',
          'IncomingTokenType',
          'ForeignLocation',
        ],
      },
      {
        key: 'MFADevices',
        title: 'MFA methods',
        columns: ['Method', 'displayName', 'createdDateTime', 'Recent'],
        rows: (b, ctx) =>
          arr(b.MFADevices).map((m) => ({
            Method: String(m['@odata.type'] || '').replace(
              '#microsoft.graph.',
              ''
            ),
            displayName: m.displayName,
            createdDateTime: m.createdDateTime,
            Recent: m.createdDateTime
              ? new Date(m.createdDateTime) >= ctx.windowStart
              : false,
          })),
        empty:
          'No MFA methods are registered. If MFA was expected, an attacker may have removed it.',
      },
      { key: 'RiskState', title: 'Identity Protection', custom: 'risk' },
      {
        key: 'RegisteredDevices',
        title: 'Entra registered devices',
        columns: [
          'displayName',
          'operatingSystem',
          'trustType',
          'registrationDateTime',
          'approximateLastSignInDateTime',
          'accountEnabled',
          'isCompliant',
          'RegisteredInWindow',
        ],
      },
      {
        key: 'IntuneDevices',
        title: 'Intune-managed devices',
        columns: [
          'deviceName',
          'operatingSystem',
          'osVersion',
          'complianceState',
          'enrolledDateTime',
          'lastSyncDateTime',
          'deviceEnrollmentType',
          'serialNumber',
        ],
        actions: 'intune',
        empty: 'No Intune-managed devices found for this user.',
      },
    ],
  },
  {
    id: 'persistence',
    title: 'Persistence',
    icon: 'Key',
    blurb:
      'Footholds that survive a password reset — rules, consents, delegations, apps.',
    findings: [
      {
        key: 'NewRules',
        title: 'Inbox rules',
        columns: ['Name', 'RecentlyChanged', 'RiskReasons', 'Description'],
        rows: (b) =>
          arr(b.NewRules).map((r) => ({
            Name: r.Name,
            RecentlyChanged: r.RecentlyChanged === true,
            RiskReasons: joinList(r.RiskReasons),
            Description: r.Description,
            // Surfaced in the More Info panel (not as columns) so the rule's behaviour is readable in full.
            MoveToFolder: r.MoveToFolder,
            DeleteMessage: r.DeleteMessage,
            MarkAsRead: r.MarkAsRead,
            StopProcessingRules: r.StopProcessingRules,
            Enabled: r.Enabled,
            Risk: r.Risk,
          })),
        sections: [
          {
            title: (ctx) => `Rule changes in the last ${ctx.windowDays} days`,
            rows: (b) => arr(b.InboxRuleChanges),
            columns: [
              'Operation',
              'RuleName',
              'Date',
              'UserKey',
              'ClientIP',
              'Country',
              'ForeignLocation',
            ],
          },
        ],
        empty: 'No inbox rules or rule changes found.',
      },
      {
        key: 'Delegations',
        title: 'Mailbox delegations',
        columns: [
          'PermissionType',
          'Trustee',
          'AccessRights',
          'Resource',
          'Flagged',
        ],
      },
      {
        key: 'UserGrants',
        title: 'Application consents',
        columns: [
          'ClientDisplayName',
          'Type',
          'Risk',
          'HighRiskScopes',
          'Publisher',
          'PublisherVerified',
          'CatalogMatch',
          'Scope',
        ],
        // nested objects the table cannot render flat
        rows: (b) =>
          arr(b.UserGrants).map((g) => ({
            ...g,
            HighRiskScopes: joinList(g.HighRiskScopes),
            CatalogMatch: g.CatalogMatch?.Name
              ? `${g.CatalogMatch.Name} (${g.CatalogMatch.Source})`
              : '',
          })),
      },
      {
        key: 'MailboxAddIns',
        title: 'Mailbox add-ins',
        columns: [
          'DisplayName',
          'ProviderName',
          'Enabled',
          'Scope',
          'Type',
          'AppVersion',
          'Flagged',
        ],
      },
      {
        key: 'AddedApps',
        title: 'New applications',
        // Catalog matches first - a match is the point of this check, whatever the app's age. The
        // catalog is CIPP's own MaliciousApps.json merged with the Huntress rogue-apps feed; Source says which.
        columns: [
          'displayName',
          'appId',
          'CatalogName',
          'Source',
          'Categories',
          'Description',
          'accountEnabled',
          'createdDateTime',
        ],
        rows: (b) =>
          arr(b.MaliciousSPs).map((a) => ({
            ...a,
            Categories: joinList(a.Categories),
          })),
        alert: (b) =>
          arr(b.MaliciousSPs).length > 0
            ? `${arr(b.MaliciousSPs).length} application(s) in this tenant match the known-malicious catalog. Consent-based access survives a password reset — remove any that are not explained.`
            : null,
        sections: [
          {
            title: 'New applications in the window',
            rows: (b) =>
              arr(b.AddedApps).map((a) => ({
                displayName: a.displayName,
                appId: a.appId,
                createdDateTime: a.createdDateTime,
                MaliciousMatch: a.MaliciousMatch?.Name || '',
                Source: a.MaliciousMatch?.Source || '',
                Categories: joinList(a.MaliciousMatch?.Categories),
                Description: a.MaliciousMatch?.Description || '',
              })),
            columns: [
              'displayName',
              'appId',
              'createdDateTime',
              'MaliciousMatch',
              'Source',
              'Categories',
            ],
          },
        ],
        empty: 'No new applications found.',
      },
    ],
  },
  {
    id: 'mailflow',
    title: 'Mail manipulation',
    icon: 'ForwardToInbox',
    blurb:
      'Bending mail flow — forwarding, safelists, transport rules, mailbox permissions.',
    findings: [
      { key: 'MailboxState', title: 'Mailbox state', custom: 'mailboxState' },
      {
        key: 'TrustedSenders',
        title: 'Trusted & blocked senders',
        columns: ['Sender', 'Type'],
        rows: (b) => [
          ...arr(b.TrustedSenders).map((s) => ({ Sender: s, Type: 'Trusted' })),
          ...arr(b.BlockedSenders).map((s) => ({ Sender: s, Type: 'Blocked' })),
        ],
        sections: [
          {
            title: (ctx) => `Changes in the last ${ctx.windowDays} days`,
            rows: (b) => arr(b.SafelistChanges),
            columns: [
              'Operation',
              'UserKey',
              'Date',
              'ClientIP',
              'Country',
              'ForeignLocation',
            ],
          },
        ],
        empty: 'No trusted or blocked senders found.',
      },
      {
        key: 'TransportRuleChanges',
        title: 'Transport rules',
        columns: [
          'Date',
          'Operation',
          'RuleName',
          'Actor',
          'ClientIP',
          'Country',
          'RiskyParameters',
          'Flagged',
        ],
        rows: (b) =>
          arr(b.TransportRuleChanges).map((c) => ({
            ...c,
            RiskyParameters: joinList(c.RiskyParameters),
          })),
        sections: [
          {
            title: 'Current rules that divert or suppress mail',
            rows: (b) =>
              arr(b.TransportRulesFlagged).map((r) => ({
                ...r,
                RiskReasons: joinList(r.RiskReasons),
              })),
            columns: [
              'Name',
              'State',
              'Mode',
              'WhenChanged',
              'ChangedInWindow',
              'RiskReasons',
            ],
          },
        ],
        empty: 'No transport-rule changes or diverting rules found.',
      },
      {
        key: 'MailboxPermissionChanges',
        title: 'Mailbox permission changes',
        columns: [
          'UserKey',
          'Operation',
          'Permissions',
          'Date',
          'ClientIP',
          'Country',
          'TargetsSuspect',
        ],
      },
    ],
  },
  {
    id: 'exfil',
    title: 'Exfiltration & spread',
    icon: 'CloudUpload',
    blurb:
      'What left and who was hit — sent bursts, sharing links, mail activity, phishing.',
    findings: [
      {
        key: 'SentMessages',
        title: 'Sent messages',
        columns: [
          'Subject',
          'RecipientAddress',
          'Status',
          'Received',
          'FromIP',
          'Country',
        ],
        summary: (b, ctx) => {
          const a = b.SentMessageAnalysis
          if (!a) return null
          const sent = arr(b.SentMessages)
          return (
            `${a.TotalMessages ?? sent.length} message(s) to ${a.TotalRecipients ?? sent.length} recipient(s) in the last ${ctx.windowDays} days.` +
            (a.FlaggedSubjectCount > 0
              ? ` ${a.FlaggedSubjectCount} subject(s) look like a campaign.`
              : '') +
            (arr(a.Bursts).length > 0
              ? ` ${arr(a.Bursts).length} send burst(s).`
              : '')
          )
        },
        sections: [
          {
            title: 'Repeated subjects',
            rows: (b) => arr(b.SentMessageAnalysis?.RepeatedSubjects),
            columns: [
              'Subject',
              'MessageCount',
              'RecipientCount',
              'FirstSent',
              'LastSent',
              'Flagged',
            ],
          },
          {
            title: 'Send bursts',
            rows: (b) => arr(b.SentMessageAnalysis?.Bursts),
            columns: [
              'WindowStart',
              'WindowMinutes',
              'MessageCount',
              'RecipientCount',
              'TopSubject',
            ],
          },
        ],
        empty: 'No sent messages found in the window.',
      },
      {
        key: 'SharingChanges',
        title: 'Sharing links',
        columns: [
          'Date',
          'Operation',
          'FileName',
          'Target',
          'Workload',
          'ClientIP',
          'Country',
          'ForeignLocation',
        ],
      },
      {
        key: 'MailActivity',
        title: 'Mailbox activity',
        columns: [
          'Operation',
          'Count',
          'ClientIP',
          'Country',
          'ForeignLocation',
          'ClientInfoString',
          'MailAccessType',
          'Actor',
          'FirstSeen',
          'LastSeen',
        ],
        summary: (b) => {
          const s = b.MailActivitySummary
          if (!s) return null
          return (
            `${s.MailItemsAccessedCount} access(es), ${s.HardDeleteCount} hard delete(s), ${s.SoftDeleteCount} soft delete(s), ${s.SendCount} send(s) from ${s.DistinctClientIPs} client IP(s). Counts only — no items were read.` +
            (s.HardDeleteExceeded
              ? ` Hard deletes exceed the ${s.HardDeleteThreshold} threshold.`
              : '')
          )
        },
        empty: 'No mailbox-activity counts were recorded.',
      },
      {
        key: 'ReceivedMailFindings',
        title: 'Received mail & Defender',
        custom: 'received',
      },
    ],
  },
  {
    id: 'blast',
    title: 'Blast radius · tenant',
    icon: 'Business',
    blurb: 'Tenant-wide signals that outlast the one mailbox.',
    findings: [
      {
        key: 'NewUsers',
        title: 'Recently added users',
        columns: ['userPrincipalName', 'createdDateTime'],
      },
      {
        key: 'ChangedPasswords',
        title: 'Recent password changes',
        columns: ['displayName', 'lastPasswordChangeDateTime'],
      },
      {
        key: 'DirectoryAudits',
        title: 'Entra directory audit',
        note: 'The Entra event timeline (who, when, from where). It intentionally overlaps the findings above — a consent, MFA registration, device add or password reset here is the event behind an item under Access or Persistence, and adds the actor, IP and time those state findings lack. Use it to corroborate and time them, not as separate incidents.',
        columns: [
          'ActivityDateTime',
          'Activity',
          'Result',
          'InitiatedBy',
          'ClientIP',
          'Country',
          'Targets',
          'Direction',
          'Flagged',
        ],
      },
    ],
  },
]

// Score signal -> objective group, so a fired signal in the triage spine jumps to its evidence.
export const BEC_SIGNAL_GROUP = {
  NewRules: 'persistence',
  InboxRuleChanges: 'persistence',
  SuspiciousRules: 'persistence',
  NewApps: 'persistence',
  MaliciousApps: 'persistence',
  FlaggedDelegations: 'persistence',
  RiskyUserGrants: 'persistence',
  CatalogUserGrants: 'persistence',
  FlaggedMailboxAddIns: 'persistence',
  PermissionChanges: 'mailflow',
  PermissionChangesTargetingUser: 'mailflow',
  SafelistChanges: 'mailflow',
  RiskyTransportRuleChanges: 'mailflow',
  ForeignSuccessfulSignIns: 'access',
  ForeignActivity: 'access',
  ForeignNonInteractiveSignIns: 'access',
  RecentMfaMethods: 'access',
  RecentIntuneDevices: 'access',
  RecentRegisteredDevices: 'access',
  RiskyUserHigh: 'access',
  RiskyUserMedium: 'access',
  RiskyUserLow: 'access',
  ConfirmedCompromised: 'access',
  AnonymousLinks: 'exfil',
  MassMail: 'exfil',
  TyposquatSenders: 'exfil',
  DefenderDetections: 'exfil',
  SuspiciousMailActivity: 'exfil',
  NewUsers: 'blast',
  FlaggedDirectoryAudits: 'blast',
}

// Completeness marker key(s) each finding depends on, so the UI can show a check that could not run
// (missing licence/permission) as "skipped" — never as a clean pass. Keyed by the finding's becData key.
export const BEC_FINDING_MARKERS = {
  SuspectUserSignIns: ['SignIns'],
  NonInteractiveSignIns: ['NonInteractiveSignIns'],
  MFADevices: ['MFAMethods'],
  RiskState: ['RiskState'],
  RegisteredDevices: ['RegisteredDevices'],
  IntuneDevices: ['IntuneDevices'],
  NewRules: ['InboxRules', 'InboxRuleChanges'],
  Delegations: ['Delegations'],
  UserGrants: ['UserGrants'],
  MailboxAddIns: ['MailboxAddIns'],
  AddedApps: ['NewApps'],
  MailboxState: ['MailboxState'],
  TrustedSenders: ['Safelists', 'SafelistChanges'],
  TransportRuleChanges: ['TransportRuleChanges', 'TransportRulesFlagged'],
  MailboxPermissionChanges: ['AuditLog'],
  SentMessages: ['SentMessages'],
  SharingChanges: ['SharingChanges'],
  MailActivity: ['MailActivity'],
  ReceivedMailFindings: ['ReceivedMailFindings', 'DefenderDetections'],
  NewUsers: ['TenantUsers'],
  ChangedPasswords: ['TenantUsers'],
  DirectoryAudits: ['DirectoryAudits'],
}

// Coverage across a finding's completeness markers, so it renders "skipped" / "failed" / "partial"
// precisely instead of a false "nothing found". `allBlocked` is true only when *every* marker was
// skipped or failed — a finding with some markers still complete (e.g. phishing ran but Defender
// was skipped) keeps `allBlocked` false so its content is still shown alongside the note.
export const becCoverage = (completeness, markerKeys) => {
  const ms = (markerKeys || []).map((k) => completeness?.[k]).filter(Boolean)
  const skipped = ms.filter((m) => m.Skipped)
  const failed = ms.filter((m) => m.Complete === false && !m.Skipped && m.Error)
  const partial = ms.filter((m) => m.Complete === false && !m.Skipped && m.Cap)
  const state =
    skipped.length > 0
      ? 'skipped'
      : failed.length > 0
        ? 'failed'
        : partial.length > 0
          ? 'partial'
          : 'ok'
  return {
    state,
    allBlocked: ms.length > 0 && skipped.length + failed.length === ms.length,
    requirement: [
      ...new Set(skipped.map((m) => m.Requirement).filter(Boolean)),
    ].join(', '),
    error: failed
      .map((m) => m.Error)
      .filter(Boolean)
      .join('; '),
    cap: partial
      .map((m) => m.Cap)
      .filter(Boolean)
      .join('; '),
  }
}

// The checks that could not run (missing licence/permission), for the triage caveat and group badges.
export const becSkippedChecks = (becData) =>
  Object.entries(becData?.Completeness || {})
    .filter(([, m]) => m && m.Skipped)
    .map(([name, m]) => ({ name, requirement: m.Requirement }))

// Start of the analysis window: windowDays before the run was extracted (now, for a run without a date).
export const becWindowStart = (becData, windowDays = 7) => {
  const extracted = new Date(becData?.ExtractedAt || Date.now())
  const base = Number.isNaN(extracted.getTime())
    ? Date.now()
    : extracted.getTime()
  return new Date(base - windowDays * 86400000)
}

export const becLevelColor = (level) =>
  level === 'High'
    ? 'error'
    : level === 'Medium'
      ? 'warning'
      : level === 'Low'
        ? 'success'
        : 'default'

// Per-finding flag: for each finding key, { count, reason } when it has something worth attention,
// else null. This is the single source of truth for "what is flagged and why" - the finding header
// shows the reason, and the group badge (below) is just the sum. Same predicates the score uses.
export const becFindingFlags = (becData, windowDays = 7) => {
  const b = becData || {}
  const a = (v) => (Array.isArray(v) ? v : [])
  const windowStart = becWindowStart(b, windowDays)
  const inWindow = (v) => {
    if (!v) return false
    const d = new Date(v)
    return !Number.isNaN(d.getTime()) && d >= windowStart
  }
  const la = b.LocationAnalysis || {}
  const flag = (count, reason) => (count > 0 ? { count, reason } : null)

  const mailboxStateReasons = []
  if (b.MailboxState?.HasForwarding)
    mailboxStateReasons.push('mail is forwarded to an external address')
  if (
    b.MailboxState?.AutoReplyState &&
    b.MailboxState.AutoReplyState !== 'Disabled'
  )
    mailboxStateReasons.push('an automatic reply is enabled')

  return {
    SuspectUserSignIns: flag(
      la.ForeignSuccessfulSignInCount || 0,
      `successful sign-in(s) from outside ${la.UsageLocation || 'the usage location'}`
    ),
    NonInteractiveSignIns: flag(
      a(b.NonInteractiveSignIns).filter(
        (s) => s.ForeignLocation === true && s.Status === 'Success'
      ).length,
      'successful token use from outside the usage location'
    ),
    MFADevices: flag(
      a(b.MFADevices).filter((m) => inWindow(m.createdDateTime)).length,
      `MFA method(s) registered in the last ${windowDays} days`
    ),
    RiskState: flag(
      b.RiskState?.Listed ? 1 : 0,
      `Identity Protection lists this user as ${b.RiskState?.RiskLevel || 'at'} risk`
    ),
    RegisteredDevices: flag(
      a(b.RegisteredDevices).filter((d) => d.RegisteredInWindow).length,
      `device(s) registered in the last ${windowDays} days`
    ),
    IntuneDevices: flag(
      a(b.IntuneDevices).filter((d) => inWindow(d.enrolledDateTime)).length,
      `device(s) enrolled in the last ${windowDays} days`
    ),
    NewRules: (() => {
      // Flag only the rules the backend marked suspicious (hiding, forwarding, delete, acts-on-all,
      // sensitive keywords) - a benign rule is not worth a flag. Old reports fall back to RiskReasons.
      const suspicious = a(b.NewRules).filter(
        (r) =>
          r.Suspicious ||
          (Array.isArray(r.RiskReasons) && r.RiskReasons.length > 0)
      )
      return suspicious.length > 0
        ? {
            count: suspicious.length,
            reason:
              'inbox rule(s) that hide, forward, delete, or act on all incoming mail',
          }
        : null
    })(),
    Delegations: flag(
      a(b.Delegations).filter((d) => d.Flagged).length,
      'delegation(s) to an external, guest or catch-all trustee'
    ),
    UserGrants: flag(
      a(b.UserGrants).filter((g) => g.Flagged).length,
      'consent(s) matching the rogue-app catalog or a high-risk scope'
    ),
    MailboxAddIns: flag(
      a(b.MailboxAddIns).filter((x) => x.Flagged).length,
      'user-installed add-in(s) from a non-Microsoft provider'
    ),
    AddedApps: flag(
      a(b.AddedApps).filter((x) => x.MaliciousMatch).length +
        a(b.MaliciousSPs).length,
      'application(s) matching the known-malicious catalog'
    ),
    MailboxState:
      mailboxStateReasons.length > 0
        ? {
            count: mailboxStateReasons.length,
            reason: mailboxStateReasons.join('; '),
          }
        : null,
    TrustedSenders: flag(
      a(b.SafelistChanges).length,
      `trusted/blocked sender change(s) in the last ${windowDays} days`
    ),
    TransportRuleChanges: flag(
      a(b.TransportRuleChanges).filter((c) => c.Flagged).length,
      'transport-rule change(s) with a diversion or suppression action'
    ),
    MailboxPermissionChanges: flag(
      a(b.MailboxPermissionChanges).filter((c) => c.TargetsSuspect === true)
        .length,
      'permission change(s) targeting this mailbox'
    ),
    SentMessages: flag(
      b.SentMessageAnalysis?.Flagged ? 1 : 0,
      'a mass-mail or campaign pattern in the sent messages'
    ),
    SharingChanges: flag(
      a(b.SharingChanges).filter((c) =>
        String(c.Operation).startsWith('AnonymousLink')
      ).length,
      'anonymous sharing link(s) anyone with the URL can open'
    ),
    MailActivity: flag(
      b.MailActivitySummary?.HardDeleteExceeded ? 1 : 0,
      'hard deletes exceed the threshold — a sign of covering tracks'
    ),
    ReceivedMailFindings: flag(
      // Every ReceivedMailFinding is already a hit (typosquat, phishing-shaped subject pattern, or
      // keyword) - counting only typosquats made a subject-pattern finding read as "clear".
      a(b.ReceivedMailFindings).length +
        a(b.DefenderDetections).filter((d) => d.Delivered).length,
      'phishing-shaped subject(s), look-alike sender domain(s) or a delivered threat'
    ),
    NewUsers: flag(
      a(b.NewUsers).length,
      `user(s) added to the tenant in the last ${windowDays} days`
    ),
    DirectoryAudits: flag(
      a(b.DirectoryAudits).filter((x) => x.Flagged).length,
      'flagged directory-audit event(s) — security-info, consent, role or token'
    ),
  }
}

// Flagged count per objective: the sum of its findings' flags, so the group badge and the per-finding
// reasons can never disagree. Shared by the case page (default-open) and the group badge.
export const becGroupFlagged = (becData, windowDays = 7) => {
  const flags = becFindingFlags(becData, windowDays)
  return BEC_GROUPS.reduce((totals, group) => {
    totals[group.id] = group.findings.reduce(
      (n, f) => n + (flags[f.key]?.count || 0),
      0
    )
    return totals
  }, {})
}
