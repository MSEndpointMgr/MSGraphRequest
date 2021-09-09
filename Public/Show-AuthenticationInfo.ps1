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
    Process {
        if ($Global:AuthenticationHeader) {
            # Construct new PS custom object
            $Response = New-Object -TypeName "PSObject"

            # Process each keys in the authentication header and add tenantId and scopes
            foreach ($AuthenticationHeaderItem in $Global:AuthenticationHeader.Keys) { 
                $Response | Add-Member -Type "NoteProperty" -Name $AuthenticationHeaderItem -Value $Global:AuthenticationHeader[$AuthenticationHeaderItem]   
            }
            $Response | Add-Member -Type "NoteProperty" -Name "TenantID" -Value $Global:AccessToken.TenantID
            $Response | Add-Member -Type "NoteProperty" -Name "Scopes" -Value $Global:AccessToken.Scopes
            
            # Handle return value
            return $Response
        }
        else {
            Write-Warning -Message "Unable to locate existing authentication header, use Get-AccessToken before running this function"
        }
    }
}