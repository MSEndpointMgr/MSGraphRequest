function Invoke-DeviceCodeAuth {
    <#
    .SYNOPSIS
        Performs device code flow authentication against Microsoft identity platform.

    .DESCRIPTION
        1. Requests a device code from the /devicecode endpoint.
        2. Displays the user code and verification URI to the user.
        3. Polls the /token endpoint at the specified interval until the user completes
           sign-in or the code expires.
        4. Handles authorization_pending, slow_down, and error responses.

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
        $deviceCodeEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        # 1. Request device code
        $deviceCodeBody = @{
            client_id = $ClientId
            scope     = $Scopes
        }

        Write-Verbose -Message "Requesting device code from: $deviceCodeEndpoint"
        try {
            $deviceCodeResponse = Invoke-RestMethod -Uri $deviceCodeEndpoint -Method Post -Body $deviceCodeBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
        catch [System.Exception] {
            throw "Failed to request device code: $($PSItem.Exception.Message)"
        }

        # 2. Display the user code and verification URI
        Write-Host ""
        Write-Host "[MSGraphRequest] To sign in, use a web browser to open the page $($deviceCodeResponse.verification_uri) and enter the code: " -ForegroundColor Yellow -NoNewline
        Write-Host "$($deviceCodeResponse.user_code)" -ForegroundColor Cyan
        Write-Host ""

        $interval = if ($deviceCodeResponse.interval) { [int]$deviceCodeResponse.interval } else { 5 }
        $expiresIn = if ($deviceCodeResponse.expires_in) { [int]$deviceCodeResponse.expires_in } else { 900 }
        $deadline = (Get-Date).AddSeconds($expiresIn)

        # 3. Poll the token endpoint
        $tokenBody = @{
            client_id   = $ClientId
            grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
            device_code = $deviceCodeResponse.device_code
        }

        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $interval

            try {
                $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
                # Success - user has authenticated
                Write-Verbose -Message "Device code authentication completed successfully."
                return $response
            }
            catch [System.Exception] {
                # Parse the error to determine if we should keep polling
                $errorBody = $null
                try {
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        if ($PSItem.ErrorDetails.Message) {
                            $errorBody = $PSItem.ErrorDetails.Message | ConvertFrom-Json
                        }
                    }
                    else {
                        if ($PSItem.Exception.Response) {
                            $streamReader = [System.IO.StreamReader]::new($PSItem.Exception.Response.GetResponseStream())
                            $streamReader.BaseStream.Position = 0
                            $streamReader.DiscardBufferedData()
                            $errorBody = $streamReader.ReadToEnd() | ConvertFrom-Json
                        }
                    }
                }
                catch {
                    # Cannot parse - treat as fatal
                }

                if ($errorBody) {
                    switch ($errorBody.error) {
                        "authorization_pending" {
                            # User hasn't authenticated yet - keep polling
                            Write-Verbose -Message "Waiting for user authentication..."
                            continue
                        }
                        "slow_down" {
                            # Server asked us to slow down - increase interval
                            $interval += 5
                            Write-Verbose -Message "Slowing down polling interval to $interval seconds."
                            continue
                        }
                        "expired_token" {
                            throw "Device code has expired. Please run the command again to get a new code."
                        }
                        "access_denied" {
                            throw "Authentication was denied by the user or administrator."
                        }
                        default {
                            throw "Device code authentication failed: $($errorBody.error) - $($errorBody.error_description)"
                        }
                    }
                }
                else {
                    throw "Device code authentication failed: $($PSItem.Exception.Message)"
                }
            }
        }

        throw "Device code authentication timed out - the code expired before the user completed sign-in."
    }
}
