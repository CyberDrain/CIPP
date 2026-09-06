// The attacker-objective model for the BEC case workspace. One place decides which finding and
// which score signal belongs to which objective, so the triage header (score spine) and the
// evidence groups stay in lock-step: click a fired signal, land on the group that explains it.
//
// A finding is { key, title, columns?, custom? }: `key` is the becData field that holds its rows and
// `columns` are the CippDataTable simpleColumns; a bespoke finding (mailbox state, sent-mail analysis)
// carries `custom: '<renderer>'` instead. What is flagged and why comes from becFindingFlags (below),
// and whether a check could run from BEC_FINDING_MARKERS — not from the finding object.

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
      { key: 'MFADevices', title: 'MFA methods', custom: 'mfa' },
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
        custom: 'intune',
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
      { key: 'NewRules', title: 'Inbox rules', custom: 'rules' },
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
      { key: 'AddedApps', title: 'New applications', custom: 'apps' },
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
        custom: 'safelist',
      },
      {
        key: 'TransportRuleChanges',
        title: 'Transport rules',
        custom: 'transport',
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
      { key: 'SentMessages', title: 'Sent messages', custom: 'sent' },
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
        custom: 'mailActivity',
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
