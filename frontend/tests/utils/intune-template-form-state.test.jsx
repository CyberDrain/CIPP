import { describe, expect, it } from 'vitest'
import { render } from '@testing-library/react'
import { Controller, useForm } from 'react-hook-form'

// Cover for the Intune template editor opening with its name blank.
//
// The editor rebuilds its fields whenever the settings change, so the name and description have to
// be carried across from the form rather than reset to what was stored - otherwise renaming a
// template and then adding a setting would undo the rename. That carry-across was written with ??,
// which only falls back on null and undefined.
//
// A field that is registered and rendered holds '', not undefined. So on the very first pass - the
// one meant to put the stored name on screen - '' won, and a template created moments earlier opened
// with an empty name even though the API had returned it. The fix tracks which pass it is on rather
// than inferring it from the value, because an empty field and an unpopulated one look identical.

const Harness = ({ onReady }) => {
  const formControl = useForm({ mode: 'onChange' })
  onReady(formControl)
  return (
    <Controller
      name="displayName"
      control={formControl.control}
      defaultValue=""
      render={({ field }) => <input {...field} />}
    />
  )
}

describe('a rendered field reports an empty string, not undefined', () => {
  it('holds an empty string once the field is on screen', () => {
    let formControl
    render(<Harness onReady={(fc) => (formControl = fc)} />)
    expect(formControl.getValues().displayName).toBe('')
  })

  it('means ?? cannot be used to fall back to the stored name', () => {
    const stored = 'Baseline - Windows'
    expect('' ?? stored).toBe('')
  })
})

// The fix does not use || either, because an empty name is a legitimate thing to have typed and ||
// would put the stored one back on the next rebuild. It tracks the pass instead. This models that.
const resolveField = ({ firstPass, storedValue, currentValue }) =>
  firstPass ? (storedValue ?? '') : currentValue

describe('name population across rebuilds', () => {
  it('takes the stored name on the first pass', () => {
    expect(
      resolveField({
        firstPass: true,
        storedValue: 'Baseline',
        currentValue: '',
      })
    ).toBe('Baseline')
  })

  it('keeps what is on screen afterwards, so adding a setting does not undo a rename', () => {
    expect(
      resolveField({
        firstPass: false,
        storedValue: 'Baseline',
        currentValue: 'Renamed',
      })
    ).toBe('Renamed')
  })

  it('lets a deliberately cleared field stay cleared', () => {
    expect(
      resolveField({
        firstPass: false,
        storedValue: 'Baseline',
        currentValue: '',
      })
    ).toBe('')
  })

  it('falls back to an empty string when nothing is stored', () => {
    expect(
      resolveField({
        firstPass: true,
        storedValue: undefined,
        currentValue: '',
      })
    ).toBe('')
  })
})
