import {
  getCippFormatting,
  isCippDateColumn,
} from '../../src/utils/get-cipp-formatting'
import { getCippTranslation } from '../../src/utils/get-cipp-translation'

describe('shared columns keep their formatting', () => {
  it('renders Status values Running and Succeeded as plain default chips', () => {
    for (const value of ['Running', 'Succeeded', 'PartialSuccess']) {
      expect(getCippFormatting(value, 'Status', 'text')).toBe(value)
      const chip = getCippFormatting(value, 'Status')
      expect(chip.props.label).toBe(value)
      expect(chip.props.color).toBe('default')
    }
  })

  it('leaves StartedAt, CompletedAt and Bytes values as they are', () => {
    const date = '2026-11-19T02:00:00Z'
    expect(getCippFormatting(date, 'StartedAt', 'text')).toBe(date)
    expect(getCippFormatting(date, 'StartedAt').props.children).toBe(date)
    expect(getCippFormatting(date, 'CompletedAt', 'text')).toBe(date)
    expect(isCippDateColumn('StartedAt')).toBe(false)
    expect(isCippDateColumn('CompletedAt')).toBe(false)
    expect(getCippFormatting(2621440, 'Bytes', 'text')).toBe('2621440')
    expect(getCippFormatting(1073741824, 'LatestBytes', 'text')).toBe(
      '1073741824'
    )
  })

  it('leaves the headers of shared keys untranslated', () => {
    expect(getCippTranslation('Bytes')).toBe('Bytes')
    expect(getCippTranslation('RetentionDays')).toBe('Retention Days')
    expect(getCippTranslation('LastRunAt')).toBe('Last Run At')
    expect(getCippTranslation('PolicyCount')).toBe('Policy Count')
  })
})

describe('Cloud Backup columns', () => {
  it('colours backup results', () => {
    const colors = {
      Succeeded: 'success',
      Passed: 'success',
      PartialSuccess: 'warning',
      Skipped: 'warning',
      Running: 'info',
      Failed: 'error',
      Queued: 'default',
      Completed: 'default',
    }
    for (const [value, color] of Object.entries(colors)) {
      expect(getCippFormatting(value, 'CloudBackupStatus').props.color).toBe(
        color
      )
    }
    expect(
      getCippFormatting('PartialSuccess', 'CloudBackupStatus', 'text')
    ).toBe('Partial success')
    expect(getCippFormatting('Failed', 'CloudBackupLastTest', 'text')).toBe(
      'Failed'
    )
    expect(
      getCippFormatting('Succeeded', 'CloudBackupLastResult').props.color
    ).toBe('success')
  })

  it('colours permission results', () => {
    expect(
      getCippFormatting('Granted', 'CloudBackupPermission').props.color
    ).toBe('success')
    expect(
      getCippFormatting('Pending', 'CloudBackupPermission').props.color
    ).toBe('info')
    expect(
      getCippFormatting('Failed', 'CloudBackupPermission').props.color
    ).toBe('error')
    expect(getCippTranslation('CloudBackupWorkload')).toBe('Service')
    expect(getCippTranslation('CloudBackupSources')).toBe('Sources')
  })

  it('colours provisioning steps', () => {
    const colors = {
      Completed: 'success',
      Running: 'info',
      Skipped: 'warning',
      Failed: 'error',
      Queued: 'default',
      Pending: 'default',
    }
    for (const [value, color] of Object.entries(colors)) {
      const chip = getCippFormatting(value, 'CloudBackupStepStatus')
      expect(chip.props.color).toBe(color)
      expect(chip.props.label).toBe(value)
    }
    expect(
      getCippFormatting('Completed', 'CloudBackupStepStatus', 'text')
    ).toBe('Completed')
    expect(getCippTranslation('CloudBackupStepStatus')).toBe('Status')
    expect(getCippTranslation('CloudBackupSignIn')).toBe('Sign-in Method')
  })

  it('formats sizes and dates', () => {
    expect(getCippFormatting(2621440, 'CloudBackupSize', 'text')).toBe('2.5 MB')
    expect(getCippFormatting(null, 'CloudBackupSize', 'text')).toBe('—')
    expect(isCippDateColumn('CloudBackupStartedAt')).toBe(true)
    expect(isCippDateColumn('CloudBackupLastRun')).toBe(true)
    expect(getCippTranslation('CloudBackupSize')).toBe('Size')
    expect(getCippTranslation('CloudBackupStartedAt')).toBe('Started At')
  })

  it('formats browse and restore columns', () => {
    for (const column of [
      'CloudBackupModified',
      'CloudBackupVersionAt',
      'CloudBackupCreatedAt',
      'CloudBackupExpiresAt',
    ]) {
      expect(isCippDateColumn(column)).toBe(true)
    }
    expect(getCippTranslation('CloudBackupItemName')).toBe('Name')
    expect(getCippTranslation('CloudBackupRestoreAction')).toBe('What Happens')
    expect(getCippTranslation('CloudBackupJobType')).toBe('Job')
    expect(getCippTranslation('CloudBackupOwner')).toBe('Backup Of')
    expect(getCippTranslation('CloudBackupTarget')).toBe('Restored To')
  })

  it('leaves the shared names of the new columns untranslated', () => {
    expect(isCippDateColumn('Modified')).toBe(false)
    expect(isCippDateColumn('ExpiresAt')).toBe(false)
    expect(getCippTranslation('RequestedBy')).toBe('Requested By')
    expect(getCippTranslation('TargetPath')).toBe('Target Path')
  })
})
