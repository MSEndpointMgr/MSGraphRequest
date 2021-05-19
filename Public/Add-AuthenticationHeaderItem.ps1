function Add-AuthenticationHeaderItem {
    <#
    .SYNOPSIS
        Extend an existing authentication header by adding a new item with a name and a value.

    .DESCRIPTION
        Extend an existing authentication header by adding a new item with a name and a value.

    .PARAMETER Name
        Specify the name, or the 'key' of the item to be added to the authentication header hash-table.

    .PARAMETER Value
        Specify the value of the item to be added to the authentication header hash-table.

    .NOTES
        Author:      Nickolaj Andersen
        Contact:     @NickolajA
        Created:     2021-05-19
        Updated:     2021-05-19

        Version history:
        1.0.0 - (2021-05-19) Script created
    #>
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the name, or the 'key' of the item to be added to the authentication header hash-table.")]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [parameter(Mandatory = $true, HelpMessage = "Specify the value of the item to be added to the authentication header hash-table.")]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )
    Process {
        if ($Global:AuthenticationHeader) {
            $Global:AuthenticationHeader.Add($Name, $Value)
        }
        else {
            Write-Warning -Message "Unable to locate existing authentication header, use Get-AccessToken before running this function"
        }
    }
}