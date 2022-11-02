#region logging
$logLocation    = "$($env:TEMP)\Intune\scripts.log"
$maxSize        = 1 # MB
$maxFileCount   = 5
$fileSize = $maxSize * 1MB

function Roll-Logs () { 
	if (Test-Path -Path $logLocation -PathType Leaf) {
        $log = Get-Item -Path $logLocation
        $existingLogs = Get-ChildItem $log.PSParentPath | Where-Object { $_.Name -like "*$($log.Name -replace '\.[^.]+$', '')*" }

        if ($existingLogs.Count -ge $maxFileCount) {
            $oldLog = $existingLogs | Sort-Object LastAccessTime -Descending | Select -Last 1
            Remove-Item $oldLog.PSPath
        }

        if ($log.length -ge $fileSize) {
            $i = 1

            do {
                if ($log.Name -Match "\.[^.]+$") {
                    $fileName = ($log.Name -Replace "\.[^.]+$", "") + "-" + $i + $matches[0]
                } else {
                    $fileName = ($log.Name -Replace "\.[^.]+$", "") + "-" + $i + ".log"
                }

                $i++

                try {
                    Rename-Item $log -NewName $fileName -ErrorAction Stop
                    $success = $True
                } catch { 
                    $success = $False
                }
            } until ($success)
        }
    }
}

function Write-Log ($Message) {
    $date = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    $output = "$date - $message"
    Write-Output $output
}

#endregion logging

#region functions
function Get-BitLockerDrives {
    return Get-BitLockerVolume | Select-Object * | Where-Object {$_.ProtectionStatus -eq "On"}
}

function Get-BitLockerKeyProtectorId {
    param($Drive)
    return $drive.KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}
}

function Invoke-BitlockerEscrow {
    param($Drive, $Key)

    try {
        BackupToAAD-BitLockerKeyProtector -MountPoint $drive.MountPoint -KeyProtectorId $key.KeyProtectorId 
        return $true
    } catch {
        return $false
    }
}

#endregion functions

#region main
Roll-Logs
Start-Transcript -Path $logLocation -Append  -Force

foreach ($drive in Get-BitLockerDrives) {
    Write-Log "Detected BitLocker Drive $($drive.MountPoint)"
    $key = Get-BitLockerKeyProtectorId -Drive $drive

    Write-Log "Backing up BitLocker Recovery Key to AAD"
    if(Invoke-BitlockerEscrow -Drive $drive -Key $key) {
        Write-Log "Succeeded"
    } else {
        Write-Log "Failed"
        $failed = $true
    }
}

Stop-Transcript
if ($failed) {
    exit 1
} else {
    exit 0
}

#endregion main