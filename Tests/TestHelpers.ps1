#Requires -Module Pester
<#
.SYNOPSIS
    Shared test helpers and JWT token generators for MSGraphRequest Pester tests.

.DESCRIPTION
    Provides:
    - New-TestJwt: Generates a valid (unsigned) JWT with configurable claims for unit tests.
    - New-MockTokenResponse: Returns a mock OAuth2 token endpoint response.
    - Initialize-TestModule: Imports the local dev module so tests use it instead of any system-installed copy.

    Helper functions are defined at global scope so they remain accessible inside
    Pester v5 InModuleScope blocks.
#>

function Initialize-TestModule {
    <#
    .SYNOPSIS
        Imports the local development copy of MSGraphRequest, removing any previously
        loaded version first (including system-installed copies).
    #>
    $ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    $ManifestPath = Join-Path $ModuleRoot 'MSGraphRequest.psd1'

    # Remove any previously loaded version (system-installed 1.x, etc.)
    Get-Module -Name MSGraphRequest -All | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import the local development version
    Import-Module $ManifestPath -Force -ErrorAction Stop
}

function global:ConvertTo-Base64Url {
    <#
    .SYNOPSIS
        Encodes a byte array as a base64url string (no padding).
    #>
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes) -replace '\+', '-' -replace '/', '_' -replace '='
}

function global:New-TestJwt {
    <#
    .SYNOPSIS
        Creates a syntactically valid (but unsigned) JWT for unit testing.
    .PARAMETER Claims
        Hashtable of payload claims. Defaults provide a typical delegated token.
    #>
    param(
        [hashtable]$Claims = @{}
    )

    $now = [DateTimeOffset]::UtcNow

    $defaultClaims = @{
        aud  = 'https://graph.microsoft.com'
        iss  = 'https://login.microsoftonline.com/contoso.onmicrosoft.com/v2.0'
        iat  = $now.ToUnixTimeSeconds()
        exp  = $now.AddHours(1).ToUnixTimeSeconds()
        nbf  = $now.ToUnixTimeSeconds()
        tid  = '00000000-0000-0000-0000-000000000001'
        azp  = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        upn  = 'testuser@contoso.com'
        scp  = 'User.Read Directory.Read.All'
        sub  = 'test-subject-id'
    }

    # Merge — caller overrides win
    foreach ($key in $Claims.Keys) {
        $defaultClaims[$key] = $Claims[$key]
    }

    $header = @{ alg = 'none'; typ = 'JWT' } | ConvertTo-Json -Compress
    $payload = $defaultClaims | ConvertTo-Json -Compress

    $headerB64  = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($header))
    $payloadB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($payload))

    # Unsigned JWT: header.payload. (empty signature)
    return "$headerB64.$payloadB64."
}

function global:New-MockTokenResponse {
    <#
    .SYNOPSIS
        Returns a PSCustomObject that mimics an OAuth2 token endpoint response.
    .PARAMETER ExpiresIn
        Token lifetime in seconds. Default 3600.
    .PARAMETER IncludeRefreshToken
        If set, includes a refresh_token field.
    .PARAMETER Claims
        Optional claims hashtable passed through to New-TestJwt.
    #>
    param(
        [int]$ExpiresIn = 3600,
        [switch]$IncludeRefreshToken,
        [hashtable]$Claims = @{}
    )

    $response = [PSCustomObject]@{
        access_token  = New-TestJwt -Claims $Claims
        expires_in    = $ExpiresIn
        token_type    = 'Bearer'
        scope         = 'User.Read Directory.Read.All'
    }

    if ($IncludeRefreshToken) {
        $response | Add-Member -Type NoteProperty -Name 'refresh_token' -Value 'mock-refresh-token-value'
    }

    return $response
}
