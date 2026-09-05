function Get-CippReportHeroImages {
    <#
    .SYNOPSIS
        The stock section-divider (hero) photos a server-rendered report can use, keyed by name.
    .DESCRIPTION
        Returns the /reportImages/<name>.jpg paths the report trees reference for their full-bleed
        section dividers. These are the same stock photos the frontend used to pull from
        public/reportImages; server-side they ship beside the CIPPSharp assembly under reportImages/ and
        the renderer resolves the path to the bundled bytes (ReportComponents.DecodeImage). Passing this
        map to a report tree's -HeroImages makes its divider pages render with their photos.
    #>
    [CmdletBinding()]
    param()

    @{
        board   = '/reportImages/board.jpg'
        glasses = '/reportImages/glasses.jpg'
        working = '/reportImages/working.jpg'
        laptop  = '/reportImages/laptop.jpg'
        city    = '/reportImages/city.jpg'
        soc     = '/reportImages/soc.jpg'
    }
}
