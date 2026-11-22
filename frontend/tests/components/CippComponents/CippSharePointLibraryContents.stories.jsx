import React from 'react'
import { http, HttpResponse } from 'msw'
import { fn, within, expect, userEvent } from 'storybook/test'
import { CippSharePointLibraryContents } from '../../../src/components/CippComponents/CippSharePointLibraryContents'

const GB = 1024 ** 3

const item = (id, name, type, sizeGb, folderPath, extra = {}) => ({
  id,
  driveId: 'b!drive',
  name,
  type,
  folderPath,
  sizeInBytes: Math.round(sizeGb * GB),
  itemCount: null,
  archiveStatus: type === 'File' ? 'active' : null,
  lastModifiedDateTime: '2025-03-14T10:22:00Z',
  lastModifiedBy: 'Megan Bowen',
  webUrl: `https://contoso.sharepoint.com/sites/projects/Shared%20Documents/${encodeURIComponent(name)}`,
  ...extra,
})

const root = [
  item('F-video', 'Video Archive', 'Folder', 612.4, '/', { itemCount: 48 }),
  item('F-design', 'Design Masters', 'Folder', 301.7, '/', { itemCount: 1204 }),
  item('F-admin', 'Admin', 'Folder', 2.1, '/', { itemCount: 87 }),
  item('A-brief', 'Client brief.docx', 'File', 0.0004, '/'),
  item('A-rates', 'Rate card 2019.xlsx', 'File', 0.00002, '/', {
    archiveStatus: 'archived',
  }),
]

const videoArchive = [
  item('A-keynote', 'Keynote master.mov', 'File', 188.2, '/Video Archive'),
  item(
    'A-raw',
    'Launch event raw footage.mxf',
    'File',
    142.9,
    '/Video Archive'
  ),
  item('F-2021', '2021 campaigns', 'Folder', 201.3, '/Video Archive', {
    itemCount: 31,
  }),
  item('A-teaser', 'Teaser v3.mp4', 'File', 4.6, '/Video Archive', {
    archiveStatus: 'reactivating',
  }),
]

const largest = [
  item('A-keynote', 'Keynote master.mov', 'File', 188.2, '/Video Archive'),
  item(
    'A-raw',
    'Launch event raw footage.mxf',
    'File',
    142.9,
    '/Video Archive'
  ),
  item('A-psd', 'Forecourt wrap.psb', 'File', 61.5, '/Design Masters/Print'),
  item(
    'F-deep',
    'Renders',
    'Folder',
    96.8,
    '/Video Archive/2021 campaigns/Q4',
    { itemCount: 640 }
  ),
]

export default {
  title: 'Components/CippSharePointLibraryContents',
  component: CippSharePointLibraryContents,
  parameters: {
    layout: 'fullscreen',
    msw: {
      handlers: [
        http.get('/api/ListSiteLibraryContents', ({ request }) => {
          const params = new URL(request.url).searchParams
          if (params.get('LargestFiles') === 'true')
            return HttpResponse.json(largest)
          if (params.get('FolderId') === 'F-video')
            return HttpResponse.json(videoArchive)
          return HttpResponse.json(root)
        }),
      ],
    },
  },
  args: {
    open: true,
    onClose: fn(),
    tenantFilter: 'testdomain.com',
    library: {
      id: '11111111-2222-3333-4444-555555555555',
      siteId: 'contoso.sharepoint.com,site,web',
      displayName: 'Documents',
      storageUsedInBytes: Math.round(1002.65 * GB),
    },
  },
}

export const LargestFoldersFirst = {
  play: async ({ canvasElement, step }) => {
    const body = within(canvasElement.ownerDocument.body)
    await step('lists folders and files with readable sizes', async () => {
      await expect(await body.findByText('Video Archive')).toBeVisible()
      await expect(body.getByText('612.40 GB')).toBeVisible()
      await expect(body.getByText('Archived')).toBeVisible()
    })
    await step('opens a folder from its row', async () => {
      await userEvent.click(body.getByText('Video Archive'))
      await expect(await body.findByText('Keynote master.mov')).toBeVisible()
      await expect(body.getByText('188.20 GB')).toBeVisible()
    })
  },
}

export const LargestFiles = {
  play: async ({ canvasElement, step }) => {
    const body = within(canvasElement.ownerDocument.body)
    await step(
      'switches to the largest files and flags folders still to search',
      async () => {
        await userEvent.click(
          await body.findByRole('button', { name: 'Largest files' })
        )
        await expect(await body.findByText('Forecourt wrap.psb')).toBeVisible()
        await expect(body.getByText(/have not been searched yet/)).toBeVisible()
      }
    )
  },
}
