import {
  Box,
  Chip,
  IconButton,
  Stack,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Tooltip,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import CippButtonCard from '../CippCards/CippButtonCard'
import { CippAutoComplete } from '../CippComponents/CippAutocomplete'
import { COVER_STOCK_OPTIONS, useBrandingSettings } from '../CippPdf'
import { CHART_KINDS } from './reportSettings'

// Editors for the report builder's structured blocks — the ones that carry data rather than prose.
//
// Text blocks stay in the builder page with the rich-text editor they need; these live here because
// they are all the same shape (a title, a small table of values, a couple of options) and because
// the page was already long enough.

/* ── Block definitions ───────────────────────────────────── */

// Data tokens resolve against the reporting database when the report renders, on the server, so a
// scheduled report reads the same data a preview does. Charts and tables pick their data with the
// DataSourcePicker below; free-text figures can still use a token.
const DATA_TOKEN_HINT =
  'Figures can be data tokens, read when the report renders: &Users& counts a collection, ' +
  '&Devices.complianceState=compliant& counts the rows that match, &Mailboxes.TotalItemSize:sum& adds a field up.'

/**
 * Every block the builder can add, grouped the way the picker offers them: a category first, then
 * the block. One flat list of all of them is more than a dropdown reads well with. The text blocks
 * ('blank', 'test', 'database') keep their editors in the builder page; everything else is a
 * structured block with an editor below. This mirrors the server engine's block vocabulary
 * (ReportComponents.RenderBlock) - a block type not listed here has no way into a report.
 */
export const BLOCK_CATEGORIES = [
  {
    label: 'Text',
    value: 'text',
    blocks: [
      { label: 'Custom Block', value: 'blank' },
      { label: 'Note', value: 'note' },
      { label: 'Bullet List', value: 'richbullets' },
      { label: 'Callout', value: 'infobox' },
      { label: 'Callout Grid', value: 'infoboxcolumns' },
    ],
  },
  {
    label: 'Data',
    value: 'data',
    blocks: [
      { label: 'Test Result', value: 'test' },
      { label: 'Database Data', value: 'database' },
      { label: 'Table', value: 'richtable' },
    ],
  },
  {
    label: 'Visuals',
    value: 'visuals',
    blocks: [
      { label: 'Chart', value: 'chart' },
      { label: 'Score Cards', value: 'scorecard' },
      { label: 'Progress Bars', value: 'progress' },
    ],
  },
  {
    label: 'Layout',
    value: 'layout',
    blocks: [
      { label: 'Cover', value: 'cover' },
      { label: 'Titled Page', value: 'page' },
      { label: 'Infographic', value: 'hero' },
      { label: 'Page Break', value: 'pagebreak' },
    ],
  },
]

/** The blocks a category offers: the second step of the picker. */
export const blockTypesFor = (category) =>
  BLOCK_CATEGORIES.find((entry) => entry.value === category)?.blocks ?? []

// One callout to the picker, three block types to the renderer; the editor switches between them.
export const CALLOUT_STYLES = [
  { label: 'Info', value: 'infobox' },
  { label: 'Good news', value: 'clearbox' },
  { label: 'Warning', value: 'alertbox' },
]

const BLOCK_META = {
  chart: { label: 'Chart', Icon: CippIcons.BarChart, colour: 'primary' },
  scorecard: { label: 'Score Cards', Icon: CippIcons.Assessment, colour: 'success' },
  progress: { label: 'Progress Bars', Icon: CippIcons.Speed, colour: 'info' },
  hero: { label: 'Infographic', Icon: CippIcons.ViewCarousel, colour: 'warning' },
  pagebreak: { label: 'Page Break', Icon: CippIcons.HorizontalRule, colour: 'default' },
  cover: { label: 'Cover', Icon: CippIcons.Window, colour: 'default' },
  page: { label: 'Titled Page', Icon: CippIcons.Description, colour: 'default' },
  note: { label: 'Note', Icon: CippIcons.InfoOutlined, colour: 'default' },
  richbullets: { label: 'Bullet List', Icon: CippIcons.List, colour: 'primary' },
  infobox: { label: 'Callout', Icon: CippIcons.Info, colour: 'info' },
  clearbox: { label: 'Callout', Icon: CippIcons.CheckCircle, colour: 'success' },
  alertbox: { label: 'Callout', Icon: CippIcons.Warning, colour: 'warning' },
  infoboxcolumns: { label: 'Callout Grid', Icon: CippIcons.ViewModule, colour: 'info' },
  richtable: { label: 'Table', Icon: CippIcons.TableChart, colour: 'secondary' },
}

export const isStructuredBlock = (type) => Object.prototype.hasOwnProperty.call(BLOCK_META, type)

/** The picker entries that are structured blocks, in picker order. */
export const STRUCTURED_BLOCK_TYPES = BLOCK_CATEGORIES.flatMap((entry) => entry.blocks).filter(
  (option) => isStructuredBlock(option.value)
)

// The stock covers, in the {label, value} shape CippAutoComplete works in.
const HERO_BACKGROUND_OPTIONS = COVER_STOCK_OPTIONS.map((option) => ({
  label: option.label,
  value: option.path,
}))

/** Starting content for a newly added block, so every one arrives with something to look at. */
export const createStructuredBlock = (type, id) => {
  const base = { id, type, title: '', static: true }
  switch (type) {
    case 'chart':
      return {
        ...base,
        title: 'Chart',
        chartKind: 'donut',
        chartData: [
          { label: 'Compliant', value: 0 },
          { label: 'Non-compliant', value: 0 },
        ],
        chartCaption: '',
        chartCentreLabel: 'Total',
        chartMax: '',
      }
    case 'scorecard':
      return {
        ...base,
        title: 'Key Figures',
        stats: [
          { label: 'Users', value: '0' },
          { label: 'Devices', value: '0' },
        ],
      }
    case 'progress':
      return {
        ...base,
        title: 'Coverage',
        items: [{ label: 'MFA enforced', value: 0, max: 100 }],
      }
    case 'hero':
      return {
        ...base,
        title: 'Section heading',
        heroHighlight: '',
        heroSubText: '',
        heroFooterText: '',
        heroImage: '/reportImages/board.jpg',
      }
    case 'pagebreak':
      return { ...base, title: '' }
    case 'cover':
      return { ...base, title: '', coverAccent: '', subtitle: '', coverLabel: '' }
    case 'page':
      return { ...base, title: 'New page', subtitle: '' }
    case 'note':
      return { ...base, content: 'A short aside for the reader.' }
    case 'richbullets':
      return {
        ...base,
        title: 'Key points',
        items: [{ label: 'First point.', text: 'What it means for the organisation.' }],
      }
    case 'infobox':
    case 'clearbox':
    case 'alertbox':
      return { ...base, title: 'Worth noting', content: 'Something the reader should not miss.' }
    case 'infoboxcolumns':
      return {
        ...base,
        columns: 2,
        items: [
          { title: 'Point one', content: 'A short explanation.' },
          { title: 'Point two', content: 'A short explanation.' },
        ],
      }
    case 'richtable':
      return {
        ...base,
        title: 'Table',
        columns: [
          { header: 'Item', key: 'c1' },
          { header: 'Value', key: 'c2' },
        ],
        rows: [{ c1: '', c2: '' }],
      }
    default:
      return base
  }
}

/* ── Data source switch ──────────────────────────────────── */

/**
 * Where a chart's or table's data comes from: typed in by hand, or the reporting database. Chosen
 * first, so each mode shows only its own controls. "Cache" mode with nothing picked yet is a source
 * object with no collection, which the renderer ignores until one is chosen.
 */
const EMPTY_SOURCE = { type: null, field: null, valueField: null, aggregate: null, filter: null }

const SourceSwitch = ({ value, onChange }) => (
  <ToggleButtonGroup
    exclusive
    size="small"
    color="primary"
    aria-label="Data source"
    value={value}
    onChange={(event, next) => next && onChange(next)}
  >
    <ToggleButton value="manual">Manual</ToggleButton>
    <ToggleButton value="cache">Reporting database</ToggleButton>
  </ToggleButtonGroup>
)

/* ── Data source picker ──────────────────────────────────── */

const FILTER_OPS = [
  { label: 'is', value: '=' },
  { label: 'is not', value: '!=' },
]

const COUNT_ROWS = { label: 'Count of rows', value: '__count' }

const AGGREGATES = [
  { label: 'One point per row', value: null },
  { label: 'Add them up', value: 'sum' },
  { label: 'Average them', value: 'avg' },
  { label: 'Take the highest', value: 'max' },
  { label: 'Take the lowest', value: 'min' },
]

/**
 * Where a chart or table gets its data: a collection from the reporting database; for a chart what
 * to show - a count of rows, or a field's value - and the field to show it per (a date field makes
 * a trend, any other a category), optionally combining rows that share a label; and a condition
 * rows must meet. Saved as { type, field, valueField, aggregate, filter } and resolved on the server
 * when the report renders. The collections and fields on offer are the shapes recorded when the
 * cache was written; a field can still be typed, since a shape is sampled.
 */
export const DataSourcePicker = ({ mode, value, onChange, dataShape = [] }) => {
  const source = value && typeof value === 'object' ? value : null
  const collections = dataShape.map((entry) => ({
    label: entry.count == null ? entry.type : `${entry.type} (${entry.count})`,
    value: entry.type,
  }))
  const fields = (dataShape.find((entry) => entry.type === source?.type)?.fields ?? []).map(
    (field) => ({ label: field.type ? `${field.name} (${field.type})` : field.name, value: field.name })
  )
  const filter = source?.filter ?? null
  const asOption = (name) => (name ? (fields.find((f) => f.value === name) ?? { label: name, value: name }) : null)
  const plotting = Boolean(source?.valueField && source.valueField !== '__count')
  const patch = (next) =>
    onChange({
      type: source?.type ?? null,
      field: source?.field ?? null,
      valueField: source?.valueField ?? null,
      aggregate: source?.aggregate ?? null,
      filter,
      ...next,
    })

  return (
    <Stack spacing={1}>
      <Stack direction="row" spacing={1}>
        <Box sx={{ flex: 1 }}>
          <CippAutoComplete
            size="small"
            label="Collection"
            placeholder="Pick a collection"
            multiple={false}
            creatable={false}
            options={collections}
            value={collections.find((option) => option.value === source?.type) ?? null}
            onChange={(option) =>
              onChange(option?.value ? { ...EMPTY_SOURCE, type: option.value } : EMPTY_SOURCE)
            }
          />
        </Box>
        {mode === 'chart' && source?.type ? (
          <>
            <Box sx={{ flex: 1 }}>
              <CippAutoComplete
                size="small"
                label="Show"
                multiple={false}
                creatable={true}
                disableClearable={true}
                options={[COUNT_ROWS, ...fields]}
                value={plotting ? asOption(source.valueField) : COUNT_ROWS}
                onChange={(option) =>
                  patch({
                    valueField: option?.value && option.value !== '__count' ? option.value : null,
                    aggregate: null,
                  })
                }
              />
            </Box>
            <Box sx={{ flex: 1 }}>
              <CippAutoComplete
                size="small"
                label="Per"
                placeholder={plotting ? 'Row order' : 'No field: a single count'}
                multiple={false}
                creatable={true}
                options={fields}
                value={asOption(source.field)}
                onChange={(option) => patch({ field: option?.value ?? null })}
              />
            </Box>
          </>
        ) : null}
      </Stack>
      {mode === 'chart' && plotting && source?.field ? (
        <Box sx={{ maxWidth: 320 }}>
          <CippAutoComplete
            size="small"
            label="Rows sharing a label"
            multiple={false}
            creatable={false}
            disableClearable={true}
            options={AGGREGATES}
            value={AGGREGATES.find((option) => option.value === (source.aggregate ?? null)) ?? AGGREGATES[0]}
            onChange={(option) => patch({ aggregate: option?.value ?? null })}
          />
        </Box>
      ) : null}
      {source?.type ? (
        <Stack direction="row" spacing={1}>
          <Box sx={{ flex: 1 }}>
            <CippAutoComplete
              size="small"
              label="Only rows where"
              placeholder="Every row"
              multiple={false}
              creatable={true}
              options={fields}
              value={asOption(filter?.field)}
              onChange={(option) =>
                patch({
                  filter: option?.value
                    ? { field: option.value, op: filter?.op ?? '=', value: filter?.value ?? '' }
                    : null,
                })
              }
            />
          </Box>
          {filter?.field ? (
            <>
              <Box sx={{ minWidth: 130 }}>
                <CippAutoComplete
                  size="small"
                  label="Condition"
                  multiple={false}
                  creatable={false}
                  disableClearable={true}
                  options={FILTER_OPS}
                  value={FILTER_OPS.find((option) => option.value === filter.op) ?? FILTER_OPS[0]}
                  onChange={(option) => patch({ filter: { ...filter, op: option?.value ?? '=' } })}
                />
              </Box>
              <TextField
                size="small"
                label="Value"
                placeholder="compliant, true, Win*"
                value={filter.value ?? ''}
                onChange={(event) => patch({ filter: { ...filter, value: event.target.value } })}
                sx={{ flex: 1 }}
              />
            </>
          ) : null}
        </Stack>
      ) : null}
      <Typography variant="caption" sx={{ color: 'text.secondary' }}>
        {mode === 'chart'
          ? 'Read from the reporting database when the report renders. Counting rows gives one slice per value of the field; a field\'s value per date field gives a trend, the last 30 points in date order.'
          : 'The rows of the collection (those the condition keeps) fill the table when the report renders; each column reads the field it names.'}
      </Typography>
    </Stack>
  )
}

/* ── Shared shell ────────────────────────────────────────── */

const BlockShell = ({ block, index, totalBlocks, onRemove, onMoveUp, onMoveDown, chips, children }) => {
  const meta = BLOCK_META[block.type] || {}
  const Icon = meta.Icon

  return (
    <CippButtonCard
      title={
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          {Icon ? <Icon fontSize="small" color={meta.colour === 'default' ? 'disabled' : meta.colour} /> : null}
          <Typography variant="subtitle2" sx={{
            fontWeight: 600
          }}>
            {block.title || meta.label}
          </Typography>
          <Chip
            label={meta.label}
            size="small"
            color={meta.colour === 'default' ? undefined : meta.colour}
            variant="outlined"
          />
          {chips}
        </Box>
      }
      cardActions={
        /* The buttons carry their own aria-label rather than relying on the tooltip: a disabled
           button has to be wrapped in a span for the tooltip to fire, and the label would then
           land on the wrapper, leaving the button itself unnamed to a screen reader. */
        <Stack direction="row" spacing={0.5} sx={{
          alignItems: "center"
        }}>
          <Tooltip title="Move up">
            <span>
              <IconButton
                size="small"
                aria-label="Move up"
                onClick={() => onMoveUp(index)}
                disabled={index === 0}
              >
                <CippIcons.ArrowUpward fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Move down">
            <span>
              <IconButton
                size="small"
                aria-label="Move down"
                onClick={() => onMoveDown(index)}
                disabled={index === totalBlocks - 1}
              >
                <CippIcons.ArrowDownward fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Remove block">
            <IconButton
              size="small"
              color="error"
              aria-label="Remove block"
              onClick={() => onRemove(index)}
            >
              <CippIcons.Delete fontSize="small" />
            </IconButton>
          </Tooltip>
        </Stack>
      }
    >
      {children}
    </CippButtonCard>
  );
}

/**
 * Editable list of rows.
 *
 * `columns` is [{ key, label, width, type }]. Deliberately plain MUI rather than react-hook-form:
 * these arrays are variable length and live inside a reorderable list, and field-array bookkeeping
 * would have to be rebuilt every time a block moves.
 */
const RowsEditor = ({ rows, columns, onChange, addLabel = 'Add row', minRows = 1 }) => {
  const update = (rowIndex, key, value) =>
    onChange(rows.map((row, i) => (i === rowIndex ? { ...row, [key]: value } : row)))

  const remove = (rowIndex) => onChange(rows.filter((_, i) => i !== rowIndex))

  const add = () =>
    onChange([...rows, Object.fromEntries(columns.map((column) => [column.key, '']))])

  return (
    <Stack spacing={1}>
      {rows.map((row, rowIndex) => (
        <Stack key={rowIndex} direction="row" spacing={1} sx={{
          alignItems: "center"
        }}>
          {columns.map((column) => (
            <TextField
              key={column.key}
              size="small"
              label={column.label}
              type={column.type || 'text'}
              slotProps={{ htmlInput: column.inputProps }}
              value={row[column.key] ?? ''}
              onChange={(event) => update(rowIndex, column.key, event.target.value)}
              sx={{ flex: column.width ?? 1 }}
            />
          ))}
          <Tooltip title="Remove row">
            <span>
              <IconButton
                size="small"
                color="error"
                aria-label="Remove row"
                onClick={() => remove(rowIndex)}
                disabled={rows.length <= minRows}
              >
                <CippIcons.Delete fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
        </Stack>
      ))}
      <Box>
        <IconButton size="small" onClick={add} aria-label={addLabel}>
          <CippIcons.Add fontSize="small" />
        </IconButton>
        <Typography variant="caption" sx={{
          color: "text.secondary"
        }}>
          {addLabel}
        </Typography>
      </Box>
    </Stack>
  );
}

const TitleField = ({ block, index, onUpdate, label = 'Block title', helperText }) => (
  <TextField
    size="small"
    fullWidth
    label={label}
    helperText={helperText}
    value={block.title ?? ''}
    onChange={(event) => onUpdate(index, { ...block, title: event.target.value })}
  />
)

/* ── Chart ───────────────────────────────────────────────── */

export const ChartBlockCard = ({ block, index, onUpdate, dataShape, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })
  const kind = block.chartKind || 'donut'

  return (
    <BlockShell
      block={block}
      index={index}
      onUpdate={onUpdate}
      chips={<Chip label={kind} size="small" variant="outlined" />}
      {...shell}
    >
      <Stack spacing={2}>
        <Stack direction="row" spacing={1}>
          <TitleField block={block} index={index} onUpdate={onUpdate} />
          <Box sx={{ minWidth: 180 }}>
            <CippAutoComplete
              size="small"
              label="Chart type"
              multiple={false}
              creatable={false}
              disableClearable={true}
              options={CHART_KINDS}
              value={CHART_KINDS.find((option) => option.value === kind) ?? CHART_KINDS[0]}
              onChange={(option) => set({ chartKind: option?.value ?? 'donut' })}
            />
          </Box>
        </Stack>

        <SourceSwitch
          value={block.chartSource ? 'cache' : 'manual'}
          onChange={(next) => set({ chartSource: next === 'cache' ? EMPTY_SOURCE : null })}
        />
        {block.chartSource ? (
          <DataSourcePicker
            mode="chart"
            value={block.chartSource}
            onChange={(chartSource) => set({ chartSource })}
            dataShape={dataShape}
          />
        ) : (
          <RowsEditor
            rows={block.chartData || []}
            columns={[
              { key: 'label', label: 'Label', width: 2 },
              { key: 'value', label: 'Value', width: 1, type: 'number' },
              { key: 'colour', label: 'Colour (optional)', width: 1 },
            ]}
            onChange={(chartData) => set({ chartData })}
            addLabel="Add data point"
          />
        )}

        <Stack direction="row" spacing={1}>
          <TextField
            size="small"
            fullWidth
            label="Caption"
            value={block.chartCaption ?? ''}
            onChange={(event) => set({ chartCaption: event.target.value })}
          />
          {kind === 'donut' ? (
            <TextField
              size="small"
              label="Centre label"
              value={block.chartCentreLabel ?? ''}
              onChange={(event) => set({ chartCentreLabel: event.target.value })}
              sx={{ minWidth: 160 }}
            />
          ) : null}
          {kind === 'trend' ? (
            <TextField
              size="small"
              type="number"
              label="Axis maximum"
              helperText="Blank = highest value"
              value={block.chartMax ?? ''}
              onChange={(event) => set({ chartMax: event.target.value })}
              sx={{ minWidth: 160 }}
            />
          ) : null}
        </Stack>
      </Stack>
    </BlockShell>
  )
}

