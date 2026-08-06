import { Button, Tooltip } from '@mui/material'
import { Refresh } from '@mui/icons-material'
import { Layout as DashboardLayout } from '../../../layouts/index.js'
import { TabbedLayout } from '../../../layouts/TabbedLayout'
import { SchedulerTable } from '../../../components/CippComponents/SchedulerTable'
import { ApiPostCall } from '../../../api/ApiCall'
import { CippApiResults } from '../../../components/CippComponents/CippApiResults'
import tabOptions from './tabOptions'

/**
 * Planned tasks that would fail if they ran right now, most often because a licence they need has been
 * consumed since the task was booked. Flagged ahead of time by Start-CIPPTaskPreflightCheck so they can
 * be fixed before the scheduled time rather than after.
 *
 * The check runs on a six-hourly timer, so after remediating (buying or freeing a licence) the flags
 * can lag by hours - Re-check Now queues an immediate pass instead of waiting.
 */
const Page = () => {
  const recheck = ApiPostCall({
    relatedQueryKeys: ['ListScheduledItems-atrisk'],
  })

  return (
    <>
      <SchedulerTable
        title="Pending with Issues"
        apiParams={{ AtRisk: true }}
        queryKeyPrefix="ListScheduledItems-atrisk"
        cardActions={
          <Tooltip title="Planned tasks are checked automatically every 6 hours for problems that would make them fail, such as a required licence no longer being available. Use this after fixing the underlying issue so the list updates immediately instead of waiting for the next scheduled check.">
            {/* span so the tooltip still shows while the button is disabled mid-check */}
            <span>
              <Button
                startIcon={<Refresh />}
                onClick={() =>
                  recheck.mutate({ url: '/api/ExecSchedulerPreflightCheck', data: {} })
                }
                disabled={recheck.isPending}
              >
                Re-check Now
              </Button>
            </span>
          </Tooltip>
        }
        simpleColumns={[
          'ScheduledTime',
          'TaskState',
          'AtRiskReason',
          'Tenant',
          'Name',
          'Command',
          'Parameters',
          'Recurrence',
        ]}
      />
      <CippApiResults apiObject={recheck} />
    </>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
)

export default Page
