function Connect-MSGraphRequest {
    <#
    .SYNOPSIS
        Authenticates to Microsoft Graph and stores the connection for subsequent calls.

    .DESCRIPTION
        Single entry-point for authentication supporting six flows, all using native REST
        calls with zero SDK dependencies:

          - Interactive: Authorization Code + PKCE via browser with localhost redirect.
          - DeviceCode: Device code flow for environments without a browser.
          - ClientSecret: Client credentials with a secret.
          - ClientCertificate: Client credentials with a signed JWT assertion.
          - ManagedIdentity: Azure IMDS or App Service managed identity.
          - Token: Bring your own pre-acquired access token.

        After connecting, the module stores connection state in script-scoped variables
        and displays account context information.

    .PARAMETER TenantId
        Azure AD / Entra ID tenant ID (GUID or domain).

    .PARAMETER ClientId
        Application (client) ID. Defaults to the well-known Microsoft Graph PowerShell
        app (14d82eec-204b-4c2f-b7e8-296a70dab67e) for Interactive and DeviceCode flows.

    .PARAMETER ClientSecret
        Client secret for app registration (client credentials flow).

    .PARAMETER ClientCertificate
        X509Certificate2 with private key for certificate-based client credentials.

    .PARAMETER DeviceCode
        Switch to use device code flow for authentication.

    .PARAMETER Scopes
        Space-separated scopes to request. Defaults vary by flow:
        - Interactive/DeviceCode: 'https://graph.microsoft.com/.default'
        - ClientSecret/ClientCertificate: 'https://graph.microsoft.com/.default'

    .PARAMETER AccessToken
        Provide an already-acquired access token directly (skips token acquisition).

    .PARAMETER ManagedIdentity
        Switch to use Azure Managed Identity for authentication.

    .PARAMETER ManagedIdentityClientId
        Client ID of a user-assigned managed identity. If omitted with -ManagedIdentity,
        the system-assigned identity is used.

    .EXAMPLE
        Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com"
        # Interactive browser sign-in using the default MS Graph PowerShell app.

    .EXAMPLE
        Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -DeviceCode
        # Device code flow - displays a code for the user to enter at https://microsoft.com/devicelogin.

    .EXAMPLE
        Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -ClientId "00000000-..." -ClientSecret "s3cret!"
        # Client credentials with a secret.

    .EXAMPLE
        Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -ClientId "00000000-..." -ClientCertificate $cert
        # Client credentials with a certificate.

    .EXAMPLE
        Connect-MSGraphRequest -ManagedIdentity
        # Azure Managed Identity (system-assigned).

    .EXAMPLE
        Connect-MSGraphRequest -AccessToken $myToken
        # Bring your own token.

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2026-02-19

        Version history:
        1.0.0 - (2026-02-19) Script created - native REST, zero SDK dependencies
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Interactive', HelpMessage = "Azure AD / Entra ID tenant ID (GUID or domain).")]
        [Parameter(Mandatory = $true, ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCertificate')]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
        [Parameter(Mandatory = $false, ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCertificate')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret', HelpMessage = "Client secret for the app registration.")]
        [ValidateNotNullOrEmpty()]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCertificate', HelpMessage = "X509Certificate2 with private key for certificate auth.")]
        [ValidateNotNull()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$ClientCertificate,

        [Parameter(Mandatory = $true, ParameterSetName = 'DeviceCode', HelpMessage = "Use device code flow for authentication.")]
        [switch]$DeviceCode,

        [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
        [Parameter(Mandatory = $false, ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ClientCertificate')]
        [string]$Scopes,

        [Parameter(Mandatory = $true, ParameterSetName = 'Token', HelpMessage = "Provide a pre-acquired access token.")]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ManagedIdentity', HelpMessage = "Use Azure Managed Identity.")]
        [switch]$ManagedIdentity,

        [Parameter(Mandatory = $false, ParameterSetName = 'ManagedIdentity', HelpMessage = "Client ID of a user-assigned managed identity.")]
        [string]$ManagedIdentityClientId
    )
    Process {
        # Well-known Microsoft Graph PowerShell application ID
        $GraphPSAppId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
        $defaultScopes = "https://graph.microsoft.com/.default"

        # --- Bring-Your-Own-Token ---
        if ($PSCmdlet.ParameterSetName -eq 'Token') {
            try {
                $context = Get-TokenContext -Token $AccessToken
                $tokenExpiry = if ($context.ExpiresOn) { $context.ExpiresOn } else { (Get-Date).AddHours(1).ToUniversalTime() }
            }
            catch {
                Write-Warning -Message "Could not decode the provided token. Assuming 1-hour expiry."
                $context = $null
                $tokenExpiry = (Get-Date).AddHours(1).ToUniversalTime()
            }

            $script:MSGraphConnection = @{
                Token         = $AccessToken
                TokenExpiry   = $tokenExpiry
                RefreshToken  = $null
                TokenEndpoint = $null
                ClientId      = $null
                Scopes        = $null
                FlowType      = 'Token'
                Context       = $context
            }

            $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $AccessToken -ExpiresOn $tokenExpiry
            Write-Host "[MSGraphRequest] Connected using provided token." -ForegroundColor Green
            if ($context) {
                Write-Host "  Identity: $($context.Identity) | Tenant: $($context.TenantId) | Expires: $($tokenExpiry.ToLocalTime())" -ForegroundColor Gray
            }
            return
        }

        # --- Managed Identity ---
        if ($PSCmdlet.ParameterSetName -eq 'ManagedIdentity') {
            $miParams = @{}
            if ($ManagedIdentityClientId) {
                $miParams['ManagedIdentityClientId'] = $ManagedIdentityClientId
            }

            $response = Invoke-ManagedIdentityAuth @miParams
            $tokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60).ToUniversalTime()

            $context = $null
            try { $context = Get-TokenContext -Token $response.access_token } catch { }

            $script:MSGraphConnection = @{
                Token                  = $response.access_token
                TokenExpiry            = $tokenExpiry
                RefreshToken           = $null
                TokenEndpoint          = $null
                ClientId               = $ManagedIdentityClientId
                Scopes                 = $null
                FlowType               = 'ManagedIdentity'
                Context                = $context
            }

            $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $response.access_token -ExpiresOn $tokenExpiry
            Write-Host "[MSGraphRequest] Connected using Managed Identity." -ForegroundColor Green
            return
        }

        # Default ClientId for interactive / device code flows
        if (-not $ClientId) { $ClientId = $GraphPSAppId }
        if (-not $Scopes) { $Scopes = $defaultScopes }

        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        switch ($PSCmdlet.ParameterSetName) {
            'Interactive' {
                $response = Invoke-InteractiveAuth -TenantId $TenantId -ClientId $ClientId -Scopes $Scopes
                $tokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60).ToUniversalTime()

                $context = $null
                try { $context = Get-TokenContext -Token $response.access_token } catch { }

                $script:MSGraphConnection = @{
                    Token         = $response.access_token
                    TokenExpiry   = $tokenExpiry
                    RefreshToken  = $response.refresh_token
                    TokenEndpoint = $tokenEndpoint
                    ClientId      = $ClientId
                    TenantId      = $TenantId
                    Scopes        = $Scopes
                    FlowType      = 'Interactive'
                    Context       = $context
                }

                $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $response.access_token -ExpiresOn $tokenExpiry
                Write-Host "[MSGraphRequest] Connected via interactive browser sign-in." -ForegroundColor Green
                if ($context) {
                    Write-Host "  Identity: $($context.Identity) | Tenant: $($context.TenantId) | Expires: $($tokenExpiry.ToLocalTime())" -ForegroundColor Gray
                }
            }

            'DeviceCode' {
                $response = Invoke-DeviceCodeAuth -TenantId $TenantId -ClientId $ClientId -Scopes $Scopes
                $tokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60).ToUniversalTime()

                $context = $null
                try { $context = Get-TokenContext -Token $response.access_token } catch { }

                $script:MSGraphConnection = @{
                    Token         = $response.access_token
                    TokenExpiry   = $tokenExpiry
                    RefreshToken  = $response.refresh_token
                    TokenEndpoint = $tokenEndpoint
                    ClientId      = $ClientId
                    TenantId      = $TenantId
                    Scopes        = $Scopes
                    FlowType      = 'DeviceCode'
                    Context       = $context
                }

                $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $response.access_token -ExpiresOn $tokenExpiry
                Write-Host "[MSGraphRequest] Connected via device code flow." -ForegroundColor Green
                if ($context) {
                    Write-Host "  Identity: $($context.Identity) | Tenant: $($context.TenantId) | Expires: $($tokenExpiry.ToLocalTime())" -ForegroundColor Gray
                }
            }

            'ClientSecret' {
                $body = @{
                    client_id     = $ClientId
                    scope         = $Scopes
                    client_secret = $ClientSecret
                    grant_type    = 'client_credentials'
                }
                $response = Invoke-TokenRequest -TokenEndpoint $tokenEndpoint -Body $body
                $tokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60).ToUniversalTime()

                $context = $null
                try { $context = Get-TokenContext -Token $response.access_token } catch { }

                $script:MSGraphConnection = @{
                    Token         = $response.access_token
                    TokenExpiry   = $tokenExpiry
                    RefreshToken  = $null
                    TokenEndpoint = $tokenEndpoint
                    ClientId      = $ClientId
                    TenantId      = $TenantId
                    ClientSecret  = $ClientSecret
                    Scopes        = $Scopes
                    FlowType      = 'ClientSecret'
                    Context       = $context
                }

                $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $response.access_token -ExpiresOn $tokenExpiry
                Write-Host "[MSGraphRequest] Connected via client credentials (secret)." -ForegroundColor Green
                if ($context) {
                    Write-Host "  App: $($context.Identity) | Tenant: $($context.TenantId) | Expires: $($tokenExpiry.ToLocalTime())" -ForegroundColor Gray
                }
            }

            'ClientCertificate' {
                $clientAssertion = New-ClientAssertion -ClientId $ClientId -TenantId $TenantId -ClientCertificate $ClientCertificate

                $body = @{
                    client_id             = $ClientId
                    scope                 = $Scopes
                    client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                    client_assertion      = $clientAssertion
                    grant_type            = 'client_credentials'
                }
                $response = Invoke-TokenRequest -TokenEndpoint $tokenEndpoint -Body $body
                $tokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60).ToUniversalTime()

                $context = $null
                try { $context = Get-TokenContext -Token $response.access_token } catch { }

                $script:MSGraphConnection = @{
                    Token              = $response.access_token
                    TokenExpiry        = $tokenExpiry
                    RefreshToken       = $null
                    TokenEndpoint      = $tokenEndpoint
                    ClientId           = $ClientId
                    ClientCertificate  = $ClientCertificate
                    TenantId           = $TenantId
                    Scopes             = $Scopes
                    FlowType           = 'ClientCertificate'
                    Context            = $context
                }

                $script:AuthenticationHeader = New-AuthenticationHeader -AccessToken $response.access_token -ExpiresOn $tokenExpiry
                Write-Host "[MSGraphRequest] Connected via client credentials (certificate)." -ForegroundColor Green
                if ($context) {
                    Write-Host "  App: $($context.Identity) | Tenant: $($context.TenantId) | Expires: $($tokenExpiry.ToLocalTime())" -ForegroundColor Gray
                }
            }
        }
    }
}
