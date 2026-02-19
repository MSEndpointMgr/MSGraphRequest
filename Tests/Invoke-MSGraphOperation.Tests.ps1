#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for Invoke-MSGraphOperation — request execution, paging,
    throttling, auto-refresh, and custom header preservation.
#>

# Import at script level so module is loaded during Pester discovery
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Initialize-TestModule

InModuleScope 'MSGraphRequest' {

    Describe 'Invoke-MSGraphOperation' {

        BeforeEach {
            # Set up a valid connection state for each test
            $script:MSGraphConnection = @{
                Token         = New-TestJwt
                TokenExpiry   = (Get-Date).AddHours(1).ToUniversalTime()
                RefreshToken  = 'test-refresh-token'
                TokenEndpoint = 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token'
                ClientId      = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
                TenantId      = 'contoso.onmicrosoft.com'
                Scopes        = 'https://graph.microsoft.com/.default'
                FlowType      = 'Interactive'
                Context       = $null
            }
            $script:AuthenticationHeader = @{
                'Authorization' = "Bearer $($script:MSGraphConnection.Token)"
                'Content-Type'  = 'application/json'
                'ExpiresOn'     = (Get-Date).AddHours(1)
            }
        }

        Context 'Prerequisites' {

            It 'Warns and breaks when no authentication header exists' {
                $script:AuthenticationHeader = $null

                $result = Invoke-MSGraphOperation -Get -Resource 'me' -WarningAction SilentlyContinue
                # The function breaks early — result should be null/empty
                $result | Should -BeNullOrEmpty
            }
        }

        Context 'GET requests' {

            It 'Constructs correct URI with v1.0 API version' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ displayName = 'Test User' }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'me'

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'https://graph.microsoft.com/v1.0/me'
                }
            }

            It 'Constructs correct URI with Beta API version' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ displayName = 'Test User' }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'me' -APIVersion 'Beta'

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'https://graph.microsoft.com/Beta/me'
                }
            }

            It 'Returns single item response correctly' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{
                        id          = '123'
                        displayName = 'Single User'
                    }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'users/123'

                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -Be 1
            }

            It 'Returns multiple items from value array' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = '1'; displayName = 'User A' }
                            [PSCustomObject]@{ id = '2'; displayName = 'User B' }
                        )
                    }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'users'

                $result.Count | Should -Be 2
            }

            It 'Handles empty result set (odata.count = 0)' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{
                        '@odata.count' = 0
                        value          = @()
                    }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'users?$filter=nonexistent'

                $result.Count | Should -Be 0
            }
        }

        Context 'Paging (nextLink)' {

            It 'Follows nextLink and aggregates all pages' {
                $script:_pagerCallCount = 0
                Mock Invoke-RestMethod {
                    $script:_pagerCallCount++
                    if ($script:_pagerCallCount -eq 1) {
                        return [PSCustomObject]@{
                            '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=page2'
                            value             = @(
                                [PSCustomObject]@{ id = '1' }
                                [PSCustomObject]@{ id = '2' }
                            )
                        }
                    }
                    else {
                        return [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{ id = '3' }
                            )
                        }
                    }
                }

                $result = Invoke-MSGraphOperation -Get -Resource 'users'

                Should -Invoke Invoke-RestMethod -Times 2 -Exactly
                $result.Count | Should -Be 3
            }
        }

        Context 'POST requests' {

            It 'Passes body and content type for POST' {
                $postBody = @{ displayName = 'New Group' } | ConvertTo-Json
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ id = 'new-id'; displayName = 'New Group' }
                }

                $result = Invoke-MSGraphOperation -Post -Resource 'groups' -Body $postBody

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body -ne $null
                }
            }

            It 'Allows POST without body' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ status = 'ok' }
                }

                { Invoke-MSGraphOperation -Post -Resource 'reports/getEmailActivityCounts' } | Should -Not -Throw
            }
        }

        Context 'PATCH requests' {

            It 'Passes body for PATCH' {
                $patchBody = @{ displayName = 'Updated' } | ConvertTo-Json
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ displayName = 'Updated' }
                }

                Invoke-MSGraphOperation -Patch -Resource 'groups/123' -Body $patchBody

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            }
        }

        Context 'DELETE requests' {

            It 'Sends DELETE without body' {
                Mock Invoke-RestMethod { return $null }

                Invoke-MSGraphOperation -Delete -Resource 'groups/123'

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE'
                }
            }
        }

        Context 'Automatic token refresh' {

            It 'Refreshes token when expiry is within 10 minutes (Interactive flow)' {
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(5).ToUniversalTime()

                $newToken = New-MockTokenResponse -IncludeRefreshToken -ExpiresIn 3600
                Mock Invoke-TokenRequest { return $newToken }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                Invoke-MSGraphOperation -Get -Resource 'me'

                Should -Invoke Invoke-TokenRequest -Times 1 -Exactly
                $script:MSGraphConnection.Token | Should -Be $newToken.access_token
            }

            It 'Does NOT refresh when token has more than 10 minutes remaining' {
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(30).ToUniversalTime()

                Mock Invoke-TokenRequest { throw "Should not be called" }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                { Invoke-MSGraphOperation -Get -Resource 'me' } | Should -Not -Throw
                Should -Invoke Invoke-TokenRequest -Times 0 -Exactly
            }

            It 'Refreshes ClientSecret flow with client_credentials grant' {
                $script:MSGraphConnection.FlowType = 'ClientSecret'
                $script:MSGraphConnection.ClientSecret = 'the-secret'
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(2).ToUniversalTime()

                $newToken = New-MockTokenResponse -ExpiresIn 3600
                Mock Invoke-TokenRequest {
                    return $newToken
                }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                Invoke-MSGraphOperation -Get -Resource 'me'

                Should -Invoke Invoke-TokenRequest -Times 1 -Exactly
            }

            It 'Warns when BYOT token is expiring' {
                $script:MSGraphConnection.FlowType = 'Token'
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(2).ToUniversalTime()
                $script:MSGraphConnection.RefreshToken = $null

                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                $warnMsg = $null
                $result = Invoke-MSGraphOperation -Get -Resource 'me' -WarningVariable warnMsg 3>&1

                $warnMsg | Should -Not -BeNullOrEmpty
            }

            It 'Warns when Interactive flow has no refresh token' {
                $script:MSGraphConnection.FlowType = 'Interactive'
                $script:MSGraphConnection.RefreshToken = $null
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(2).ToUniversalTime()

                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                $warnMsg = $null
                $result = Invoke-MSGraphOperation -Get -Resource 'me' -WarningVariable warnMsg 3>&1

                $warnMsg | Should -Not -BeNullOrEmpty
            }

            It 'Preserves custom header items across token refresh' {
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(2).ToUniversalTime()
                $script:AuthenticationHeader['consistencylevel'] = 'eventual'
                $script:AuthenticationHeader['X-Custom'] = 'test-value'

                $newToken = New-MockTokenResponse -IncludeRefreshToken -ExpiresIn 3600
                Mock Invoke-TokenRequest { return $newToken }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                Invoke-MSGraphOperation -Get -Resource 'me'

                $script:AuthenticationHeader['consistencylevel'] | Should -Be 'eventual'
                $script:AuthenticationHeader['X-Custom'] | Should -Be 'test-value'
                $script:AuthenticationHeader['Authorization'] | Should -BeLike 'Bearer *'
            }

            It 'Continues with current token if refresh fails' {
                $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(2).ToUniversalTime()
                $originalToken = $script:MSGraphConnection.Token

                Mock Invoke-TokenRequest { throw "Token endpoint unavailable" }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = '1' } }

                { Invoke-MSGraphOperation -Get -Resource 'me' } | Should -Not -Throw
                $script:MSGraphConnection.Token | Should -Be $originalToken
            }
        }

        Context 'Headers passed to Invoke-RestMethod' {

            It 'Passes the authentication header to the HTTP request' {
                Mock Invoke-RestMethod {
                    $Headers['Authorization'] | Should -BeLike 'Bearer *'
                    return [PSCustomObject]@{ id = '1' }
                }

                Invoke-MSGraphOperation -Get -Resource 'me'

                Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            }
        }
    }
}

AfterAll {
    Get-Module MSGraphRequest | Remove-Module -Force -ErrorAction SilentlyContinue
}