/* ── Score cards ─────────────────────────────────────────── */

export const ScorecardBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const stats = block.stats || []

  return (
    <BlockShell block={block} index={index} chips={<Chip label={`${stats.length} cards`} size="small" variant="outlined" />} {...shell}>
      <Stack spacing={2}>
        <TitleField block={block} index={index} onUpdate={onUpdate} />
        <RowsEditor
          rows={stats}
          columns={[
            { key: 'value', label: 'Figure', width: 1 },
            { key: 'label', label: 'Label', width: 2 },
            { key: 'caption', label: 'Caption (optional)', width: 2 },
          ]}
          onChange={(next) => onUpdate(index, { ...block, stats: next })}
          addLabel="Add card"
        />
        <Typography variant="caption" sx={{ color: 'text.secondary' }}>
          {DATA_TOKEN_HINT}
        </Typography>
        {stats.length > 4 ? (
          <Typography variant="caption" sx={{
            color: "warning.main"
          }}>
            More than four cards on a row get too narrow to read in the PDF.
          </Typography>
        ) : null}
      </Stack>
    </BlockShell>
  );
}

/* ── Progress bars ───────────────────────────────────────── */

export const ProgressBlockCard = ({ block, index, onUpdate, ...shell }) => (
  <BlockShell block={block} index={index} {...shell}>
    <Stack spacing={2}>
      <TitleField block={block} index={index} onUpdate={onUpdate} />
      <RowsEditor
        rows={block.items || []}
        columns={[
          { key: 'label', label: 'Label', width: 2 },
          { key: 'value', label: 'Value', width: 1, type: 'number' },
          { key: 'max', label: 'Out of', width: 1, type: 'number' },
        ]}
        onChange={(items) => onUpdate(index, { ...block, items })}
        addLabel="Add bar"
      />
      <Typography variant="caption" sx={{ color: 'text.secondary' }}>
        {DATA_TOKEN_HINT}
      </Typography>
    </Stack>
  </BlockShell>
)

