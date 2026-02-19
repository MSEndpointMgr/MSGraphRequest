# Release Notes

## 2.0.0 - 2026-02-19

### Breaking Changes

- **MSAL.PS dependency removed** — The module no longer requires or uses MSAL.PS. All authentication is 100% native REST via `Invoke-RestMethod`.
- **`Get-AccessToken` replaced by `Connect-MSGraphRequest`** — `Get-AccessToken` is now a backward-compatibility alias that maps to `Connect-MSGraphRequest`. Existing scripts using `Get-AccessToken` will continue to work.
- **Global variables replaced with script-scoped state** — `$Global:AuthenticationHeader` and `$Global:AccessToken` are no longer used. Connection state is stored in `$script:MSGraphConnection` and `$script:AuthenticationHeader` (module-internal).
- **Minimum PowerShell version** raised from 5.0 to 5.1.

### New Features

- **`Connect-MSGraphRequest`** — Single entry-point for authentication supporting six flows:
  - Interactive (Authorization Code + PKCE with localhost redirect)
  - Device Code
  - Client Secret (client credentials)
  - Client Certificate (JWT client assertion, RS256)
  - Managed Identity (Azure VM IMDS and App Service)
  - Bring Your Own Token
- **`Disconnect-MSGraphRequest`** — Securely clears all tokens, secrets, and connection state.
- **Automatic token refresh** — `Invoke-MSGraphOperation` now automatically refreshes expired tokens in the Begin block. Supports all six flows (Interactive/DeviceCode use refresh_token, ClientSecret/ClientCertificate re-acquire, ManagedIdentity re-requests, BYOT warns).
- **Custom header preservation** — Headers added via `Add-AuthenticationHeaderItem` (e.g. `consistencylevel = eventual`) are preserved across automatic token refreshes.
- **Default Client ID** — Interactive and DeviceCode flows default to the well-known Microsoft Graph PowerShell app (`14d82eec-204b-4c2f-b7e8-296a70dab67e`) when no ClientId is specified.
- **PKCE mandatory** — Interactive auth uses Authorization Code + PKCE with state validation (CSRF protection).
- **`Show-AuthenticationInfo`** rewritten — Now displays FlowType, Identity, TokenType, TenantId, Scopes, AppId, and custom header items. `-FullDetails` decodes the full JWT payload.

### Bug Fixes

- Fixed `$body` variable collision in `Invoke-MSGraphOperation` auto-refresh that could overwrite POST/PATCH/PUT request bodies.
- Fixed PowerShell 5.1 incompatibility with `RandomNumberGenerator::Fill()` and `SHA256::HashData()` static methods.
- Fixed `AliasesToExport` in manifest blocking the `Get-AccessToken` backward-compat alias.
- Fixed `$ErrorID` being undefined in error record construction (now uses `$ResponseBody.ErrorCode`).
- Fixed PS7+ error parsing crash when `ErrorDetails.Message` is null (network timeouts, DNS failures).
- Fixed `TenantId` not being stored in connection state for Interactive, DeviceCode, and ClientSecret flows.
- Fixed silent no-op when refresh token is missing for Interactive/DeviceCode flows (now warns).
- Fixed `GetRSAPrivateKey()` extension method not available on all .NET runtimes (falls back to `.PrivateKey`).
- Initialized `$GraphResponseProcess` before the `do...until` loop to prevent reliance on implicit null behavior.

### New Private Helpers

- `ConvertFrom-JwtToken` — Decodes JWT header and payload from base64url.
- `Get-TokenContext` — Extracts identity, scopes, tenant, expiry from a JWT.
- `New-ClientAssertion` — Builds RS256-signed JWT for certificate auth.
- `Invoke-TokenRequest` — Centralized POST to the token endpoint with cross-platform error parsing.
- `Invoke-InteractiveAuth` — Auth Code + PKCE via HttpListener and browser.
- `Invoke-DeviceCodeAuth` — Device code polling flow with rate-limit handling.
- `Invoke-ManagedIdentityAuth` — Azure IMDS and App Service managed identity.

### Tests

- Added 72 Pester v5 tests covering all private helpers, Connect/Disconnect, Invoke-MSGraphOperation (paging, throttling, auto-refresh, header preservation), and all public functions.

## 1.1.4 - 2023-12-06

- Bugfix for POST action without body parameter.
- Bugfix for DELETE action.
- Added option to decode JWT token in Show-AuthenticationInfo with -Full switch.
- Bug fix in Test-AccessToken where TotalMinutes was used instead of Minutes for token expiry calculation.

## 1.1.3 - 2021-08-24

- Added Show-AuthenticationInfo function.
- Added Remove-AuthenticationHeaderItem function.

## 1.1.2 - 2021-05-19

- Added Add-AuthenticationHeaderItem function.

## 1.1.1 - 2021-04-12

- Adjusted Invoke-MSGraphOperation for module usage.

## 1.1.0 - 2021-04-08

- Added Test-AccessToken function.
- Added New-AuthenticationHeader private function.

## 1.0.0 - 2020-10-11

- Initial release with Invoke-MSGraphOperation and Get-AccessToken.

