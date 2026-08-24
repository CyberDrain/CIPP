import { useMemo, useState } from 'react'
import { Box, Stack } from '@mui/system'
import { Alert, Button, Chip, Typography } from '@mui/material'
import CippButtonCard from '../CippCards/CippButtonCard'
import { CippDataTable } from '../CippTable/CippDataTable'
import { PropertyList } from '../property-list'
import { PropertyListItem } from '../property-list-item'
import { getIconByName } from '../../utils/icon-registry'
import { getBecIntuneDeviceActions } from './CippIntuneDeviceActions.jsx'
import { CippBecPhishingSpreadDialog } from './CippBecPhishingSpreadDialog'
import { CippApiDialog } from './CippApiDialog'
import { useDialog } from '../../hooks/use-dialog'
import {
  BEC_GROUPS,
  becGroupFlagged,
  becFindingFlags,
  becCoverage,
  BEC_FINDING_MARKERS,
} from '../../utils/bec-objectives'

const joinList = (value) =>
  Array.isArray(value) ? value.join(', ') : (value ?? '')
const arr = (value) => (Array.isArray(value) ? value : [])

// Generic findings whose rows carry nested objects the table can't render flat.
const FLATTEN = {
  UserGrants: (g) => ({
    ...g,
    HighRiskScopes: joinList(g.HighRiskScopes),
    CatalogMatch: g.CatalogMatch?.Name
      ? `${g.CatalogMatch.Name} (${g.CatalogMatch.Source})`
      : '',
  }),
}

