<#
.SYNOPSIS
Refreshes the prices in backend/Config/LicenseCatalog.json from Microsoft's public retail prices.

.DESCRIPTION
Microsoft's plans-and-pricing pages hydrate their prices from an unauthenticated JSON endpoint
(https://www.microsoft.com/msonecloudapi/m365/product/price). This tool resolves the retail
(MSRP/list) price for a curated set of Microsoft catalog product IDs, joins each to its licensing
skuPartNumber + GUID (Microsoft's "Product names and service plan identifiers" CSV), and writes the
result into the `prices` map of each product in the license catalog the optimization report reads.

The catalog's other sections (capabilities, families, per-product family/tier/eligibleTarget) are
hand-maintained and left untouched. A scraped SKU that is not yet in the catalog is appended with
family 'other' and eligibleTarget false so it prices but is never recommended until someone
classifies it.

Prices are the per-user/month retail rate on an annual commitment. Month-to-month costs
meta.monthlyCommitmentUplift (20%) more; the report derives that.

The endpoint is undocumented and could change - this is a best-effort estimate source, not an
authoritative feed. Real per-partner cost/RRP still comes from the MSP price override table and,
later, distributor/Partner Center integrations.

.PARAMETER Market
One or more Microsoft market codes (US, AU, GB, CA, NZ, IE, ...). Each maps to its local currency
(US->USD, AU->AUD, GB->GBP, CA->CAD, NZ->NZD, IE->EUR). Each product's `prices` map gains one
entry per currency. The loader (Get-CIPPLicensePrice -Currency) filters to the currency in view.

.PARAMETER OutFile
Target catalog JSON. Defaults to backend/Config/LicenseCatalog.json.

.PARAMETER NoMerge
Drop every existing price before writing. By default existing (skuId, currency) prices are kept so
SKUs/currencies this tool does not yet scrape never regress.

.EXAMPLE
pwsh build/tools/Update-LicensePricingDefaults.ps1
Regenerates the multi-currency defaults, merging over the existing curated rows.

.EXAMPLE
pwsh -Command "& build/tools/Update-LicensePricingDefaults.ps1 -Market US,AU,GB"
Regenerate for a specific market set (use -Command, not -File, so the array binds).

.NOTES
Date: 2026-08-26
Version: 1.0 - Initial script
Version: 1.1 - Writes into LicenseCatalog.json instead of the retired LicensePricingDefaults.csv
#>
[CmdletBinding()]
param(
    [string[]] $Market = @('US', 'AU', 'GB', 'CA', 'NZ', 'IE'),
    [string]   $OutFile,
    [switch]   $NoMerge
)

$ErrorActionPreference = 'Stop'

# This script lives in build/tools/, so the repo root is two levels up.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutFile) { $OutFile = Join-Path $RepoRoot 'backend/Config/LicenseCatalog.json' }

$PriceEndpoint = 'https://www.microsoft.com/msonecloudapi/m365/product/price'
$LicenseCsvUrl = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

# --- Curated catalog product IDs harvested from the public pricing pages -------------------------
# business / enterprise / frontline / office-365 / additional-services / exchange / teams / power-bi
# *-plans-and-pricing pages. _alt chains carry with/without-Teams variants; the parser keeps each
# (productId, skuId) pair, so both Teams variants resolve to their own sku.title (and own GUID).
$RawTokens = @'
a0c4p0_pidcfq7ttc0lchc_skuid0002_r2p3
a0c4p0_pidcfq7ttc0ldpb_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lchc_skuid001q_r2p3
a0c4p0_pidcfq7ttc0ldpb_skuid001x_r2p3
a0c4p0_pidcfq7ttc0lh18_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lchc_skuid001p_r2p3_alta0c4p0_pidcfq7ttc0lchc_skuid001r_r2p3
a0c4p0_pidcfq7ttc0ldpb_skuid001z_r2p3_alta0c4p0_pidcfq7ttc0ldpb_skuid001w_r2p3
a0c4p0_pidcfq7ttc0lh18_skuid000p_r2p3_alta0c4p0_pidcfq7ttc0lh18_skuid000d_r2p3
a0c4p0_pidcfq7ttc0lh1g_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lh0t_skuid0001_r2p3
a0c4p0_pidcfq7ttc0hx56_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lflz_skuid0002_r2p3_alta0c4p0_pidcfq7ttc0lflz_skuid0003_r2p3
a0c4p0_pidcfq7ttc0lflx_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lflz_skuid001p_r2p3_alta0c4p0_pidcfq7ttc0lflz_skuid000z_r2p3_alta0c4p0_pidcfq7ttc0lflz_skuid001l_r2p3
a0c4p0_pidcfq7ttc0lflx_skuid0021_r2p3_alta0c4p0_pidcfq7ttc0lflx_skuid0010_r2p3
a0c4p0_pidcfq7ttc0mzjf_skuid0009_r2p3
a0c4p0_pidcfq7ttc0lh05_skuid0001_r2p3
a0c4p0_pidcfq7ttc0mbmd_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lh05_skuid0013_r2p3_alta0c4p0_pidcfq7ttc0lh05_skuid000m_r2p3
a0c4p0_pidcfq7ttc0mbmd_skuid002t_r2p3_alta0c4p0_pidcfq7ttc0mbmd_skuid001p_r2p3
a0c4p0_pidcfq7ttc0lgzt_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lf8s_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lf8r_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lf8q_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lf8q_skuid001s_r2p3
a0c4p0_pidcfq7ttc0lf8r_skuid0020_r2p3
a0c4p0_pidcfq7ttc0lf8s_skuid001j_r2p3
a0c4p0_pidcfq7ttc0lfj2_skuid0007_r2p3
a0c4p0_pidcfq7ttc0mm8r_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lh1p_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lh16_skuid0001_r2p3
a0c4p0_pidcfq7ttc0jn4r_skuid0002_r2p3
a0c4p0_pidcfq7ttc0mzjf_skuid0009_r2p3
a0c4p0_pidcfq7ttc0lhsf_skuid0001_r2p3
a0c4p0_pidcfq7ttc0hl8w_skuid0001_r2p3
a0c4p0_pidcfq7ttc0qw7c_skuid0001_r2p3
a0c4p0_pidcfq7ttc0mm8r_skuid001p_r2p3
a0c4p0_pidcfq7ttc0lfls_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lfk5_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lfj1_skuid0001_r2p3
a0c4p0_pidcfq7ttc0rp76_skuid0002_r2p3
a0c4p0_pidcfq7ttc0mft1_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lh04_skuid_r2p3
a0c4p0_pidcfq7ttc0lhxh_skuid_r2p3
a0c4p0_pidcfq7ttc0hd33_skuid_r2p3
a0c4p0_pidcfq7ttc0hd32_skuid_r2p3
a0c4p0_pidcfq7ttc0lsgz_skuid_r2p3
a0c4p0_pidcfq7ttc0r9qb_skuid_r2p3
a0c4p0_pidcfq7ttc0nggx_skuid0004_r2p3
a0c4p0_pidcfq7ttc0hdb0_skuid0002_r2p3
a0c4p0_pidcfq7ttc0hdb1_skuid0002_r2p3
a0c4p0_pidcfq7ttc0lhq5_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lh2h_skuid0002_r2p3
a0c4p0_pidcfq7ttc0rm8k_skuid0022_r2p3
a0c4p0_pidcfq7ttc0qw7c_skuid0006_r2p3
a0c4p0_pidcfq7ttc0hl73_skuid0001_r2p3
a0c4p0_pidcfq7ttc0lh18_skuid000p_r2p3
a0c4p0_pidcfq7ttc0ldpb_skuid001w_r2p3
a0c4p0_pidcfq7ttc0lchc_skuid001p_r2p3
a0c4p0_pidcfq7ttc0lh05_skuid0013_r2p3
a0c4p0_pidcfq7ttc0mbmd_skuid002t_r2p3
'@

# Curated productId -> correct skuPartNumber, for cases the name join gets wrong:
#  - LH18 "Microsoft 365 Business Basic" name-collides on SMB_BUSINESS_ESSENTIALS (legacy) vs the
#    current O365_BUSINESS_ESSENTIALS.
#  - MM8R the pricing feed says "Microsoft 365 Copilot" but the licensing CSV calls it
#    "Microsoft Copilot for Microsoft 365" (skuPartNumber Microsoft_365_Copilot).
$OverridePart = @{
    'CFQ7TTC0LH18' = 'O365_BUSINESS_ESSENTIALS'
    'CFQ7TTC0MM8R' = 'Microsoft_365_Copilot'
    'CFQ7TTC0LH04' = 'ATP_ENTERPRISE'                # Defender for Office 365 (Plan 1)
    'CFQ7TTC0LHXH' = 'THREAT_INTELLIGENCE'           # Defender for Office 365 (Plan 2)
    'CFQ7TTC0HD33' = 'VISIOONLINE_PLAN1'             # Visio Plan 1 (name also matches the _DEPT SKU)
    'CFQ7TTC0HD32' = 'VISIOCLIENT'                   # Visio Plan 2
    'CFQ7TTC0LSGZ' = 'POWERAUTOMATE_ATTENDED_RPA'    # Power Automate Premium
    'CFQ7TTC0R9QB' = 'Workload_Identities_P2'        # Entra Workload ID
    'CFQ7TTC0NGGX' = 'Microsoft_Intune_Advanced_Analytics' # sku 0004 = enterprise; default sku is the FLW variant
    'CFQ7TTC0HDB0' = 'PROJECTPROFESSIONAL'            # Planner and Project Plan 3
    'CFQ7TTC0HDB1' = 'PROJECT_P1'                     # Planner Plan 1
    'CFQ7TTC0LHQ5' = 'EXCHANGEARCHIVE'                # Exchange Online Archiving for Exchange Server
    'CFQ7TTC0LH2H' = 'POWERAPPS_PER_USER'             # Power Apps Premium (name also matches the GCC / embedded SKUs)
    'CFQ7TTC0RM8K' = 'M365_TEAMS_PREMIUM'             # Teams Premium
    'CFQ7TTC0HL73' = 'MCOTEAMS_ESSENTIALS'            # Teams Phone with Calling Plan
}
# productId + skuId -> skuPartNumber, where one product carries several SKUs with their own GUID
$OverridePartBySku = @{
    'CFQ7TTC0QW7C|0006' = 'Microsoft_Teams_Rooms_Pro_without_Audio_Conferencing'
    'CFQ7TTC0LH18|000P' = 'Microsoft_365_Business_Basic_(no Teams)'
    # Business Standard/Premium (no Teams) SKUs on the pricing pages are Copilot bundles now, so
    # the Copilot skip below drops them rather than attaching a bundle price to the plain SKU.
}

# productIds with no single clean per-seat subscribedSku (config-matrix or too new for the CSV).
$SkipProduct = @('CFQ7TTC0HHS9', 'CFQ7TTC0LHQB', 'CFQ7TTC0LHR4') # Windows 365, Defender Suite, Purview Suite

function Get-NormalizedName {
    param([string] $Value)
    if (-not $Value) { return '' }
    # collapse everything non-alphanumeric to spaces (strips TM/(R), punctuation; keeps "no teams")
    $Value = $Value -replace '[^a-zA-Z0-9]', ' '
    return ($Value.ToLowerInvariant().Trim() -replace '\s+', ' ')
}

# --- 1. Parse every unique (productId, skuId, recurrence, cadence) tuple ------------------------
$Tuples = [System.Collections.Generic.List[object]]::new()
$Seen = [System.Collections.Generic.HashSet[string]]::new()
# An empty skuid ("_skuid_") asks the endpoint for the product's default SKU.
foreach ($M in [regex]::Matches($RawTokens, 'pid([a-z0-9]+)_skuid([a-z0-9]*)_r(\d+)p(\d+)')) {
    $ProductId = $M.Groups[1].Value
    $SkuIdPart = $M.Groups[2].Value
    if ($Seen.Add("$ProductId|$SkuIdPart")) {
        $Tuples.Add([pscustomobject]@{
                Token = ('a0c4p0_pid{0}_skuid{1}_r{2}p{3}' -f $ProductId, $SkuIdPart, $M.Groups[3].Value, $M.Groups[4].Value)
            })
    }
}
Write-Host ("Parsed {0} unique (productId, skuId) pairs." -f $Tuples.Count)

# --- 2. Licensing CSV: skuPartNumber -> {GUID, DisplayName} and name -> {part, GUID, DisplayName}
$TempLicense = Join-Path ([System.IO.Path]::GetTempPath()) 'LicensePricing-LicenseSKUs.csv'
Invoke-WebRequest -Uri $LicenseCsvUrl -OutFile $TempLicense -Headers @{ 'User-Agent' = $UserAgent }
$License = Import-Csv -Path $TempLicense -Encoding utf8BOM -Delimiter ','

$ByPart = @{}   # String_Id (lower) -> row
$ByName = @{}   # normalized Product_Display_Name -> row (first wins)
foreach ($Row in $License) {
    if (-not $Row.String_Id) { continue }
    $PartKey = $Row.String_Id.ToLowerInvariant()
    if (-not $ByPart.ContainsKey($PartKey)) {
        $ByPart[$PartKey] = [pscustomobject]@{ SkuPartNumber = $Row.String_Id; Guid = $Row.GUID; DisplayName = $Row.Product_Display_Name }
    }
    $NameKey = Get-NormalizedName $Row.Product_Display_Name
    if ($NameKey -and -not $ByName.ContainsKey($NameKey)) {
        $ByName[$NameKey] = $ByPart[$PartKey]
    }
}
Write-Host ("Licensing CSV: {0} skuPartNumbers, {1} product names indexed." -f $ByPart.Count, $ByName.Count)

# --- 3. Resolve prices per market --------------------------------------------------------------
function Get-RetailPrice {
    param([object[]] $ResolveTuples, [string] $Llcc)
    $Rows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $ResolveTuples.Count; $i += 5) {
        $Batch = $ResolveTuples[$i..([Math]::Min($i + 4, $ResolveTuples.Count - 1))]
        $Query = ($Batch.Token | ForEach-Object { [uri]::EscapeDataString($_) }) -join ','
        $Url = '{0}?q={1}&llcc={2}&v=4&r=json' -f $PriceEndpoint, $Query, $Llcc
        try {
            $Response = Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = $UserAgent }
            # The endpoint blocks bursts; pace the batches.
            Start-Sleep -Seconds 3
        } catch {
            Write-Warning ("price batch @{0} ({1}) failed: {2}" -f $i, $Llcc, $_.Exception.Message)
            continue
        }
        foreach ($Item in $Response) {
            if ($Item.responseCode -ne 'Success') { continue }
            $Rows.Add([pscustomobject]@{
                    ProductId = $Item.productId
                    Product   = $Item.title
                    SkuTitle  = $Item.sku.title
                    SkuId     = [string]$Item.sku.id
                    Currency  = $Item.sku.currencyCode
                    Monthly   = [decimal]$Item.sku.msrpPrice
                })
        }
    }
    return $Rows
}

