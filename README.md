# PowerShell
Just a collection of PowerShell scripts I create for use at work.
Nothing special, just might be of use to someone else one day.

Any improvements are welcome :)

## SecurePassword.ps1
A small collection of functions that can be used to encrypt and decrypt passwords using a 256-bit AES key.

## RaidMonitor.ps1
A script that can be scheduled to check the HPE SmartArray status of Hyper-V Servers using remote PowerShell. Utilises SecurePassword.ps1 for encrypted passwords. Will send an email out with the status of each server in the format of:

|Server|RAID Status|
|-|-|
|Server01|Healthy|
|Server02|Failed|
|Server03|Failed to communicate with host|