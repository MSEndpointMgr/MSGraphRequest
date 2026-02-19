# MSGraphRequest

![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/MSGraphRequest)

A PowerShell module that simplifies interacting with Microsoft Graph API. Provides consolidated authentication (six flows) and functions to perform GET, POST, PATCH, PUT, and DELETE operations with automatic paging, throttling, and token refresh.

**v2.0.0 is 100% native REST — zero SDK or MSAL dependencies.**

## Functions

| Function | Description |
|----------|-------------|
| `Connect-MSGraphRequest` | Authenticate to Microsoft Graph (six flows) |
| `Disconnect-MSGraphRequest` | Clear all tokens and connection state |
| `Invoke-MSGraphOperation` | Execute Graph API requests with automatic paging, throttling, and token refresh |
| `Test-AccessToken` | Check if the current token is near expiry |
| `Show-AuthenticationInfo` | Display current connection context and token details |
| `Add-AuthenticationHeaderItem` | Add custom HTTP headers (e.g. `consistencylevel`) |
| `Remove-AuthenticationHeaderItem` | Remove custom HTTP headers |

> **Backward compatibility:** `Get-AccessToken` is available as an alias for `Connect-MSGraphRequest`.

## Installing the module

```powershell
Install-Module -Name "MSGraphRequest" -AcceptLicense
```

## Requirements

- PowerShell 5.1 or later
- No external module dependencies

## Supported authentication flows

| Flow | Parameter | Use case |
|------|-----------|----------|
| Interactive (Auth Code + PKCE) | `-TenantId` | User sign-in via browser — default flow |
| Device Code | `-TenantId -DeviceCode` | Environments without a browser |
| Client Secret | `-TenantId -ClientId -ClientSecret` | App-only with a secret |
| Client Certificate | `-TenantId -ClientId -ClientCertificate` | App-only with a certificate (JWT assertion) |
| Managed Identity | `-ManagedIdentity` | Azure VMs, App Service, Functions |
| Bring Your Own Token | `-AccessToken` | Pre-acquired token from any source |

## How to use the module

### Connect — Interactive (default)

Uses the well-known Microsoft Graph PowerShell app ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`) by default. Opens the browser with an account picker.

```powershell
Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com"
```

With a custom app registration:

```powershell
Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -ClientId "00000000-0000-0000-0000-000000000001"
```

### Connect — Device Code

```powershell
Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -DeviceCode
```

### Connect — Client Secret

```powershell
Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -ClientId "<AppId>" -ClientSecret "<Secret>"
```

### Connect — Client Certificate

```powershell
$cert = Get-Item "Cert:\CurrentUser\My\<Thumbprint>"
Connect-MSGraphRequest -TenantId "contoso.onmicrosoft.com" -ClientId "<AppId>" -ClientCertificate $cert
```

### Connect — Managed Identity

```powershell
# System-assigned
Connect-MSGraphRequest -ManagedIdentity

# User-assigned
Connect-MSGraphRequest -ManagedIdentity -ManagedIdentityClientId "<ClientId>"
```

### Connect — Bring Your Own Token

```powershell
Connect-MSGraphRequest -AccessToken $myToken
```

### Graph API requests

`Invoke-MSGraphOperation` handles paging (`@odata.nextLink`), throttling (`Retry-After`), and automatic token refresh.

```powershell
# GET all Intune managed devices
Invoke-MSGraphOperation -Get -Resource "deviceManagement/managedDevices" -APIVersion "v1.0"

# GET with Beta API
Invoke-MSGraphOperation -Get -Resource "devices" -APIVersion "Beta"

# POST
Invoke-MSGraphOperation -Post -Resource "deviceManagement/deviceCategories" -Body ($body | ConvertTo-Json) -APIVersion "v1.0"

# PATCH
Invoke-MSGraphOperation -Patch -Resource "deviceManagement/managedDevices('$id')" -Body ($body | ConvertTo-Json)

# DELETE
Invoke-MSGraphOperation -Delete -Resource "deviceManagement/managedDevices('$id')"
```

### Custom headers

Some Graph operations require additional headers (e.g. advanced queries with `$count`):

```powershell
Add-AuthenticationHeaderItem -Name "consistencylevel" -Value "eventual"

# Later, remove if no longer needed
Remove-AuthenticationHeaderItem -Name "consistencylevel"
```

Custom headers are preserved across automatic token refreshes.

### Check connection status

```powershell
# Quick expiry check
Test-AccessToken

# Full connection context
Show-AuthenticationInfo

# Decoded JWT payload
Show-AuthenticationInfo -FullDetails
```

### Disconnect

```powershell
Disconnect-MSGraphRequest
```
