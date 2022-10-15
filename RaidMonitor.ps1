
param(
    $Key,
    $Config
)

<################################# < RaidMonitor.ps1 > #################################
Primarily use HPE Servers but do not have an ILO network setup so we use a PowerShell
script to monitor the SmartArray RAID statuses and get alerts when the status is 
abnormal
########################################################################################>

# Import my SecurePassword functions
Import-Module -Name ".\SecurePassword.ps1"
# Convert the provided JSON array to an object
$Key = $Key | ConvertFrom-Json

# Read the JSON config file
function Get-Config {
    param(
        $Path
    )

    return (Get-Content -Path $Path -ErrorAction Stop | ConvertFrom-Json)
}

# Uses the Invoke-Command cmdlet to run the RAID status command on the server
function Test-RAIDPowerShell {
    param(
        $Server
    )

    # Get ServerFQDN and Credentials
    $serverFQDN = Get-ServerFQDN -Server $Server
    $credentials = Get-ServerCredentials -Server $Server -Key $Key

    # Build the scriptblock command
    $command = [scriptblock]::Create($server.command)

    # Try to invoke the command on the server
    try {
        $response = Invoke-Command -ComputerName $serverFQDN -Credential $credentials -ScriptBlock $command -ErrorAction Stop
    } catch {
        # Invoke failed so we will report a communication failure
        return @{
            "Server" = $server.hostname
            "RAID Status" = "Failed to communicate with host"
            "Response" = $error[0]
        }
    }

    # Check if the response from the server matches the failedRegex value defined in the config
    if($response -match $server.failedRegex) {
        return @{
            "Server" = $server.hostname
            "RAID Status" = "Failed"
            "Response" = $response
        }
    }

    # Return server healthy
    return @{
        "Server" = $server.hostname
        "RAID Status" = "Healthy"
        "Response" = $response
    }
}

# Build the FQDN name of the server
function Get-ServerFQDN {
    param(
        $Server
    )

    # Get domain details of the doamin the server is a member of
    $domain = $global:cfg.domains | Where-Object {$_.domain -eq $Server.domain}

    # Concatenate hostname and domain FQDN
    return "$($server.hostname).$($domain.domainFQDN)"
}

# Gets the credentials from file and decrypts the password. Returns a PsCredential object.
function Get-ServerCredentials {
    param(
        $Server
    )

    # Read doamin config, get username and password
    $encryptedCredentials = $global:cfg.domains | Where-Object {$_.domain -eq $Server.domain} | Select-Object *
    $username = "$($encryptedCredentials.svcAccUser)@$($encryptedCredentials.domainFQDN)"

    # Decrypts password with provided key
    $password = Get-SecurePassword -Key $Key -Password $encryptedCredentials.svcAccPass

    # Build PSCredential object
    [pscredential]$credentials = New-Object System.Management.Automation.PSCredential ($username, $password)

    return $credentials
}

# Builds the HTML report table
function New-ReportTable {
    param (
        $Report
    )

    # Define our styling
    $header =  `
@"
<style>
table {border: 1px solid black; border-collapse: collapse;}
th {padding: 5px; background-color: #398fcd; color: white;}
td {padding: 5px; border-top: 1px solid black;}
</style>
"@

    # Builds the HTML and uses regex to replace/style certain words
    $html = $report | Select-Object Server,'Raid Status' | ConvertTo-Html -Head $header
    $html = $html  -replace "Failed to communicate with host", "<b style='color: red'>Failed to communicate with host</b>" `
                   -replace "Failed", "<b style='color: red'>Failed</b>" `
                   -replace "Healthy", "<b style='color: green'>Healthy</b>"

    return [string]$html
}

# Sends the report to the specified recipient in the config file
function Send-Report {
    param (
        $Report
    )

    # Call New-ReportTable to build HTLML
    $html = New-ReportTable -Report $Report

    # Check if we have a failure in the table so we can set appropriate subject
    if ($null -ne ($report | Where-Object {$_.'RAID Status' -eq "Failed"})) {
        $subject = "$($global:cfg.smtp.subject) - Failed"
        $priority = "High"
    } else {
        $subject = "$($global:cfg.smtp.subject) - Healthy"
        $priority = "Normal"
    }

    # Save responses to a text file in a temp directory
    foreach ($entry in $report) {
        $entry.response | Out-File -FilePath "$($env:temp)\$($entry.server) RAID Monitor.txt" -Force
    }

    $attachments = Get-ChildItem -Path $env:temp | Where-Object { $_.Name -like '*RAID Monitor.txt'} | ForEach-Object FullName
    
    # Send email using specified SMTP server in config file
    Send-MailMessage -SmtpServer $global:cfg.smtp.server `
    -Port $global:cfg.smtp.port `
    -Subject $subject `
    -Body $html `
    -BodyAsHtml `
    -From $global:cfg.smtp.from `
    -To $global:cfg.smtp.to `
    -Attachments $attachments `
    -Priority $priority
}

# Starts the RAID Monitor report
function Start-Report {
    # Calls Get-Config to read the config file
    $global:Cfg = Get-Config -Path $Config
    
    # Loop through each server defined in the config file and test its RAID status using the appropriate function.
    # Currently these are: Test-RAIDPowerShell
    $report = @()
    foreach ($server in $global:cfg.servers) {
        switch ($server.connectionType) {
            "PS" { $report += Test-RAIDPowerShell -Server $server }
        }
    }
    
    # Make the report a table
    $report = $report | ForEach-Object { New-Object object | Add-Member -NotePropertyMembers $_ -PassThru }

    # Send the report
    Send-Report -Report $report
}

# Start the report
Start-Report