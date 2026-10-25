import { Fragment, useState } from 'react'
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CardHeader,
  Chip,
  Collapse,
  Divider,
  IconButton,
  Skeleton,
  Stack,
  Typography,
} from '@mui/material'
import Link from 'next/link'
import { CippIcons } from '../../utils/icon-registry'
import { ApiGetCall } from '../../api/ApiCall'

// The alert configuration page for one alert.
const editLink = (row) =>
  `/tenant/administration/alert-configuration/alert?id=${encodeURIComponent(row.RuleKey)}`

const EditButton = ({ row }) => (
  <Button
    size="small"
    component={Link}
    href={editLink(row)}
    startIcon={<CippIcons.Edit fontSize="small" />}
    sx={{ ml: 'auto' }}
  >
    Edit alert
  </Button>
)

// How each outcome reads and looks. Colour always comes with an icon and words.
const outcomeStyle = {
  Fires: {
    title: 'This alert fires',
    color: 'success',
    icon: <CippIcons.NotificationsActive fontSize="small" />,
  },
  AlsoMatches: {
    title: 'Matches too, but another alert fires first',
    color: 'info',
    icon: <CippIcons.Notifications fontSize="small" />,
  },
  Close: {
    title: 'Close: looks at this activity, but a condition is not met',
    color: 'warning',
    icon: <CippIcons.NotificationsOff fontSize="small" />,
  },
  Excluded: {
    title: 'This tenant is excluded from this alert',
    color: 'secondary',
    icon: <CippIcons.NotificationsOff fontSize="small" />,
  },
}

const ConditionLine = ({ condition }) => (
  <Stack direction="row" spacing={1.5} sx={{ alignItems: 'flex-start' }}>
    {condition.Passed ? (
      <CippIcons.CheckCircle
        color="success"
        fontSize="small"
        sx={{ mt: 0.25 }}
      />
    ) : (
      <CippIcons.Cancel color="error" fontSize="small" sx={{ mt: 0.25 }} />
    )}
    <Box sx={{ minWidth: 0 }}>
      <Typography variant="body2">
        <strong>{condition.Property}</strong>{' '}
        {String(condition.Operator ?? '').toLowerCase()}{' '}
        <Box
          component="code"
          sx={{ px: 0.5, borderRadius: 0.5, bgcolor: 'action.hover' }}
        >
          {condition.Expected}
        </Box>
        {condition.Passed ? '' : ' (not met)'}
      </Typography>
      <Typography
        variant="caption"
        sx={{
          color: condition.Passed ? 'text.secondary' : 'error.main',
          wordBreak: 'break-all',
        }}
      >
        This log has:{' '}
        {condition.Actual ? condition.Actual : 'nothing for this property'}
      </Typography>
    </Box>
  </Stack>
)

// One alert: its groups that look at this activity, each condition with what the log has.
const AlertCard = ({ row }) => {
  const style = outcomeStyle[row.Outcome]
  const groups = row.Groups ?? []
  const shown = groups.filter((group) => group.LooksAtThisActivity)
  const hidden = groups.length - shown.length
  return (
    <Box
      sx={{
        border: 1,
        borderColor: 'divider',
        borderLeft: 4,
        borderLeftColor: `${style.color}.main`,
        borderRadius: 1,
        p: 2,
      }}
    >
      <Stack
        direction="row"
        spacing={1}
        useFlexGap
        sx={{ alignItems: 'center', flexWrap: 'wrap', mb: 1.5 }}
      >
        <Box
          title={style.title}
          aria-label={style.title}
          sx={{ color: `${style.color}.main`, display: 'flex' }}
        >
          {style.icon}
        </Box>
        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
          {row.Alert}
        </Typography>
        <EditButton row={row} />
      </Stack>
      {row.Outcome === 'Excluded' && (
        <Alert severity="warning" sx={{ mb: 1.5 }}>
          This tenant is excluded from this alert, so it never sends here.{' '}
          {row.Matches
            ? 'Without the exclusion, every condition would match and it would fire.'
            : 'Not every condition would match either.'}
        </Alert>
      )}
      <Stack spacing={1.5}>
        {shown.map((group, index) => (
          <Fragment key={group.Group}>
            {index > 0 && (
              <Divider>
                <Chip size="small" label="OR" />
              </Divider>
            )}
            {groups.length > 1 && (
              <Typography variant="caption" sx={{ color: 'text.secondary' }}>
                Group {groups.indexOf(group) + 1}:{' '}
                {group.Matched
                  ? 'every condition met'
                  : 'not every condition met'}
              </Typography>
            )}
            {(group.Conditions ?? []).map((condition, conditionIndex) => (
              <ConditionLine key={conditionIndex} condition={condition} />
            ))}
          </Fragment>
        ))}
        {hidden > 0 && (
          <Typography variant="caption" sx={{ color: 'text.secondary' }}>
            {hidden} other {hidden === 1 ? 'group looks' : 'groups look'} for
            different activity.
          </Typography>
        )}
      </Stack>
    </Box>
  )
}

