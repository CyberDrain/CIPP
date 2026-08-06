import { useState } from 'react'
import { Button } from '@mui/material'
import CippTablePage from './CippTablePage'
import ScheduledTaskDetails from './ScheduledTaskDetails'
import { CippScheduledTaskActions } from './CippScheduledTaskActions'
import { CippSchedulerDrawer } from './CippSchedulerDrawer'
import { useSettings } from '../../hooks/use-settings'

const buildApiUrl = (params) => {
  const query = new URLSearchParams(params).toString()
  return query ? `/api/ListScheduledItems?${query}` : '/api/ListScheduledItems'
}

/**
 * Shared scheduled task table used by every scheduler tab. The tabs differ only in which tasks they
 * ask the API for and which columns matter, so the table, actions, off-canvas and edit/clone drawers
 * are defined once here rather than repeated per tab.
 */
export const SchedulerTable = ({
  title,
  apiParams = {},
  queryKeyPrefix,
  simpleColumns,
  filters,
  showSystemJobsToggle = false,
  showAddTask = false,
  cardActions = null,
}) => {
  const [editTaskId, setEditTaskId] = useState(null)
  const [cloneTaskId, setCloneTaskId] = useState(null)
  const [showHiddenJobs, setShowHiddenJobs] = useState(false)
  const currentTenant = useSettings().currentTenant

  const drawerHandlers = {
    openEditDrawer: (row) => setEditTaskId(row.RowKey),
    openCloneDrawer: (row) => setCloneTaskId(row.RowKey),
  }

  const actions = CippScheduledTaskActions(drawerHandlers)

  const params = { ...apiParams }
  if (showSystemJobsToggle && showHiddenJobs) {
    params.ShowHidden = true
  }

  const offCanvas = {
    children: (extendedData) => (
      <ScheduledTaskDetails data={extendedData} showActions={true} showTitle={false} />
    ),
    size: 'xl',
    actions: actions,
  }

  const cardButton =
    showSystemJobsToggle || showAddTask || cardActions ? (
      <>
        {showSystemJobsToggle && (
          <Button onClick={() => setShowHiddenJobs((prev) => !prev)}>
            {showHiddenJobs ? 'Hide' : 'Show'} System Jobs
          </Button>
        )}
        {showAddTask && <CippSchedulerDrawer buttonText="Add Task" />}
        {cardActions}
      </>
    ) : undefined

  return (
    <>
      <CippTablePage
        cardButton={cardButton}
        title={title}
        apiUrl={buildApiUrl(params)}
        queryKey={`${queryKeyPrefix}${showHiddenJobs ? '-hidden' : ''}-${currentTenant}`}
        simpleColumns={simpleColumns}
        actions={actions}
        offCanvas={offCanvas}
        filters={filters}
      />

      {/* Edit Drawer */}
      {editTaskId && (
        <CippSchedulerDrawer
          key={`edit-${editTaskId}`}
          taskId={editTaskId}
          onSuccess={() => setEditTaskId(null)}
          onClose={() => setEditTaskId(null)}
          PermissionButton={({ children }) => <>{children}</>}
        />
      )}

      {/* Clone Drawer */}
      {cloneTaskId && (
        <CippSchedulerDrawer
          key={`clone-${cloneTaskId}`}
          taskId={cloneTaskId}
          cloneMode={true}
          onSuccess={() => setCloneTaskId(null)}
          onClose={() => setCloneTaskId(null)}
          PermissionButton={({ children }) => <>{children}</>}
        />
      )}
    </>
  )
}

export default SchedulerTable
