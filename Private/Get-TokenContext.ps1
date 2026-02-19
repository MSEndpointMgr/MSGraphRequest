function Get-TokenContext {
    <#
    .SYNOPSIS
        Extracts display-friendly context information from a decoded JWT token.

    .DESCRIPTION
        Takes a raw JWT access token string, decodes it using ConvertFrom-JwtToken,
        and returns a PSCustomObject with user/app identity, tenant, scopes, and expiry.

    .PARAMETER Token
        The raw JWT access token string.

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "The raw JWT access token string.")]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )
    Process {
        $decoded = ConvertFrom-JwtToken -Token $Token
        $payload = $decoded.Payload

        # Determine identity — delegated tokens have 'upn', app tokens have 'app_displayname' or 'azp'
        $identity = if ($payload.upn) { $payload.upn }
                    elseif ($payload.unique_name) { $payload.unique_name }
                    elseif ($payload.app_displayname) { $payload.app_displayname }
                    elseif ($payload.azp) { $payload.azp }
                    else { "Unknown" }

        # Determine token type
        $tokenType = if ($payload.scp) { "Delegated" } else { "Application" }

        # Convert epoch timestamps to DateTime
        $issuedAt = if ($payload.iat) {
            [DateTimeOffset]::FromUnixTimeSeconds([long]$payload.iat).UtcDateTime
        } else { $null }

        $expiresOn = if ($payload.exp) {
            [DateTimeOffset]::FromUnixTimeSeconds([long]$payload.exp).UtcDateTime
        } else { $null }

        # Extract scopes or roles
        $scopes = if ($payload.scp) { $payload.scp }
                  elseif ($payload.roles) { $payload.roles -join " " }
                  else { "N/A" }

        return [PSCustomObject]@{
            Identity  = $identity
            TokenType = $tokenType
            TenantId  = if ($payload.tid) { $payload.tid } else { "Unknown" }
            Audience  = if ($payload.aud) { $payload.aud } else { "Unknown" }
            Scopes    = $scopes
            IssuedAt  = $issuedAt
            ExpiresOn = $expiresOn
            AppId     = if ($payload.azp) { $payload.azp } elseif ($payload.appid) { $payload.appid } else { "Unknown" }
        }
    }
}
