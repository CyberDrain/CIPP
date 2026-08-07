import { useEffect, useMemo, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  List,
  ListItemButton,
  ListItemText,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import {
  fetchIntuneDefinition,
  useIntuneSettingIndex,
} from '../../hooks/use-intune-collection'
import {
  childDefinitionIds,
  definitionInstanceType,
  requiredChildIds,
} from '../../utils/intune-setting-builder'

// Picks a setting to add to a settings catalog policy.
//
// The search runs entirely in the browser against the platform index that ships with the release.
// It is static data, so a round trip per keystroke would buy nothing and would occupy one of Craft's
// PowerShell workers each time - workers that should be doing tenant work. The index is fetched once
// when this dialog first opens and kept for the life of the tab.
//
// Only the definition for the setting actually picked is fetched in full, through the same
// hash-addressed cache every other screen uses.

const SEARCH_DEBOUNCE_MS = 200
const MAX_RESULTS = 100
const EMPTY_EXISTING = []

// Ranks a row against the query: an exact name first, then a name that starts with it, then a name
// that contains it, then everything else that matched on category or id. Without this, searching
// "BitLocker" buries the BitLocker settings under everything that merely mentions it.
const rankRow = (row, query) => {
  const name = (row.displayName ?? '').toLowerCase()
  if (name === query) return 0
  if (name.startsWith(query)) return 1
  if (name.includes(query)) return 2
  return 3
}

const searchIndex = (rows, query) => {
  const needle = query.toLowerCase()
  const matched = []

  for (const row of rows) {
    const haystack = `${row.displayName ?? ''} ${row.categoryName ?? ''} ${row.description ?? ''} ${row.id ?? ''}`
    if (!haystack.toLowerCase().includes(needle)) continue
    matched.push(row)
  }

  matched.sort((a, b) => {
    const rank = rankRow(a, needle) - rankRow(b, needle)
    if (rank !== 0) return rank
    return (a.displayName ?? '').localeCompare(b.displayName ?? '')
  })

  return matched
}


const MAX_DEPTH = 4

// Collects every definition nested beneath one, keyed by id, so the builder can construct the whole
// setting in one go. Visited ids are tracked because the catalog links parents to children and
// children back to parents.
const resolveDescendants = async (definition) => {
  const byId = {}
  const seen = new Set([definition?.id])

  const walk = async (current, depth) => {
    if (!current || depth > MAX_DEPTH) return

    const options = Array.isArray(current.options) ? current.options : []
    const option = options.find((o) => o.id === current.defaultOptionId) ?? options[0]

    const wanted = [
      ...childDefinitionIds(current),
      ...(option ? requiredChildIds(current, option.id) : []),
    ].filter((id) => id && !seen.has(id))

    if (wanted.length === 0) return
    wanted.forEach((id) => seen.add(id))

    const resolved = (await Promise.all(wanted.map(fetchIntuneDefinition))).filter(Boolean)
    resolved.forEach((child) => {
      byId[child.id] = child
    })
    await Promise.all(resolved.map((child) => walk(child, depth + 1)))
  }

  await walk(definition, 0)
  return byId
}

export const CippIntuneSettingPicker = ({
  open,
  onClose,
  onAdd,
  platform,
  technology,
  existingIds = EMPTY_EXISTING,
}) => {
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [pendingId, setPendingId] = useState(null)

  useEffect(() => {
    const timer = setTimeout(
      () => setDebounced(search.trim()),
      SEARCH_DEBOUNCE_MS
    )
    return () => clearTimeout(timer)
  }, [search])

  // Reset on the way out rather than in an effect watching `open`: the close is the event, and
  // reacting to the resulting prop change would set state during render for no reason.
  const handleClose = () => {
    setSearch('')
    setDebounced('')
    setPendingId(null)
    onClose()
  }

  // Resolving one definition is a consequence of the click, not of a render, so it is awaited here
  // instead of being watched for by an effect.
  const handleSelect = async (id) => {
    setPendingId(id)
    try {
      const definition = await fetchIntuneDefinition(id)
      if (!definition) return

      // Everything the builder will need underneath this setting: the members of a group, and the
      // settings the chosen option requires. Intune rejects a policy that is missing either - an
      // empty group is "SettingGroupValue should not be empty", a missing dependant is "Setting
      // contains parent setting that are not present" - and nothing on those settings records that
      // they belong to something, so they can only be resolved from this side.
      //
      // Walked rather than fetched one level deep, because a group's member can itself be a choice
      // with requirements of its own. Bounded so a cycle in the catalog cannot spin here.
      const childDefinitionsById = await resolveDescendants(definition)

      onAdd(definition, childDefinitionsById)
    } finally {
      setPendingId(null)
    }
  }

  // Loaded only once the dialog is opened, so a template nobody adds settings to never pays for it.
  const {
    rows: indexRows,
    isLoading: indexLoading,
    isError: indexError,
  } = useIntuneSettingIndex(platform, { enabled: open })

  const { results, totalMatches } = useMemo(() => {
    if (debounced.length <= 1) return { results: [], totalMatches: 0 }

    let matched = searchIndex(indexRows, debounced)

    if (technology) {
      matched = matched.filter((row) =>
        (row.technologies ?? '').includes(technology)
      )
    }
    // A setting the policy already configures cannot be added twice - Intune rejects the duplicate,
    // and offering it invites exactly that.
    matched = matched.filter((row) => !existingIds.includes(row.id))

    return {
      results: matched.slice(0, MAX_RESULTS),
      totalMatches: matched.length,
    }
  }, [indexRows, debounced, technology, existingIds])

  const truncated = totalMatches > results.length

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>Add a setting</DialogTitle>
      <DialogContent dividers>
        <Stack spacing={2}>
          <TextField
            autoFocus
            fullWidth
            size="small"
            label="Search settings"
            placeholder="e.g. BitLocker, password length, Defender"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            helperText={
              platform
                ? `Searching settings that apply to ${platform}.`
                : 'Searching all platforms.'
            }
          />

          {indexLoading ? (
            <Stack direction="row" spacing={1.5} alignItems="center">
              <CircularProgress size={18} />
              <Typography variant="body2" color="text.secondary">
                Loading the setting catalog…
              </Typography>
            </Stack>
          ) : indexError ? (
            <Alert severity="error">
              The setting catalog could not be loaded.
            </Alert>
          ) : debounced.length <= 1 ? (
            <Typography variant="body2" color="text.secondary">
              Type at least two characters to search{' '}
              {indexRows.length.toLocaleString()} settings.
            </Typography>
          ) : results.length === 0 ? (
            <Typography variant="body2" color="text.secondary">
              No settings matched, or every match is already in this policy.
            </Typography>
          ) : (
            <>
              {truncated && (
                <Alert severity="info">
                  Showing the first {results.length} of {totalMatches} matches.
                  Narrow the search to see more.
                </Alert>
              )}
              <List dense sx={{ maxHeight: 420, overflowY: 'auto' }}>
                {results.map((row) => {
                  // The index only lists settings the settings catalog surfaces, so all that is
                  // left to check is whether this is a shape the builder can construct.
                  const addable = !!definitionInstanceType({
                    '@odata.type': row.settingType,
                  })
                  return (
                    <ListItemButton
                      key={row.id}
                      disabled={!addable || !!pendingId}
                      onClick={() => handleSelect(row.id)}
                      alignItems="flex-start"
                    >
                      <ListItemText
                        primary={
                          <Stack
                            direction="row"
                            spacing={1}
                            alignItems="center"
                            flexWrap="wrap"
                          >
                            <Typography variant="body2">
                              {row.displayName || row.id}
                            </Typography>
                            {row.categoryName && (
                              <Chip
                                label={row.categoryName}
                                size="small"
                                variant="outlined"
                              />
                            )}
                            {!addable && (
                              <Chip
                                label="Not addable here"
                                size="small"
                                color="warning"
                              />
                            )}
                          </Stack>
                        }
                        secondary={
                          <Box component="span" sx={{ display: 'block' }}>
                            <Typography
                              variant="caption"
                              color="text.secondary"
                              component="span"
                            >
                              {row.description
                                ? row.description.slice(0, 180)
                                : row.id}
                            </Typography>
                          </Box>
                        }
                      />
                    </ListItemButton>
                  )
                })}
              </List>
            </>
          )}

          {pendingId && (
            <Stack direction="row" spacing={1.5} alignItems="center">
              <CircularProgress size={18} />
              <Typography variant="body2" color="text.secondary">
                Loading the setting definition…
              </Typography>
            </Stack>
          )}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose}>Close</Button>
      </DialogActions>
    </Dialog>
  )
}

export default CippIntuneSettingPicker
