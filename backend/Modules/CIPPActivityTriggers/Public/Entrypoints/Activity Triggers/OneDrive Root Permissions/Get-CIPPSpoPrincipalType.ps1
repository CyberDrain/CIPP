function Get-CIPPSpoPrincipalType {
    param($Entity)
    if ($Entity.LoginName -match '(?i)federateddirectoryclaimprovider') { return 'M365 Group' }
    switch ($Entity.PrincipalType) {
        1 { 'User' }
        4 { 'Security Group' }
        8 { 'SharePoint Group' }
        default { 'Other' }
    }
}
