import { ApiGetCall } from '../api/ApiCall'
import { isCloudBackupJobActive } from '../utils/cloud-backup'

const POLL_MS = 3000

const firstJob = (data) => (Array.isArray(data) ? data[0] : data)

export const cloudBackupJobRefetchInterval = (query) =>
  isCloudBackupJobActive(firstJob(query?.state?.data)?.Status) ? POLL_MS : false

export const useCloudBackupJob = (jobId) => {
  const request = ApiGetCall({
    url: '/api/ListCloudBackupJobs',
    data: { Id: jobId },
    queryKey: `ListCloudBackupJobs-job-${jobId}`,
    waiting: !!jobId,
    refetchInterval: cloudBackupJobRefetchInterval,
  })
  const job = jobId ? firstJob(request.data) : undefined
  return {
    request,
    job,
    isActive:
      !!jobId &&
      !request.isError &&
      (!job || isCloudBackupJobActive(job.Status)),
  }
}
