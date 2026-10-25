import { useMemo, useState } from 'react'
import {
  Box,
  Button,
  Card,
  CardContent,
  CardHeader,
  Chip,
  Divider,
  InputAdornment,
  Stack,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { getCippTranslation } from '../../utils/get-cipp-translation'
import auditLogTranslation from '../../data/audit-log-translations.json'

// Fields CIPP adds for itself, or that the page shows elsewhere.
const internalFields = new Set([
  'CreationTime',
  'AuditRecord',
  'CIPPClause',
  'CIPPAction',
  'CIPPBecActions',
  'CIPPAlertComment',
  'CIPPCustomSubject',
  'CIPPPsaTicketPriority',
  'CIPPParameters',
  'CIPPLocationInfo',
  'CIPPDeviceProperties',
  'CIPPExtendedProperties',
  'CIPPModifiedProperties',
  'HasLocationData',
  'ModifiedProperties',
  'CIPPActor',
])

// Plain names for the fields CIPP derives.
const fieldLabels = {
  CIPPUserId: 'User',
  CIPPActorType: 'Done by a',
  CIPPActorIsTarget: 'Acted on itself',
  CIPPTargetType: 'Done to a',
  CIPPGeoLocation: 'Country',
  CIPPBadRepIP: 'Known VPN, proxy or anonymiser',
  CIPPHostedIP: 'Hosting provider address',
  CIPPIPDetected: 'IP address',
  CIPPThresholdCount: 'Times repeated',
}

const labelOf = (name) =>
  fieldLabels[name] ?? getCippTranslation(String(name).replace(/\.+$/, ''))

const sections = [
  {
    title: 'Who',
    fields: [
      'CIPPUserId',
      'UserId',
      'UserKey',
      'UserType',
      'Actor',
      'CIPPActorType',
      'CIPPActorIsTarget',
    ],
  },
  {
    title: 'What',
    fields: [
      'Operation',
      'ResultStatus',
      'Workload',
      'RecordType',
      'extendedAuditEventCategory',
      'ObjectId',
      'Target',
      'CIPPTargetType',
    ],
  },
  {
    title: 'Where',
    fields: [
      'ClientIP',
      'CIPPGeoLocation',
      'CIPPBadRepIP',
      'CIPPHostedIP',
      'CIPPIPDetected',
    ],
  },
  {
    title: 'Technical IDs',
    fields: [
      'Id',
      'OrganizationId',
      'ActorContextId',
      'TargetContextId',
      'InterSystemsId',
      'IntraSystemId',
      'SupportTicketId',
      'Version',
      'AzureActiveDirectoryEventType',
    ],
  },
]

const parseJson = (value) => {
  if (typeof value !== 'string' || !/^\s*[[{]/.test(value)) return value
  try {
    return JSON.parse(value)
  } catch {
    return value
  }
}

const isEmpty = (value) =>
  value === null ||
  value === undefined ||
  value === '' ||
  (Array.isArray(value) && value.length === 0) ||
  value === '[]'

// The record's changed properties as before and after, from ModifiedProperties.
const changesOf = (raw) =>
  (Array.isArray(raw.ModifiedProperties) ? raw.ModifiedProperties : [])
    .map((change) => ({
      name: change.Name,
      before: change.OldValue ?? '',
      after: change.NewValue ?? '',
    }))
    .filter((change) => change.before !== change.after)

// Every field worth showing: not internal, not empty, and not a copy of a change.
const fieldsOf = (raw) => {
  const changed = new Set(changesOf(raw).map((change) => change.name))
  return Object.entries(raw).filter(
    ([key, value]) =>
      !internalFields.has(key) &&
      !key.startsWith('Previous_Value_') &&
      !changed.has(key) &&
      !isEmpty(value)
  )
}

const LongText = ({ text }) => {
  const [open, setOpen] = useState(false)
  if (text.length <= 160) return text
  return (
    <>
      {open ? text : `${text.slice(0, 160)}…`}{' '}
      <Button
        size="small"
        sx={{ p: 0, minWidth: 0 }}
        onClick={() => setOpen(!open)}
      >
        {open ? 'Show less' : 'Show all'}
      </Button>
    </>
  )
}

// A field's value in plain form: lists of IDs as chips, name/value lists as lines, yes/no for booleans.
const FieldValue = ({ name, value }) => {
  const parsed = parseJson(value)
  if (Array.isArray(parsed)) {
    if (
      parsed.every((item) => item && typeof item === 'object' && 'ID' in item)
    ) {
      return (
        <Stack
          direction="row"
          spacing={0.5}
          useFlexGap
          sx={{ flexWrap: 'wrap' }}
        >
          {parsed.map((item, index) => (
            <Chip
              key={index}
              size="small"
              variant="outlined"
              label={String(item.ID)}
              title={String(item.ID)}
              sx={{ maxWidth: '100%' }}
            />
          ))}
        </Stack>
      )
    }
    if (
      parsed.every((item) => item && typeof item === 'object' && 'Name' in item)
    ) {
      return (
        <Stack spacing={0.25}>
          {parsed.map((item, index) => (
            <span key={index}>
              <strong>{item.Name}:</strong>{' '}
              <LongText text={String(item.Value ?? '')} />
            </span>
          ))}
        </Stack>
      )
    }
    return (
      <LongText text={parsed.map((item) => JSON.stringify(item)).join(', ')} />
    )
  }
  if (parsed && typeof parsed === 'object') {
    return (
      <Stack spacing={0.25}>
        {Object.entries(parsed).map(([key, item]) => (
          <span key={key}>
            <strong>{key}:</strong>{' '}
            <LongText
              text={
                typeof item === 'object' ? JSON.stringify(item) : String(item)
              }
            />
          </span>
        ))}
      </Stack>
    )
  }
  if (typeof parsed === 'boolean' || /^(true|false)$/i.test(String(parsed))) {
    return /^true$/i.test(String(parsed)) ? 'Yes' : 'No'
  }
  const text = String(parsed)
  return <LongText text={auditLogTranslation[name]?.[text] ?? text} />
}

const FieldRow = ({ name, value }) => (
  <Box
    sx={{
      display: 'grid',
      gridTemplateColumns: { xs: 'minmax(0, 1fr)', sm: '220px minmax(0, 1fr)' },
      columnGap: 2,
      py: 0.75,
      borderBottom: 1,
      borderColor: 'divider',
      '&:last-of-type': { borderBottom: 0 },
    }}
  >
    <Typography variant="body2" sx={{ color: 'text.secondary' }}>
      {labelOf(name)}
    </Typography>
    <Typography
      variant="body2"
      component="div"
      sx={{ wordBreak: 'break-word' }}
    >
      <FieldValue name={name} value={value} />
    </Typography>
  </Box>
)

// Long lists such as permission scopes: what was added and removed, not both lists in full.
const ChangeRow = ({ change }) => {
  const split = (text) =>
    String(text)
      .split(/[\s,]+/)
      .filter(Boolean)
  const before = split(change.before)
  const after = split(change.after)
  const isList = before.length > 3 || after.length > 3
  const added = after.filter((item) => !before.includes(item))
  const removed = before.filter((item) => !after.includes(item))
  return (
    <Box
      sx={{
        py: 1,
        borderBottom: 1,
        borderColor: 'divider',
        '&:last-of-type': { borderBottom: 0 },
      }}
    >
      <Typography variant="body2" sx={{ fontWeight: 600, mb: 0.5 }}>
        {labelOf(change.name)}
      </Typography>
      {isList ? (
        <Stack spacing={0.75}>
          {added.length === 0 && removed.length === 0 && (
            <Typography variant="body2" sx={{ color: 'text.secondary' }}>
              No change to its {after.length} values.
            </Typography>
          )}
          {added.length > 0 && (
            <Stack
              direction="row"
              spacing={0.5}
              useFlexGap
              sx={{ flexWrap: 'wrap', alignItems: 'center' }}
            >
              <Typography
                variant="caption"
                sx={{ color: 'success.main', mr: 0.5 }}
              >
                Added
              </Typography>
              {added.map((item) => (
                <Chip
                  key={item}
                  size="small"
                  color="success"
                  variant="outlined"
                  label={item}
                />
              ))}
            </Stack>
          )}
          {removed.length > 0 && (
            <Stack
              direction="row"
              spacing={0.5}
              useFlexGap
              sx={{ flexWrap: 'wrap', alignItems: 'center' }}
            >
              <Typography
                variant="caption"
                sx={{ color: 'error.main', mr: 0.5 }}
              >
                Removed
              </Typography>
              {removed.map((item) => (
                <Chip
                  key={item}
                  size="small"
                  color="error"
                  variant="outlined"
                  label={item}
                />
              ))}
            </Stack>
          )}
        </Stack>
      ) : (
        <Stack
          direction="row"
          spacing={1}
          useFlexGap
          sx={{ flexWrap: 'wrap', alignItems: 'center' }}
        >
          <Typography
            variant="body2"
            sx={{ color: 'text.secondary', textDecoration: 'line-through' }}
          >
            {change.before || 'empty'}
          </Typography>
          <CippIcons.ArrowForward fontSize="small" />
          <Typography variant="body2">{change.after || 'empty'}</Typography>
        </Stack>
      )}
    </Box>
  )
}

const SectionBlock = ({ title, children }) => (
  <Box>
    <Typography variant="overline" sx={{ color: 'text.secondary' }}>
      {title}
    </Typography>
    <Box>{children}</Box>
  </Box>
)

const Sections = ({ raw }) => {
  const fields = Object.fromEntries(fieldsOf(raw))
  const changes = changesOf(raw)
  const placed = new Set(sections.flatMap((section) => section.fields))
  const others = Object.entries(fields).filter(([key]) => !placed.has(key))
  // A repeated activity alert keeps the record that reached its count.
  const samples = parseJson(raw.AuditRecord)
  return (
    <Stack spacing={2}>
      {sections.slice(0, 3).map((section) => {
        const rows = section.fields.filter((key) => key in fields)
        return (
          rows.length > 0 && (
            <SectionBlock key={section.title} title={section.title}>
              {rows.map((key) => (
                <FieldRow key={key} name={key} value={fields[key]} />
              ))}
            </SectionBlock>
          )
        )
      })}
      {changes.length > 0 && (
        <SectionBlock title="What changed">
          {changes.map((change) => (
            <ChangeRow key={change.name} change={change} />
          ))}
        </SectionBlock>
      )}
      {Array.isArray(samples) && samples.length > 0 && (
        <SectionBlock
          title={
            samples.length === 1
              ? 'The record that reached the count'
              : `Sample records (${samples.length})`
          }
        >
          {samples.map((sample, index) => (
            <FieldRow
              key={sample.Id ?? index}
              name={sample.Operation ?? 'Record'}
              value={[
                sample.CreationTime,
                sample.ObjectId ?? sample.SourceFileName,
              ]
                .filter(Boolean)
                .join('  ·  ')}
            />
          ))}
        </SectionBlock>
      )}
      {others.length > 0 && (
        <SectionBlock title="Other details">
          {others.map(([key, value]) => (
            <FieldRow key={key} name={key} value={value} />
          ))}
        </SectionBlock>
      )}
      {sections[3].fields.some((key) => key in fields) && (
        <SectionBlock title="Technical IDs">
          {sections[3].fields
            .filter((key) => key in fields)
            .map((key) => (
              <FieldRow key={key} name={key} value={fields[key]} />
            ))}
        </SectionBlock>
      )}
    </Stack>
  )
}

const ChangesAndSearch = ({ raw }) => {
  const [search, setSearch] = useState('')
  const changes = changesOf(raw)
  const term = search.trim().toLowerCase()
  const fields = fieldsOf(raw).filter(
    ([key, value]) =>
      !term ||
      labelOf(key).toLowerCase().includes(term) ||
      JSON.stringify(value).toLowerCase().includes(term)
  )
  return (
    <Stack spacing={2}>
      {changes.length > 0 && (
        <SectionBlock title="What changed">
          {changes.map((change) => (
            <ChangeRow key={change.name} change={change} />
          ))}
        </SectionBlock>
      )}
      <SectionBlock title="Fields">
        <TextField
          size="small"
          fullWidth
          placeholder="Find a field or value"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          sx={{ my: 1 }}
          slotProps={{
            input: {
              startAdornment: (
                <InputAdornment position="start">
                  <CippIcons.Search fontSize="small" />
                </InputAdornment>
              ),
            },
          }}
        />
        {fields.length === 0 ? (
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            No field matches “{search}”.
          </Typography>
        ) : (
          fields.map(([key, value]) => (
            <FieldRow key={key} name={key} value={value} />
          ))
        )}
      </SectionBlock>
    </Stack>
  )
}

const RawJson = ({ raw }) => {
  const [copied, setCopied] = useState(false)
  // The record as Microsoft sent it, when CIPP kept it; otherwise the fields CIPP shows.
  const original = parseJson(raw.AuditRecord)
  const json = JSON.stringify(
    original && typeof original === 'object'
      ? original
      : Object.fromEntries(fieldsOf(raw)),
    null,
    2
  )
  return (
    <Stack spacing={1}>
      <Stack
        direction="row"
        sx={{ justifyContent: 'space-between', alignItems: 'center' }}
      >
        <Typography variant="body2" sx={{ color: 'text.secondary' }}>
          The audit record as Microsoft sent it.
        </Typography>
        <Button
          size="small"
          startIcon={<CippIcons.ContentCopy fontSize="small" />}
          onClick={() => {
            navigator.clipboard?.writeText(json)
            setCopied(true)
          }}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </Stack>
      <Box
        component="pre"
        sx={{
          m: 0,
          p: 2,
          maxHeight: 600,
          overflow: 'auto',
          borderRadius: 1,
          bgcolor: 'action.hover',
          fontSize: 12,
          lineHeight: 1.5,
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-all',
        }}
      >
        {json}
      </Box>
    </Stack>
  )
}

const views = [
  { value: 'sections', label: 'Sections' },
  { value: 'search', label: 'Changes and search' },
  { value: 'json', label: 'Raw JSON' },
]

// The full audit record of a saved log, in a few ways to read it.
export const CippAuditRecordView = ({ raw }) => {
  const [view, setView] = useState('sections')
  const record = useMemo(() => raw ?? {}, [raw])
  return (
    <Card variant="outlined">
      <CardHeader
        title="Everything in the audit record"
        action={
          <ToggleButtonGroup
            size="small"
            exclusive
            value={view}
            onChange={(_, next) => next && setView(next)}
          >
            {views.map((option) => (
              <ToggleButton key={option.value} value={option.value}>
                {option.label}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
        }
      />
      <Divider />
      <CardContent>
        {view === 'sections' && <Sections raw={record} />}
        {view === 'search' && <ChangesAndSearch raw={record} />}
        {view === 'json' && <RawJson raw={record} />}
      </CardContent>
    </Card>
  )
}

export default CippAuditRecordView
