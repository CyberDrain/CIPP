// Builds one correlated event stream from a completed BEC case — the same signals the PDF report's
// "Order of Events" folds together, shaped for the case-page views. Each event carries the attacker
// objective it serves, a severity, and structured correlation keys (source IP, app, location, external
// sender, and the other account it acted on) so a graph view can cluster events that share a source or
// a target, not just lay them out by time. The earliest access/foothold event is the likely start.

const toDate = (value) => {
  if (!value) return null
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}
const shortUpn = (value) => {
  const text = String(value ?? '')
  return text.length > 34 && text.includes('@') ? text.split('@')[0] : text
}
const clean = (value) => {
  const text = String(value ?? '').trim()
  return text.length > 0 ? text : null
}
const joinDetail = (...parts) => parts.filter(Boolean).join(' · ')

export const BEC_OBJECTIVE_LABEL = {
  access: 'Access',
  persistence: 'Persistence',
  mailflow: 'Mail flow',
  exfil: 'Exfiltration',
  blast: 'Blast radius',
}

export const BEC_OBJECTIVE_COLOR = {
  access: '#3182CE',
  persistence: '#805AD5',
  mailflow: '#DD6B20',
  exfil: '#E53E3E',
  blast: '#718096',
}

const auditObjective = (activity) => {
  const text = String(activity || '').toLowerCase()
  if (
    text.includes('consent') ||
    text.includes('permission grant') ||
    text.includes('role assignment') ||
    text.includes('service principal') ||
    text.includes('application')
  ) {
    return 'persistence'
  }
  if (
    text.includes('security info') ||
    text.includes('strong authentication') ||
    text.includes('password') ||
    text.includes('device')
  ) {
    return 'access'
  }
  if (text.includes('role') || text.includes('member')) return 'blast'
  return 'persistence'
}

const signInIp = (s) => clean(s.IPAddress || s.ipAddress || s.ClientIP)
const signInApp = (s) =>
  clean(s.AppDisplayName || s.appDisplayName || s.ClientAppUsed)
const signInLocation = (s) =>
  clean([s.City, s.Country].filter(Boolean).join(', '))

/**
 * @param {object} becData a completed BEC case payload (execBECCheck result)
 * @param {number} windowDays analysis window, for the "recent" cutoff on state findings
 * @returns {{ events: object[], startOfCompromise: object|null }}
 *   events are sorted ascending; each carries { id, ts, date, category, objective, severity, label,
 *   detail, graphDetail, ip, app, location, sender, actor, affects }.
 */
