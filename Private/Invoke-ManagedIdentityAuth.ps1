function Invoke-ManagedIdentityAuth {
    <#
    .SYNOPSIS
        Acquires an access token using Azure Managed Identity (IMDS or App Service).

    .DESCRIPTION
        Supports two managed identity environments:
          - Azure VM (IMDS): Requests from http://169.254.169.254/metadata/identity/oauth2/token
            with the required Metadata: true header to prevent SSRF attacks.
          - App Service / Azure Functions: Requests from the IDENTITY_ENDPOINT environment variable
            with the X-IDENTITY-HEADER to validate caller identity.

        For user-assigned managed identity, the ManagedIdentityClientId parameter
        specifies which identity to use.

    .PARAMETER Resource
        The resource URI to request a token for. Defaults to 'https://graph.microsoft.com'.

    .PARAMETER ManagedIdentityClientId
        Optional. The client ID of a user-assigned managed identity. If omitted,
        the system-assigned managed identity is used.

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Resource = 'https://graph.microsoft.com',

        [Parameter(Mandatory = $false)]
        [string]$ManagedIdentityClientId
    )
    Process {
        # Determine which managed identity endpoint to use
        if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
            # App Service / Azure Functions environment
            Write-Verbose -Message "Detected App Service / Azure Functions managed identity environment."

            $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$([uri]::EscapeDataString($Resource))"
            if ($ManagedIdentityClientId) {
                $uri += "&client_id=$([uri]::EscapeDataString($ManagedIdentityClientId))"
            }

            $headers = @{
                "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER
            }
        }
        else {
            # Azure VM IMDS endpoint
            Write-Verbose -Message "Using Azure VM IMDS endpoint for managed identity."

            $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$([uri]::EscapeDataString($Resource))"
            if ($ManagedIdentityClientId) {
                $uri += "&client_id=$([uri]::EscapeDataString($ManagedIdentityClientId))"
            }

            # Metadata header is required - IMDS rejects requests without it to prevent SSRF
            $headers = @{
                "Metadata" = "true"
            }
        }

        try {
            Write-Verbose -Message "Requesting managed identity token for resource: $Resource"
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop

            # Normalise the response to match OAuth2 token response format
            # IMDS returns 'access_token', 'expires_in' (or 'expires_on' as epoch)
            $result = [PSCustomObject]@{
                access_token = $response.access_token
                expires_in   = if ($response.expires_in) {
                                   [int]$response.expires_in
                               }
                               elseif ($response.expires_on) {
                                   $expiresOnEpoch = [long]$response.expires_on
                                   $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                                   [int]($expiresOnEpoch - $nowEpoch)
                               }
                               else { 3600 }
                token_type   = if ($response.token_type) { $response.token_type } else { "Bearer" }
                resource     = if ($response.resource) { $response.resource } else { $Resource }
            }

            Write-Verbose -Message "Managed identity token acquired successfully. Expires in $($result.expires_in) seconds."
            return $result
        }
        catch [System.Exception] {
            $errorMessage = $PSItem.Exception.Message

            # Check if this is likely not a managed identity environment
            if ($errorMessage -match "Unable to connect|No connection|timeout|404") {
                throw "Managed identity token acquisition failed. Ensure this code is running in an Azure environment with managed identity enabled. Error: $errorMessage"
            }

            throw "Managed identity token acquisition failed: $errorMessage"
        }
    }
}