// The evidence half of the case workspace: every finding, grouped by attacker objective, flagged
// first. A check that could not run (missing licence/permission) is shown as "not checked", never as
// a clean pass. A group with flagged findings opens by default; the triage spine can open and scroll
// to any group. Tables are metadata only, exactly what the collectors returned.
export const CippBecObjectiveGroups = ({
  becData,
  windowDays,
  tenantFilter,
  userData,
  openGroups,
  onToggleGroup,
  groupRefs,
}) => {
  const [spreadOpen, setSpreadOpen] = useState(false)
  const [spread, setSpread] = useState({ sender: '', subject: '' })
  const dismissRiskDialog = useDialog()
  const intuneDeviceActions = useMemo(
    () => getBecIntuneDeviceActions({ tenantFilter }),
    [tenantFilter]
  )

  const analysisWindowStart = useMemo(() => {
    const parsed = becData?.ExtractedAt
      ? new Date(becData.ExtractedAt)
      : new Date()
    const extractedAt = Number.isNaN(parsed.getTime()) ? new Date() : parsed
    return new Date(extractedAt.getTime() - windowDays * 24 * 60 * 60 * 1000)
  }, [becData, windowDays])

  // Blocking a sender/domain now lives in the containment drawer (tenant-wide, catalog-driven), not
  // as a per-row action. The one row action left scopes the phishing wave: it pre-fills the spread
  // search with this message's sender and subject and runs it, so "who else got this" is one click.
  const receivedMailActions = useMemo(
    () => [
      {
        label: 'Who else got this email?',
        noConfirm: true,
        customFunction: (row) => {
          setSpread({
            sender: row.SenderAddress || '',
            subject: row.Subject || '',
          })
          setSpreadOpen(true)
        },
      },
    ],
    []
  )

  const counts = useMemo(
    () => becGroupFlagged(becData, windowDays),
    [becData, windowDays]
  )
  const flags = useMemo(
    () => becFindingFlags(becData, windowDays),
    [becData, windowDays]
  )

  if (!becData) return null

  const completeness = becData.Completeness || {}
  const table = (data, columns, actions) => {
    if (!data || data.length === 0) return null
    // "More Info" per row: the offcanvas renders every field of the record as a full-value property
    // list, so the detail — a rule's whole description, a sign-in's device/app/IP — is one click away
    // instead of a resized column. A row click opens it too. Fields are the union of keys across the rows.
    const extendedInfoFields = [
      ...new Set(data.flatMap((row) => Object.keys(row || {}))),
    ]
    return (
      <Box sx={{ mt: 1 }}>
        <CippDataTable
          noCard
          hideTitle
          data={data}
          simpleColumns={columns}
          actions={actions}
          offCanvas={{ extendedInfoFields }}
          offCanvasOnRowClick
        />
      </Box>
    )
  }

  const subHeader = (title) => (
    <Typography variant="subtitle2" sx={{ mt: 2 }}>
      {title}
    </Typography>
  )

  // Content-only renderers for findings whose shape is not one flat table. Header and coverage note
  // are owned by renderFinding, so these render nothing when the check was skipped or failed.
  const custom = {
    mfa: () => {
      const rows = arr(becData.MFADevices).map((m) => ({
        Method: String(m['@odata.type'] || '').replace('#microsoft.graph.', ''),
        displayName: m.displayName,
        createdDateTime: m.createdDateTime,
        Recent: m.createdDateTime
          ? new Date(m.createdDateTime) >= analysisWindowStart
          : false,
      }))
      return rows.length === 0 ? (
        <Typography variant="body2" color="text.secondary">
          No MFA methods are registered. If MFA was expected, an attacker may
          have removed it.
        </Typography>
      ) : (
        table(rows, ['Method', 'displayName', 'createdDateTime', 'Recent'])
      )
    },
    risk: () => {
      const rs = becData.RiskState
      const detections = arr(rs?.Detections)
      return (
        <>
          <Typography variant="body2" color="text.secondary">
            {rs?.Listed
              ? `Listed as ${rs.RiskState} at ${rs.RiskLevel} risk (${rs.RiskDetail || 'no detail'}).`
              : 'Not listed as risky.'}
          </Typography>
          {table(detections, [
            'DetectedDateTime',
            'RiskEventType',
            'RiskLevel',
            'RiskState',
            'IPAddress',
            'Country',
            'City',
            'Activity',
          ])}
          {rs?.Listed && userData && (
            <Box sx={{ mt: 1 }}>
              <Button
                size="small"
                variant="outlined"
                onClick={() => dismissRiskDialog.handleOpen()}
              >
                Dismiss risk in Identity Protection
              </Button>
              <CippApiDialog
                title="Dismiss user risk"
                createDialog={dismissRiskDialog}
                api={{
                  url: '/api/ExecDismissRiskyUser',
                  type: 'POST',
                  data: {
                    tenantFilter: `!${tenantFilter}`,
                    userId: 'id',
                    userDisplayName: 'displayName',
                  },
                  confirmText:
                    'Dismiss the Identity Protection risk for [userPrincipalName]? Do this only once the account is contained and the activity explained.',
                }}
                row={userData}
              />
            </Box>
          )}
        </>
      )
    },
    intune: () =>
      table(
        arr(becData.IntuneDevices),
        [
          'deviceName',
          'operatingSystem',
          'osVersion',
          'complianceState',
          'enrolledDateTime',
          'lastSyncDateTime',
          'deviceEnrollmentType',
          'serialNumber',
        ],
        intuneDeviceActions
      ) ?? (
        <Typography variant="body2" color="text.secondary">
          No Intune-managed devices found for this user.
        </Typography>
      ),
    rules: () => {
      const newRules = arr(becData.NewRules).map((r) => ({
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
      }))
      const changes = arr(becData.InboxRuleChanges)
      return (
        <>
          {newRules.length === 0 && changes.length === 0 && (
            <Typography variant="body2" color="text.secondary">
              No inbox rules or rule changes found.
            </Typography>
          )}
          {table(newRules, [
            'Name',
            'RecentlyChanged',
            'RiskReasons',
            'Description',
          ])}
          {changes.length > 0 &&
            subHeader(`Rule changes in the last ${windowDays} days`)}
          {table(changes, [
            'Operation',
            'RuleName',
            'Date',
            'UserKey',
            'ClientIP',
            'Country',
            'ForeignLocation',
          ])}
        </>
      )
    },
    apps: () => {
      const added = arr(becData.AddedApps).map((a) => ({
        displayName: a.displayName,
        appId: a.appId,
        createdDateTime: a.createdDateTime,
        MaliciousMatch: a.MaliciousMatch?.Name || '',
      }))
      const malicious = arr(becData.MaliciousSPs)
      return (
        <>
          {added.length === 0 && malicious.length === 0 && (
            <Typography variant="body2" color="text.secondary">
              No new applications found.
            </Typography>
          )}
          {/* Malicious apps first - a catalog match is the point of this check, whatever its age. */}
          {malicious.length > 0 && (
            <Alert severity="warning" sx={{ mt: 1 }}>
              {malicious.length} application(s) in this tenant match the
              known-malicious catalog. Consent-based access survives a password
              reset — remove any that are not explained.
            </Alert>
          )}
          {table(malicious, [
            'displayName',
            'appId',
            'CatalogName',
            'accountEnabled',
            'createdDateTime',
          ])}
          {added.length > 0 && subHeader('New applications in the window')}
          {table(added, [
            'displayName',
            'appId',
            'createdDateTime',
            'MaliciousMatch',
          ])}
        </>
      )
    },
    mailboxState: () => {
      const ms = becData.MailboxState
      if (!ms) return null
      const protocols = ['OWA', 'EWS', 'IMAP', 'POP', 'MAPI', 'ActiveSync']
        .filter((p) => ms[`${p}Enabled`] === true)
        .join(', ')
      return (
        <PropertyList>
          <PropertyListItem
            align="horizontal"
            label="Forwarding"
            value={
              ms.HasForwarding
                ? ms.ForwardingSmtpAddress || ms.ForwardingAddress || 'set'
                : 'None'
            }
          />
          <PropertyListItem
            align="horizontal"
            label="Automatic reply"
            value={`${ms.AutoReplyState || 'Unknown'}${
              ms.AutoReplyExternalAudience
                ? ` / ${ms.AutoReplyExternalAudience}`
                : ''
            }`}
          />
          <PropertyListItem
            align="horizontal"
            label="Protocols enabled"
            value={protocols || 'None'}
          />
          <PropertyListItem
            align="horizontal"
            label="SMTP AUTH disabled"
            value={String(ms.SmtpClientAuthenticationDisabled ?? 'Unknown')}
          />
          <PropertyListItem
            align="horizontal"
            label="Mailbox auditing"
            value={String(ms.AuditEnabled ?? 'Unknown')}
          />
        </PropertyList>
      )
    },
    safelist: () => {
      const senders = [
        ...arr(becData.TrustedSenders).map((s) => ({
          Sender: s,
          Type: 'Trusted',
        })),
        ...arr(becData.BlockedSenders).map((s) => ({
          Sender: s,
          Type: 'Blocked',
        })),
      ]
      const changes = arr(becData.SafelistChanges)
      return (
        <>
          {senders.length === 0 && changes.length === 0 && (
            <Typography variant="body2" color="text.secondary">
              No trusted or blocked senders found.
            </Typography>
          )}
          {table(senders, ['Sender', 'Type'])}
          {changes.length > 0 &&
            subHeader(`Changes in the last ${windowDays} days`)}
          {table(changes, [
            'Operation',
            'UserKey',
            'Date',
            'ClientIP',
            'Country',
            'ForeignLocation',
          ])}
        </>
      )
    },
    transport: () => {
      const changes = arr(becData.TransportRuleChanges).map((c) => ({
        ...c,
        RiskyParameters: joinList(c.RiskyParameters),
      }))
      const flagged = arr(becData.TransportRulesFlagged).map((r) => ({
        ...r,
        RiskReasons: joinList(r.RiskReasons),
      }))
      return (
        <>
          {changes.length === 0 && flagged.length === 0 && (
            <Typography variant="body2" color="text.secondary">
              No transport-rule changes or diverting rules found.
            </Typography>
          )}
          {table(changes, [
            'Date',
            'Operation',
            'RuleName',
            'Actor',
            'ClientIP',
            'Country',
            'RiskyParameters',
            'Flagged',
          ])}
          {flagged.length > 0 &&
            subHeader('Current rules that divert or suppress mail')}
          {table(flagged, [
            'Name',
            'State',
            'Mode',
            'WhenChanged',
            'ChangedInWindow',
            'RiskReasons',
          ])}
        </>
      )
    },
    sent: () => {
      const analysis = becData.SentMessageAnalysis
      const sent = arr(becData.SentMessages)
      return (
        <>
          {analysis ? (
            <Typography variant="body2" color="text.secondary">
              {analysis.TotalMessages ?? sent.length} message(s) to{' '}
              {analysis.TotalRecipients ?? sent.length} recipient(s) in the last{' '}
              {windowDays} days.
              {analysis.FlaggedSubjectCount > 0
                ? ` ${analysis.FlaggedSubjectCount} subject(s) look like a campaign.`
                : ''}
              {analysis.Bursts?.length > 0
                ? ` ${analysis.Bursts.length} send burst(s).`
                : ''}
            </Typography>
          ) : (
            sent.length === 0 && (
              <Typography variant="body2" color="text.secondary">
                No sent messages found in the window.
              </Typography>
            )
          )}
          {table(sent, [
            'Subject',
            'RecipientAddress',
            'Status',
            'Received',
            'FromIP',
            'Country',
          ])}
        </>
      )
    },
    mailActivity: () => {
      const summary = becData.MailActivitySummary
      const rows = arr(becData.MailActivity)
      return (
        <>
          {summary ? (
            <Typography variant="body2" color="text.secondary">
              {summary.MailItemsAccessedCount} access(es),{' '}
              {summary.HardDeleteCount} hard delete(s),{' '}
              {summary.SoftDeleteCount} soft delete(s), {summary.SendCount}{' '}
              send(s) from {summary.DistinctClientIPs} client IP(s). Counts only
              — no items were read.
              {summary.HardDeleteExceeded
                ? ` Hard deletes exceed the ${summary.HardDeleteThreshold} threshold.`
                : ''}
            </Typography>
          ) : (
            <Typography variant="body2" color="text.secondary">
              No mailbox-activity counts were recorded.
            </Typography>
          )}
          {table(rows, [
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
          ])}
        </>
      )
    },
    received: () => {
      const findings = arr(becData.ReceivedMailFindings)
      const defender = arr(becData.DefenderDetections).map((r) => ({
        ...r,
        ThreatTypes: joinList(r.ThreatTypes),
      }))
      return (
        <>
          <Box sx={{ mt: 1 }}>
            <Button
              size="small"
              variant="outlined"
              onClick={() => {
                setSpread({ sender: '', subject: '' })
                setSpreadOpen(true)
              }}
            >
              Trace a sender&apos;s spread
            </Button>
          </Box>
          {findings.length === 0 && (
            <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
              No phishing-shaped or look-alike senders found.
            </Typography>
          )}
          {table(
            findings,
            [
              'Received',
              'FindingType',
              'Severity',
              'SenderAddress',
              'Subject',
              'Reason',
              'Status',
            ],
            receivedMailActions
          )}
          {defender.length > 0 &&
            subHeader('Defender for Office 365 detections')}
          {table(defender, [
            'ReceivedDateTime',
            'SenderAddress',
            'Subject',
            'ThreatTypes',
            'DeliveryAction',
            'LatestDeliveryLocation',
            'Delivered',
          ])}
        </>
      )
    },
  }

  // One coverage note per finding: skipped (missing entitlement) reads as "not checked", a hard
  // failure as "couldn't check", a cap as "partial". A skipped/failed check renders no content, so an
  // empty section is never mistaken for a clean one.
  const coverageOf = (finding) =>
    becCoverage(completeness, BEC_FINDING_MARKERS[finding.key] || [])

  const renderFinding = (finding) => {
    const cov = coverageOf(finding)
    const fl = flags[finding.key]
    // Only suppress content when every check behind the finding was blocked; a finding with some
    // checks still complete (phishing ran, Defender skipped) keeps its content and adds the note.
    const blocked = cov.allBlocked
    const content = () => {
      if (finding.custom) return custom[finding.custom]?.()
      const raw = arr(becData[finding.key])
      const rows = FLATTEN[finding.key] ? raw.map(FLATTEN[finding.key]) : raw
      return rows.length === 0 ? (
        <Typography variant="body2" color="text.secondary">
          Nothing found.
        </Typography>
      ) : (
        table(rows, finding.columns)
      )
    }
    return (
      <Box key={finding.key} sx={{ mt: 2 }}>
        <Stack direction="row" spacing={1} alignItems="center">
          <Typography variant="subtitle2">{finding.title}</Typography>
          {fl ? (
            <Chip size="small" color="warning" label={`${fl.count} flagged`} />
          ) : cov.allBlocked ? (
            <Chip size="small" variant="outlined" label="not checked" />
          ) : cov.state !== 'ok' ? (
            <Chip size="small" variant="outlined" label="partial" />
          ) : (
            <Chip size="small" color="success" label="clear" />
          )}
        </Stack>
        {fl && (
          <Typography
            variant="caption"
            color="warning.main"
            sx={{ display: 'block' }}
          >
            Flagged: {fl.reason}.
          </Typography>
        )}
        {finding.note && (
          <Typography
            variant="caption"
            color="text.secondary"
            sx={{ display: 'block' }}
          >
            {finding.note}
          </Typography>
        )}
        {cov.state === 'skipped' &&
          (cov.allBlocked ? (
            <Alert severity="info" sx={{ mt: 1 }}>
              Not checked —{' '}
              {cov.requirement ||
                'a licence, permission, mailbox or service that is not present'}
              . This is not a pass; the result is unknown.
            </Alert>
          ) : (
            <Alert severity="info" sx={{ mt: 1 }}>
              Some checks here could not run (
              {cov.requirement || 'missing a licence, permission or service'});
              the rest is shown below.
            </Alert>
          ))}
        {cov.state === 'failed' && (
          <Alert severity="warning" sx={{ mt: 1 }}>
            Couldn&apos;t check: {cov.error}
          </Alert>
        )}
        {cov.state === 'partial' && (
          <Typography variant="caption" color="text.secondary">
            Partial results — {cov.cap}.
          </Typography>
        )}
        {!blocked && content()}
      </Box>
    )
  }

  const la = becData.LocationAnalysis

  return (
    <Stack spacing={2}>
      {BEC_GROUPS.map((group) => {
        const flagged = counts[group.id] || 0
        const notChecked = group.findings.filter((f) => {
          const s = coverageOf(f).state
          return s === 'skipped' || s === 'failed'
        }).length
        const GroupIcon = getIconByName(group.icon, { fontSize: 'small' })
        return (
          <Box key={group.id} ref={(el) => (groupRefs.current[group.id] = el)}>
            <CippButtonCard
              variant="outlined"
              component="accordion"
              accordionExpanded={!!openGroups[group.id]}
              onAccordionChange={(exp) => onToggleGroup(group.id, exp)}
              title={
                <Stack
                  direction="row"
                  spacing={2}
                  alignItems="center"
                  justifyContent="space-between"
                  sx={{ width: '100%' }}
                >
                  <Stack direction="row" spacing={1} alignItems="center">
                    {GroupIcon}
                    <Box>{group.title}</Box>
                  </Stack>
                  <Stack direction="row" spacing={0.5} alignItems="center">
                    {flagged > 0 && (
                      <Chip
                        size="small"
                        color="warning"
                        label={`${flagged} flagged`}
                      />
                    )}
                    {notChecked > 0 && (
                      <Chip
                        size="small"
                        variant="outlined"
                        label={`${notChecked} not checked`}
                      />
                    )}
                    {flagged === 0 && notChecked === 0 && (
                      <Chip size="small" color="success" label="clear" />
                    )}
                  </Stack>
                </Stack>
              }
            >
              <Typography variant="body2" color="text.secondary">
                {group.blurb}
              </Typography>
              {group.id === 'access' && la && (
                <Box sx={{ mt: 1 }}>
                  <PropertyList>
                    <PropertyListItem
                      align="horizontal"
                      label="Usage location"
                      value={la.UsageLocation || 'not set'}
                    />
                    <PropertyListItem
                      align="horizontal"
                      label="Sign-in countries"
                      value={
                        arr(la.SignInCountries)
                          .map((c) => `${c.Country} (${c.Count})`)
                          .join(', ') || 'none recorded'
                      }
                    />
                    <PropertyListItem
                      align="horizontal"
                      label="Activity outside usage location"
                      value={`${la.ForeignSuccessfulSignInCount || 0} sign-in(s), ${
                        (la.ForeignRuleChangeCount || 0) +
                        (la.ForeignSafelistChangeCount || 0) +
                        (la.ForeignSharingChangeCount || 0) +
                        (la.ForeignSentMessageCount || 0)
                      } change(s)/send(s)`}
                    />
                  </PropertyList>
                </Box>
              )}
              {group.findings.map(renderFinding)}
            </CippButtonCard>
          </Box>
        )
      })}

      <CippBecPhishingSpreadDialog
        open={spreadOpen}
        onClose={() => setSpreadOpen(false)}
        tenantFilter={tenantFilter}
        defaultSender={spread.sender}
        defaultSubject={spread.subject}
        key={`${spread.sender}|${spread.subject}`}
      />
    </Stack>
  )
}

export default CippBecObjectiveGroups