export function buildBecTimeline(becData, windowDays = 7, accountUpn = null) {
  if (!becData) return { events: [], startOfCompromise: null }
  const arr = (value) => (Array.isArray(value) ? value : [])

  // The investigated mailbox. Used to tell an action ON another account apart from one on this one:
  // `affects` is the *other* party, so the graph can draw the victim reaching out to colleagues,
  // recipients and mailboxes — never a self-referential edge back to the victim. The caller may pass
  // the UPN explicitly (the case page has it); production runs also store it on becData.
  const victimUpn = clean(
    accountUpn ||
      becData.UserPrincipalName ||
      becData?.userData?.userPrincipalName
  )
  const isVictim = (value) => {
    const cleaned = clean(value)
    return (
      !!victimUpn &&
      !!cleaned &&
      cleaned.toLowerCase() === victimUpn.toLowerCase()
    )
  }
  // First candidate that is a real, non-victim account — the other party an action touched.
  const otherAccount = (...candidates) => {
    for (const candidate of candidates) {
      const cleaned = clean(candidate)
      if (cleaned && !isVictim(cleaned)) return cleaned
    }
    return null
  }

  const analysisStart = (() => {
    const extracted = becData.ExtractedAt
      ? new Date(becData.ExtractedAt)
      : new Date()
    const base = Number.isNaN(extracted.getTime()) ? new Date() : extracted
    return new Date(base.getTime() - windowDays * 86400000)
  })()
  const isRecent = (value) => {
    const parsed = toDate(value)
    return parsed && parsed >= analysisStart
  }

  const foreignSignIns = arr(becData.SuspectUserSignIns).filter(
    (signIn) => signIn.ForeignLocation === true
  )

  const raw = [
    ...foreignSignIns.map((signIn) => ({
      key: 'signin',
      date: toDate(
        signIn.CreatedDateTime || signIn.createdDateTime || signIn.Timestamp
      ),
      category: 'signin',
      objective: 'access',
      severity: signIn.Status === 'Success' ? 'high' : 'medium',
      label: `Sign-in ${signIn.Status === 'Success' ? 'success' : `(${signIn.Status || 'attempt'})`}`,
      ip: signInIp(signIn),
      app: signInApp(signIn),
      location: signInLocation(signIn),
    })),
    ...arr(becData.DirectoryAudits)
      .filter((audit) => audit.Flagged)
      .map((audit) => ({
        key: 'audit',
        date: toDate(audit.ActivityDateTime),
        category: 'audit',
        objective: auditObjective(audit.Activity),
        severity: 'medium',
        label: audit.Activity || 'Directory change',
        ip: clean(audit.ClientIP),
        actor: shortUpn(audit.InitiatedBy),
      })),
    ...arr(becData.InboxRuleChanges).map((change) => ({
      key: 'rule',
      date: toDate(change.Date),
      category: 'rule',
      objective: 'persistence',
      severity: 'high',
      label: change.Operation || 'Inbox rule change',
      ip: clean(change.ClientIP),
      target: clean(change.RuleName),
      foreign: change.ForeignLocation === true,
    })),
    ...arr(becData.MailboxPermissionChanges).map((change) => ({
      key: 'permission',
      date: toDate(change.Date),
      category: 'permission',
      objective: 'mailflow',
      severity: change.TargetsSuspect ? 'high' : 'medium',
      label: change.Operation || 'Mailbox permission change',
      ip: clean(change.ClientIP),
      targetsSuspect: !!change.TargetsSuspect,
      // The counterparty, whichever isn't the victim: the grantee (Trustee) of a delegation first, then
      // the mailbox acted on. So a FullAccess/SendAs grant to a colleague ties that colleague in.
      affects: otherAccount(
        change.Trustee,
        change.ObjectId,
        change.User,
        change.UserKey
      ),
    })),
    ...arr(becData.SafelistChanges).map((change) => ({
      key: 'safelist',
      date: toDate(change.Date),
      category: 'safelist',
      objective: 'mailflow',
      severity: 'medium',
      label: change.Operation || 'Safelist change',
      ip: clean(change.ClientIP),
    })),
    ...arr(becData.SharingChanges).map((change) => ({
      key: 'sharing',
      date: toDate(change.Date),
      category: 'sharing',
      objective: 'exfil',
      severity: String(change.Operation || '').startsWith('AnonymousLink')
        ? 'high'
        : 'medium',
      label: change.Operation || 'Sharing change',
      ip: clean(change.ClientIP),
      target: clean(change.FileName),
      affects: otherAccount(
        change.SharedWith,
        change.TargetUserOrGroupName,
        change.Target
      ),
    })),
    ...arr(becData.SentMessages).map((message) => ({
      key: 'sent',
      date: toDate(message.Received),
      category: 'sent',
      objective: 'exfil',
      severity: 'info',
      label: 'Sent mail',
      ip: clean(message.FromIP),
      target: clean(message.Subject),
      recipient: clean(message.RecipientAddress),
      // The recipient is an account the compromised mailbox reached — onward/lateral phishing.
      affects: otherAccount(message.RecipientAddress),
    })),
    ...arr(becData.ReceivedMailFindings).map((finding) => ({
      key: 'received',
      date: toDate(finding.Received),
      category: 'received',
      objective: 'exfil',
      severity: finding.Severity === 'high' ? 'high' : 'medium',
      label: `Received: ${finding.FindingType || 'finding'}`,
      target: clean(finding.Subject),
      sender: clean(finding.SenderAddress),
    })),
    ...arr(becData.DefenderDetections)
      .filter((threat) => threat.Delivered)
      .map((threat) => ({
        key: 'threat',
        date: toDate(threat.ReceivedDateTime),
        category: 'threat',
        objective: 'exfil',
        severity: 'high',
        label: 'Threat delivered',
        target: clean(threat.Subject),
        sender: clean(threat.SenderAddress),
      })),
    ...arr(becData.NewUsers).map((user) => ({
      key: 'user',
      date: toDate(user.createdDateTime),
      category: 'user',
      objective: 'blast',
      severity: 'medium',
      label: 'User created',
      target: clean(user.displayName),
      // A brand-new account is itself the other party — attacker-provisioned persistence.
      affects: otherAccount(user.userPrincipalName, user.displayName),
    })),
    ...arr(becData.MFADevices)
      .filter((method) => isRecent(method.createdDateTime))
      .map((method) => ({
        key: 'mfa',
        date: toDate(method.createdDateTime),
        category: 'mfa',
        objective: 'access',
        severity: 'high',
        label: 'MFA method registered',
        target: String(method['@odata.type'] || '').replace(
          '#microsoft.graph.',
          ''
        ),
      })),
    ...arr(becData.RegisteredDevices)
      .filter((device) => device.RegisteredInWindow)
      .map((device) => ({
        key: 'device',
        date: toDate(device.registrationDateTime || device.createdDateTime),
        category: 'device',
        objective: 'access',
        severity: 'medium',
        label: 'Device registered',
        target: clean(device.displayName || device.deviceId),
      })),
    ...arr(becData.ChangedPasswords).map((user) => ({
      key: 'password',
      date: toDate(user.lastPasswordChangeDateTime),
      category: 'password',
      objective: 'access',
      severity: 'medium',
      label: 'Password changed',
      target: clean(user.displayName || user.userPrincipalName),
    })),
  ].filter((event) => event.date)

  const events = raw
    .sort((a, b) => a.date - b.date)
    .map((event, index) => ({
      ...event,
      id: `${event.key}-${index}`,
      ts: event.date.getTime(),
      // A single human-readable line for the timeline view, from whatever this event carries.
      detail: joinDetail(
        event.location,
        event.app,
        event.actor,
        event.target,
        event.recipient ? `to ${event.recipient}` : null,
        event.sender,
        event.foreign ? 'foreign' : null,
        event.targetsSuspect ? 'targets this mailbox' : null,
        event.ip
      ),
      // The graph shows the source IP/location on the hub and the affected account as its own node, so
      // the event body drops both to avoid repeating what its edges already say.
      graphDetail: joinDetail(
        event.app,
        event.actor,
        event.target,
        event.sender,
        event.foreign ? 'foreign' : null,
        event.targetsSuspect ? 'targets this mailbox' : null
      ),
    }))

  // Start of compromise: the earliest event evidencing unauthorised access or a foothold — a
  // successful foreign sign-in first, then an attacker-registered method / consent / rule, then the
  // earliest high-severity event, then simply the earliest event.
  const startOfCompromise =
    events.find(
      (event) => event.category === 'signin' && event.severity === 'high'
    ) ||
    events.find(
      (event) =>
        event.severity === 'high' &&
        (event.objective === 'access' || event.objective === 'persistence')
    ) ||
    events.find((event) => event.severity === 'high') ||
    events[0] ||
    null

  return { events, startOfCompromise }
}

