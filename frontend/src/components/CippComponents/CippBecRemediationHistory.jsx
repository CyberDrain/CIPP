import {
  Box,
  Card,
  CardContent,
  CardHeader,
  Divider,
  Stack,
  Typography,
} from '@mui/material'
import { CippDataTable } from '../CippTable/CippDataTable'

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
                  {entry.At
                    ? new Date(entry.At).toLocaleString()
                    : 'Unknown time'}{' '}
                  · {entry.By || 'CIPP'} · {(entry.Actions || []).length}{' '}
                  action(s)
                </Typography>
                {results.length > 0 ? (
                  <CippDataTable
                    noCard
                    hideTitle
                    data={results}
                    simpleColumns={['Action', 'Target', 'resultText', 'state']}
                  />
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
