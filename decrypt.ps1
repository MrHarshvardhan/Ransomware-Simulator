<#
PowerShell Ransomware Decrypter with Modes
.Description
This PowerShell script decrypts files using an X.509 public key certificate.
It supports two modes:
1. Default Mode (--Mode default): Decrypts files on mapped network drives.
2. Custom Mode (--Mode custom): Decrypts files in the current working directory.
3. Help Mode (--Mode help): Displays usage instructions.

.Instructions
- Provide the thumbprint of the X.509 certificate used during encryption.
- Use "--Mode default", "--Mode custom", or "--Mode help" to specify the mode during execution.

.Notes
This script is for educational purposes only and should not be used maliciously.
#>

# Parameter Parsing
param (
    [string]$Mode = "default"  # Default execution mode
)

# Help Option
if ($Mode -eq "help") {
    Write-Host "Usage: .\decrypt.ps1 --Mode <mode>"
    Write-Host "Modes:"
    Write-Host "  default : Decrypts files on mapped network drives."
    Write-Host "  custom  : Decrypts files in the current working directory."
    Write-Host "  help    : Displays this help message."
    Exit
}

# Check parameter value
if ($Mode -eq "default") {
    Write-Host "Running in default mode: Targeting network drives."
} elseif ($Mode -eq "custom") {
    Write-Host "Running in custom mode: Decrypting files in the current directory."
} else {
    Write-Error "Invalid mode specified. Use '--Mode help' for usage instructions."
    Exit
}

# Define the certificate for decryption
$Cert = $(Get-ChildItem Cert:\CurrentUser\My\F09CC285277DBAC041935B8D96ABE2C1BF123C46)
if (-not $Cert) {
    Write-Error "Certificate not found. Please provide a valid certificate thumbprint."
    Exit
}

# File enumeration based on mode
if ($Mode -eq "default") {
    # Enumerate network drives
    $psdrives = Get-PSDrive | Where-Object { $_.DriveType -eq "Network" } | Select-Object -ExpandProperty Root
    $FileToDecrypt = foreach ($drive in $psdrives) {
        Get-ChildItem -Path $drive -Recurse -Force | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq ".enc" } -ErrorAction SilentlyContinue
    }
} elseif ($Mode -eq "custom") {
    # Decrypt files in the current directory
    $currentDir = Get-Location
    $FileToDecrypt = Get-ChildItem -Path $currentDir.Path -Recurse -Force | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq ".enc" }
} else {
    Write-Error "Unhandled mode. Exiting."
    Exit
}

# Decryption and file stream function
Function Decrypt-File {
    Param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$FileToDecrypt,
        [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
    )

    Try { [System.Reflection.Assembly]::LoadWithPartialName("System.Security.Cryptography") } Catch {
        Write-Error "Could not load required assembly."; Return
    }

    $AesProvider = New-Object System.Security.Cryptography.AesManaged
    $AesProvider.KeySize = 256
    $AesProvider.BlockSize = 128
    $AesProvider.Mode = [System.Security.Cryptography.CipherMode]::CBC
    [Byte[]]$LenKey = New-Object Byte[] 4
    [Byte[]]$LenIV = New-Object Byte[] 4

    If ($Cert.HasPrivateKey -eq $False -or $Cert.PrivateKey -eq $null) {
        Write-Error "The supplied certificate does not contain a private key, or it could not be accessed."
        Return
    }

    Try { $FileStreamReader = New-Object System.IO.FileStream("$($FileToDecrypt.FullName)", [System.IO.FileMode]::Open) } Catch {
        Write-Error "Unable to open input file for reading."; Return
    }

    $FileStreamReader.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $FileStreamReader.Read($LenKey, 0, 4) | Out-Null
    $FileStreamReader.Read($LenIV, 0, 4) | Out-Null

    [Int]$LKey = [System.BitConverter]::ToInt32($LenKey, 0)
    [Int]$LIV = [System.BitConverter]::ToInt32($LenIV, 0)
    [Byte[]]$KeyEncrypted = New-Object Byte[] $LKey
    [Byte[]]$IV = New-Object Byte[] $LIV

    $FileStreamReader.Read($KeyEncrypted, 0, $LKey) | Out-Null
    $FileStreamReader.Read($IV, 0, $LIV) | Out-Null

    [Byte[]]$KeyDecrypted = $Cert.PrivateKey.Decrypt($KeyEncrypted, $false)
    $Transform = $AesProvider.CreateDecryptor($KeyDecrypted, $IV)

    Try { $FileStreamWriter = New-Object System.IO.FileStream("$($env:TEMP)\$($FileToDecrypt.Name.TrimEnd(".enc"))", [System.IO.FileMode]::Create) } Catch {
        Write-Error "Unable to open output file for writing.`n$($_.Message)"
        $FileStreamReader.Close()
        Return
    }

    [Int]$Count = 0
    [Int]$Offset = 0
    [Int]$BlockSizeBytes = $AesProvider.BlockSize / 8
    [Byte[]]$Data = New-Object Byte[] $BlockSizeBytes
    $CryptoStream = New-Object System.Security.Cryptography.CryptoStream($FileStreamWriter, $Transform, [System.Security.Cryptography.CryptoStreamMode]::Write)

    Do {
        $Count = $FileStreamReader.Read($Data, 0, $Data.Length)
        $CryptoStream.Write($Data, 0, $Count)
    } While ($Count -gt 0)

    $CryptoStream.FlushFinalBlock()
    $CryptoStream.Close()
    $FileStreamWriter.Close()
    $FileStreamReader.Close()

    Move-Item -Path "$($env:TEMP)\$($FileToDecrypt.Name.TrimEnd(".enc"))" -Destination "$($FileToDecrypt.FullName.TrimEnd(".enc"))" -Force
}

# Decrypt files in the list
foreach ($file in $FileToDecrypt) {
    Write-Host "Decrypting $file"
    Decrypt-File -FileToDecrypt $file -Cert $Cert -ErrorAction SilentlyContinue
}

Write-Host "Decryption process completed."
Exit
