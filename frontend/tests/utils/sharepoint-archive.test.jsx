import { describe, it, expect } from 'vitest'
import { ARCHIVE_WAIT_NOTE } from '../../src/utils/sharepoint-archive'
import { getCippFormatting } from '../../src/utils/get-cipp-formatting'

describe('ARCHIVE_WAIT_NOTE', () => {
  it('says archived content can take up to 24 hours to come back', () => {
    expect(ARCHIVE_WAIT_NOTE).toContain('up to 24 hours')
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
