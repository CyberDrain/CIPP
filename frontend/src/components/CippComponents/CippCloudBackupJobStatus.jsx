import { Alert, LinearProgress, Stack, Typography } from '@mui/material'

export const CippCloudBackupJobStatus = ({ jobState, runningText }) => {
  const { request, job, isActive } = jobState
  if (request.isError) {
    return (
      <Alert severity="error">
        The job could not be loaded. It may be older than 30 days, or you may
        not have access to its tenant.
      </Alert>
    )
  }
  if (isActive) {
    return (
      <Stack spacing={1}>
        <Typography variant="body2">
          {runningText}
          {job?.Status === 'Queued' ? ' Waiting to start.' : ''}
        </Typography>
        <LinearProgress />
      </Stack>
    )
  }
  if (job?.Status === 'Failed') {
    return (
      <Alert severity="error">
        The job failed: {job.Error || 'no reason was recorded.'}
      </Alert>
    )
  }
  return null
}