# --- 4. Resolve + join -------------------------------------------------------------------------
$Catalog = [System.Collections.Generic.List[object]]::new()
$Unmatched = [System.Collections.Generic.List[object]]::new()
foreach ($Mkt in $Market) {
    $Llcc = 'en-{0}' -f $Mkt
    Write-Host ("Resolving prices for {0} ..." -f $Llcc) -ForegroundColor Cyan
    foreach ($Price in (Get-RetailPrice -ResolveTuples $Tuples -Llcc $Llcc)) {
        if ($SkipProduct -contains $Price.ProductId.ToUpperInvariant()) { continue }
        # The Business Standard/Premium headline SKUs are now Copilot bundles (sku.title "... with
        # Copilot"). Their price is not the base SKU's price, so don't attach it to plain SPB /
        # O365_BUSINESS_PREMIUM - skip and let the base price come from the curated merge. The real
        # Copilot product (MM8R) is exempt.
        if ($Price.SkuTitle -match '(?i)copilot' -and $Price.ProductId.ToUpperInvariant() -ne 'CFQ7TTC0MM8R') { continue }

        $Hit = $null
        $PartOverride = $OverridePartBySku[('{0}|{1}' -f $Price.ProductId.ToUpperInvariant(), $Price.SkuId.ToUpperInvariant())]
        if (-not $PartOverride) { $PartOverride = $OverridePart[$Price.ProductId.ToUpperInvariant()] }
        if ($PartOverride) {
            $Hit = $ByPart[$PartOverride.ToLowerInvariant()]
        }
        if (-not $Hit) { $Hit = $ByName[(Get-NormalizedName $Price.SkuTitle)] }   # catches "(no Teams)"
        if (-not $Hit) { $Hit = $ByName[(Get-NormalizedName $Price.Product)] }
        if (-not $Hit) {
            $Unmatched.Add([pscustomobject]@{ Product = $Price.Product; SkuTitle = $Price.SkuTitle; ProductId = $Price.ProductId })
            continue
        }

        $Catalog.Add([pscustomobject]@{
                skuId                = $Hit.Guid.ToLowerInvariant()
                skuPartNumber        = $Hit.SkuPartNumber
                Product_Display_Name = $Hit.DisplayName
                MonthlyPrice         = [Math]::Round($Price.Monthly, 2)
                Currency             = $Price.Currency
            })
    }
}