/**
 * Reshapes the timeline into a correlation graph: the account fans out to each distinct source IP it
 * acted from (a hub), the events from that source hang off it, and events that touched another account
 * fan back out to that account (a target). This is the non-linear view — it groups what an attacker did
 * by where it came from and who it reached, rather than laying everything out by time.
 *
 * @returns {{ account, hubs, orphans, targets, startOfCompromise, eventCount }}
 *   hubs = [{ ip, location, foreign, events }]; orphans = events with no source IP;
 *   targets = [{ account, events }] the other accounts the victim's events acted on.
 */
export function buildBecCorrelationGraph(
  becData,
  windowDays = 7,
  accountUpn = null
) {
  const { events, startOfCompromise } = buildBecTimeline(
    becData,
    windowDays,
    accountUpn
  )
  const resolvedAccount = clean(
    accountUpn ||
      becData?.UserPrincipalName ||
      becData?.userData?.userPrincipalName
  )
  const byIp = new Map()
  const orphans = []

  events.forEach((event) => {
    if (event.ip) {
      if (!byIp.has(event.ip)) {
        byIp.set(event.ip, {
          ip: event.ip,
          location: event.location || null,
          foreign: event.category === 'signin' || event.foreign || false,
          events: [],
        })
      }
      const hub = byIp.get(event.ip)
      hub.events.push(event)
      if (event.location && !hub.location) hub.location = event.location
      if (event.foreign || event.category === 'signin') hub.foreign = true
    } else {
      orphans.push(event)
    }
  })

  // Busiest sources first — the IP an attacker did the most from reads as the primary source.
  const hubs = [...byIp.values()].sort(
    (a, b) => b.events.length - a.events.length
  )

  // The other accounts the victim's activity acted on, each with the events that reached it. Most-hit
  // first so the biggest blast radius sits at the top of the column.
  const byTarget = new Map()
  events.forEach((event) => {
    if (!event.affects) return
    if (!byTarget.has(event.affects)) {
      byTarget.set(event.affects, { account: event.affects, events: [] })
    }
    byTarget.get(event.affects).events.push(event)
  })
  const targets = [...byTarget.values()]
    .filter(
      (target) =>
        !resolvedAccount ||
        target.account.toLowerCase() !== resolvedAccount.toLowerCase()
    )
    .sort((a, b) => b.events.length - a.events.length)

  return {
    account:
      resolvedAccount ||
      becData?.userData?.userPrincipalName ||
      becData?.UserPrincipalName ||
      'Account',
    hubs,
    orphans,
    targets,
    startOfCompromise,
    eventCount: events.length,
  }
}
