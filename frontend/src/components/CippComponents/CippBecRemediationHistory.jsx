import {
  Box,
  Card,
  CardContent,
  CardHeader,
  Chip,
  Divider,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'

const stateColor = (state) =>
  ({
    success: 'success',
    error: 'error',
    warning: 'warning',
    info: 'default',
  })[state] || 'default'

// Action ids are stored PascalCase (RemoveMFA); space them for display.
const humanize = (id) =>
  String(id || '')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .trim()

const fmt = (value) => {
  if (!value) return 'Unknown time'
  try {
    return new Date(value).toLocaleString()
  } catch {
    return String(value)
  }
}

// The containment actions run for this case and their per-target results, newest first. Reads the
// history persisted on the run (becData.Run.Containment); renders nothing until something has run.
export const CippBecRemediationHistory = ({ becData }) => {
  const history = [...(becData?.Run?.Containment || [])].reverse()
  if (history.length === 0) return null

  return (
    <Card variant="outlined">
      <CardHeader
        title="Remediation taken"
        subheader="Containment actions run for this case and their results"
        titleTypographyProps={{ variant: 'h6' }}
      />
      <Divider />
      <CardContent>
        <Stack spacing={2.5}>
          {history.map((entry, index) => {
            const results = Array.isArray(entry.Results) ? entry.Results : []
            return (
              <Box key={index}>
                <Typography variant="subtitle2" gutterBottom>
                  {fmt(entry.At)} · {entry.By || 'CIPP'} ·{' '}
                  {(entry.Actions || []).length} action(s)
                </Typography>
                {results.length > 0 ? (
                  <Box sx={{ overflowX: 'auto' }}>
                    <Table size="small">
                      <TableHead>
                        <TableRow>
                          <TableCell>Action</TableCell>
                          <TableCell>Target</TableCell>
                          <TableCell>Result</TableCell>
                          <TableCell>State</TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {results.map((row, rowIndex) => (
                          <TableRow key={rowIndex}>
                            <TableCell>{humanize(row.Action)}</TableCell>
                            <TableCell sx={{ wordBreak: 'break-all' }}>
                              {row.Target}
                            </TableCell>
                            <TableCell>{row.resultText}</TableCell>
                            <TableCell>
                              <Chip
                                size="small"
                                color={stateColor(row.state)}
                                label={row.state || 'unknown'}
                              />
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </Box>
                ) : (
                  <Typography variant="body2" color="text.secondary">
                    No per-action results were recorded.
                  </Typography>
                )}
              </Box>
            )
          })}
        </Stack>
      </CardContent>
    </Card>
  )
}

export default CippBecRemediationHistory
