# PowerShell
Just a collection of PowerShell scripts I create for use at work. Hopefully someone else might fun them or parts of them useful.

*Note: These are built for my work's environment and may need adjusting to fit yours.*

Any improvements are welcome :)

## SecurePassword.ps1
A small collection of functions that can be used to encrypt and decrypt passwords using a 256-bit AES key.

## RaidMonitor.ps1
A script that can be scheduled to check the HPE SmartArray status of Hyper-V & ESXI Servers using remote PowerShell. Utilises SecurePassword.ps1 for encrypted passwords. Will send an email out with the status of each server in the format of:

|Server|RAID Status|
|-|-|
|Server01|OK|
|Server02|Disk Failure|
|Server03|Unable to check aray status|
|Server04|Failed to communicate with server|

ESXI servers will need the HP Smart Array drivers and utility software installed. Hyper-V Servers will need ssacli to be installed.