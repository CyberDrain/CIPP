import {
  Alert,
  Button,
  Chip,
  CircularProgress,
  LinearProgress,
  Stack,
  SvgIcon,
  Typography,
} from '@mui/material'
import { Box } from '@mui/system'
import { CippIcons } from '../../utils/icon-registry'
import ReactTimeAgo from 'react-time-ago'
import CippButtonCard from './CippButtonCard'
import { CippJobProgress } from '../CippComponents/CippJobProgress'
import { CippBecContainmentDrawer } from '../CippComponents/CippBecContainmentDrawer'
import { PropertyList } from '../property-list'
import { PropertyListItem } from '../property-list-item'

const levelColor = (level) =>
  level === 'High'
    ? 'error'
    : level === 'Medium'
      ? 'warning'
      : level === 'Low'
        ? 'success'
        : 'default'

const toDate = (value) => {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

/**
 * The investigation's status card: what the page is showing and what is happening to it.
 * state: loading | none | waiting | error | completed
 *  - none:      the user has no run yet; nothing starts until the button is pressed
 *  - waiting:   a run is queued (no worker has picked it up) or running (live steps from the
 *               async-deployment job, the same progress rows the SharePoint deploy uses)
 *  - error:     the run failed; the failed phase is shown
 *  - completed: a summary of the run on screen
 * The header carries only the title and the state chips; the buttons live in the footer so a
 * long UPN never fights the actions for space.
 */
export const CippBecRunStatusCard = ({
  userPrincipalName,
  userId,
  tenantFilter,
  state,
  caseId,
  scope,
  poll,
  becData,
  onStart,
  startPending = false,
  windowDays = 7,
}) => {
  const progress = poll?.Progress
  const steps = Array.isArray(progress?.Steps) ? progress.Steps : []
  const doneCount = steps.filter((step) => step.Status === 'succeeded').length
  const runningStep = steps.find((step) => step.Status === 'running')
  const failedStep = steps.find((step) => step.Status === 'failed')
  const jobQueued =
    state === 'waiting' && (!progress || progress.Status === 'queued')
  const requestedAt = toDate(poll?.RequestedAt ?? becData?.Run?.RequestedAt)
  const startedAt = toDate(poll?.StartedAt)
  const busy = state === 'waiting' || state === 'loading' || startPending
  const run = becData?.Run
  const completeness = becData?.Completeness || {}
  const markers = Object.values(completeness).filter(Boolean)
  const incomplete = markers.filter((marker) => marker.Complete === false)
  const extractedAt = toDate(run?.ExtractedAt ?? becData?.ExtractedAt)
  const evidenceAt = toDate(run?.EvidenceCreatedAt)

  let statusChip = null
  if (state === 'loading') {
    statusChip = <Chip size="small" variant="outlined" label="Loading" />
  } else if (state === 'none') {
    statusChip = <Chip size="small" variant="outlined" label="No runs yet" />
  } else if (state === 'waiting') {
    statusChip = jobQueued ? (
      <Chip
        size="small"
        variant="outlined"
        icon={<CippIcons.HourglassTop />}
        label="Queued - waiting for a worker"
      />
    ) : (
      <Chip
        size="small"
        color="info"
        label={`Running - step ${Math.min(doneCount + 1, steps.length || 1)} of ${
          steps.length || '?'
        }`}
      />
    )
  } else if (state === 'error') {
    statusChip = <Chip size="small" color="error" label="Failed" />
  } else if (state === 'completed') {
    statusChip = becData?.Score ? (
      <Chip
        size="small"
        color={levelColor(becData.Score.Level)}
        label={`${becData.Score.Level} (${becData.Score.Value})`}
      />
    ) : (
      <Chip size="small" color="success" label="Completed" />
    )
  }

  const startButton = (
    <Button
      variant="contained"
      size="small"
      onClick={() => onStart()}
      disabled={busy}
      startIcon={
        <SvgIcon fontSize="small">
          <CippIcons.TravelExplore />
        </SvgIcon>
      }
    >
      {state === 'completed' || state === 'error'
        ? 'Run a new investigation'
        : 'Run investigation'}
    </Button>
  )

  return (
    <CippButtonCard
      title={
        <Stack spacing={1}>
          <Box>
            <Typography variant="h6">Business Email Compromise</Typography>
            <Typography
              variant="body2"
              color="text.secondary"
              sx={{ wordBreak: 'break-all' }}
            >
              {userPrincipalName}
            </Typography>
          </Box>
          <Stack
            direction="row"
            spacing={1}
            alignItems="center"
            flexWrap="wrap"
            useFlexGap
          >
            {statusChip}
            {scope === 'Quick' && (
              <Chip
                size="small"
                variant="outlined"
                label="Quick check (older run)"
              />
            )}
            {caseId && (
              <Chip size="small" variant="outlined" label={`Case ${caseId}`} />
            )}
          </Stack>
        </Stack>
      }
      CardButton={
        <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
          {startButton}
          {state === 'completed' && (
            <CippBecContainmentDrawer
              userPrincipalName={userPrincipalName}
              userId={userId}
              tenantFilter={tenantFilter}
              caseId={caseId}
              becData={becData}
              disabled={busy}
              buttonText="Contain user"
            />
          )}
        </Stack>
      }
      isFetching={false}
    >
      {state === 'loading' && (
        <Stack direction="row" spacing={1} alignItems="center">
          <CircularProgress size={16} />
          <Typography variant="body2">
            Loading the user&apos;s runs...
          </Typography>
        </Stack>
      )}

      {state === 'none' && (
        <Stack spacing={2}>
          <Typography variant="body2">
            No investigation has been run for this user yet. Nothing is
            collected until you start one; every run is kept as a case you can
            return to, report on and export evidence from.
          </Typography>
          <Typography variant="body2" color="text.secondary">
            The investigation reads the last {windowDays} days of audit records,
            sign-ins, permissions, rules, consents, devices and trace headers
            across 21 checks. It collects metadata only - never message content
            - and usually takes a few minutes.
          </Typography>
        </Stack>
      )}

      {state === 'waiting' && (
        <Stack spacing={2}>
          {jobQueued ? (
            <Typography variant="body2">
              The run is queued and waits for a background worker to pick it up
              {requestedAt && (
                <>
                  {' '}
                  (requested <ReactTimeAgo date={requestedAt} />)
                </>
              )}
              . Busy instances can hold it for a few minutes; the steps below
              start moving as soon as a worker takes it.
            </Typography>
          ) : (
            <Typography variant="body2">
              {runningStep
                ? `${runningStep.Title}: ${runningStep.Message || 'in progress'}`
                : 'The worker has picked the run up.'}
              {startedAt && (
                <>
                  {' '}
                  Started <ReactTimeAgo date={startedAt} />.
                </>
              )}{' '}
              A run usually finishes within a few minutes; a tenant with a lot
              of audit data can take up to ten.
            </Typography>
          )}
          <LinearProgress
            variant={
              steps.length > 0 && !jobQueued ? 'determinate' : 'indeterminate'
            }
            value={
              steps.length > 0
                ? Math.round((doneCount / steps.length) * 100)
                : 0
            }
          />
          {progress ? (
            <CippJobProgress rows={[progress]} />
          ) : (
            <Typography variant="caption" color="text.secondary">
              Waiting for the first status update...
            </Typography>
          )}
        </Stack>
      )}

      {state === 'error' && (
        <Stack spacing={2}>
          <Alert severity="error">
            {poll?.Error || 'The run failed.'}
            {failedStep && ` Failed during: ${failedStep.Title}.`}
          </Alert>
          {progress && <CippJobProgress rows={[progress]} />}
          <Typography variant="body2" color="text.secondary">
            The failure is recorded in the logbook with the case id. Start a new
            run once the cause is fixed; the failed run stays in the history.
          </Typography>
        </Stack>
      )}

      {state === 'completed' && (
        <Stack spacing={2}>
          <Typography variant="body2">
            Use the findings below as a guide to whether the mailbox has been
            compromised. Everything was read from the last {windowDays} days and
            is metadata only: audit records, sign-ins, permissions, rules and
            trace headers - never message content.
          </Typography>
          <PropertyList>
            <PropertyListItem
              label="Extracted"
              value={
                extractedAt ? (
                  <>
                    <ReactTimeAgo date={extractedAt} /> (
                    {extractedAt.toLocaleString()})
                  </>
                ) : (
                  'unknown'
                )
              }
            />
            <PropertyListItem
              label="Requested by"
              value={run?.RequestedBy || 'unknown'}
            />
            <PropertyListItem
              label="Checks"
              value={
                markers.length > 0
                  ? `${markers.length - incomplete.length} of ${markers.length} complete${
                      incomplete.length > 0
                        ? `, ${incomplete.length} partial or failed`
                        : ''
                    }`
                  : 'no completeness data'
              }
            />
            <PropertyListItem
              label="Containment"
              value={
                (run?.Containment || []).length > 0
                  ? `${run.Containment.length} run(s) recorded on this case`
                  : 'not run on this case'
              }
            />
            <PropertyListItem
              label="Evidence"
              value={
                run?.EvidenceSha256 ? (
                  <>
                    exported {evidenceAt && <ReactTimeAgo date={evidenceAt} />}{' '}
                    <Box component="span" sx={{ fontFamily: 'monospace' }}>
                      {run.EvidenceSha256.slice(0, 12)}...
                    </Box>
                  </>
                ) : (
                  'not exported'
                )
              }
            />
          </PropertyList>
          <Typography variant="body2" color="text.secondary">
            <strong>Contain user</strong> opens the containment drawer: pick any
            combination of the classic six steps and the targeted actions the
            findings support; critical actions need the UPN typed to confirm.
          </Typography>
        </Stack>
      )}
    </CippButtonCard>
  )
}

export default CippBecRunStatusCard
