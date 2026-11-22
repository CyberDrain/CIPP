import React from 'react'
import { describe, it, expect, vi } from 'vitest'
import { fireEvent, screen } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { getResult } from '../../mocks/api-call'
import { CippSharePointLargeFiles } from '../../../src/components/CippComponents/CippSharePointLargeFiles'
import { CippSharePointArchiveReadiness } from '../../../src/components/CippComponents/CippSharePointArchiveReadiness'

let table
vi.mock('../../../src/hooks/use-permissions', () => ({
  usePermissions: () => ({ checkPermissions: () => true }),
}))
vi.mock('../../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    table = props
    return null
  },
}))

const GB = 1024 ** 3
const files = getResult({
  data: [
    {
      id: 'b!d_1',
      itemId: '1',
      driveId: 'b!d',
      name: 'Keynote master.mov',
      siteName: 'Projects',
      libraryName: 'Documents',
      folderPath: '/Video Archive',
      sizeInBytes: 100 * GB,
      archiveStatus: 'active',
      lastModifiedDateTime: '2020-01-01T00:00:00Z',
      collectedAt: '2026-11-22T09:00:00Z',
    },
    {
      id: 'b!d_2',
      itemId: '2',
      driveId: 'b!d',
      name: 'Current edit.mov',
      siteName: 'Projects',
      libraryName: 'Documents',
      folderPath: '/',
      sizeInBytes: 50 * GB,
      archiveStatus: 'active',
      lastModifiedDateTime: new Date().toISOString(),
      collectedAt: '2026-11-22T09:00:00Z',
    },
    {
      id: 'b!d_3',
      itemId: '3',
      driveId: 'b!d',
      name: 'Already cold.mov',
      siteName: 'Projects',
      libraryName: 'Documents',
      folderPath: '/Video Archive',
      sizeInBytes: 20 * GB,
      archiveStatus: 'archived',
      lastModifiedDateTime: '2020-01-01T00:00:00Z',
      collectedAt: '2026-11-22T09:00:00Z',
    },
  ],
})

