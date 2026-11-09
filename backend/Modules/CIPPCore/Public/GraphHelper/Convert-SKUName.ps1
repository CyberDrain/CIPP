function Convert-SKUname {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $SkuName,
        $SkuID
    )
    $ConversionTable = Get-CIPPConversionTable
    if ($SkuName) { $ReturnedName = $ConversionTable.NameByPartNumber[([string]$SkuName).Trim()] }
    if ($SkuID) { $ReturnedName = $ConversionTable.NameBySkuId[([string]$SkuID).Trim().ToLowerInvariant()] }
    if ($ReturnedName) { return $ReturnedName } else { return $SkuName, $SkuID }
}
