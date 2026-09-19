import { useState } from 'react'
import {
  Box,
  Stack,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material'
import { CippBecTimelineCustom } from './CippBecTimelineCustom'
import { CippBecCorrelationGraph } from './CippBecCorrelationGraph'

const VERSIONS = [
  { key: 'timeline', label: 'Timeline' },
  { key: 'graph', label: 'Correlation graph' },
]

// Two takes on the same correlated events: a compact vertical timeline, and a non-linear graph that
// groups events by the source they came from and the accounts they reached. Both render natively and
// follow the app theme; the toggle just swaps which one shows.
export const CippBecTimelineEvaluator = ({
  becData,
  windowDays = 7,
  userData,
}) => {
  const [version, setVersion] = useState('timeline')
  return (
    <Box>
      <Stack
        direction="row"
        justifyContent="space-between"
        alignItems="center"
        flexWrap="wrap"
        useFlexGap
        sx={{ mb: 1.5 }}
      >
        <Typography variant="body2" color="text.secondary">
          The same correlated events as a dense timeline, or as a graph grouped
          by attacker source and the accounts it reached.
        </Typography>
        <ToggleButtonGroup
          size="small"
          exclusive
          value={version}
          onChange={(event, value) => value && setVersion(value)}
        >
          {VERSIONS.map((option) => (
            <ToggleButton key={option.key} value={option.key}>
              {option.label}
            </ToggleButton>
          ))}
        </ToggleButtonGroup>
      </Stack>
      {version === 'timeline' && (
        <CippBecTimelineCustom becData={becData} windowDays={windowDays} />
      )}
      {version === 'graph' && (
        <CippBecCorrelationGraph
          becData={becData}
          windowDays={windowDays}
          userData={userData}
        />
      )}
    </Box>
  )
}

export default CippBecTimelineEvaluator
