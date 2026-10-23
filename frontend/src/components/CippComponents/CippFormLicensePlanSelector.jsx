import { useWatch } from "react-hook-form";
import { Grid } from "@mui/system";
import { CippFormComponent } from "./CippFormComponent";
import { getLicenseSelectorApi } from "./CippFormLicenseSelector";
import { ApiGetCallWithPagination } from "../../api/ApiCall";
import { useSettings } from "../../hooks/use-settings";
import { getCippLicenseTranslation } from "../../utils/get-cipp-license-translation";
import { getCatalogSku, getServicePlanFriendlyName } from "../../utils/get-cipp-license-catalog";

// Only user-level plans can be toggled per assignment; company-level ones (EXCHANGE_S_FOUNDATION, ...)
// are not offered by the admin center either.
const planOptions = (plans) =>
  plans
    .filter((plan) => !plan.appliesTo || plan.appliesTo === "User")
    .map((plan) => {
      const id = plan.servicePlanId;
      const friendly = getServicePlanFriendlyName(id) || plan.friendlyName;
      return {
        label: friendly ? `${friendly} (${plan.servicePlanName})` : plan.servicePlanName || id,
        value: id,
      };
    });

/**
 * One "Disabled service plans for <license>" multi-select per SKU, stored under `${name}.<skuId>` so the
 * form posts a map skuId -> plan options next to the license field. Set-CIPPGroupLicense reads that map.
 *
 * SKUs come from the selected options of `licenseField`, or from `licenses` ({ skuId }[]) when the caller
 * already knows them (licenses the group has today). Plan lists come from the tenant's subscribedSkus via
 * the same ListLicenses query the license dropdown runs (shared react-query cache, no extra request), with
 * the local M365 catalog as the fallback for a SKU the current tenant does not own (templates).
 */
export const CippFormLicensePlanSelector = ({
  formControl,
  licenseField,
  name,
  licenses,
  isFetching = false,
  disabled = false,
}) => {
  const tenant = useSettings().currentTenant;
  const selected = useWatch({ control: formControl.control, name: licenseField ?? name });
  // MUI keeps a placeholder visible next to the chips in multiple mode, so only show it while empty
  const planMap = useWatch({ control: formControl.control, name });
  const skuIds = licenses
    ? licenses.map((lic) => lic.skuId)
    : (Array.isArray(selected) ? selected : [])
        .map((option) => option?.value ?? option)
        .filter((skuId) => typeof skuId === "string" && skuId);

  const api = getLicenseSelectorApi(tenant);
  const licenseQuery = ApiGetCallWithPagination({
    url: api.url,
    // CippAutocomplete suffixes the tenant onto api.queryKey and merges tenantFilter into data; mirror
    // both so this resolves to the dropdown's cache entry instead of a second ListLicenses call.
    queryKey: `${api.queryKey}-${tenant}`,
    data: { tenantFilter: tenant, ...api.data },
    waiting: skuIds.length > 0,
  });
  const tenantSkus = (licenseQuery.data?.pages ?? []).flatMap((page) =>
    Array.isArray(page) ? page : [],
  );

  const optionsFor = (skuId) => {
    const key = skuId.toLowerCase();
    const tenantSku = tenantSkus.find((sku) => sku?.skuId?.toLowerCase() === key);
    const plans = tenantSku?.ServicePlans ?? getCatalogSku(skuId)?.servicePlans ?? [];
    return planOptions(plans);
  };

  if (skuIds.length === 0) return null;

  return (
    <>
      {skuIds.map((skuId) => (
        <Grid key={skuId} size={{ xs: 12 }}>
          <CippFormComponent
            type="autoComplete"
            name={`${name}.${skuId}`}
            label={`Disabled service plans for ${getCippLicenseTranslation([{ skuId }])[0]}`}
            formControl={formControl}
            multiple={true}
            creatable={false}
            options={optionsFor(skuId)}
            sortOptions={true}
            isFetching={isFetching || licenseQuery.isFetching}
            disabled={disabled}
            placeholder={
              (planMap?.[skuId] ?? []).length > 0
                ? undefined
                : "None disabled (all service plans enabled)"
            }
          />
        </Grid>
      ))}
    </>
  );
};

export default CippFormLicensePlanSelector;
