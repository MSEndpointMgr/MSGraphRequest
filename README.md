# Overview
![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/MSGraphRequest)

This module is intended to simplify interacting with Microsoft Graph API, by consolidating access token retrieval and refresh operations (backed by MSAL.PS module) and by providing a function to perform GET, POST, PATCH, PUT and DELETE operations.

Currently the following functions are supported in the module:
- Get-AccessToken
- Test-AccessToken
- Invoke-MSGraphOperation

## Installing the module from PSGallery
The MSGraphRequest module is published to the PowerShell Gallery. Install it on your system by running the following in an elevated PowerShell console:
```PowerShell
Install-Module -Name "MSGraphRequest"
```

## Module dependencies
MSGraphRequest module requires the following modules, which will be automatically installed as dependencies:
- MSAL.PS

## Supported authentication flows
MSGraphRequest module currently supports the following authentication flows:
- Authorization code flow (Interactive)
- Client credentials flow (ClientSecret)
- Client credentials flow (ClientCertificate)
- DeviceCode flow (DeviceCode) 

# How to use the module
Below follows a few examples of how the module can be used either on the command line or embedded within scripts. Before you start using the module, depending on how you intend to retrieve an access token, some parameter input is required. At minimum, the following variable should be available unless it's value is passed directory on the command line:

```PowerShell
$TenantID = "tenant.onmicrosoft.com"
```

## Get an access token
The Get-AccessToken function performs two main operations. The first is to call Get-MsalToken to retrieve an access token. Additionally, it will also call the private function in this module named New-AuthenticationHeader to return a usage hash-table that's automatically referenced when using the Invoke-MSGraphOperation function.
