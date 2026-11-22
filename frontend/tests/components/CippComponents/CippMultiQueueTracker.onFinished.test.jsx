import React from 'react'
import { describe, it, expect, vi } from 'vitest'
import { renderWithProviders } from '../../test-utils'
import { api, getResult } from '../../mocks/api-call'
import { CippMultiQueueTracker } from '../../../src/components/CippComponents/CippMultiQueueTracker'

vi.mock('../../../src/api/ApiCall', async () =>
  (await import('../../mocks/api-call')).apiCallMock()
)
vi.mock('../../../src/hooks/use-craft-events', () => ({
  useCraftJobEvents: () => false,
}))

const queues = (status) =>
  getResult({
    data: {
      Queues: [
        { QueueId: 'queue-1', Name: 'StorageLargeFiles', Status: status },
      ],
      Summary: { Status: status, CompletedTasks: 1, TotalTasks: 1 },
    },
  })

describe('CippMultiQueueTracker onFinished', () => {
  it.each(['Completed', 'Failed', 'Completed (with errors)'])(
    'reports a run that ended %s once',
    (status) => {
      api.get = queues(status)
      const onFinished = vi.fn()
      renderWithProviders(
        <CippMultiQueueTracker
          queueIds={['queue-1']}
          label="Large file scan"
          onFinished={onFinished}
        />
      )

      expect(onFinished).toHaveBeenCalledTimes(1)
      expect(onFinished).toHaveBeenCalledWith(status, 'queue-1')
    }
  )

  it('says nothing while the run is still going', () => {
    api.get = queues('Running')
    const onFinished = vi.fn()
    renderWithProviders(
      <CippMultiQueueTracker queueIds={['queue-1']} onFinished={onFinished} />
    )

    expect(onFinished).not.toHaveBeenCalled()
  })
})