/* ── Infographic ─────────────────────────────────────── */

export const HeroBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })
  // The stock photos, then the covers uploaded to the branding gallery under the names given there.
  // A gallery cover is stored as 'gallery:<id>' and read into the report when it renders.
  const branding = useBrandingSettings()
  const backgroundOptions = [
    ...HERO_BACKGROUND_OPTIONS,
    ...(branding.coverImages || []).map((image, position) => ({
      label: `Uploaded: ${image.name || `cover ${position + 1}`}`,
      value: `gallery:${image.id}`,
    })),
  ]

  return (
    <BlockShell block={block} index={index} {...shell}>
      <Stack spacing={2}>
        <Typography variant="caption" sx={{
          color: "text.secondary"
        }}>
          Takes a full page of its own, with the background image bleeding to the paper edge.
        </Typography>
        <Stack direction="row" spacing={1}>
          <TextField
            size="small"
            label="Big figure"
            placeholder="83%"
            value={block.heroHighlight ?? ''}
            onChange={(event) => set({ heroHighlight: event.target.value })}
            sx={{ minWidth: 140 }}
          />
          <TitleField block={block} index={index} onUpdate={onUpdate} label="Headline" />
        </Stack>
        <TextField
          size="small"
          fullWidth
          multiline
          minRows={2}
          label="Supporting text"
          value={block.heroSubText ?? ''}
          onChange={(event) => set({ heroSubText: event.target.value })}
        />
        <Stack direction="row" spacing={1}>
          <TextField
            size="small"
            fullWidth
            label="Corner note"
            value={block.heroFooterText ?? ''}
            onChange={(event) => set({ heroFooterText: event.target.value })}
          />
          <Box sx={{ minWidth: 190 }}>
            <CippAutoComplete
              size="small"
              label="Background"
              multiple={false}
              creatable={false}
              disableClearable={true}
              options={backgroundOptions}
              value={
                backgroundOptions.find(
                  (option) => option.value === (block.heroImage || 'none')
                ) ?? backgroundOptions[0]
              }
              onChange={(option) =>
                set({ heroImage: !option || option.value === 'none' ? '' : option.value })
              }
            />
          </Box>
        </Stack>
      </Stack>
    </BlockShell>
  );
}

