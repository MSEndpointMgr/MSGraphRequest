function Test-AccessToken {
    <#
    .SYNOPSIS
        Use to check if the existing access token is about to expire.

    .DESCRIPTION
        Use to check if the existing access token is about to expire.
        With the modernized auth, auto-refresh is built into Invoke-MSGraphOperation,
        but this function is kept for diagnostic/opt-in use.

    .PARAMETER RenewalThresholdMinutes
        Specify the renewal threshold for access token age in minutes.

    .NOTES
        Author:      Nickolaj Andersen
        Contributor: Jan Ketil Skanke
        Contact:     @NickolajA/@JankeSkanke
        Created:     2021-04-08
        Updated:     2026-02-19

        Version history:
        1.0.0 - (2021-04-08) Script created
        1.0.1 - (2023-12-04) Bug fix as token time can be longer than 1 hour we have to use TotalMinutes instead of Minutes
        2.0.0 - (2026-02-19) Switched to script-scoped connection state. Removed MSAL dependency.
    #>
    param(
        [parameter(Mandatory = $false, HelpMessage = "Specify the renewal threshold for access token age in minutes.")]
        [ValidateNotNullOrEmpty()]
        [int]$RenewalThresholdMinutes = 10
    )
    Process {
        if (-not $script:MSGraphConnection -or -not $script:MSGraphConnection.TokenExpiry) {
            Write-Warning -Message "No active connection found. Use Connect-MSGraphRequest before running this function."
            return $false
        }

        # Determine the current time in UTC
        $UTCDateTime = (Get-Date).ToUniversalTime()
                    
        # Determine the token expiration count as minutes
        $TokenExpireMinutes = ($script:MSGraphConnection.TokenExpiry - $UTCDateTime).TotalMinutes

        # Determine if refresh of access token is required when expiration count is less than or equal to minimum age
        if ($TokenExpireMinutes -le $RenewalThresholdMinutes) {
            Write-Verbose -Message "Access token refresh is required, current token expires in (minutes): $($TokenExpireMinutes)"
            return $false
        }
        else {
            Write-Verbose -Message "Access token refresh is not required, remaining minutes until expiration: $($TokenExpireMinutes)"
            return $true
        }
    }
}