import React from 'react'
import { Stack } from '@mui/material'
import { within, expect } from 'storybook/test'
import { CippSharePointLargeFiles } from '../../../src/components/CippComponents/CippSharePointLargeFiles'
import { CippSharePointArchiveReadiness } from '../../../src/components/CippComponents/CippSharePointArchiveReadiness'

const GB = 1024 ** 3
const monthsAgo = (months) => {
  const date = new Date()
  date.setMonth(date.getMonth() - months)
  return date.toISOString()
}

const file = (
  itemId,
  name,
  folderPath,
  sizeGb,
  months,
  archiveStatus = 'active'
) => ({
  rowType: 'File',
  id: `b!drive_${itemId}`,
  itemId,
  driveId: 'b!drive',
  siteName: 'Projects & Assets',
  siteUrl: 'https://contoso.sharepoint.com/sites/projects',
  libraryName: 'Documents',
  name,
  folderPath,
  sizeInBytes: Math.round(sizeGb * GB),
  archiveStatus,
  lastModifiedDateTime: monthsAgo(months),
  lastModifiedBy: 'Megan Bowen',
  webUrl: `https://contoso.sharepoint.com/sites/projects/Shared%20Documents/${encodeURIComponent(name)}`,
  collectedAt: new Date().toISOString(),
})

const files = {
  isFetching: false,
  isError: false,
  refetch: () => {},
  data: [
    file('1', 'Keynote master.mov', '/Video Archive', 188.2, 30),
    file('2', 'Launch event raw footage.mxf', '/Video Archive', 142.9, 26),
    file('3', 'Forecourt wrap.psb', '/Design Masters/Print', 61.5, 18),
    file('4', 'Campaign edit v12.prproj', '/Current', 22.4, 1),
    file('5', 'Teaser v3.mp4', '/Video Archive', 20, 40, 'archived'),
  ],
}

const settings = {
  archiveEnabled: true,
  allowFileArchive: true,
  allowFileArchiveOnNewSites: true,
  archivedFileStorageInBytes: 20 * GB,
  storageQuotaInBytes: 2160 * GB,
}

export default {
  title: 'Components/CippSharePointLargeFiles',
  component: CippSharePointLargeFiles,
  parameters: { layout: 'padded' },
}

export const ArchiveCandidates = {
  render: () => (
    <Stack spacing={1}>
      <CippSharePointArchiveReadiness settings={settings} sitesBlocked={2} />
      <CippSharePointLargeFiles
        files={files}
        queryKey="ListStorageLargeFiles-testdomain.com"
        archiveSettings={settings}
        activeBytes={2150 * GB}
      />
    </Stack>
  ),
  play: async ({ canvasElement, step }) => {
    const canvas = within(canvasElement)
    await step(
      'says the tenant can archive and how long content takes to come back',
      async () => {
        await expect(
          await canvas.findByText('Microsoft 365 Archive is turned on')
        ).toBeVisible()
        await expect(
          canvas.getAllByText(/up to 24 hours/).length
        ).toBeGreaterThan(0)
      }
    )
    await step('counts the archive candidates and prices them', async () => {
      await expect(
        canvas.getByText(/3 files have not changed in 12 months/)
      ).toBeVisible()
      await expect(canvas.getByText(/78\.52 a month/)).toBeVisible()
      await expect(await canvas.findByText('Keynote master.mov')).toBeVisible()
    })
  },
}

export const ArchiveNotTurnedOn = {
  render: () => (
    <CippSharePointArchiveReadiness
      settings={{
        ...settings,
        archiveEnabled: false,
        archivedFileStorageInBytes: 0,
      }}
    />
  ),
}

export const IncompleteSearchAndUnarchivableFiles = {
  render: () => (
    <CippSharePointLargeFiles
      files={{
        ...files,
        data: [
          {
            ...file('6', 'Board minutes.one', '/Notebooks', 12.4, 30),
            searchComplete: false,
          },
          { ...file('7', 'Home.aspx', '/', 9.1, 30), searchComplete: false },
          ...files.data.map((row) => ({ ...row, searchComplete: true })),
        ],
      }}
      queryKey="ListStorageLargeFiles-testdomain.com"
      archiveSettings={settings}
    />
  ),
  play: async ({ canvasElement, step }) => {
    const canvas = within(canvasElement)
    await step('says some folders were not searched', async () => {
      await expect(
        canvas.getByText(/not every folder in them was searched/)
      ).toBeVisible()
    })
    await step(
      'leaves OneNote files and pages out of the candidates and gives only the most it could cost',
      async () => {
        await expect(
          canvas.getByText(/3 files have not changed in 12 months/)
        ).toBeVisible()
        await expect(canvas.getByText(/would cost at most/)).toBeVisible()
      }
    )
  },
}

export const SettingsNotCollected = {
  render: () => (
    <CippSharePointArchiveReadiness
      settings={null}
      error={{
        response: {
          status: 404,
          data: {
            Results:
              'No SharePoint configuration is stored for this tenant yet. It is collected with the nightly tenant data, or run the SPOTenant cache from the CIPP data cache settings.',
          },
        },
      }}
    />
  ),
}
