import { describe, it, expect } from 'vitest'
import {
  ARCHIVE_WAIT_NOTE,
  canBeArchived,
  estimateArchiveCost,
  getArchiveFileActions,
  isArchiveCandidate,
} from '../../src/utils/sharepoint-archive'
import { getCippFormatting } from '../../src/utils/get-cipp-formatting'

const GB = 1024 ** 3
const now = new Date('2026-11-22T00:00:00Z')

describe('isArchiveCandidate', () => {
  it.each([
    [
      'an active file last changed over a year ago',
      'active',
      '2024-01-01T00:00:00Z',
      true,
    ],
    [
      'an active file changed last month',
      'active',
      '2026-10-20T00:00:00Z',
      false,
    ],
    [
      'a file that is already archived',
      'archived',
      '2020-01-01T00:00:00Z',
      false,
    ],
    [
      'a file that is being reactivated',
      'reactivating',
      '2020-01-01T00:00:00Z',
      false,
    ],
    ['a file with no change date', 'active', null, false],
    [
      'a file whose status could not be read',
      'unknown',
      '2020-01-01T00:00:00Z',
      false,
    ],
  ])('%s', (_name, archiveStatus, lastModifiedDateTime, expected) => {
    expect(
      isArchiveCandidate({ archiveStatus, lastModifiedDateTime }, 12, now)
    ).toBe(expected)
  })

  it('compares the raw status, not the display label', () => {
    expect(
      isArchiveCandidate(
        {
          archiveStatus: 'Active',
          lastModifiedDateTime: '2020-01-01T00:00:00Z',
        },
        12,
        now
      )
    ).toBe(false)
  })

  it.each([
    ['a OneNote section', { name: 'Minutes.one' }],
    ['a OneNote table of contents', { name: 'Open Notebook.onetoc2' }],
    ['a SharePoint page', { name: 'Home.ASPX' }],
    ['a file in Site Assets', { name: 'logo.png', libraryName: 'Site Assets' }],
    [
      'a file whose address is in Site Assets',
      {
        name: 'Notebook.zip',
        siteUrl: 'https://contoso.sharepoint.com/sites/projects',
        webUrl:
          'https://contoso.sharepoint.com/sites/projects/SiteAssets/Notebook.zip',
      },
    ],
  ])('leaves out %s, which Microsoft 365 Archive cannot archive', (_n, row) => {
    expect(
      isArchiveCandidate(
        {
          archiveStatus: 'active',
          lastModifiedDateTime: '2020-01-01T00:00:00Z',
          ...row,
        },
        12,
        now
      )
    ).toBe(false)
  })
})

describe('canBeArchived', () => {
  it('allows an ordinary file and folder in a document library', () => {
    const webUrl =
      'https://contoso.sharepoint.com/sites/projects/Shared%20Documents/Video'
    expect(
      canBeArchived({ name: 'Keynote.mov', libraryName: 'Documents', webUrl })
    ).toBe(true)
    expect(canBeArchived({ name: 'Video', isFolder: true, webUrl })).toBe(true)
  })

  it('refuses a folder in Site Assets', () => {
    expect(
      canBeArchived({
        name: 'Notebooks',
        isFolder: true,
        siteUrl: 'https://contoso.sharepoint.com/sites/projects/',
        webUrl:
          'https://contoso.sharepoint.com/sites/projects/SiteAssets/Notebooks',
      })
    ).toBe(false)
  })

  const siteUrl = 'https://contoso.sharepoint.com/sites/projects'
  it.each([
    [
      'refuses a file in the real Site Assets library',
      {
        name: 'Project Notebook.zip',
        libraryName: 'Site Assets',
        siteUrl,
        webUrl: `${siteUrl}/SiteAssets/Project%20Notebook.zip`,
      },
      false,
    ],
    [
      'allows a file in a folder named SiteAssets inside Documents',
      {
        name: 'logo.png',
        libraryName: 'Documents',
        siteUrl,
        webUrl: `${siteUrl}/Shared%20Documents/SiteAssets/logo.png`,
      },
      true,
    ],
    [
      'refuses a file in a library titled site assets in lower case',
      {
        name: 'logo.png',
        libraryName: 'site assets',
        siteUrl,
        webUrl: `${siteUrl}/site%20assets/logo.png`,
      },
      false,
    ],
    [
      'refuses a file whose address is in Site Assets whatever the case',
      {
        name: 'logo.png',
        libraryName: 'Assets',
        siteUrl: `${siteUrl}/`,
        webUrl: 'https://CONTOSO.sharepoint.com/sites/Projects/siteassets/logo.png',
      },
      false,
    ],
    [
      'allows a file in another site whose address only contains SiteAssets',
      {
        name: 'logo.png',
        libraryName: 'Documents',
        siteUrl: `${siteUrl}/SiteAssets`,
        webUrl: `${siteUrl}/Shared%20Documents/logo.png`,
      },
      true,
    ],
  ])('%s', (_name, row, expected) => {
    expect(canBeArchived(row)).toBe(expected)
  })
})

