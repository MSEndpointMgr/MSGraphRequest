<#
.SYNOPSIS
    Script that initiates the MSGraphRequest module

.NOTES
    Author:      Nickolaj Andersen & Jan Ketil Skanke
    Contact:     @NickolajA & @JankeSkanke
    Website:     https://www.msendpointmgr.com
#>
[CmdletBinding()]
param()
process {
    # Initialize script-scoped connection state
    $script:MSGraphConnection = $null
    $script:AuthenticationHeader = $null

    # Locate all the public and private function specific files
    $PublicFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Public") -Filter "*.ps1" -ErrorAction SilentlyContinue
    $PrivateFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Private") -Filter "*.ps1" -ErrorAction SilentlyContinue

    # Dot source the function files
    foreach ($FunctionFile in @($PublicFunctions + $PrivateFunctions)) {
        try {
            . $FunctionFile.FullName -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Error -Message "Failed to import function '$($FunctionFile.FullName)' with error: $($_.Exception.Message)"
        }
    }

    # Backward-compatibility alias — log deprecation warning when used
    Set-Alias -Name "Get-AccessToken" -Value "Connect-MSGraphRequest"

    Export-ModuleMember -Function $PublicFunctions.BaseName -Alias *
}