/* ── Page break ──────────────────────────────────────────── */

export const PageBreakBlockCard = ({ block, index, ...shell }) => (
  <BlockShell block={block} index={index} {...shell}>
    <Typography variant="caption" sx={{
      color: "text.secondary"
    }}>
      Everything after this starts on a new page.
    </Typography>
  </BlockShell>
)

/* ── Cover ───────────────────────────────────────────────── */

export const CoverBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })

  return (
    <BlockShell block={block} index={index} {...shell}>
      <Stack spacing={2}>
        <Typography variant="caption" sx={{ color: 'text.secondary' }}>
          The cover page. Leave the title blank to use the report's name; the accent is the part of
          the title set in the brand colour.
        </Typography>
        <Stack direction="row" spacing={1}>
          <TitleField
            block={block}
            index={index}
            onUpdate={onUpdate}
            label="Cover title"
            helperText="Blank = the report's name"
          />
          <TextField
            size="small"
            label="Accent"
            placeholder="Review"
            value={block.coverAccent ?? ''}
            onChange={(event) => set({ coverAccent: event.target.value })}
            sx={{ minWidth: 180 }}
          />
        </Stack>
        <TextField
          size="small"
          fullWidth
          multiline
          minRows={2}
          label="Subtitle"
          value={block.subtitle ?? ''}
          onChange={(event) => set({ subtitle: event.target.value })}
        />
        <TextField
          size="small"
          label="Label"
          placeholder="Assessment Report"
          helperText="The small pill above the title"
          value={block.coverLabel ?? ''}
          onChange={(event) => set({ coverLabel: event.target.value })}
          sx={{ maxWidth: 320 }}
        />
      </Stack>
    </BlockShell>
  )
}

