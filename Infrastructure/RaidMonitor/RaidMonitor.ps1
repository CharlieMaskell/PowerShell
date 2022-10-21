param(
    $Key,
    $Config
)

<################################# < RaidMonitor.ps1 > #################################
Primarily use HPE Servers but do not have an ILO network setup so we use a PowerShell
script to monitor the SmartArray RAID statuses and get alerts when the status is 
abnormal
########################################################################################>

# Import my SecurePassword functions and Posh-SSH for ESXi Servers
Import-Module -Name ".\SecurePassword.ps1"
Import-Module -Name "Posh-SSH"

# Convert the provided JSON array to an object
$Key = $Key | ConvertFrom-Json

# Read the JSON config file
function Get-Config {
    param($Path)

    return (Get-Content -Path $Path -ErrorAction Stop | ConvertFrom-Json)
}

# Builds a data table to send the server raid status back in a standard format
function New-ResponseTable {
    param ($Hostname, $Status, $Response)

    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Server")
    [void]$table.Columns.Add("Status")
    [void]$table.Columns.Add("Response")
    $table.Rows.Add($Hostname, $Status, [string]$Response) | Out-Null

    return $table
}

# Uses the Invoke-Command cmdlet to run the RAID status command on the server
function Test-RAIDPowerShell {
    param($Server)

    # Get ServerFQDN and Credentials
    $serverFQDN = Get-ServerFQDN -Server $Server
    $credentials = Get-DomainCredentials -Server $Server -Key $key

    # Run PowerShell command
    $command = [scriptblock]::Create($server.command)
    $response = Invoke-Command -ComputerName $serverFQDN -Credential $credentials -ScriptBlock $command -ErrorAction SilentlyContinue

    # Determine the RAID status
    if ($response -match $server.failedRegex) {
        $status = "Disk Failure"
    } elseif ($null -eq $response) {
        $status = "Failed to communicate with server"
    } else {
        $status = "OK"
    }
    
    return New-ResponseTable -Hostname $Server.hostname -Status $status -Response $response
}

# Uses SSH to run a command to check the RAID status
function Test-RAIDSSH {
    param($Server)

    # Get Credentials
    $credentials = Get-ServerCredentials -Server $Server
    
    # Run SSH command
    $session = New-SSHSession -ComputerName $server.ip -Credential $credentials -AcceptKey
    $response = Invoke-SSHCommand -SSHSession $session -Command $server.command
    Remove-SSHSession $session | Out-Null

    # Determine the RAID Status
    if ($response.output -match $server.failedRegex) {
        $status = "Disk Failure"
    } elseif ($null -eq $response.output) {
        $status = "Failed to communicate with server"
    } elseif ($response.ExitStatus -ne 0) {
        $status = "Unable to check array status"
    } else {
        $status = "OK"
    }
    
    return New-ResponseTable -Hostname $Server.hostname -Status $status -Response $response.output
}

# Build the FQDN name of the server
function Get-ServerFQDN {
    param($Server)

    # Get domain details of the doamin the server is a member of
    $domain = $global:cfg.domains | Where-Object {$_.domain -eq $Server.domain}

    # Concatenate hostname and domain FQDN
    return "$($server.hostname).$($domain.domainFQDN)"
}

# Gets the credentials from file and decrypts the password. Returns a PSCredential object.
function Get-DomainCredentials {
    param($Server)

    # Read doamin config, get username and password
    $encryptedCredentials = $global:cfg.domains | Where-Object {$_.domain -eq $Server.domain} | Select-Object *
    $username = "$($encryptedCredentials.svcAccUser)@$($encryptedCredentials.domainFQDN)"

    # Decrypts password with provided key
    $password = Get-SecurePassword -Key $key -Password $encryptedCredentials.svcAccPass

    # Build PSCredential object
    [pscredential]$credentials = New-Object System.Management.Automation.PSCredential ($username, $password)

    return $credentials
}

# Gets the servers credentials from file and decrypts the password. Returns a PSCredential object.
function Get-ServerCredentials {
    param ($Server)

    # Get username and password
    $username = $Server.sshUser
    $password = Get-SecurePassword -Key $key -Password $Server.sshPass

    # Build PSCredential object
    [pscredential]$credentials = New-Object System.Management.Automation.PSCredential ($username, $password)

    return $credentials
}

# Builds the HTML report table
function New-ReportTable {
    param ($Report)

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
    $html = $report | Select-Object Server,Status | ConvertTo-Html -Head $header
    $html = $html  -replace "Failed to communicate with host", "<b style='color: red'>Failed to communicate with host</b>" `
                   -replace "Disk Failure", "<b style='color: red'>Disk Failure</b>" `
                   -replace "OK", "<b style='color: green'>OK</b>" `
                   -replace "Unable to check array status", "<b style='color: orange'>Unable to check array status</b>"

    return [string]$html
}

# Sends the report to the specified recipient in the config file
function Send-Report {
    param ($Report)

    # Call New-ReportTable to build HTLML
    $html = New-ReportTable -Report $Report

    # Check if we have a failure in the table so we can set appropriate subject
    if ($null -ne ($report | Where-Object {$_.'Status' -eq "Disk Failure"})) {
        $subject = "$($global:cfg.smtp.subject) - Disk Failure"
        $priority = "High"
    } else {
        $subject = "$($global:cfg.smtp.subject) - OK"
        $priority = "Normal"
    }

    # Save responses to a text file in a temp directory
    foreach ($entry in $report) {
        if ($null -ne $entry.response) {
            $entry.response | Out-File -FilePath "$($env:temp)\$($entry.server) RAID Monitor.txt" -Force
        }
    }

    # Get our reports to attach to the email
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
    foreach ($server in $global:cfg.servers) {
        switch ($server.connectionType) {
            "PS" { [array]$report += Test-RAIDPowerShell -Server $server }
            "SSH" { [array]$report += Test-RAIDSSH -Server $server }
        }
    }
    
    # Send the report
    Send-Report -Report $report
    return $report
}

# Start the report
Start-Report