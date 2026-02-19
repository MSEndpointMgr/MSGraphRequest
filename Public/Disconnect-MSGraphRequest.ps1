function Disconnect-MSGraphRequest {
    <#
    .SYNOPSIS
        Clears the current MSGraphRequest connection state.

    .DESCRIPTION
        Securely clears all stored tokens, refresh tokens, secrets, and connection
        metadata from script-scoped variables. After disconnecting, Graph operations
        will require a new Connect-MSGraphRequest call.

    .EXAMPLE
        Disconnect-MSGraphRequest

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created
    #>
    [CmdletBinding()]
    param()
    Process {
        # Clear the connection state — null out all sensitive fields
        if ($script:MSGraphConnection) {
            $script:MSGraphConnection.Token            = $null
            $script:MSGraphConnection.TokenExpiry       = $null
            $script:MSGraphConnection.RefreshToken      = $null
            $script:MSGraphConnection.TokenEndpoint     = $null
            $script:MSGraphConnection.ClientId          = $null
            $script:MSGraphConnection.Scopes            = $null
            $script:MSGraphConnection.FlowType          = $null
            $script:MSGraphConnection.Context           = $null

            # Clear optional fields that may exist depending on the flow
            if ($script:MSGraphConnection.ContainsKey('ClientSecret')) {
                $script:MSGraphConnection.ClientSecret = $null
            }
            if ($script:MSGraphConnection.ContainsKey('ClientCertificate')) {
                $script:MSGraphConnection.ClientCertificate = $null
            }
            if ($script:MSGraphConnection.ContainsKey('TenantId')) {
                $script:MSGraphConnection.TenantId = $null
            }

            $script:MSGraphConnection = $null
        }

        # Clear the authentication header
        $script:AuthenticationHeader = $null

        Write-Host "[MSGraphRequest] Disconnected. All tokens and connection state have been cleared." -ForegroundColor Yellow
    }
}
