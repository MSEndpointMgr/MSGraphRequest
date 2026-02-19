#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for Connect-MSGraphRequest and Disconnect-MSGraphRequest.
#>

# Import at script level so module is loaded during Pester discovery
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Initialize-TestModule

InModuleScope 'MSGraphRequest' {

    Describe 'Connect-MSGraphRequest' {

        BeforeEach {
            # Reset state before each test
            $script:MSGraphConnection = $null
            $script:AuthenticationHeader = $null
        }

        Context 'Token (BYOT) flow' {

            It 'Stores connection state with FlowType Token' {
                $jwt = New-TestJwt -Claims @{ upn = 'byot@contoso.com'; tid = 'byot-tenant' }
                Connect-MSGraphRequest -AccessToken $jwt

                $script:MSGraphConnection | Should -Not -BeNullOrEmpty
                $script:MSGraphConnection.FlowType | Should -Be 'Token'
                $script:MSGraphConnection.Token | Should -Be $jwt
                $script:MSGraphConnection.RefreshToken | Should -BeNullOrEmpty
            }

            It 'Creates authentication header with Bearer token' {
                $jwt = New-TestJwt
                Connect-MSGraphRequest -AccessToken $jwt

                $script:AuthenticationHeader | Should -Not -BeNullOrEmpty
                $script:AuthenticationHeader['Authorization'] | Should -BeLike 'Bearer *'
                $script:AuthenticationHeader['Content-Type'] | Should -Be 'application/json'
            }

            It 'Decodes token context when JWT is valid' {
                $jwt = New-TestJwt -Claims @{ upn = 'test@contoso.com'; tid = 'my-tenant' }
                Connect-MSGraphRequest -AccessToken $jwt

                $script:MSGraphConnection.Context | Should -Not -BeNullOrEmpty
                $script:MSGraphConnection.Context.Identity | Should -Be 'test@contoso.com'
                $script:MSGraphConnection.Context.TenantId | Should -Be 'my-tenant'
            }

            It 'Handles non-decodable token gracefully with 1-hour fallback expiry' {
                Mock Get-TokenContext { throw "Invalid JWT" }

                Connect-MSGraphRequest -AccessToken 'opaque-token-string'

                $script:MSGraphConnection | Should -Not -BeNullOrEmpty
                $script:MSGraphConnection.FlowType | Should -Be 'Token'
                $script:MSGraphConnection.Context | Should -BeNullOrEmpty
                $minutesUntilExpiry = ($script:MSGraphConnection.TokenExpiry - (Get-Date).ToUniversalTime()).TotalMinutes
                $minutesUntilExpiry | Should -BeGreaterThan 55
                $minutesUntilExpiry | Should -BeLessThan 65
            }
        }

        Context 'Interactive flow' {

            It 'Calls Invoke-InteractiveAuth and stores connection with RefreshToken' {
                $mockResponse = New-MockTokenResponse -IncludeRefreshToken -Claims @{ upn = 'interactive@contoso.com' }
                Mock Invoke-InteractiveAuth { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com'

                Should -Invoke Invoke-InteractiveAuth -Times 1 -Exactly
                $script:MSGraphConnection.FlowType | Should -Be 'Interactive'
                $script:MSGraphConnection.RefreshToken | Should -Be 'mock-refresh-token-value'
                $script:MSGraphConnection.TenantId | Should -Be 'contoso.onmicrosoft.com'
            }

            It 'Defaults ClientId to MS Graph PowerShell well-known app' {
                $mockResponse = New-MockTokenResponse -IncludeRefreshToken
                Mock Invoke-InteractiveAuth { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com'

                $script:MSGraphConnection.ClientId | Should -Be '14d82eec-204b-4c2f-b7e8-296a70dab67e'
            }

            It 'Accepts a custom ClientId' {
                $mockResponse = New-MockTokenResponse -IncludeRefreshToken
                Mock Invoke-InteractiveAuth { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com' -ClientId 'custom-app-id'

                $script:MSGraphConnection.ClientId | Should -Be 'custom-app-id'
            }

            It 'Sets default scopes to .default' {
                $mockResponse = New-MockTokenResponse -IncludeRefreshToken
                Mock Invoke-InteractiveAuth { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com'

                $script:MSGraphConnection.Scopes | Should -Be 'https://graph.microsoft.com/.default'
            }
        }

        Context 'DeviceCode flow' {

            It 'Calls Invoke-DeviceCodeAuth and stores connection' {
                $mockResponse = New-MockTokenResponse -IncludeRefreshToken -Claims @{ upn = 'device@contoso.com' }
                Mock Invoke-DeviceCodeAuth { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com' -DeviceCode

                Should -Invoke Invoke-DeviceCodeAuth -Times 1 -Exactly
                $script:MSGraphConnection.FlowType | Should -Be 'DeviceCode'
                $script:MSGraphConnection.RefreshToken | Should -Be 'mock-refresh-token-value'
                $script:MSGraphConnection.TenantId | Should -Be 'contoso.onmicrosoft.com'
            }
        }

        Context 'ClientSecret flow' {

            It 'Calls Invoke-TokenRequest with client_credentials grant and stores secret' {
                $mockResponse = New-MockTokenResponse -Claims @{ azp = 'secret-app' }
                Mock Invoke-TokenRequest { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com' -ClientId 'secret-app' -ClientSecret 's3cret!'

                Should -Invoke Invoke-TokenRequest -Times 1 -Exactly
                $script:MSGraphConnection.FlowType | Should -Be 'ClientSecret'
                $script:MSGraphConnection.ClientSecret | Should -Be 's3cret!'
                $script:MSGraphConnection.RefreshToken | Should -BeNullOrEmpty
                $script:MSGraphConnection.TenantId | Should -Be 'contoso.onmicrosoft.com'
            }

            It 'Builds correct token endpoint URL' {
                $mockResponse = New-MockTokenResponse
                Mock Invoke-TokenRequest { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'mytenant.onmicrosoft.com' -ClientId 'app1' -ClientSecret 'sec'

                $script:MSGraphConnection.TokenEndpoint | Should -Be 'https://login.microsoftonline.com/mytenant.onmicrosoft.com/oauth2/v2.0/token'
            }
        }

        Context 'ClientCertificate flow' {

            BeforeAll {
                $script:TestCert = New-SelfSignedCertificate `
                    -Subject 'CN=ConnectTest' `
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

            It 'Calls New-ClientAssertion and Invoke-TokenRequest, stores certificate and TenantId' {
                $mockResponse = New-MockTokenResponse -Claims @{ azp = 'cert-app' }
                Mock Invoke-TokenRequest { return $mockResponse }

                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com' -ClientId 'cert-app' -ClientCertificate $script:TestCert

                Should -Invoke Invoke-TokenRequest -Times 1 -Exactly
                $script:MSGraphConnection.FlowType | Should -Be 'ClientCertificate'
                $script:MSGraphConnection.ClientCertificate | Should -Not -BeNullOrEmpty
                $script:MSGraphConnection.TenantId | Should -Be 'contoso.onmicrosoft.com'
            }
        }

        Context 'ManagedIdentity flow' {

            It 'Calls Invoke-ManagedIdentityAuth and stores connection' {
                $mockResponse = [PSCustomObject]@{
                    access_token = New-TestJwt -Claims @{ azp = 'mi-app' }
                    expires_in   = 3600
                    token_type   = 'Bearer'
                    resource     = 'https://graph.microsoft.com'
                }
                Mock Invoke-ManagedIdentityAuth { return $mockResponse }

                Connect-MSGraphRequest -ManagedIdentity

                Should -Invoke Invoke-ManagedIdentityAuth -Times 1 -Exactly
                $script:MSGraphConnection.FlowType | Should -Be 'ManagedIdentity'
            }

            It 'Passes ManagedIdentityClientId for user-assigned MI' {
                $mockResponse = [PSCustomObject]@{
                    access_token = New-TestJwt
                    expires_in   = 3600
                    token_type   = 'Bearer'
                    resource     = 'https://graph.microsoft.com'
                }
                Mock Invoke-ManagedIdentityAuth { return $mockResponse }

                Connect-MSGraphRequest -ManagedIdentity -ManagedIdentityClientId 'user-mi-id'

                Should -Invoke Invoke-ManagedIdentityAuth -Times 1 -Exactly
                $script:MSGraphConnection.ClientId | Should -Be 'user-mi-id'
            }
        }

        Context 'Token expiry calculation' {

            It 'Subtracts 60 seconds from expires_in as safety buffer' {
                $mockResponse = New-MockTokenResponse -ExpiresIn 3600 -IncludeRefreshToken
                Mock Invoke-InteractiveAuth { return $mockResponse }

                $beforeConnect = (Get-Date).ToUniversalTime()
                Connect-MSGraphRequest -TenantId 'contoso.onmicrosoft.com'
                $afterConnect = (Get-Date).ToUniversalTime()

                $expectedMin = $beforeConnect.AddSeconds(3600 - 60)
                $expectedMax = $afterConnect.AddSeconds(3600 - 60)

                $script:MSGraphConnection.TokenExpiry | Should -BeGreaterOrEqual $expectedMin.AddSeconds(-2)
                $script:MSGraphConnection.TokenExpiry | Should -BeLessOrEqual $expectedMax.AddSeconds(2)
            }
        }
    }

    Describe 'Disconnect-MSGraphRequest' {

        BeforeEach {
            $jwt = New-TestJwt
            $script:MSGraphConnection = @{
                Token         = $jwt
                TokenExpiry   = (Get-Date).AddHours(1).ToUniversalTime()
                RefreshToken  = 'fake-refresh-token'
                TokenEndpoint = 'https://login.microsoftonline.com/t/oauth2/v2.0/token'
                ClientId      = 'test-client'
                TenantId      = 'test-tenant'
                ClientSecret  = 'secret-value'
                Scopes        = 'https://graph.microsoft.com/.default'
                FlowType      = 'ClientSecret'
                Context       = @{ Identity = 'test' }
            }
            $script:AuthenticationHeader = @{
                'Authorization' = 'Bearer fake'
                'Content-Type'  = 'application/json'
                'ExpiresOn'     = (Get-Date).AddHours(1)
            }
        }

        It 'Nulls the connection state' {
            Disconnect-MSGraphRequest

            $script:MSGraphConnection | Should -BeNullOrEmpty
        }

        It 'Nulls the authentication header' {
            Disconnect-MSGraphRequest

            $script:AuthenticationHeader | Should -BeNullOrEmpty
        }

        It 'Does not throw when already disconnected' {
            $script:MSGraphConnection = $null
            $script:AuthenticationHeader = $null

            { Disconnect-MSGraphRequest } | Should -Not -Throw
        }

        It 'Clears optional fields like ClientSecret and TenantId' {
            $script:MSGraphConnection.ClientSecret | Should -Be 'secret-value'

            Disconnect-MSGraphRequest

            $script:MSGraphConnection | Should -BeNullOrEmpty
        }
    }
}

AfterAll {
    Get-Module MSGraphRequest | Remove-Module -Force -ErrorAction SilentlyContinue
}
