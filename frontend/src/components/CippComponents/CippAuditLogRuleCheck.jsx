import { Fragment } from 'react'
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Alert,
  Box,
  Card,
  CardContent,
  CardHeader,
  Chip,
  Divider,
  Skeleton,
  Stack,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { ApiGetCall } from '../../api/ApiCall'

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
        <Chip size="small" variant="outlined" label={row.Log} />
      </Stack>
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

// Which of the audit log alerts set up now would fire on a saved log, shown condition by condition.
export const CippAuditLogRuleCheck = ({ tenant, logId }) => {
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
  const others = pick('OtherActivity', 'Excluded', 'NotChecked')

  return (
    <Card variant="outlined">
      <CardHeader
        title="Would your alerts fire on this log?"
        subheader="Checked against your audit log alerts as they are set up now. Nothing is sent."
      />
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
                label={`${others.length} look for other activity`}
              />
            </Stack>

            {fires.length === 0 && (
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
              description="Every condition is met too, but only one alert is sent per log, and an earlier alert fires first."
              rows={also}
            />
            <Section
              title="Close"
              description="These alerts look at this activity, but at least one condition is not met. The red lines show what stops them."
              rows={close}
            />

            {counts.length > 0 && (
              <Stack spacing={1}>
                <Typography variant="h6">Repeated activity alerts</Typography>
                {counts.map((row) => (
                  <Stack
                    key={row.RuleKey}
                    direction="row"
                    spacing={1}
                    sx={{ alignItems: 'center' }}
                  >
                    <CippIcons.CheckCircle color="success" fontSize="small" />
                    <Typography variant="body2">
                      <strong>{row.Alert}</strong>: {row.Reason}
                    </Typography>
                  </Stack>
                ))}
              </Stack>
            )}

            {others.length > 0 && (
              <Accordion variant="outlined" disableGutters>
                <AccordionSummary expandIcon={<CippIcons.ExpandMore />}>
                  <Typography variant="body2">
                    {others.length} other{' '}
                    {others.length === 1 ? 'alert looks' : 'alerts look'} for
                    different activity, or {others.length === 1 ? 'does' : 'do'}{' '}
                    not apply here
                  </Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Stack spacing={0.75}>
                    {others.map((row) => (
                      <Typography
                        key={row.RuleKey}
                        variant="body2"
                        sx={{ color: 'text.secondary' }}
                      >
                        <strong>{row.Alert}</strong> ({row.Log}): {row.Reason}
                      </Typography>
                    ))}
                  </Stack>
                </AccordionDetails>
              </Accordion>
            )}
          </Stack>
        )}
      </CardContent>
    </Card>
  )
}

export default CippAuditLogRuleCheck
