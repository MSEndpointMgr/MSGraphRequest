function Remove-AuthenticationHeaderItem {
    <#
    .SYNOPSIS
        Removes an existing authentication header by name.

    .DESCRIPTION
        Removes an existing authentication header by name

    .PARAMETER Name
        Specify the name, or the 'key' of the item to be removed from the authentication header hash-table.

    .NOTES
        Author:      Jan Ketil Skanke
        Contact:     @JankeSkanke
        Created:     2021-08-24
        Updated:     2021-08-24

        Version history:
        1.0.0 - (2021-08-24) Script created
    #>
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the name, or the 'key' of the item to be removed from the authentication header hash-table.")]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    Process {
        if ($Global:AuthenticationHeader) {
            $Global:AuthenticationHeader.Remove($Name)
        }
        else {
            Write-Warning -Message "Unable to locate existing authentication header, use Get-AccessToken before running this function"
        }
    }
}