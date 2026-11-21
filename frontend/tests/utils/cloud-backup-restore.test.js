import { describe, it, expect } from 'vitest'
import {
  cloudBackupCanRestore,
  cloudBackupDownloadFileName,
  cloudBackupExportAvailable,
  cloudBackupItemTypes,
  cloudBackupJobCounts,
  cloudBackupJobResults,
  cloudBackupJobSummary,
  cloudBackupOwnerLabel,
  cloudBackupRecoveryPoints,
  cloudBackupRestoreCount,
  cloudBackupSelectionSummary,
  formatCloudBackupSelection,
  parseCloudBackupListing,
  toCloudBackupItemRow,
} from '../../src/utils/cloud-backup'

describe('Cloud Backup browse helpers', () => {
  it('labels owners, flagging leavers and exclusions', () => {
    expect(
      cloudBackupOwnerLabel({
        DisplayName: 'Adele Vance',
        UserPrincipalName: 'adele@contoso.com',
      })
    ).toBe('Adele Vance (adele@contoso.com)')
    expect(
      cloudBackupOwnerLabel({
        DisplayName: 'Sales',
        SiteUrl: 'https://contoso.sharepoint.com/sites/sales',
        Removed: true,
        RemovedReason: 'Excluded',
      })
    ).toBe(
      'Sales (https://contoso.sharepoint.com/sites/sales), excluded from the policy'
    )
    expect(cloudBackupOwnerLabel({ OwnerId: 'u-1', Removed: true })).toBe(
      'u-1, removed from the tenant'
    )
  })

  it('reads recovery points and listings as objects or JSON', () => {
    expect(
      cloudBackupRecoveryPoints('[{"RunStamp":"20261119T020000Z"}]')
    ).toEqual([{ label: '20261119T020000Z', value: '20261119T020000Z' }])
    expect(
      parseCloudBackupListing(
        '{"Total":3,"Items":[{"Key":"a"}],"Folders":"[{\\"Name\\":\\"Inbox\\"}]"}'
      )
    ).toEqual({
      RunStamp: undefined,
      Total: 3,
      Items: [{ Key: 'a' }],
      Folders: [{ Name: 'Inbox' }],
    })
    expect(parseCloudBackupListing(undefined).Items).toEqual([])
  })

  it('builds item rows from the index fields', () => {
    expect(
      toCloudBackupItemRow({
        Key: 'k',
        Path: '',
        Name: '',
        Type: 'chatMessage',
        Extra: { subject: 'Hello', from: 'a@b.com' },
      })
    ).toMatchObject({
      CloudBackupItemName: 'Hello',
      CloudBackupItemType: 'Chat message',
      CloudBackupItemFolder: '/',
      CloudBackupFrom: 'a@b.com',
    })
  })

  it('knows which services restore and their item types', () => {
    expect(cloudBackupCanRestore('teams')).toBe(false)
    expect(cloudBackupCanRestore('Exchange')).toBe(true)
    expect(cloudBackupItemTypes('onedrive')).toEqual([
      { label: 'File', value: 'file' },
    ])
  })

  it('turns the selection into keys, paths or the open folder', () => {
    expect(
      formatCloudBackupSelection({ keys: [], paths: [], path: '' })
    ).toEqual({})
    expect(
      formatCloudBackupSelection({ keys: [], paths: [], path: 'Inbox' })
    ).toEqual({ Paths: ['Inbox'] })
    expect(
      formatCloudBackupSelection({ keys: ['a'], paths: [], path: 'Inbox' })
    ).toEqual({ Keys: ['a'] })
    expect(
      cloudBackupSelectionSummary({ keys: ['a', 'b'], paths: ['x'], path: '' })
    ).toBe('2 items and 1 folder')
    expect(cloudBackupSelectionSummary({ keys: [], paths: [], path: '' })).toBe(
      'everything in this backup'
    )
  })
})

describe('Cloud Backup job helpers', () => {
  it('reads results as an array, JSON or a truncated page', () => {
    expect(cloudBackupJobResults('[{"Key":"a"}]')).toEqual({
      rows: [{ Key: 'a' }],
      total: 1,
    })
    expect(
      cloudBackupJobResults({ Items: [{ Key: 'a' }], Total: 900 })
    ).toEqual({ rows: [{ Key: 'a' }], total: 900 })
    expect(cloudBackupJobResults(null)).toEqual({ rows: [], total: 0 })
  })

  it('counts from the summary, or from the results when it is missing', () => {
    const preview = {
      Type: 'RestorePreview',
      Result: [{ Action: 'Create' }, { Action: 'Copy' }, { Action: 'Skip' }],
    }
    expect(cloudBackupJobCounts(preview)).toEqual({
      Create: 1,
      Copy: 1,
      Skip: 1,
    })
    expect(cloudBackupRestoreCount(cloudBackupJobCounts(preview))).toBe(2)
    expect(cloudBackupJobSummary(preview)).toBe(
      '1 to restore, 1 to restore as copies, 1 already exist'
    )
    expect(
      cloudBackupJobSummary({
        Type: 'Restore',
        Summary: '{"Succeeded":3,"Skipped":2}',
      })
    ).toBe('3 restored, 2 skipped')
    expect(
      cloudBackupJobSummary({ Type: 'Export', Summary: { Items: 1 } })
    ).toBe('1 item exported')
    expect(cloudBackupJobSummary({ Type: 'Restore' })).toBe('Nothing to do')
  })

  it('offers export downloads only while they exist', () => {
    const now = Date.parse('2026-11-20T00:00:00Z')
    const job = {
      Type: 'Export',
      Status: 'Completed',
      ExpiresAt: '2026-11-25T00:00:00Z',
    }
    expect(cloudBackupExportAvailable(job, now)).toBe(true)
    expect(
      cloudBackupExportAvailable(
        { ...job, ExpiresAt: '2026-11-19T00:00:00Z' },
        now
      )
    ).toBe(false)
    expect(
      cloudBackupExportAvailable({ ...job, DownloadAvailable: false }, now)
    ).toBe(false)
    expect(cloudBackupExportAvailable({ ...job, Status: 'Running' }, now)).toBe(
      false
    )
  })

  it('reads the download file name from the response', () => {
    expect(
      cloudBackupDownloadFileName('attachment; filename="a b.eml"', 'x')
    ).toBe('a b.eml')
    expect(
      cloudBackupDownloadFileName(
        'attachment; filename="fallback.zip"; filename*=UTF-8\'\'r%C3%A9sum%C3%A9.zip',
        'x'
      )
    ).toBe('résumé.zip')
    expect(cloudBackupDownloadFileName(null, 'item')).toBe('item')
  })
})
