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

$ActiveHeader = $Global:AuthenticationHeader

$Response = New-Object -TypeName PSObject 
foreach ($item in $ActiveHeader.keys) { 
    $Response | Add-Member -Type NoteProperty -Name $item -Value  $ActiveHeader[$item]   
}
$Response | Add-Member -Type NoteProperty -Name "TenantID" -Value $Global:AccessToken.TenantID
$Response | Add-Member -Type NoteProperty -Name "Scopes" -Value $Global:AccessToken.Scopes
return $Response
}

