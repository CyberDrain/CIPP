import { CippFormComponent } from './CippFormComponent'
import { getCippLicenseTranslation } from '../../utils/get-cipp-license-translation'
import { useSettings } from '../../hooks/use-settings'

// The ListLicenses query behind the dropdown. CippFormLicensePlanSelector reuses it to read each SKU's
// service plans out of the same react-query entry, so keep url/queryKey/data defined here only.
export const getLicenseSelectorApi = (tenant) => ({
  url: '/api/ListLicenses',
  queryKey: `ListLicenses-${tenant ?? undefined}`,
  data: {
    Endpoint: 'subscribedSkus',
    $count: true,
    IncludeExcluded: true,
  },
})

export const CippFormLicenseSelector = ({
  formControl,
  name,
  label,
  multiple = true,
  select,
  addedField,
  showRefresh = false,
  ...other
}) => {
  const userSettingsDefaults = useSettings()
  const licenseApi = getLicenseSelectorApi(userSettingsDefaults?.currentTenant)
  return (
    <CippFormComponent
      name={name}
      label={label}
      type="autoComplete"
      formControl={formControl}
      multiple={multiple}
      creatable={false}
      api={{
        addedField: addedField,
        tenantFilter: userSettingsDefaults.currentTenant ?? undefined,
        ...licenseApi,
        labelField: (option) =>
          `${getCippLicenseTranslation([option])} (${option?.availableUnits} available)`,
        valueField: 'skuId',
        showRefresh,
      }}
    />
  )
}
