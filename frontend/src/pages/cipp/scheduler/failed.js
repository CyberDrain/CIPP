import { Layout as DashboardLayout } from '../../../layouts/index.js'
import { TabbedLayout } from '../../../layouts/TabbedLayout'
import { SchedulerTable } from '../../../components/CippComponents/SchedulerTable'
import tabOptions from './tabOptions'

/**
 * Tasks that need re-running. Covers both outright failures and tasks that reported success while a
 * step inside them failed - a scheduled user creation where the licence could not be assigned lands
 * here rather than looking green on the main list.
 */
const Page = () => {
  // The API has already narrowed this to tasks needing attention, so within that set TaskState alone
  // separates an outright failure from one that finished while a step inside it failed.
  const filterList = [
    {
      filterName: 'Failed outright',
      value: [{ id: 'TaskState', value: 'Failed' }],
      type: 'column',
    },
    {
      filterName: 'Recurring failures',
      value: [{ id: 'TaskState', value: 'Failed - Planned' }],
      type: 'column',
    },
    {
      filterName: 'Completed with errors',
      value: [{ id: 'TaskState', value: 'Completed' }],
      type: 'column',
    },
  ]

  return (
    <SchedulerTable
      title="Failed Queue"
      apiParams={{ NeedsAttention: true }}
      queryKeyPrefix="ListScheduledItems-failed"
      filters={filterList}
      simpleColumns={[
        'ExecutedTime',
        'TaskState',
        'HasErrors',
        'ErrorSummary',
        'Tenant',
        'Name',
        'Command',
        'ScheduledTime',
        'Recurrence',
        'Results',
      ]}
    />
  )
}

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
)

export default Page
