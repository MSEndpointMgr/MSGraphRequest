function New-ClientAssertion {
    <#
    .SYNOPSIS
        Builds a signed JWT client assertion from an X509Certificate2 for certificate-based
        client credentials authentication.

    .DESCRIPTION
        Constructs a JWT with the required header (alg, typ, x5t) and payload (aud, iss, sub,
        jti, nbf, exp), then signs it with the certificate's RSA private key using RS256.
        The resulting JWT is used as the client_assertion parameter in the token request.

        The certificate's private key never leaves the process - only the signed assertion
        string is returned.

    .PARAMETER ClientId
        The application (client) ID of the app registration.

    .PARAMETER TenantId
        The Azure AD / Entra ID tenant ID (GUID or domain).

    .PARAMETER ClientCertificate
        The X509Certificate2 containing the private key used to sign the assertion.

    .PARAMETER LifetimeMinutes
        The lifetime of the assertion in minutes. Defaults to 5 to minimize replay risk.

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
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$ClientCertificate,

        [Parameter(Mandatory = $false)]
        [int]$LifetimeMinutes = 5
    )
    Process {
        # Validate the certificate has a private key
        if (-not $ClientCertificate.HasPrivateKey) {
            throw "The provided certificate does not contain a private key. A private key is required to sign the client assertion."
        }

        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        # Helper: Convert bytes to base64url string
        function ConvertTo-Base64Url {
            param([byte[]]$Bytes)
            [Convert]::ToBase64String($Bytes) -replace '\+', '-' -replace '/', '_' -replace '='
        }

        # Build x5t (base64url-encoded SHA-1 thumbprint of the certificate)
        $thumbprintBytes = $ClientCertificate.GetCertHash()  # SHA-1 by default
        $x5t = ConvertTo-Base64Url -Bytes $thumbprintBytes

        # Build JWT header
        $header = @{
            alg = "RS256"
            typ = "JWT"
            x5t = $x5t
        } | ConvertTo-Json -Compress

        # Build JWT payload
        $now = [DateTimeOffset]::UtcNow
        $payload = @{
            aud = $tokenEndpoint
            iss = $ClientId
            sub = $ClientId
            jti = [guid]::NewGuid().ToString()
            nbf = $now.ToUnixTimeSeconds()
            exp = $now.AddMinutes($LifetimeMinutes).ToUnixTimeSeconds()
        } | ConvertTo-Json -Compress

        # Encode header and payload as base64url
        $headerBase64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($header))
        $payloadBase64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($payload))

        # Construct the signing input
        $signingInput = "$headerBase64.$payloadBase64"

        # Sign with RSA-SHA256 using the certificate's private key
        $rsa = if ($ClientCertificate | Get-Member -Name 'GetRSAPrivateKey' -MemberType Method -ErrorAction SilentlyContinue) {
            $ClientCertificate.GetRSAPrivateKey()
        } else {
            $ClientCertificate.PrivateKey
        }
        if (-not $rsa) {
            throw "Could not extract RSA private key from the certificate."
        }
        $signatureBytes = $rsa.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $signatureBase64 = ConvertTo-Base64Url -Bytes $signatureBytes

        # Return the complete JWT
        return "$signingInput.$signatureBase64"
    }
}
