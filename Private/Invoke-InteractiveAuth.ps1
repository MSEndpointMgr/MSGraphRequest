function Invoke-InteractiveAuth {
    <#
    .SYNOPSIS
        Performs Authorization Code + PKCE interactive authentication via a localhost
        HTTP listener and the user's default browser.

    .DESCRIPTION
        1. Generates a PKCE code verifier and challenge.
        2. Starts a temporary HttpListener on a random high port.
        3. Opens the browser to the /authorize endpoint with prompt=select_account.
        4. Captures the redirect, validates the state parameter (CSRF protection),
           and extracts the authorization code.
        5. Exchanges the code + verifier for tokens via Invoke-TokenRequest.

        PKCE is mandatory - mitigates authorization code interception attacks.
        The state parameter is validated to prevent CSRF.
        Token values are never logged.

    .PARAMETER TenantId
        Azure AD / Entra ID tenant ID (GUID or domain).

    .PARAMETER ClientId
        Application (client) ID.

    .PARAMETER Scopes
        Space-separated scopes to request.

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
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scopes
    )
    Process {
        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        # 1. Generate PKCE code verifier & challenge
        $codeVerifierBytes = [byte[]]::new(32)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($codeVerifierBytes)
        $rng.Dispose()
        $codeVerifier = [Convert]::ToBase64String($codeVerifierBytes) -replace '\+', '-' -replace '/', '_' -replace '='

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $challengeHash = $sha256.ComputeHash(
            [System.Text.Encoding]::ASCII.GetBytes($codeVerifier)
        )
        $sha256.Dispose()
        $codeChallenge = [Convert]::ToBase64String($challengeHash) -replace '\+', '-' -replace '/', '_' -replace '='

        # 2. Pick a random localhost port and set up a temporary HTTP listener
        $port = Get-Random -Minimum 49152 -Maximum 65535
        $redirectUri = "http://localhost:$port/"
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($redirectUri)
        $listener.Start()

        # 3. Build and open the authorize URL (prompt=select_account forces account picker)
        $state = [guid]::NewGuid().ToString('N')
        $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?" + (
            @(
                "client_id=$ClientId"
                "response_type=code"
                "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
                "response_mode=query"
                "scope=$([uri]::EscapeDataString($Scopes))"
                "state=$state"
                "code_challenge=$codeChallenge"
                "code_challenge_method=S256"
                "prompt=select_account"
            ) -join '&'
        )

        Write-Host "[MSGraphRequest] Opening browser for sign-in..." -ForegroundColor Yellow
        Start-Process $authUrl

        # 4. Wait for the redirect (browser posts back)
        try {
            $httpContext = $listener.GetContext()  # blocks until browser redirects
            $query = $httpContext.Request.QueryString

            # Return a friendly page to the user
            $html = '<html><body><h3>Authentication complete - you can close this tab.</h3></body></html>'
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
            $httpContext.Response.ContentLength64 = $buffer.Length
            $httpContext.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $httpContext.Response.OutputStream.Close()

            # Validate state to prevent CSRF
            if ($query['state'] -ne $state) {
                throw "State mismatch - possible CSRF attack. Aborting authentication."
            }
            if ($query['error']) {
                throw "Authorization error: $($query['error']) - $($query['error_description'])"
            }
            $authCode = $query['code']
        }
        finally {
            $listener.Stop()
            $listener.Close()
        }

        # 5. Exchange auth code + verifier for tokens
        $tokenBody = @{
            client_id     = $ClientId
            scope         = $Scopes
            code          = $authCode
            redirect_uri  = $redirectUri
            grant_type    = 'authorization_code'
            code_verifier = $codeVerifier
        }

        $response = Invoke-TokenRequest -TokenEndpoint $tokenEndpoint -Body $tokenBody
        Write-Verbose -Message "Interactive authentication completed successfully."

        return $response
    }
}
