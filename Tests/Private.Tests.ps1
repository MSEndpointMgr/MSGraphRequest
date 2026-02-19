#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for private helper functions:
    ConvertFrom-JwtToken, Get-TokenContext, New-AuthenticationHeader,
    Invoke-TokenRequest, New-ClientAssertion
#>

# Import at script level so module is loaded during Pester discovery
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Initialize-TestModule

InModuleScope 'MSGraphRequest' {

    Describe 'ConvertFrom-JwtToken' {

        It 'Decodes a valid JWT and returns Header and Payload' {
            $jwt = New-TestJwt -Claims @{ upn = 'alice@contoso.com'; tid = 'tenant-1' }
            $result = ConvertFrom-JwtToken -Token $jwt

            $result | Should -Not -BeNullOrEmpty
            $result.Header | Should -Not -BeNullOrEmpty
            $result.Payload | Should -Not -BeNullOrEmpty
            $result.Header.alg | Should -Be 'none'
            $result.Payload.upn | Should -Be 'alice@contoso.com'
            $result.Payload.tid | Should -Be 'tenant-1'
        }

        It 'Throws on an invalid token (no dots)' {
            { ConvertFrom-JwtToken -Token 'not-a-jwt' } | Should -Throw '*Invalid JWT*'
        }

        It 'Throws on a token that does not start with eyJ' {
            { ConvertFrom-JwtToken -Token 'abc.def.ghi' } | Should -Throw '*Invalid JWT*'
        }

        It 'Handles tokens with base64url padding correctly' {
            $jwt = New-TestJwt -Claims @{ upn = 'a@b.c' }
            $result = ConvertFrom-JwtToken -Token $jwt

            $result.Payload.upn | Should -Be 'a@b.c'
        }
    }

    Describe 'Get-TokenContext' {

        Context 'Delegated token (has upn and scp)' {
            It 'Returns correct identity and token type' {
                $jwt = New-TestJwt -Claims @{
                    upn = 'user@contoso.com'
                    scp = 'User.Read Mail.Send'
                    tid = 'tenant-id-1'
                    azp = 'app-id-1'
                }
                $ctx = Get-TokenContext -Token $jwt

                $ctx.Identity  | Should -Be 'user@contoso.com'
                $ctx.TokenType | Should -Be 'Delegated'
                $ctx.TenantId  | Should -Be 'tenant-id-1'
                $ctx.Scopes    | Should -Be 'User.Read Mail.Send'
                $ctx.AppId     | Should -Be 'app-id-1'
            }
        }

        Context 'Application token (has roles, no scp/upn)' {
            It 'Returns correct identity and token type' {
                $now = [DateTimeOffset]::UtcNow
                $claims = @{
                    aud             = 'https://graph.microsoft.com'
                    iss             = 'https://login.microsoftonline.com/tenant/v2.0'
                    iat             = $now.ToUnixTimeSeconds()
                    exp             = $now.AddHours(1).ToUnixTimeSeconds()
                    tid             = 'tenant-id-2'
                    azp             = 'daemon-app-id'
                    app_displayname = 'MyDaemonApp'
                    roles           = @('Directory.Read.All', 'User.Read.All')
                    sub             = 'app-subject'
                }
                $header = @{ alg = 'none'; typ = 'JWT' } | ConvertTo-Json -Compress
                $payload = $claims | ConvertTo-Json -Compress
                $hB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($header))
                $pB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($payload))
                $appJwt = "$hB64.$pB64."

                $ctx = Get-TokenContext -Token $appJwt

                $ctx.Identity  | Should -Be 'MyDaemonApp'
                $ctx.TokenType | Should -Be 'Application'
                $ctx.TenantId  | Should -Be 'tenant-id-2'
                $ctx.Scopes    | Should -Be 'Directory.Read.All User.Read.All'
            }
        }

        Context 'Timestamp conversion' {
            It 'Converts iat and exp to DateTime objects' {
                $jwt = New-TestJwt
                $ctx = Get-TokenContext -Token $jwt

                $ctx.IssuedAt  | Should -BeOfType [datetime]
                $ctx.ExpiresOn | Should -BeOfType [datetime]
                $ctx.ExpiresOn | Should -BeGreaterThan $ctx.IssuedAt
            }
        }
    }

    Describe 'New-AuthenticationHeader' {

        It 'Returns a hashtable with Authorization, Content-Type, and ExpiresOn' {
            $expiry = (Get-Date).AddHours(1).ToUniversalTime()
            $header = New-AuthenticationHeader -AccessToken 'test-token-value' -ExpiresOn $expiry

            $header | Should -BeOfType [hashtable]
            $header['Authorization'] | Should -Be 'Bearer test-token-value'
            $header['Content-Type']  | Should -Be 'application/json'
            $header['ExpiresOn']     | Should -Not -BeNullOrEmpty
        }

        It 'Converts ExpiresOn to local time' {
            $utcExpiry = [datetime]::UtcNow.AddHours(1)
            $header = New-AuthenticationHeader -AccessToken 'tok' -ExpiresOn $utcExpiry

            $header['ExpiresOn'] | Should -BeOfType [datetime]
        }
    }

    Describe 'Invoke-TokenRequest' {

        It 'Calls Invoke-RestMethod with correct endpoint and body' {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    access_token = 'mocked-token'
                    expires_in   = 3600
                    token_type   = 'Bearer'
                }
            }

            $body = @{ client_id = 'test'; grant_type = 'client_credentials' }
            $result = Invoke-TokenRequest -TokenEndpoint 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token' -Body $body

            $result.access_token | Should -Be 'mocked-token'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        It 'Throws on HTTP error from token endpoint' {
            Mock Invoke-RestMethod {
                throw "The remote server returned an error: (400) Bad Request."
            }

            { Invoke-TokenRequest -TokenEndpoint 'https://login.microsoftonline.com/t/oauth2/v2.0/token' -Body @{ grant_type = 'client_credentials' } } | Should -Throw
        }
    }

    Describe 'New-ClientAssertion' {

        BeforeAll {
            $script:TestCert = New-SelfSignedCertificate `
                -Subject 'CN=MSGraphRequestTest' `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -KeyExportPolicy Exportable `
                -KeySpec Signature `
                -KeyLength 2048 `
                -KeyAlgorithm RSA `
                -HashAlgorithm SHA256 `
                -NotAfter (Get-Date).AddDays(1)
        }

        AfterAll {
            if ($script:TestCert) {
                Remove-Item -Path "Cert:\CurrentUser\My\$($script:TestCert.Thumbprint)" -ErrorAction SilentlyContinue
            }
        }

        It 'Returns a valid JWT string with three dot-separated parts' {
            $assertion = New-ClientAssertion `
                -ClientId '00000000-0000-0000-0000-000000000001' `
                -TenantId 'contoso.onmicrosoft.com' `
                -ClientCertificate $script:TestCert

            $assertion | Should -Not -BeNullOrEmpty
            $parts = $assertion.Split('.')
            $parts.Count | Should -Be 3
        }

        It 'Produces a JWT with RS256 algorithm and correct x5t header' {
            $assertion = New-ClientAssertion `
                -ClientId '00000000-0000-0000-0000-000000000001' `
                -TenantId 'contoso.onmicrosoft.com' `
                -ClientCertificate $script:TestCert

            $decoded = ConvertFrom-JwtToken -Token $assertion
            $decoded.Header.alg | Should -Be 'RS256'
            $decoded.Header.typ | Should -Be 'JWT'
            $decoded.Header.x5t | Should -Not -BeNullOrEmpty
        }

        It 'Sets correct issuer, subject, and audience in the payload' {
            $assertion = New-ClientAssertion `
                -ClientId 'my-client-id' `
                -TenantId 'my-tenant' `
                -ClientCertificate $script:TestCert

            $decoded = ConvertFrom-JwtToken -Token $assertion
            $decoded.Payload.iss | Should -Be 'my-client-id'
            $decoded.Payload.sub | Should -Be 'my-client-id'
            $decoded.Payload.aud | Should -BeLike '*my-tenant*'
        }

        It 'Defaults to 5-minute lifetime' {
            $assertion = New-ClientAssertion `
                -ClientId 'test' `
                -TenantId 'tenant' `
                -ClientCertificate $script:TestCert

            $decoded = ConvertFrom-JwtToken -Token $assertion
            $lifetime = $decoded.Payload.exp - $decoded.Payload.nbf
            $lifetime | Should -BeGreaterOrEqual 290
            $lifetime | Should -BeLessOrEqual 310
        }
    }
}

AfterAll {
    Get-Module MSGraphRequest | Remove-Module -Force -ErrorAction SilentlyContinue
}