describe('CippSharePointLargeFiles', () => {
  it('marks the dormant active files as archive candidates and says what archiving saves', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
        archiveSettings={{
          archivedFileStorageInBytes: 0,
          storageQuotaInBytes: 2000 * GB,
        }}
        activeBytes={2000 * GB}
      />
    )

    expect(table.data.map((row) => row.archiveCandidate)).toEqual([
      'Yes',
      'No',
      'No',
    ])
    expect(table.data.map((row) => row.archiveStatus)).toEqual([
      'active',
      'active',
      'archived',
    ])
    expect(table.defaultSorting).toEqual([{ id: 'sizeInBytes', desc: true }])
    expect(screen.getByText(/1 file has not changed in 12 months/)).toBeTruthy()
    expect(
      screen.getByText(/would free 100 GB of SharePoint storage/)
    ).toBeTruthy()
    expect(
      screen.getByText(
        /When CIPP last collected its storage figures, this tenant was within its storage quota/
      )
    ).toBeTruthy()
    expect(
      screen.getByText(
        /storage figures CIPP last collected for the tenant, not a live reading/
      )
    ).toBeTruthy()
    expect(screen.queryByText(/current/i)).toBeNull()
    expect(screen.getByText(/20\.00 a month/)).toBeTruthy()
    expect(screen.getAllByText(/up to 24 hours/).length).toBeGreaterThan(0)
  })

  it('archives by the scanned item id, not the row id', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )
    const archive = table.actions.find((action) => action.label === 'Archive')

    expect(archive.data.ItemId).toBe('itemId')
    expect(archive.condition(table.data[0])).toBe(true)
    expect(archive.condition(table.data[2])).toBe(false)
  })

  it('filters archived files on the label the column shows', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )
    const archived = table.filters.find((f) => f.filterName === 'Archived')

    expect(archived.value).toEqual([
      { id: 'archiveStatus', value: 'Archived', filterFn: 'equals' },
    ])
  })

  it('leaves OneNote files, pages and Site Assets out of the candidates', () => {
    const old = '2020-01-01T00:00:00Z'
    renderWithProviders(
      <CippSharePointLargeFiles
        files={getResult({
          data: [
            {
              itemId: '1',
              name: 'Minutes.one',
              libraryName: 'Documents',
              archiveStatus: 'active',
              sizeInBytes: 5 * GB,
              lastModifiedDateTime: old,
            },
            {
              itemId: '2',
              name: 'Home.aspx',
              libraryName: 'Site Pages',
              archiveStatus: 'active',
              sizeInBytes: 5 * GB,
              lastModifiedDateTime: old,
            },
            {
              itemId: '3',
              name: 'hero.png',
              libraryName: 'Site Assets',
              archiveStatus: 'active',
              sizeInBytes: 5 * GB,
              lastModifiedDateTime: old,
            },
            {
              itemId: '4',
              name: 'Keynote.mov',
              libraryName: 'Documents',
              archiveStatus: 'active',
              sizeInBytes: 5 * GB,
              lastModifiedDateTime: old,
            },
          ],
        })}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )

    expect(table.data.map((row) => row.archiveCandidate)).toEqual([
      'No',
      'No',
      'No',
      'Yes',
    ])
    const archive = table.actions.find((action) => action.label === 'Archive')
    expect(table.data.map((row) => archive.condition(row))).toEqual([
      false,
      false,
      false,
      true,
    ])
    expect(screen.getByText(/1 file has not changed in 12 months/)).toBeTruthy()
  })

  it('does not blame recent changes when the old files are already archived', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={getResult({ data: [files.data[2]] })}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )

    expect(
      screen.getByText(
        'No eligible active files last changed more than 12 months ago were found.'
      )
    ).toBeTruthy()
    expect(screen.queryByText(/without a change/)).toBeNull()
  })

  it('gives only the most archiving could cost without the stored SharePoint pool usage', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
        archiveSettings={{
          archivedFileStorageInBytes: 0,
          storageQuotaInBytes: 2000 * GB,
        }}
      />
    )

    expect(screen.getByText(/would cost at most 5\.00 a month/)).toBeTruthy()
    expect(screen.queryByText(/CIPP last collected for the tenant/)).toBeNull()
    expect(screen.queryByText(/within its storage quota, so/)).toBeNull()
    expect(
      screen.getByText(/defaults are Microsoft's US list prices/)
    ).toBeTruthy()
  })

  it('takes its prices from the page and reports edits back to it', () => {
    const onPricesChange = vi.fn()
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
        prices={{ archiveRate: 0.04, storageRate: 0.16 }}
        onPricesChange={onPricesChange}
      />
    )

    expect(screen.getByText(/would cost at most 4\.00 a month/)).toBeTruthy()
    fireEvent.change(screen.getByLabelText('Archive price per GB a month'), {
      target: { value: '0.03' },
    })
    expect(onPricesChange).toHaveBeenCalledWith({
      archiveRate: '0.03',
      storageRate: 0.16,
    })
  })

  it('says when some folders were not searched', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={getResult({
          data: [
            { ...files.data[0], searchComplete: true },
            { ...files.data[1], searchComplete: false },
          ],
        })}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )

    expect(
      screen.getByText(/not every folder in them was searched/)
    ).toBeTruthy()
  })

  it('shows no search note when every site was searched', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={getResult({
          data: [{ ...files.data[0], searchComplete: true }],
        })}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )

    expect(
      screen.queryByText(/not every folder in them was searched/)
    ).toBeNull()
  })

  it('promises only up to 25 of the largest files found in each site', () => {
    renderWithProviders(
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-contoso"
      />
    )

    expect(
      screen.getByText(/up to 25 of the largest files found in each site/)
    ).toBeTruthy()
    expect(screen.queryByText(/the 25 largest files/)).toBeNull()
  })

  const notFound = (overrides = {}) =>
    getResult({
      isError: true,
      isSuccess: false,
      error: { response: { status: 404 } },
      ...overrides,
    })

  // The fixture rows were collected at 09:00.
  const BEFORE_ROWS = Date.parse('2026-11-22T08:00:00Z')
  const AFTER_ROWS = Date.parse('2026-11-22T10:00:00Z')
  const ended = (endState, listedAt = AFTER_ROWS) => ({
    listedAt,
    queueId: 'queue-1',
    endState,
    endedAt: listedAt + 1000,
  })
  const renderScan = (scanFiles, scan) =>
    renderWithProviders(
      <CippSharePointLargeFiles
        files={scanFiles}
        queryKey="ListStorageLargeFiles-contoso"
        scan={scan}
      />
    )

  it('does not call retained files old when the list could not be read again', () => {
    renderScan(
      getResult({
        data: files.data,
        isError: true,
        isSuccess: false,
        error: { response: { status: 500 } },
      }),
      ended('Completed')
    )

    expect(screen.queryByText(/did not store new results/)).toBeNull()
  })

  it('says the first scan is running instead of asking for one', () => {
    renderScan(notFound(), { listedAt: AFTER_ROWS, queueId: 'queue-1' })

    expect(screen.getByText(/The large file scan has started/)).toBeTruthy()
    expect(
      screen.getByText(/progress shows next to Scan large files/)
    ).toBeTruthy()
    expect(screen.queryByText(/No large file scan has run/)).toBeNull()
  })

  it('keeps saying the scan is running while the list is read again after it ends', () => {
    renderScan(notFound({ isFetching: true, errorUpdatedAt: 1000 }), {
      listedAt: 500,
      queueId: 'queue-1',
      endState: 'Completed',
      endedAt: 2000,
    })

    expect(screen.getByText(/The large file scan has started/)).toBeTruthy()
  })

  it('does not say the scan has started again on a later Refresh', () => {
    renderScan(getResult({ data: [], isFetching: true, dataUpdatedAt: 3000 }), {
      listedAt: 500,
      queueId: 'queue-1',
      endState: 'Completed',
      endedAt: 2000,
    })

    expect(screen.queryByText(/The large file scan has started/)).toBeNull()
    expect(
      screen.getByText(
        /The large file scan finished and no large files were stored/
      )
    ).toBeTruthy()
  })

  it('shows nothing while a rescan runs over earlier results', () => {
    renderScan(files, { listedAt: AFTER_ROWS, queueId: 'queue-1' })

    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('gives a plain note when a completed scan found no large files', () => {
    renderScan(getResult({ data: [] }), ended('Completed'))

    const alert = screen.getByRole('alert')
    expect(alert.className).toMatch(/MuiAlert-colorInfo/)
    expect(alert.textContent).toBe(
      'The large file scan finished and no large files were stored. Only sites holding 1 GB or more are scanned. If you expected files here, the logbook has the detail.'
    )
  })

  it('warns when a failed scan leaves earlier files on screen and the list cannot be read', () => {
    renderScan(
      getResult({
        data: files.data,
        isError: true,
        isSuccess: false,
        error: { response: { status: 500 } },
      }),
      ended('Failed')
    )

    expect(screen.queryByText(/Some sites could not be read/)).toBeNull()
    expect(
      screen.getByText(
        /^The large file scan did not finish\. Check the logbook/
      )
    ).toBeTruthy()
  })

  it.each(['Failed', 'Completed (with errors)', 'Completed'])(
    'warns that a scan ending %s with nothing ever stored did not finish',
    (endState) => {
      renderScan(notFound(), ended(endState))

      const alert = screen.getByRole('alert')
      expect(alert.className).toMatch(/MuiAlert-colorWarning/)
      expect(alert.textContent).toMatch(
        /^The large file scan did not finish, so there are no files to show\. Check the logbook/
      )
    }
  )

  it.each(['Completed', 'Failed', 'Completed (with errors)'])(
    'says the files are from the previous scan when a scan ending %s stored nothing new',
    (endState) => {
      renderScan(files, ended(endState))

      expect(
        screen.getByText(
          /did not store new results, so the files listed are from the previous scan\. Check the logbook/
        )
      ).toBeTruthy()
    }
  )

  it('says nothing when a completed scan stored new files', () => {
    renderScan(files, ended('Completed', BEFORE_ROWS))

    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('says some sites could not be read when a scan with errors still stored new files', () => {
    renderScan(files, ended('Completed (with errors)', BEFORE_ROWS))

    expect(
      screen.getByText(/Some sites could not be read by the large file scan/)
    ).toBeTruthy()
    expect(screen.getByText(/Check the logbook/)).toBeTruthy()
    expect(
      screen.queryByText(/files listed are from the previous scan/)
    ).toBeNull()
  })

  it('says a scan was already running, in the past tense, without promising progress', () => {
    renderScan(notFound(), { listedAt: AFTER_ROWS, queueId: null })

    expect(
      screen.getByText(
        'A large file scan for this tenant was already running when you asked, so a second one was not started. Use Refresh to check for its results.'
      )
    ).toBeTruthy()
    expect(screen.queryByText(/progress shows next to/)).toBeNull()
    expect(screen.queryByText(/No large file scan has run/)).toBeNull()
  })

  it('keeps the already-running note while the files listed predate the request', () => {
    renderScan(files, { listedAt: AFTER_ROWS, queueId: null })

    expect(screen.getByText(/was already running when you asked/)).toBeTruthy()
  })

  it('drops the already-running note once the list holds files collected since the request', () => {
    renderScan(files, { listedAt: BEFORE_ROWS, queueId: null })

    expect(screen.queryByText(/was already running when you asked/)).toBeNull()
  })

  it('shows a list error and the scan warning together', () => {
    renderScan(
      getResult({
        isError: true,
        isSuccess: false,
        error: {
          response: { status: 500, data: { Results: 'Table read failed.' } },
        },
      }),
      ended('Failed')
    )

    expect(screen.getByText(/Table read failed\./)).toBeTruthy()
    expect(
      screen.getByText(
        /^The large file scan did not finish\. Check the logbook/
      )
    ).toBeTruthy()
  })

  it('asks for a scan when none has run', () => {
    renderScan(notFound())

    expect(
      screen.getByText(/No large file scan has run for this tenant yet/)
    ).toBeTruthy()
    expect(table.data).toEqual([])
  })
})

describe('CippSharePointArchiveReadiness', () => {
  it('renders nothing until the settings are known', () => {
    const { container } = renderWithProviders(
      <CippSharePointArchiveReadiness settings={null} />
    )
    expect(container.textContent).toBe('')
  })

  it('says the settings have not been collected when the endpoint has none', () => {
    renderWithProviders(
      <CippSharePointArchiveReadiness
        settings={null}
        error={{
          response: {
            status: 404,
            data: {
              Results:
                'No SharePoint configuration is stored for this tenant yet.',
            },
          },
        }}
      />
    )
    expect(
      screen.getByText(
        "This tenant's SharePoint settings have not been collected yet"
      )
    ).toBeTruthy()
    expect(
      screen.getByText(/No SharePoint configuration is stored/)
    ).toBeTruthy()
  })

  it('says the settings could not be read when the endpoint fails', () => {
    renderWithProviders(
      <CippSharePointArchiveReadiness
        settings={null}
        error={{
          response: { status: 500, data: { Results: 'Table read failed.' } },
        }}
      />
    )
    expect(
      screen.getByText("This tenant's SharePoint settings could not be read")
    ).toBeTruthy()
    expect(screen.getByText(/Table read failed\./)).toBeTruthy()
  })

  it('warns when Microsoft 365 Archive is not turned on', () => {
    renderWithProviders(
      <CippSharePointArchiveReadiness
        settings={{
          archiveEnabled: false,
          allowFileArchive: true,
          archivedFileStorageInBytes: 0,
        }}
      />
    )
    expect(
      screen.getByText('Microsoft 365 Archive does not appear to be turned on')
    ).toBeTruthy()
  })

  it('treats existing archive usage as proof that it is on', () => {
    renderWithProviders(
      <CippSharePointArchiveReadiness
        settings={{
          archiveEnabled: false,
          allowFileArchive: true,
          allowFileArchiveOnNewSites: true,
          archivedFileStorageInBytes: 0,
        }}
        hasArchiveUsage={true}
        sitesBlocked={2}
      />
    )
    expect(screen.getByText('Microsoft 365 Archive is turned on')).toBeTruthy()
    expect(screen.getByText(/2 sites do not allow file archiving/)).toBeTruthy()
    expect(screen.getByText(/up to 24 hours/)).toBeTruthy()
  })

  it('warns when file archiving is switched off for the tenant', () => {
    renderWithProviders(
      <CippSharePointArchiveReadiness
        settings={{
          archiveEnabled: true,
          allowFileArchive: false,
          archivedFileStorageInBytes: 0,
        }}
      />
    )
    expect(
      screen.getByText('File archiving is switched off for this tenant')
    ).toBeTruthy()
  })
})
