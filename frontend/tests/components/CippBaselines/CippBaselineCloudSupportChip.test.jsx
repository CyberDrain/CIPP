import React from 'react'
import { describe, it, expect } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ThemeProvider } from '@mui/material/styles'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Provider } from 'react-redux'
import { configureStore } from '@reduxjs/toolkit'
import { useForm } from 'react-hook-form'
import { createTheme } from '../../../src/theme'
import { SettingsContext } from '../../../src/contexts/settings-context'
import { CippBaselineStandardDialog } from '../../../src/components/CippBaselines/CippBaselineStandardDialog'
import CippBaselineStandardItem from '../../../src/components/CippBaselines/CippBaselineStandardItem'

// redanthrax/CIPP#4: the baseline catalog and the collapsed staged items show the same "Not supported in
// GCC High" chip as the classic standards dialog, but only for an estate with a tenant in that cloud.
const commercialTenants = [
  { defaultDomainName: 'AllTenants', customerId: 'AllTenants' },
  { defaultDomainName: 'contoso.com', customerId: 'c1', cloudEnvironment: 'Commercial' },
]
const mixedTenants = [
  ...commercialTenants,
  { defaultDomainName: 'gov.us', customerId: 'g1', cloudEnvironment: 'USGovHigh' },
]

// CopilotSettings is listed as unsupported in GCC High in cloudFeatureSupport.json; AuditLog is not.
const unsupported = {
  name: 'CopilotSettings',
  label: 'Copilot settings',
  cat: 'Copilot',
  impact: 'Low Impact',
  helpText: '',
  tag: [],
  recommendedBy: [],
  variables: {},
}
const supported = { ...unsupported, name: 'AuditLog', label: 'Unified audit log' }

const theme = createTheme({ colorPreset: 'orange', direction: 'ltr', paletteMode: 'light', contrast: 'high' })

const store = configureStore({ reducer: { toasts: (state = { toasts: [] }) => state } })

const renderIn = (ui, tenants) => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  client.setQueryData(['TenantSelector'], tenants)
  return render(
    <Provider store={store}>
      <QueryClientProvider client={client}>
        <SettingsContext.Provider value={{ currentTenant: 'contoso.com' }}>
          <ThemeProvider theme={theme}>{ui}</ThemeProvider>
        </SettingsContext.Provider>
      </QueryClientProvider>
    </Provider>
  )
}

const Dialog = () => (
  <CippBaselineStandardDialog
    open
    onClose={() => {}}
    catalog={[unsupported, supported]}
    selectedStandards={[]}
    onToggle={() => {}}
  />
)

const StagedItem = ({ standard }) => {
  const formControl = useForm({ mode: 'onBlur' })
  return (
    <CippBaselineStandardItem
      standard={standard}
      instanceId={standard.name}
      formControl={formControl}
      expanded={false}
      onToggle={() => {}}
      onRemove={() => {}}
    />
  )
}

describe('baseline catalog cloud support chip', () => {
  it('flags only the unsupported standard in card view for a GCC High estate', () => {
    renderIn(<Dialog />, mixedTenants)
    expect(screen.getAllByText('Not supported in GCC High')).toHaveLength(1)
  })

  it('flags only the unsupported standard in list view for a GCC High estate', () => {
    renderIn(<Dialog />, mixedTenants)
    fireEvent.click(screen.getByRole('button', { name: 'list view' }))
    expect(screen.getAllByText('Not supported in GCC High')).toHaveLength(1)
  })

  it('shows no chip in either view for a commercial-only estate', () => {
    renderIn(<Dialog />, commercialTenants)
    expect(screen.queryByText(/Not supported in/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'list view' }))
    expect(screen.queryByText(/Not supported in/)).toBeNull()
  })
})

describe('staged baseline standard cloud support chip', () => {
  it('shows the chip on a collapsed staged item for a GCC High estate', () => {
    renderIn(<StagedItem standard={unsupported} />, mixedTenants)
    expect(screen.getByText('Not supported in GCC High')).toBeInTheDocument()
  })

  it('shows no chip for a supported standard or a commercial-only estate', () => {
    renderIn(<StagedItem standard={supported} />, mixedTenants)
    expect(screen.queryByText(/Not supported in/)).toBeNull()
  })

  it('shows no chip on a collapsed staged item for a commercial-only estate', () => {
    renderIn(<StagedItem standard={unsupported} />, commercialTenants)
    expect(screen.queryByText(/Not supported in/)).toBeNull()
  })
})