/* ── Titled page ─────────────────────────────────────────── */

export const PageBlockCard = ({ block, index, onUpdate, ...shell }) => (
  <BlockShell block={block} index={index} {...shell}>
    <Stack spacing={2}>
      <Typography variant="caption" sx={{ color: 'text.secondary' }}>
        Starts a new page with this title and subtitle in its header. The blocks that follow land on
        it.
      </Typography>
      <Stack direction="row" spacing={1}>
        <TitleField block={block} index={index} onUpdate={onUpdate} label="Page title" />
        <TextField
          size="small"
          fullWidth
          label="Subtitle"
          value={block.subtitle ?? ''}
          onChange={(event) => onUpdate(index, { ...block, subtitle: event.target.value })}
        />
      </Stack>
    </Stack>
  </BlockShell>
)

/* ── Note ────────────────────────────────────────────────── */

export const NoteBlockCard = ({ block, index, onUpdate, ...shell }) => (
  <BlockShell block={block} index={index} {...shell}>
    <TextField
      size="small"
      fullWidth
      multiline
      minRows={2}
      label="Note"
      helperText="A small italic aside, the size of a caption."
      value={block.content ?? ''}
      onChange={(event) => onUpdate(index, { ...block, content: event.target.value })}
    />
  </BlockShell>
)

