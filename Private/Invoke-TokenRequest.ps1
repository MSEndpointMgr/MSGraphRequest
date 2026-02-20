function Invoke-TokenRequest {
    <#
    .SYNOPSIS
        Sends a token request to the Microsoft identity platform v2.0 token endpoint.

    .DESCRIPTION
        Centralised wrapper around Invoke-RestMethod for all OAuth2 token requests.
        Handles error parsing and returns the raw token response object.
        Never logs token values - only diagnostic metadata.

    .PARAMETER TokenEndpoint
        The full URL of the token endpoint, e.g.
        https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token

    .PARAMETER Body
        A hashtable containing the form-encoded body parameters for the token request.

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TokenEndpoint,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Body
    )
    Process {
        Write-Verbose -Message "Requesting token from endpoint: $TokenEndpoint"
        Write-Verbose -Message "Grant type: $($Body['grant_type'])"

        try {
            $response = Invoke-RestMethod -Uri $TokenEndpoint -Method Post -Body $Body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            Write-Verbose -Message "Token request successful. Token expires in $($response.expires_in) seconds."
            return $response
        }
        catch [System.Exception] {
            $errorMessage = $PSItem.Exception.Message

            # Try to parse error details from the response
            try {
                $errorDetails = $null
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    # PowerShell 7+
                    if ($PSItem.ErrorDetails.Message) {
                        $errorDetails = $PSItem.ErrorDetails.Message | ConvertFrom-Json
                    }
                }
                else {
                    # PowerShell 5.1
                    if ($PSItem.Exception.Response) {
                        $streamReader = [System.IO.StreamReader]::new($PSItem.Exception.Response.GetResponseStream())
                        $streamReader.BaseStream.Position = 0
                        $streamReader.DiscardBufferedData()
                        $errorDetails = $streamReader.ReadToEnd() | ConvertFrom-Json
                    }
                }

                if ($errorDetails) {
                    $errorMessage = "Token request failed: $($errorDetails.error) - $($errorDetails.error_description)"
                }
            }
            catch {
                # If we can't parse the error body, use the original exception message
            }

            throw $errorMessage
        }
    }
}
