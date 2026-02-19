#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for remaining public functions:
    Test-AccessToken, Show-AuthenticationInfo,
    Add-AuthenticationHeaderItem, Remove-AuthenticationHeaderItem
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TestModule
}

InModuleScope 'MSGraphRequest' {

    Describe 'Test-AccessToken' {

        BeforeEach {
            $script:MSGraphConnection = @{
                Token       = New-TestJwt
                TokenExpiry = (Get-Date).AddHours(1).ToUniversalTime()
                FlowType    = 'Interactive'
            }
            $script:AuthenticationHeader = @{
                'Authorization' = 'Bearer fake'
                'Content-Type'  = 'application/json'
                'ExpiresOn'     = (Get-Date).AddHours(1)
            }
        }

        It 'Returns $true when token is not near expiry' {
            $script:MSGraphConnection.TokenExpiry = (Get-Date).AddHours(1).ToUniversalTime()

            $result = Test-AccessToken -RenewalThresholdMinutes 10

            $result | Should -BeTrue
        }

        It 'Returns $false when token is within threshold' {
            $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(5).ToUniversalTime()

            $result = Test-AccessToken -RenewalThresholdMinutes 10

            $result | Should -BeFalse
        }

        It 'Returns $false when token is already expired' {
            $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(-5).ToUniversalTime()

            $result = Test-AccessToken

            $result | Should -BeFalse
        }

        It 'Returns $false and warns when no connection exists' {
            $script:MSGraphConnection = $null

            $result = Test-AccessToken -WarningAction SilentlyContinue

            $result | Should -BeFalse
        }

        It 'Uses default threshold of 10 minutes' {
            $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(9).ToUniversalTime()

            $result = Test-AccessToken

            $result | Should -BeFalse
        }

        It 'Accepts custom threshold' {
            $script:MSGraphConnection.TokenExpiry = (Get-Date).AddMinutes(25).ToUniversalTime()

            $result = Test-AccessToken -RenewalThresholdMinutes 30

            $result | Should -BeFalse
        }
    }

    Describe 'Show-AuthenticationInfo' {

        BeforeEach {
            $jwt = New-TestJwt -Claims @{
                upn = 'show@contoso.com'
                tid = 'show-tenant'
                scp = 'User.Read'
                azp = 'show-app-id'
            }
            $context = Get-TokenContext -Token $jwt

            $script:MSGraphConnection = @{
                Token       = $jwt
                TokenExpiry = (Get-Date).AddHours(1).ToUniversalTime()
                FlowType    = 'Interactive'
                Context     = $context
            }
            $script:AuthenticationHeader = @{
                'Authorization' = "Bearer $jwt"
                'Content-Type'  = 'application/json'
                'ExpiresOn'     = (Get-Date).AddHours(1)
            }
        }

        It 'Returns FlowType and TokenExpiry' {
            $result = Show-AuthenticationInfo

            $result.FlowType | Should -Be 'Interactive'
            $result.TokenExpiry | Should -Not -BeNullOrEmpty
        }

        It 'Includes identity context properties' {
            $result = Show-AuthenticationInfo

            $result.Identity  | Should -Be 'show@contoso.com'
            $result.TenantId  | Should -Be 'show-tenant'
            $result.Scopes    | Should -Be 'User.Read'
            $result.AppId     | Should -Be 'show-app-id'
            $result.TokenType | Should -Be 'Delegated'
        }

        It 'Includes custom header items (excluding Authorization and ExpiresOn)' {
            $script:AuthenticationHeader['consistencylevel'] = 'eventual'

            $result = Show-AuthenticationInfo

            $result.HeaderItems | Should -Not -BeNullOrEmpty
            $result.HeaderItems['consistencylevel'] | Should -Be 'eventual'
            $result.HeaderItems['Content-Type'] | Should -Be 'application/json'
            $result.HeaderItems.ContainsKey('Authorization') | Should -BeFalse
            $result.HeaderItems.ContainsKey('ExpiresOn') | Should -BeFalse
        }

        It 'Returns DecodedToken when -FullDetails is specified' {
            $result = Show-AuthenticationInfo -FullDetails

            $result.DecodedToken | Should -Not -BeNullOrEmpty
            $result.DecodedToken.upn | Should -Be 'show@contoso.com'
        }

        It 'Does not include DecodedToken without -FullDetails' {
            $result = Show-AuthenticationInfo

            $result.PSObject.Properties.Name | Should -Not -Contain 'DecodedToken'
        }

        It 'Warns when no connection exists' {
            $script:MSGraphConnection = $null
            $script:AuthenticationHeader = $null

            $result = Show-AuthenticationInfo -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Describe 'Add-AuthenticationHeaderItem' {

        BeforeEach {
            $script:AuthenticationHeader = @{
                'Authorization' = 'Bearer fake'
                'Content-Type'  = 'application/json'
                'ExpiresOn'     = (Get-Date).AddHours(1)
            }
        }

        It 'Adds a new key-value pair to the header' {
            Add-AuthenticationHeaderItem -Name 'consistencylevel' -Value 'eventual'

            $script:AuthenticationHeader['consistencylevel'] | Should -Be 'eventual'
        }

        It 'Adds multiple items' {
            Add-AuthenticationHeaderItem -Name 'X-Custom-1' -Value 'value1'
            Add-AuthenticationHeaderItem -Name 'X-Custom-2' -Value 'value2'

            $script:AuthenticationHeader['X-Custom-1'] | Should -Be 'value1'
            $script:AuthenticationHeader['X-Custom-2'] | Should -Be 'value2'
        }

        It 'Warns when no authentication header exists' {
            $script:AuthenticationHeader = $null

            $warnMsg = $null
            Add-AuthenticationHeaderItem -Name 'test' -Value 'val' -WarningVariable warnMsg 3>&1

            $warnMsg | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Remove-AuthenticationHeaderItem' {

        BeforeEach {
            $script:AuthenticationHeader = @{
                'Authorization'    = 'Bearer fake'
                'Content-Type'     = 'application/json'
                'ExpiresOn'        = (Get-Date).AddHours(1)
                'consistencylevel' = 'eventual'
            }
        }

        It 'Removes an existing header item by name' {
            Remove-AuthenticationHeaderItem -Name 'consistencylevel'

            $script:AuthenticationHeader.ContainsKey('consistencylevel') | Should -BeFalse
        }

        It 'Does not affect other header items' {
            Remove-AuthenticationHeaderItem -Name 'consistencylevel'

            $script:AuthenticationHeader['Content-Type'] | Should -Be 'application/json'
            $script:AuthenticationHeader['Authorization'] | Should -BeLike 'Bearer *'
        }

        It 'Warns when no authentication header exists' {
            $script:AuthenticationHeader = $null

            $warnMsg = $null
            Remove-AuthenticationHeaderItem -Name 'test' -WarningVariable warnMsg 3>&1

            $warnMsg | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Get-AccessToken backward-compatibility alias' {

        It 'Alias Get-AccessToken resolves to Connect-MSGraphRequest' {
            $alias = Get-Alias -Name 'Get-AccessToken' -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.ReferencedCommand.Name | Should -Be 'Connect-MSGraphRequest'
        }
    }
}

AfterAll {
    Get-Module MSGraphRequest | Remove-Module -Force -ErrorAction SilentlyContinue
}