/* ── Bullet list ─────────────────────────────────────────── */

export const BulletsBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const items = block.items || []
  return (
    <BlockShell
      block={block}
      index={index}
      chips={<Chip label={`${items.length} bullets`} size="small" variant="outlined" />}
      {...shell}
    >
      <Stack spacing={2}>
        <TitleField block={block} index={index} onUpdate={onUpdate} />
        <RowsEditor
          rows={items}
          columns={[
            { key: 'label', label: 'Lead (bold)', width: 1 },
            { key: 'text', label: 'Text', width: 3 },
          ]}
          onChange={(next) => onUpdate(index, { ...block, items: next })}
          addLabel="Add bullet"
        />
      </Stack>
    </BlockShell>
  )
}

/* ── Callout ─────────────────────────────────────────────── */

export const CalloutBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })
  const style = CALLOUT_STYLES.find((option) => option.value === block.type) ?? CALLOUT_STYLES[0]

  return (
    <BlockShell
      block={block}
      index={index}
      chips={<Chip label={style.label} size="small" variant="outlined" />}
      {...shell}
    >
      <Stack spacing={2}>
        <Stack direction="row" spacing={1}>
          <TitleField block={block} index={index} onUpdate={onUpdate} label="Callout title" />
          <Box sx={{ minWidth: 180 }}>
            <CippAutoComplete
              size="small"
              label="Style"
              multiple={false}
              creatable={false}
              disableClearable={true}
              options={CALLOUT_STYLES}
              value={style}
              onChange={(option) => set({ type: option?.value ?? 'infobox' })}
            />
          </Box>
        </Stack>
        <TextField
          size="small"
          fullWidth
          multiline
          minRows={3}
          label="Text"
          helperText="Markdown works here: **bold**, _italic_ and links."
          value={block.content ?? ''}
          onChange={(event) => set({ content: event.target.value })}
        />
      </Stack>
    </BlockShell>
  )
}