describe('archive status display', () => {
  it.each([
    ['active', 'Active'],
    ['archived', 'Archived'],
    ['reactivating', 'Reactivating'],
    ['unknown', 'Unknown'],
  ])('shows %s as %s', (status, label) => {
    expect(getCippFormatting(status, 'archiveStatus', 'text')).toBe(label)
  })

  it.each([['Pending'], ['fullyArchived'], ['constructor'], [null], [true]])(
    'passes %s through as any other column would show it',
    (value) => {
      expect(getCippFormatting(value, 'archiveStatus', 'text')).toEqual(
        getCippFormatting(value, 'someOtherColumn', 'text')
      )
    }
  )

  it('shows an unrecognised value unchanged', () => {
    expect(getCippFormatting('Pending', 'archiveStatus', 'text')).toBe(
      'Pending'
    )
  })
})

describe('estimateArchiveCost', () => {
  it('charges nothing while active plus archived storage stays within the quota', () => {
    const result = estimateArchiveCost({
      candidateBytes: 500 * GB,
      activeBytes: 2000 * GB,
      archivedBytes: 0,
      quotaBytes: 2000 * GB,
    })
    expect(result.exact).toBe(true)
    expect(result.withinQuota).toBe(true)
    expect(result.archiveCost).toBe(0)
    expect(result.extraStorageCost).toBeCloseTo(100)
  })

  it('charges only the archived storage that is over the quota', () => {
    // 200 GB over quota: of the 500 GB archived, 200 GB is billed.
    const result = estimateArchiveCost({
      candidateBytes: 500 * GB,
      activeBytes: 2200 * GB,
      archivedBytes: 0,
      quotaBytes: 2000 * GB,
    })
    expect(result.withinQuota).toBe(false)
    expect(result.archiveCost).toBeCloseTo(10)
  })

  it('does not charge again for storage that is already archived and billed', () => {
    const result = estimateArchiveCost({
      candidateBytes: 100 * GB,
      activeBytes: 2000 * GB,
      archivedBytes: 300 * GB,
      quotaBytes: 2000 * GB,
    })
    // 300 GB over quota and 300 GB already archived: the overage is fully billed already.
    expect(result.archiveCost).toBe(0)
  })

  it('gives the most it could cost when the tenant figures are unknown', () => {
    const result = estimateArchiveCost({ candidateBytes: 100 * GB })
    expect(result.exact).toBe(false)
    expect(result.withinQuota).toBeNull()
    expect(result.archiveCost).toBeCloseTo(5)
    expect(result.extraStorageCost).toBeCloseTo(20)
  })

  it('uses the prices it is given', () => {
    const result = estimateArchiveCost({
      candidateBytes: 100 * GB,
      archiveRate: 0.04,
      storageRate: 0.16,
    })
    expect(result.archiveCost).toBeCloseTo(4)
    expect(result.extraStorageCost).toBeCloseTo(16)
  })
})

describe('getArchiveFileActions', () => {
  const [archive, reactivate] = getArchiveFileActions({
    canWrite: true,
    relatedQueryKeys: ['Files*'],
    itemIdField: 'itemId',
  })

  it('reads the item id from the field the table uses', () => {
    expect(archive.data).toMatchObject({
      DriveId: 'driveId',
      ItemId: 'itemId',
      Action: '!Archive',
    })
    expect(reactivate.data).toMatchObject({
      ItemId: 'itemId',
      Action: '!Reactivate',
    })
    expect(archive.relatedQueryKeys).toEqual(['Files*'])
  })

  it('warns in both confirmations that archived files take up to 24 hours to come back', () => {
    expect(archive.confirmText).toContain('up to 24 hours')
    expect(reactivate.confirmText).toContain('up to 24 hours')
    expect(ARCHIVE_WAIT_NOTE).toContain('up to 24 hours')
  })

  it('disables both actions without write access', () => {
    const [noArchive, noReactivate] = getArchiveFileActions({ canWrite: false })
    expect(noArchive.condition({ archiveStatus: 'active' })).toBe(false)
    expect(noReactivate.condition({ archiveStatus: 'archived' })).toBe(false)
  })

  it.each([
    ['active', true, false],
    ['archived', false, true],
    ['reactivating', false, false],
    ['unknown', false, false],
  ])(
    'for a %s file offers Archive %s and Reactivate %s',
    (archiveStatus, canArchive, canReactivate) => {
      const row = { name: 'Keynote.mov', isFolder: false, archiveStatus }
      expect(archive.condition(row)).toBe(canArchive)
      expect(reactivate.condition(row)).toBe(canReactivate)
    }
  )

  it('does not offer Archive for content Microsoft 365 Archive cannot archive', () => {
    expect(
      archive.condition({ name: 'Home.aspx', archiveStatus: 'active' })
    ).toBe(false)
    expect(
      archive.condition({
        name: 'Assets',
        isFolder: true,
        libraryName: 'Site Assets',
      })
    ).toBe(false)
  })

  it('says a folder archives only the eligible files inside it', () => {
    expect(archive.confirmText).toContain(
      'Archiving a folder archives the eligible files inside it'
    )
  })
})