const Section = ({ title, description, rows }) =>
  rows.length > 0 && (
    <Stack spacing={1.5}>
      <Box>
        <Typography variant="h6">{title}</Typography>
        <Typography variant="body2" sx={{ color: 'text.secondary' }}>
          {description}
        </Typography>
      </Box>
      {rows.map((row) => (
        <AlertCard key={row.RuleKey} row={row} />
      ))}
    </Stack>
  )

// A short list of alerts with an icon, for the outcomes worth acting on that have no conditions to show.
const NoteList = ({ title, description, rows, icon }) =>
  rows.length > 0 && (
    <Stack spacing={1}>
      <Box>
        <Typography variant="h6">{title}</Typography>
        <Typography variant="body2" sx={{ color: 'text.secondary' }}>
          {description}
        </Typography>
      </Box>
      {rows.map((row) => (
        <Stack
          key={row.RuleKey}
          direction="row"
          spacing={1}
          sx={{ alignItems: 'center' }}
        >
          {icon}
          <Typography variant="body2">
            <strong>{row.Alert}</strong> ({row.Log})
          </Typography>
          <EditButton row={row} />
        </Stack>
      ))}
    </Stack>
  )

// Alerts that cannot fire on this log, as name chips grouped by the log they read.
const ChipAccordion = ({ summary, description, rows }) => {
  const byLog = rows.reduce((groups, row) => {
    ;(groups[row.Log] = groups[row.Log] ?? []).push(row)
    return groups
  }, {})
  return (
    rows.length > 0 && (
      <Accordion variant="outlined" disableGutters>
        <AccordionSummary expandIcon={<CippIcons.ExpandMore />}>
          <Typography variant="body2">{summary}</Typography>
        </AccordionSummary>
        <AccordionDetails>
          <Stack spacing={2}>
            <Typography variant="body2" sx={{ color: 'text.secondary' }}>
              {description}
            </Typography>
            {Object.entries(byLog).map(([log, logRows]) => (
              <Box key={log}>
                <Typography variant="subtitle2" sx={{ mb: 1 }}>
                  {log} ({logRows.length})
                </Typography>
                <Stack
                  direction="row"
                  spacing={1}
                  useFlexGap
                  sx={{ flexWrap: 'wrap' }}
                >
                  {logRows.map((row) => (
                    <Chip
                      key={row.RuleKey}
                      size="small"
                      variant="outlined"
                      label={row.Alert}
                      component={Link}
                      href={editLink(row)}
                      clickable
                      title="Edit alert"
                    />
                  ))}
                </Stack>
              </Box>
            ))}
          </Stack>
        </AccordionDetails>
      </Accordion>
    )
  )
}

