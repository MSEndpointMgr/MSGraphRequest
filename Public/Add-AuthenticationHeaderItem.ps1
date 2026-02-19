function Add-AuthenticationHeaderItem {
    <#
    .SYNOPSIS
        Extend an existing authentication header by adding a new item with a name and a value.For example consistencylevel = eventual

    .DESCRIPTION
        Extend an existing authentication header by adding a new item with a name and a value.

    .PARAMETER Name
        Specify the name, or the 'key' of the item to be added to the authentication header hash-table.

    .PARAMETER Value
        Specify the value of the item to be added to the authentication header hash-table.

    .EXAMPLE
        Add-AuthenticationHeaderItem -Name consistencylevel -Value eventual

    .NOTES
        Author:      Nickolaj Andersen 
        Contributor: Jan Ketil Skanke
        Contact:     @NickolajA / @JankeSkanke
        Created:     2021-05-19
        Updated:     2023-12-04

        Version history:
        1.0.0 - (2021-05-19) Script created
        1.0.1 - (2023-12-04) Minor changes to the help text
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
        if ($script:AuthenticationHeader) {
            $script:AuthenticationHeader.Add($Name, $Value)
        }
        else {
            Write-Warning -Message "Unable to locate existing authentication header, use Connect-MSGraphRequest before running this function"
        }
    }
}