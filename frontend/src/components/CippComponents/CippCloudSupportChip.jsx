import { Chip, Tooltip } from '@mui/material'
import { useGovernmentClouds } from '../../hooks/use-tenant-cloud'
import {
  cloudLabel,
  getCloudSupportEntry,
} from '../../utils/cloud-feature-support'

// Informational only: templates span many tenants and the backend skips unsupported ones.
export const CippCloudSupportChip = ({ type, name, sx }) => {
  const governmentClouds = useGovernmentClouds()
  const entry = name ? getCloudSupportEntry(type, name) : undefined
  const clouds = entry
    ? entry.unsupportedClouds.filter((cloud) =>
        governmentClouds.includes(cloud)
      )
    : []
  if (clouds.length === 0) return null

  const labels = clouds.map(cloudLabel).join(' / ')
  return (
    <Tooltip
      title={`${entry.reason} It is skipped for ${labels} tenants, with one log line per run; other tenants are not affected.`}
    >
      <Chip
        label={`Not supported in ${labels}`}
        size="small"
        color="warning"
        variant="outlined"
        sx={{ fontSize: '0.7rem', height: 20, ...sx }}
      />
    </Tooltip>
  )
}

export default CippCloudSupportChip