# dedup by (skuId, currency) - first (primary/with-Teams) wins
$DedupSeen = [System.Collections.Generic.HashSet[string]]::new()
$Catalog = @($Catalog | Where-Object { $DedupSeen.Add(('{0}|{1}' -f $_.skuId, $_.Currency.ToLowerInvariant())) })

# --- 5. Write the prices into the catalog JSON, keyed by (skuId, currency) ---------------------
if (-not (Test-Path $OutFile)) { throw "Catalog not found at $OutFile - the capabilities/families sections are hand-maintained and cannot be regenerated here." }
$CatalogJson = Get-Content -Path $OutFile -Raw | ConvertFrom-Json
$ProductBySku = @{}
foreach ($Product in @($CatalogJson.products)) {
    $ProductBySku[([string]$Product.skuId).ToLowerInvariant()] = $Product
    if ($NoMerge) { $Product.prices = [pscustomobject]@{} }
}

$Added = [System.Collections.Generic.List[string]]::new()
foreach ($Row in $Catalog) {
    $Product = $ProductBySku[$Row.skuId]
    if (-not $Product) {
        # No name or part number: the SKU list (ConversionTable.csv) is the one place those live.
        $Product = [pscustomobject]@{
            skuId          = $Row.skuId
            family         = 'other'
            tier           = 0
            eligibleTarget = $false
            prices         = [pscustomobject]@{}
        }
        $CatalogJson.products = @($CatalogJson.products) + $Product
        $ProductBySku[$Row.skuId] = $Product
        $Added.Add(('{0} ({1})' -f $Row.Product_Display_Name, $Row.skuPartNumber))
    }
    if ($null -eq $Product.prices) { $Product.prices = [pscustomobject]@{} }
    # scraped wins over the existing value for this currency
    if ($Product.prices.PSObject.Properties[$Row.Currency]) {
        $Product.prices.($Row.Currency) = $Row.MonthlyPrice
    } else {
        $Product.prices | Add-Member -NotePropertyName $Row.Currency -NotePropertyValue $Row.MonthlyPrice
    }
}

