<################################# < SecurePassword.ps1 > #################################
A slightly more secure way of storing passwords and using stored passwords by encrypting 
the SecureString object by using a randomly generated 256-bit AES key. The password cannot 
be decrypted without using the same key that was used to encrypt it. It is more secure than
storing plain text passwords in the script which are easy to identify and be abused.
Example usage at bottom of file :)
###########################################################################################>


# Function used to randomly generate a new 256-bit AES Key (32 byte array) which is used to
# encrypt/decrypt the password.
# Use $WarningPreference = "SilentlyContinue" to silence warning outputs.
function New-AESKey {
    $AESKey = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($AESKey)

    Write-Warning "Make sure you save this AES key somewhere secure. Do not save on this system."
    return $AESKey
}

# Read the password we want to encrypt as a secure string
function Get-Password {
    Read-Host "Enter the password you would like to encrypt" -AsSecureString
}

# Creates a secure password. Uses the provided AES Key generated from New-ByteArray to
# encrypt the password.
function New-SecurePassword {
    param(
        $Key
    )
    
    return Get-Password | ConvertFrom-SecureString -Key $Key
}

function Get-SecurePassword {
    param(
        $Key,
        $Password
    )

    return $password | ConvertTo-SecureString -Key $Key
}

<# ------------------------ < EXAMPLE USAGE > ------------------------ >

# Create a new 256-bit AES Key
# Will output the AES Key and warns you to save it somewhere secure
#$key = New-AESKey


$jsonKey = "[28,203,138,250,254,170,151,12,186,150,82,239,132,26,2,89,102,189,179,193,64,105,188,21,43,113,244,247,159,2,178,151]"
$jsonKeyConverted = $jsonKey | ConvertFrom-Json

# Encrypt the password using the automatically generated AES key.
# You can store the encrypted password to file by piping to Out-File
$secPwd = New-SecurePassword $jsonKeyConverted

# Encrypted password cannot be read until its decrypted using the same key used to encrypt it
# Will return something like: 76492d1116743f04234...
# $secPwd

# Will return InputObjectNotBound exception
# $secPwd | ConvertFrom-SecureString

$jsonKeyConverted = $jsonKey | ConvertFrom-Json

# To decrypt the password back to a SecureString which can be used in further scripts.
# You can use Get-Content here if you saved the encrypted password to a file using Out-File
$password = Get-SecurePassword -Password $secPwd -Key $jsonKeyConverted

# Will return: System.Security.SecureString
# $password

# Will return something like: 01000000d08c9ddf011... 
# $password | ConvertFrom-SecureString

< ------------------------ </ EXAMPLE USAGE > ------------------------ #>