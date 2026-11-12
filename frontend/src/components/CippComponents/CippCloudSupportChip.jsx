import { Chip, Tooltip } from '@mui/material'
import { useGovernmentClouds } from '../../hooks/use-tenant-cloud'
import {
  cloudLabel,
  getCloudSupportEntry,
} from '../../utils/cloud-feature-support'

// Marks a standard (or baseline standard) the cloud support matrix lists as unsupported in a cloud
// the user has tenants in (redanthrax/CIPP#4). Templates apply to many tenants, so the item stays
// selectable: the backend skips it for those tenants with one log line. Renders nothing for an
// estate without government tenants and for items the matrix does not list.
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
