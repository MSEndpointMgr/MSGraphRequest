function Get-AccessToken {
    <#
    .SYNOPSIS
        Get or refresh an access token using either authorization code flow (interactive) or client credentials (secret), that can be used to authenticate and authorize against resources in Graph API.

    .DESCRIPTION
        Get or refresh an access token using either authorization code flow (interactive) or client credentials (secret), that can be used to authenticate and authorize against resources in Graph API.

    .PARAMETER TenantID
        Specify the tenant name or ID, e.g. tenant.onmicrosoft.com or <GUID>.

    .PARAMETER ClientID
        Application ID (Client ID) for an Azure AD service principal.Uses Microsoft Graph PowerShell by default.(14d82eec-204b-4c2f-b7e8-296a70dab67e)
        If you need to use the old legacy Microsoft Intune Powershell, use ClientID d1ddf0e4-d672-4dae-b554-9d5bdfd93547

    .PARAMETER ClientSecret
        Specify the client secret for an Azure AD service principal.

    .PARAMETER ClientCertificate
        Specify the client certificate.

    .PARAMETER RedirectUri
        Specify the Redirect URI (also known as Reply URL) of the custom Azure AD service principal.

    .PARAMETER DeviceCode
        Specify delegated login using devicecode flow, you will be prompted to navigate to https://microsoft.com/devicelogin

    .PARAMETER Interactive
        Specify to force an interactive prompt for credentials.

    .PARAMETER Refresh
        Specify to refresh an existing access token.

    .PARAMETER ClearCache
        Specify to clear existing access token from the local cache.

    .PARAMETER Scopes
        Specify scopes to the access request, can be used for consent flow in interactive mode. 
        Type: Array
        Example: $scopes = @('Device.Read.All','User.Read.All','DeviceManagementManagedDevices.Read.All') 

    .PARAMETER AddConsistencyLevelEventualHeader
        Switch: Specify to add consistencylevel eventual to the authentication header. 

    .NOTES
        Author:      Nickolaj Andersen & Jan Ketil Skanke
        Contact:     @NickolajA @JankeSkanke
        Created:     2021-04-08
        Updated:     2023-12-06

        Version history:
        1.0.0 - (2021-04-08) Script created
        1.0.1 - (2021-05-05) Added delegated login using devicecode flow
        1.0.2 - (2023-12-05) Added scopes parameter, added MS Graph Application as default app. Use -ClientID parameter to specify other app, added AddConsistencyLevelEventualHeader switch
    #>
    [CmdletBinding(DefaultParameterSetName = "Interactive")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = "Interactive", HelpMessage = "Specify the tenant name or ID, e.g. tenant.onmicrosoft.com or <GUID>.")]
        [parameter(Mandatory = $true, ParameterSetName = "ClientSecret")]
        [parameter(Mandatory = $true, ParameterSetName = "ClientCertificate")]
        [parameter(Mandatory = $true, ParameterSetName = "DeviceCode")]
        [ValidateNotNullOrEmpty()]
        [string]$TenantID,
        
        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Application ID (Client ID) for an Azure AD service principal. Uses by default the 'Microsoft Intune PowerShell' service principal Application ID.")]
        [parameter(Mandatory = $true, ParameterSetName = "ClientSecret")]
        [parameter(Mandatory = $true, ParameterSetName = "ClientCertificate")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [ValidateNotNullOrEmpty()]
        [string]$ClientID = "14d82eec-204b-4c2f-b7e8-296a70dab67e",

        [parameter(Mandatory = $false, ParameterSetName = "ClientSecret", HelpMessage = "Specify the client secret for an Azure AD service principal.")]
        [ValidateNotNullOrEmpty()]
        [string]$ClientSecret,

        [parameter(Mandatory = $false, HelpMessage = "Add scopes to the access request, can be used for consent flow in interactive mode.")]
        [array]$Scopes,

        [Parameter(Mandatory=$false, HelpMessage = "Add consistencylevel eventual to the authentication header.")]
        [switch]$AddConsistencyLevelEventualHeader,
        
        [parameter(Mandatory = $true, ParameterSetName = "ClientCertificate", HelpMessage = "Specify the client certificate.")]
        [ValidateNotNullOrEmpty()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$ClientCertificate,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify the Redirect URI (also known as Reply URL) of the custom Azure AD service principal.")]
        [parameter(Mandatory = $false, ParameterSetName = "ClientSecret")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [ValidateNotNullOrEmpty()]
        [string]$RedirectUri = [string]::Empty,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify to force an interactive prompt for credentials.")]
        [switch]$Interactive,

        [parameter(Mandatory = $true, ParameterSetName = "DeviceCode", HelpMessage = "Specify to do delegated login using devicecode flow, you will be prompted to navigate to https://microsoft.com/devicelogin")]
        [switch]$DeviceCode,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify to refresh an existing access token.")]
        [parameter(Mandatory = $false, ParameterSetName = "ClientSecret")]
        [parameter(Mandatory = $false, ParameterSetName = "ClientCertificate")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [switch]$Refresh,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify to clear existing access token from the local cache.")]
        [parameter(Mandatory = $false, ParameterSetName = "ClientSecret")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [switch]$ClearCache
    )
    Begin {
        # Determine the correct RedirectUri (also known as Reply URL) to use with MSAL.PS
        if ($ClientID -like "d1ddf0e4-d672-4dae-b554-9d5bdfd93547") {
            $RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
        }        
        else 
        {
            if (-not([string]::IsNullOrEmpty($ClientID))) {
                Write-Verbose -Message "Using custom Azure AD service principal specified with Application ID: $($ClientID)"

                # Adjust RedirectUri parameter input in case non was passed on command line
                if ([string]::IsNullOrEmpty($RedirectUri)) {
                    $RedirectUri = "http://localhost"                    
                    <#switch -Wildcard ($PSVersionTable["PSVersion"]) {
                        "5.*" {
                            $RedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"
                        }
                        "7.*" {
                            $RedirectUri = "http://localhost"
                        }
                    }#>
                }
            }
        }
        Write-Verbose -Message "Using RedirectUri with value: $($RedirectUri)"

        # Convert client secret to secure string
        if ($PSCmdlet.ParameterSetName -eq "ClientSecret") {
            $ClientSecretSecure = $ClientSecret | ConvertTo-SecureString -AsPlainText -Force
        }

        # Set default error action preference configuration
        $ErrorActionPreference = "Stop"
    }
    Process {
        Write-Verbose -Message "Using authentication flow: $($PSCmdlet.ParameterSetName)"

        # Clear existing access token from local cache
        if ($PSBoundParameters["ClearCache"]) {
            Clear-MsalTokenCache
            }

        try {
            # Construct table with common parameter input for Get-MsalToken cmdlet
            $AccessTokenArguments = @{
                "TenantId" = $TenantID
                "ClientId" = $ClientID
                "RedirectUri" = $RedirectUri
                "ErrorAction" = "Stop"
            }

            # Dynamically add parameter input for Get-MsalToken based on parameter set name
            switch ($PSCmdlet.ParameterSetName) {
                "Interactive" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                        $AccessTokenArguments.Add("Silent", $true)
                    }
                }
                "DeviceCode" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                    }
                }
                "ClientSecret" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                    }
                }
                "ClientCertificate" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                    }
                }
            }

            # Dynamically add parameter input for Get-MsalToken based on command line input
            if ($PSBoundParameters["Interactive"]) {
                $AccessTokenArguments.Add("Interactive", $true)
            }
            if ($PSBoundParameters["DeviceCode"]) {
                if (-not($PSBoundParameters["Refresh"])){
                    $AccessTokenArguments.Add("DeviceCode", $true)
                }
            }
            if ($PSBoundParameters["ClientSecret"]) {
                $AccessTokenArguments.Add("ClientSecret", $ClientSecretSecure)
            }
            if ($PSBoundParameters["ClientCertificate"]) {
                $AccessTokenArguments.Add("ClientCertificate", $ClientCertificate)
            }
            if ($PSBoundParameters["Scopes"]) {
                $AccessTokenArguments.Add("Scopes", $Scopes)
            }

            try {
                # Attempt to retrieve or refresh an access token
                $Global:AccessToken = Get-MsalToken @AccessTokenArguments
                Write-Verbose -Message "Successfully retrieved access token"
                
                try {
                    # Construct the required authentication header
                    $Global:AuthenticationHeader = New-AuthenticationHeader -AccessToken $Global:AccessToken
                    if ($PSBoundParameters["AddConsistencyLevelEventualHeader"]) {
                        Add-AuthenticationHeaderItem -Name "ConsistencyLevel" -Value "eventual"
                    }
                    Write-Verbose -Message "Successfully constructed authentication header"

                    # Handle return value
                    return $Global:AuthenticationHeader
                }
                catch [System.Exception] {
                    Write-Warning -Message "An error occurred while attempting to construct authentication header. Error message: $($PSItem.Exception.Message)"
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "An error occurred while attempting to retrieve or refresh access token. Error message: $($PSItem.Exception.Message)"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "An error occurred while constructing parameter input for access token retrieval. Error message: $($PSItem.Exception.Message)"
        }
    }
}