// Which of the audit log alerts set up now would fire on a saved log, shown condition by condition.
export const CippAuditLogRuleCheck = ({ tenant, logId }) => {
  const [open, setOpen] = useState(true)
  const request = ApiGetCall({
    url: '/api/ListAuditLogRuleMatches',
    data: { tenantFilter: tenant, LogId: logId },
    queryKey: `AuditLogRuleMatches-${tenant}-${logId}`,
    waiting: Boolean(tenant && logId),
  })
  const rows = Array.isArray(request.data?.Results) ? request.data.Results : []
  const meta = request.data?.Metadata ?? {}
  const pick = (...outcomes) =>
    rows.filter((row) => outcomes.includes(row.Outcome))
  const fires = pick('Fires')
  const also = pick('AlsoMatches')
  const close = pick('Close')
  const counts = pick('CountsToward')
  const excluded = pick('Excluded')
  const notChecked = pick('NotChecked')
  const others = pick('OtherActivity')
  const otherLogs = pick('OtherLog')

  return (
    <Card variant="outlined">
      <CardHeader
        title="Would your alerts fire on this log?"
        subheader="Checked against the audit log alerts assigned to this tenant, as they are set up now. Nothing is sent."
        action={
          <IconButton
            onClick={() => setOpen(!open)}
            aria-label={
              open ? 'Collapse the alert check' : 'Expand the alert check'
            }
          >
            <CippIcons.ExpandMore
              sx={{
                transform: open ? 'rotate(180deg)' : 'none',
                transition: 'transform 0.2s',
              }}
            />
          </IconButton>
        }
      />
      <Collapse in={open}>
        <Divider />
        <CardContent>
          {request.isFetching ? (
            <Skeleton variant="rounded" sx={{ height: 200 }} />
          ) : request.isError || typeof request.data?.Results === 'string' ? (
            <Alert severity="error">
              {typeof request.data?.Results === 'string'
                ? request.data.Results
                : 'Could not check this log against your alerts.'}
            </Alert>
          ) : (
            <Stack spacing={3}>
              <Stack
                direction="row"
                spacing={1}
                useFlexGap
                sx={{ flexWrap: 'wrap', alignItems: 'center' }}
              >
                <Typography
                  variant="body2"
                  sx={{ color: 'text.secondary', mr: 1 }}
                >
                  This log: <strong>{meta.Operation}</strong>
                  {meta.User ? ` by ${meta.User}` : ''}
                </Typography>
                <Chip
                  size="small"
                  color={fires.length ? 'success' : 'default'}
                  icon={<CippIcons.NotificationsActive fontSize="small" />}
                  label={`${fires.length} ${fires.length === 1 ? 'alert fires' : 'alerts fire'}`}
                />
                {also.length > 0 && (
                  <Chip
                    size="small"
                    color="info"
                    icon={<CippIcons.Notifications fontSize="small" />}
                    label={`${also.length} also ${also.length === 1 ? 'matches' : 'match'}`}
                  />
                )}
                {close.length > 0 && (
                  <Chip
                    size="small"
                    color="warning"
                    icon={<CippIcons.NotificationsOff fontSize="small" />}
                    label={`${close.length} close`}
                  />
                )}
                <Chip
                  size="small"
                  variant="outlined"
                  label={`${others.length + otherLogs.length} can't fire on this log`}
                />
              </Stack>

              {fires.length === 0 && counts.length > 0 && (
                <Alert severity="info">
                  These records count toward the repeated activity alerts below.
                  Those alert when one user or app does this often enough, not
                  on a single record.
                </Alert>
              )}
              {fires.length === 0 && counts.length === 0 && (
                <Alert severity="info">
                  None of your alerts would fire on this log now.
                  {close.length > 0 &&
                    ' The close matches below show which conditions stop them.'}
                </Alert>
              )}
              <Section
                title="Fires"
                description="Every condition is met, so this alert is sent."
                rows={fires}
              />
              <Section
                title="Also matches"
                description="Every condition is met here too. Only one alert is sent for each log entry: the first matching alert in your alert list, shown above."
                rows={also}
              />
              <Section
                title="Close"
                description="These alerts look at this activity, but at least one condition is not met. The red lines show what stops them."
                rows={close}
              />
              <NoteList
                title="Repeated activity alerts"
                description="This log counts toward these. They alert when one user or app does it often enough."
                rows={counts}
                icon={
                  <CippIcons.CheckCircle color="success" fontSize="small" />
                }
              />
              <Section
                title="Excluded for this tenant"
                description="These alerts look at this activity, but this tenant is excluded from them. Their conditions are still checked so you can see what would happen without the exclusion."
                rows={excluded}
              />
              <NoteList
                title="Not checked"
                description="These alerts never run: each group of their conditions needs an Operation condition using Equals, In or Like. Edit them to fix this."
                rows={notChecked}
                icon={<CippIcons.Warning color="warning" fontSize="small" />}
              />

              <ChipAccordion
                summary={`${others.length} ${others.length === 1 ? 'alert' : 'alerts'} on the ${meta.Log ?? 'same'} log ${others.length === 1 ? 'looks' : 'look'} for other activity`}
                description={`They read this log, but look for activity other than ${meta.Operation}, so they never check this record.`}
                rows={others}
              />
              <ChipAccordion
                summary={`${otherLogs.length} ${otherLogs.length === 1 ? 'alert reads' : 'alerts read'} a different log and can never fire on this one`}
                description={`This record is in the ${meta.Log ?? 'audit'} log. These alerts read other logs, so they never see it.`}
                rows={otherLogs}
              />
            </Stack>
          )}
        </CardContent>
      </Collapse>
    </Card>
  )
}

export default CippAuditLogRuleCheck
