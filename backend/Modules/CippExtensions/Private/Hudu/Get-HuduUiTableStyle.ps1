function Get-HuduUiTableStyle {
    <#
        .SYNOPSIS
        Inline styles for tables, header cells and body cells.

        .DESCRIPTION
        Hudu's rich text CSS gives tables a full grid, header fill and margins; these reset them inline.
    #>
    $Cell = 'border-width:0 0 1px;background:transparent;vertical-align:top'
    @{
        Table = 'width:100%;border:0;margin:0;table-layout:auto;border-collapse:collapse;font-size:13px'
        Th    = "$Cell;text-align:left;font-weight:500;opacity:.7;padding:6px 8px;border-bottom:1px solid rgba(128,128,128,.35)"
        Td    = "$Cell;padding:8px;border-bottom:1px solid rgba(128,128,128,.2)"
    }
}
