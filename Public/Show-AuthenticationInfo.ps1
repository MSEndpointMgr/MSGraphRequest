function Show-AuthenticationInfo {
    <#
    .SYNOPSIS
        Shows info about current access token and header items.

    .DESCRIPTION
        Shows info about current access token and header items.

    .NOTES
        Author:      Jan Ketil Skanke
        Contact:     @JankeSkanke
        Created:     2021-08-24
        Updated:     2021-08-24

        Version history:
        1.0.0 - (2021-08-24) Script created
    #>
$ActiveTenant = "Connected to tenant: $($Global:AccessToken.TenantID)"
$ActiveHeader = $Global:AuthenticationHeader

return $ActiveTenant, $ActiveHeader
}