# Stable output: products by name, currencies alphabetical
foreach ($Product in @($CatalogJson.products)) {
    $Sorted = [ordered]@{}
    foreach ($P in ($Product.prices.PSObject.Properties | Sort-Object Name)) { $Sorted[$P.Name] = [double]$P.Value }
    $Product.prices = [pscustomobject]$Sorted
}
$CatalogJson.products = @($CatalogJson.products | Sort-Object name)

$Json = $CatalogJson | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutFile, $Json + "`n", [System.Text.UTF8Encoding]::new($false))
$Currencies = @($CatalogJson.products | ForEach-Object { $_.prices.PSObject.Properties.Name } | Sort-Object -Unique)
Write-Host ("`nWrote {0} ({1} products across {2})" -f $OutFile, @($CatalogJson.products).Count, ($Currencies -join ',')) -ForegroundColor Green
if ($Added.Count) {
    Write-Host "`nADDED to the catalog as family 'other' (classify them: family / tier / eligibleTarget):" -ForegroundColor Yellow
    $Added | ForEach-Object { Write-Host "  $_" }
}

if ($Unmatched.Count) {
    Write-Host "`nUNMATCHED (excluded - no clean subscribedSku; add an override or leave out):" -ForegroundColor Yellow
    $Unmatched | Select-Object Product, SkuTitle, ProductId -Unique | Format-Table -AutoSize
}
