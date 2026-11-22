import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { act, fireEvent, screen } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { api, getResult } from '../../mocks/api-call'
import { CippSharePointLibraryContents } from '../../../src/components/CippComponents/CippSharePointLibraryContents'

let table
let requests
vi.mock('../../../src/api/ApiCall', async () =>
  (await import('../../mocks/api-call')).apiCallMock()
)
vi.mock('../../../src/hooks/use-permissions', () => ({
  usePermissions: () => ({ checkPermissions: () => true }),
}))
vi.mock('../../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    table = props
    return null
  },
}))

const library = {
  id: '11111111-2222-3333-4444-555555555555',
  siteId: 'contoso.sharepoint.com,site,web',
  displayName: 'Documents',
  storageUsedInBytes: 1000,
}

const folderResult = getResult({
  data: [
    {
      id: 'F1',
      driveId: 'drive-1',
      name: 'Video Archive',
      type: 'Folder',
      sizeInBytes: 800,
    },
    {
      id: 'A1',
      driveId: 'drive-1',
      name: 'live.mp4',
      type: 'File',
      sizeInBytes: 150,
      archiveStatus: 'active',
    },
    {
      id: 'A2',
      driveId: 'drive-1',
      name: 'cold.mp4',
      type: 'File',
      sizeInBytes: 50,
      archiveStatus: 'archived',
    },
  ],
})

const renderDialog = (props = {}) =>
  renderWithProviders(
    <CippSharePointLibraryContents
      open={true}
      onClose={() => {}}
      library={library}
      tenantFilter="contoso.onmicrosoft.com"
      {...props}
    />
  )

const lastRequest = () => requests[requests.length - 1]
const action = (label) => table.actions.find((item) => item.label === label)

describe('CippSharePointLibraryContents', () => {
  beforeEach(() => {
    requests = []
    api.get = (opts) => {
      requests.push(opts)
      return folderResult
    }
  })

  it('lists the top of the library, largest first, with each item as a share of the library', () => {
    renderDialog()

    expect(lastRequest().url).toBe('/api/ListSiteLibraryContents')
    expect(lastRequest().data).toEqual({
      tenantFilter: 'contoso.onmicrosoft.com',
      SiteId: library.siteId,
      ListId: library.id,
    })
    expect(lastRequest().queryKey).toContain('contoso.onmicrosoft.com')
    expect(table.defaultSorting).toEqual([{ id: 'sizeInBytes', desc: true }])
    expect(table.data.map((row) => row.percentOfLibrary)).toEqual([80, 15, 5])
    expect(table.data.map((row) => row.archiveStatus)).toEqual([
      undefined,
      'active',
      'archived',
    ])
  })

  it('addresses the site by URL for a library row that has no site id', () => {
    renderDialog({
      library: {
        ...library,
        siteId: undefined,
        siteUrl: 'https://contoso.sharepoint.com/sites/x',
      },
    })

    expect(lastRequest().data.SiteUrl).toBe(
      'https://contoso.sharepoint.com/sites/x'
    )
    expect(lastRequest().data.SiteId).toBeUndefined()
  })

  it('opens a folder from its name and goes back up from the path', () => {
    renderDialog()
    const [folder, file] = table.data

    expect(table.cellRenderers.name(file, 'plain cell')).toBe('plain cell')
    expect(action('Open folder').condition(folder)).toBe(true)
    expect(action('Open folder').condition(file)).toBe(false)
    act(() => table.cellRenderers.name(folder, 'plain cell').props.onClick())

    expect(lastRequest().data.FolderId).toBe('F1')
    expect(table.title).toBe('Video Archive')

    fireEvent.click(screen.getByRole('button', { name: 'Documents' }))

    expect(lastRequest().data.FolderId).toBeUndefined()
    expect(table.title).toBe('Documents')
  })

  it('searches for the largest files below the current folder', () => {
    renderDialog()
    act(() => action('Open folder').customFunction(table.data[0]))

    fireEvent.click(screen.getByRole('button', { name: 'Largest files' }))

    expect(lastRequest().data).toMatchObject({
      FolderId: 'F1',
      LargestFiles: true,
    })
    expect(table.simpleColumns).toContain('folderPath')
    expect(screen.getByText(/have not been searched yet/)).toBeTruthy()
  })

  it('offers Archive for active files and Reactivate for archived ones', () => {
    renderDialog()
    const [folder, active, archived] = table.data

    expect(action('Archive').condition(active)).toBe(true)
    expect(action('Archive').condition(archived)).toBe(false)
    expect(action('Reactivate').condition(active)).toBe(false)
    expect(action('Reactivate').condition(archived)).toBe(true)
    expect(action('Archive').condition(folder)).toBe(true)
    expect(action('Reactivate').condition(folder)).toBe(true)
    expect(action('Archive').data).toMatchObject({
      DriveId: 'driveId',
      ItemId: 'id',
      IsFolder: 'isFolder',
      Action: '!Archive',
    })
    expect(action('Reactivate').data.Action).toBe('!Reactivate')
    expect(folder.isFolder).toBe(true)
    expect(active.isFolder).toBe(false)
  })

  it('offers no Archive anywhere in the Site Assets library', () => {
    renderDialog({ library: { ...library, displayName: 'Site Assets' } })
    const [folder, active] = table.data

    expect(action('Archive').condition(folder)).toBe(false)
    expect(action('Archive').condition(active)).toBe(false)
  })

  it('gives each row the site address and library name the archive rule reads', () => {
    const siteUrl = 'https://contoso.sharepoint.com/sites/projects'
    api.get = () =>
      getResult({
        data: [
          {
            id: 'S1',
            driveId: 'drive-2',
            name: 'Notebook.zip',
            type: 'File',
            sizeInBytes: 10,
            archiveStatus: 'active',
            webUrl: `${siteUrl}/SiteAssets/Notebook.zip`,
          },
        ],
      })
    renderDialog({ library: { ...library, displayName: 'Assets', siteUrl } })
    const [row] = table.data

    expect(row).toMatchObject({ siteUrl, libraryName: 'Assets' })
    expect(action('Archive').condition(row)).toBe(false)
  })

  it('skips the server cache after an archive action so the new status shows', () => {
    renderDialog()
    expect(lastRequest().data.InvalidateCIPPCache).toBeUndefined()

    act(() => action('Archive').onSuccess())

    expect(lastRequest().data.InvalidateCIPPCache).toBe(true)
  })
})
