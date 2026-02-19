function Show-AuthenticationInfo {
    <#
    .SYNOPSIS
        Shows info about the current MSGraphRequest connection and access token.

    .DESCRIPTION
        Displays connection state including identity, tenant, scopes, expiry, and
        authentication header items. Use -FullDetails to decode and display the
        full JWT token payload.

    .PARAMETER FullDetails
        If specified, decodes the JWT token and includes the full payload in the output.

    .NOTES
        Author:      Jan Ketil Skanke
        Contact:     @JankeSkanke
        Created:     2021-08-24
        Updated:     2026-02-19

        Version history:
        1.0.0 - (2021-08-24) Script created
        1.0.1 - (2023-12-04) Added option Full to decode JWT token
        2.0.0 - (2026-02-19) Rewritten to use script-scoped state and ConvertFrom-JwtToken helper
    #>
    param(
        [Parameter(Mandatory = $false)]
        [switch]$FullDetails
    )
    Process {
        if (-not $script:MSGraphConnection -or -not $script:AuthenticationHeader) {
            Write-Warning -Message "No active connection found. Use Connect-MSGraphRequest before running this function."
            return
        }

        # Build the response object
        $Response = [PSCustomObject]@{
            FlowType      = $script:MSGraphConnection.FlowType
            TokenExpiry   = if ($script:MSGraphConnection.TokenExpiry) { $script:MSGraphConnection.TokenExpiry.ToLocalTime() } else { "Unknown" }
        }

        # Add context info if available
        if ($script:MSGraphConnection.Context) {
            $ctx = $script:MSGraphConnection.Context
            $Response | Add-Member -Type "NoteProperty" -Name "Identity" -Value $ctx.Identity
            $Response | Add-Member -Type "NoteProperty" -Name "TokenType" -Value $ctx.TokenType
            $Response | Add-Member -Type "NoteProperty" -Name "TenantId" -Value $ctx.TenantId
            $Response | Add-Member -Type "NoteProperty" -Name "Scopes" -Value $ctx.Scopes
            $Response | Add-Member -Type "NoteProperty" -Name "AppId" -Value $ctx.AppId
        }

        # Add header items (excluding Authorization and ExpiresOn for security)
        $headerItems = @{}
        foreach ($key in $script:AuthenticationHeader.Keys) {
            if ($key -notin @('Authorization', 'ExpiresOn')) {
                $headerItems[$key] = $script:AuthenticationHeader[$key]
            }
        }
        if ($headerItems.Count -gt 0) {
            $Response | Add-Member -Type "NoteProperty" -Name "HeaderItems" -Value $headerItems
        }

        # Full JWT decode if requested
        if ($FullDetails -and $script:MSGraphConnection.Token) {
            try {
                $decoded = ConvertFrom-JwtToken -Token $script:MSGraphConnection.Token
                $Response | Add-Member -Type "NoteProperty" -Name "DecodedToken" -Value $decoded.Payload
            }
            catch {
                Write-Warning -Message "Could not decode the access token: $($_.Exception.Message)"
            }
        }

        return $Response
    }
}