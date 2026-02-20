function ConvertFrom-JwtToken {
    <#
    .SYNOPSIS
        Decodes a JWT token payload from base64url to a PSObject.

    .DESCRIPTION
        Splits a JWT into its three parts (header, payload, signature), decodes the
        header and payload from base64url encoding, and returns them as a PSCustomObject
        with Header and Payload properties.

    .PARAMETER Token
        The raw JWT string (e.g. an access token).

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "The raw JWT token string to decode.")]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )
    Process {
        # Validate basic JWT structure
        if (-not $Token.Contains(".") -or -not $Token.StartsWith("eyJ")) {
            throw "Invalid JWT token format."
        }

        $parts = $Token.Split(".")
        if ($parts.Count -lt 2) {
            throw "Invalid JWT token format - expected at least 2 dot-separated parts."
        }

        # Decode header
        $headerBase64 = $parts[0].Replace('-', '+').Replace('_', '/')
        while ($headerBase64.Length % 4) { $headerBase64 += "=" }
        $headerJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($headerBase64))
        $header = $headerJson | ConvertFrom-Json

        # Decode payload
        $payloadBase64 = $parts[1].Replace('-', '+').Replace('_', '/')
        while ($payloadBase64.Length % 4) { $payloadBase64 += "=" }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payloadBase64))
        $payload = $payloadJson | ConvertFrom-Json

        # Return result
        return [PSCustomObject]@{
            Header  = $header
            Payload = $payload
        }
    }
}
