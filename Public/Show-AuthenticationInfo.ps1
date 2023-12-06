function Show-AuthenticationInfo {
    <#
    .SYNOPSIS
        Shows info about current access token and header items.

    .DESCRIPTION
        Shows info about current access token and header items.

    .NOTES
        Author:      Jan Ketil Skanke
        Contact:     @JankeSkanke
        Created:     2021-08-24
        Updated:     2023-12-04

        Version history:
        1.0.0 - (2021-08-24) Script created
        1.0.1 - (2023-12-04) Added option Full to decode JWT token
    #>
    param(
        [Parameter(Mandatory=$false)]
        [switch]$FullDetails
    )
    Process {
        if ($Global:AuthenticationHeader) {
            # Construct new PS custom object
            $Response = New-Object -TypeName "PSObject"
            # Process each keys in the authentication header and add tenantId and scopes
            foreach ($AuthenticationHeaderItem in $Global:AuthenticationHeader.Keys) { 
                $Response | Add-Member -Type "NoteProperty" -Name $AuthenticationHeaderItem -Value $Global:AuthenticationHeader[$AuthenticationHeaderItem]   
            }
            $Response | Add-Member -Type "NoteProperty" -Name "TenantID" -Value $Global:AccessToken.TenantID
            $Response | Add-Member -Type "NoteProperty" -Name "Scopes" -Value $Global:AccessToken.Scopes
            if ($FullDetails){
                $RawToken = ($authenticationheader.Authorization).TrimStart("Bearer").Trim()
                if (!$RawToken.Contains(".") -or !$RawToken.StartsWith("eyJ")) { 
                    Write-Error "Invalid token" -ErrorAction Stop 
                }
                $TokenHeader = $RawToken.Split(".")[0].Replace('-', '+').Replace('_', '/')
                #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
                while ($Tokenheader.Length % 4) { 
                    Write-Verbose "Invalid length for a Base-64 char array or string, adding ="
                    $Tokenheader += "=" 
                }
                Write-Verbose "Base64 encoded (padded) header:"
                Write-Verbose $tokenheader
                #Convert from Base64 encoded string to PSObject all at once
                Write-Verbose "Decoded header: $([System.Text.Encoding]::ASCII.GetString([system.convert]::FromBase64String($tokenheader)) | ConvertFrom-Json | Format-List)"
                #Payload
                $TokenPayload = $RawToken.Split(".")[1].Replace('-', '+').Replace('_', '/')
                #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
                while ($TokenPayload.Length % 4) {
                    Write-Verbose "Invalid length for a Base-64 char array or string, adding ="
                    $TokenPayload += "=" 
                }
                Write-Verbose "Base64 encoded (padded) payload:"
                Write-Verbose $TokenPayload
                #Convert to Byte array
                $TokenByteArray = [System.Convert]::FromBase64String($TokenPayload)
                #Convert to string array
                $TokenArray = [System.Text.Encoding]::ASCII.GetString($TokenByteArray)
                Write-Verbose "Decoded array in JSON format:"
                Write-Verbose $TokenArray
                #Convert from JSON to PSObject
                $TokenObject = $TokenArray | ConvertFrom-Json
                Write-Verbose "Decoded payload: $($TokenObject | Format-List)"
                $Response | Add-Member -Type "NoteProperty" -Name "DecodedToken" -Value $TokenObject
            }
            
            # Handle return value
            return $Response
        }
        else {
            Write-Warning -Message "Unable to locate existing authentication header, use Get-AccessToken before running this function"
        }
    }
}