/* ── Callout grid ────────────────────────────────────────── */

const GRID_LAYOUT_OPTIONS = [
  { label: '1 across', value: 1 },
  { label: '2 across', value: 2 },
  { label: '3 across', value: 3 },
]

export const CalloutGridBlockCard = ({ block, index, onUpdate, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })
  const items = block.items || []
  const layout =
    GRID_LAYOUT_OPTIONS.find((option) => option.value === Number(block.columns)) ??
    GRID_LAYOUT_OPTIONS[1]
  const updateItem = (position, patch) =>
    set({ items: items.map((entry, i) => (i === position ? { ...entry, ...patch } : entry)) })

  return (
    <BlockShell
      block={block}
      index={index}
      chips={<Chip label={`${items.length} callouts`} size="small" variant="outlined" />}
      {...shell}
    >
      <Stack spacing={2}>
        <Box sx={{ maxWidth: 200 }}>
          <CippAutoComplete
            size="small"
            label="Layout"
            multiple={false}
            creatable={false}
            disableClearable={true}
            options={GRID_LAYOUT_OPTIONS}
            value={layout}
            onChange={(option) => set({ columns: option?.value ?? 2 })}
          />
        </Box>
        {/* Laid out the way the page will be, so the grid can be judged without a preview. */}
        <Box
          data-testid="callout-grid"
          data-columns={layout.value}
          sx={{
            display: 'grid',
            gridTemplateColumns: `repeat(${layout.value}, minmax(0, 1fr))`,
            gap: 1.5,
          }}
        >
          {items.map((entry, position) => (
            <Box
              key={position}
              sx={{
                borderLeft: '4px solid',
                borderColor: 'primary.main',
                bgcolor: 'action.hover',
                borderRadius: 1,
                p: 1.5,
              }}
            >
              <Stack spacing={1}>
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                  <TextField
                    size="small"
                    fullWidth
                    label="Title"
                    value={entry.title ?? ''}
                    onChange={(event) => updateItem(position, { title: event.target.value })}
                  />
                  <Tooltip title="Remove callout">
                    <span>
                      <IconButton
                        size="small"
                        color="error"
                        aria-label="Remove callout"
                        onClick={() => set({ items: items.filter((_, i) => i !== position) })}
                        disabled={items.length <= 1}
                      >
                        <CippIcons.Delete fontSize="small" />
                      </IconButton>
                    </span>
                  </Tooltip>
                </Stack>
                <TextField
                  size="small"
                  fullWidth
                  multiline
                  minRows={2}
                  label="Text"
                  value={entry.content ?? ''}
                  onChange={(event) => updateItem(position, { content: event.target.value })}
                />
              </Stack>
            </Box>
          ))}
        </Box>
        <Box>
          <IconButton
            size="small"
            aria-label="Add callout"
            onClick={() => set({ items: [...items, { title: '', content: '' }] })}
          >
            <CippIcons.Add fontSize="small" />
          </IconButton>
          <Typography variant="caption" sx={{ color: 'text.secondary' }}>
            Add callout
          </Typography>
        </Box>
      </Stack>
    </BlockShell>
  )
}

