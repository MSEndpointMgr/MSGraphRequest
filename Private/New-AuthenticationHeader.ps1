function New-AuthenticationHeader {
    <#
    .SYNOPSIS
        Constructs a header hash-table from a plain access token string and expiry datetime.

    .DESCRIPTION
        Builds the HTTP headers required for Microsoft Graph API requests, including
        the Authorization bearer header and Content-Type. No SDK dependencies - accepts
        a plain token string.

    .PARAMETER AccessToken
        The raw access token string (JWT).

    .PARAMETER ExpiresOn
        The UTC datetime when the token expires.

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2021-04-08
        Updated:     2026-02-19

        Version history:
        1.0.0 - (2021-04-08) Script created
        2.0.0 - (2026-02-19) Rewritten to accept plain token string - removed MSAL dependency
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "The raw access token string (JWT).")]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $true, HelpMessage = "The UTC datetime when the token expires.")]
        [ValidateNotNull()]
        [datetime]$ExpiresOn
    )
    Process {
        # Construct default header parameters
        $AuthenticationHeader = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Bearer $AccessToken"
            "ExpiresOn"     = $ExpiresOn.ToLocalTime()
        }

        # Handle return value
        return $AuthenticationHeader
    }
}