/* ── Table ───────────────────────────────────────────────── */

export const TableBlockCard = ({ block, index, onUpdate, dataShape, ...shell }) => {
  const set = (patch) => onUpdate(index, { ...block, ...patch })
  const columns = block.columns || []
  const rows = block.rows || []
  // The picked collection's fields, offered on each column's field input.
  const sourceFields = dataShape?.find((entry) => entry.type === block.dataSource?.type)?.fields ?? []
  const fieldListId = `table-fields-${block.id}`

  // Columns are keyed rather than positional, so renaming a header never detaches the cells under
  // it. A new column takes the next free key; a removed one takes its cells with it.
  const nextKey = () =>
    `c${columns.reduce((max, column) => Math.max(max, Number(String(column.key).replace(/[^0-9]/g, '')) || 0), 0) + 1}`
  const setColumns = (next) => {
    const keyed = next.map((column) => (column.key ? column : { ...column, key: nextKey() }))
    const keep = new Set(keyed.map((column) => column.key))
    set({
      columns: keyed,
      rows: rows.map((row) => Object.fromEntries(Object.entries(row).filter(([key]) => keep.has(key)))),
    })
  }

  return (
    <BlockShell
      block={block}
      index={index}
      chips={<Chip label={`${rows.length} rows`} size="small" variant="outlined" />}
      {...shell}
    >
      <Stack spacing={2}>
        <TitleField block={block} index={index} onUpdate={onUpdate} />
        <SourceSwitch
          value={block.dataSource ? 'cache' : 'manual'}
          onChange={(next) => set({ dataSource: next === 'cache' ? EMPTY_SOURCE : null })}
        />
        {block.dataSource ? (
          <>
            <DataSourcePicker
              mode="table"
              value={block.dataSource}
              onChange={(dataSource) => set({ dataSource })}
              dataShape={dataShape}
            />
            <datalist id={fieldListId}>
              {sourceFields.map((field) => (
                <option key={field.name} value={field.name} />
              ))}
            </datalist>
            <Typography variant="caption" sx={{ color: 'text.secondary' }}>
              Columns: the field each one reads (its header when blank)
            </Typography>
            <RowsEditor
              rows={columns}
              columns={[
                { key: 'header', label: 'Column header', width: 1 },
                { key: 'field', label: 'Field', width: 1, inputProps: { list: fieldListId } },
              ]}
              onChange={setColumns}
              addLabel="Add column"
            />
          </>
        ) : (
          <>
            <Typography variant="caption" sx={{ color: 'text.secondary' }}>
              Columns
            </Typography>
            <RowsEditor
              rows={columns}
              columns={[{ key: 'header', label: 'Column header', width: 1 }]}
              onChange={setColumns}
              addLabel="Add column"
            />
            <Typography variant="caption" sx={{ color: 'text.secondary' }}>
              Rows
            </Typography>
            <RowsEditor
              rows={rows}
              columns={columns.map((column, position) => ({
                key: column.key,
                label: column.header || `Column ${position + 1}`,
                width: 1,
              }))}
              onChange={(next) => set({ rows: next })}
              addLabel="Add row"
            />
          </>
        )}
      </Stack>
    </BlockShell>
  )
}

/** Pick the editor for a structured block. Returns null for block types handled elsewhere. */
export const StructuredBlockCard = ({ block, ...props }) => {
  switch (block.type) {
    case 'cover':
      return <CoverBlockCard block={block} {...props} />
    case 'page':
      return <PageBlockCard block={block} {...props} />
    case 'note':
      return <NoteBlockCard block={block} {...props} />
    case 'richbullets':
      return <BulletsBlockCard block={block} {...props} />
    case 'infobox':
    case 'clearbox':
    case 'alertbox':
      return <CalloutBlockCard block={block} {...props} />
    case 'infoboxcolumns':
      return <CalloutGridBlockCard block={block} {...props} />
    case 'richtable':
      return <TableBlockCard block={block} {...props} />
    case 'chart':
      return <ChartBlockCard block={block} {...props} />
    case 'scorecard':
      return <ScorecardBlockCard block={block} {...props} />
    case 'progress':
      return <ProgressBlockCard block={block} {...props} />
    case 'hero':
      return <HeroBlockCard block={block} {...props} />
    case 'pagebreak':
      return <PageBreakBlockCard block={block} {...props} />
    default:
      return null
  }
}
