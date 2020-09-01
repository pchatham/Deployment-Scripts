<#	
	.NOTES
	===========================================================================
	 Created on:   	01/09/2020
	 Created by:   	Phil Chatham
	 Filename:     	Update-LenovoBIOS
	===========================================================================
	.DESCRIPTION
		Updates Lenovo BIOS based on current detected firmware version

	.NOTES
		Create a folder for each hardware model and add it under the "MODIFY HARDWARE LIST" section
		Added Example hardware models
		Adapted from VB script from windowstech.net https://windowstech.net/lenovo-bios-update-script
#>

#region function Write-Log
# Writes a cmtrace compatible Log file
function Write-log {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[String]
		$Path = $logpath,
		[Parameter(Mandatory = $false,
				   Position = 1)]
		[String]
		$Message = " ",
		[Parameter(Mandatory = $false)]
		[String]
		$Component = $($AppName),
		[Parameter(Mandatory = $false)]
		[ValidateSet('Info', 'Warning', 'Error')]
		[String]
		$Type = "Info"
	)
	
	switch ($Type) {
		"Info" {
			[int]$Type = 1
		}
		"Warning" {
			[int]$Type = 2
		}
		"Error" {
			[int]$Type = 3
		}
	}
	# Test for Log file
	if (!(Test-Path $logpath)) {
		New-Item -Path "$logroot" -ItemType file -Name $logname -Force
	}
	# Create a log entry
	$Content = "<![LOG[$Message]LOG]!>" +`
	"<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " +`
	"date=`"$(Get-Date -Format "M-d-yyyy")`" " +`
	"component=`"$Component`" " +`
	"context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
	"type=`"$Type`" " +`
	"thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
	"file=`"`">"
	
	# Write the line to the log file
	Add-Content -Path $Path -Value $Content
}
#endregion function Write-Log

#region function Execute-BIOSupdate
function Execute-BIOSupdate {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias('F')]
		[string]
		$FolderName
	)
	
	# determine update type (flash/winuptp)
	If (Test-Path "$($PSScriptRoot)\$($FolderName)\flash.cmd") {
		$uType = 'Flash'
		Write-Log "Update Type : $($uType)"
	}
	If (Test-Path "$($PSScriptRoot)\$($FolderName)\winuptp.exe") {
		$uType = 'winuptp'
		Write-Log "Update Type : $($uType)"
		Write-Log "=============================="
	}
	switch ($uType) {
		'Flash' {
			$cmdPath = "$($PSScriptRoot)\$($FolderName)\flash.cmd"
			$args = "/quiet /sccm"
		}
		'winuptp' {
			$cmdPath = "$($PSScriptRoot)\$($FolderName)\winuptp.exe"
			$args = '-s'
		}
	}
	
	if (Test-Path "$($PSScriptRoot)\$($FolderName)\phlash.ini") {
		Write-Log "Removing 'phlash.ini'`r" -Type Warning
		Remove-Item "$($PSScriptRoot)\$($FolderName)\phlash.ini"
	}
		
	#execute Update
	Write-Log "EXECUTING : $($cmdPath) $($args)" -Type Warning
	Start-Process $cmdPath -ArgumentList $args -WindowStyle Hidden -Wait
	EXIT 3010
}
#endregion function Update-Dektop

#region Variables & Setup
# Current Directory
$currentDir = $PSScriptRoot
Write-Log "Current Directory : $($currentDir)"
# Loading the COM object for the TS Environment, this is to read / write to TS Variables
$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment

# Setting up logpath if in OSD Process will log to _SMSTSLogPath variable else Windows\Temp
If ($tsenv) {
	# In a SCCM Task Sequence Environment
	$AppName = $script:MyInvocation.MyCommand.Name
	$AppName = $AppName -replace ".ps1", ""
	$AppName = $AppName -replace "Invoke-", "SMSTS-Script-"
	$logname = "$AppName.log"
	# Getting the log path variable "_SMSTSLogPath"
	$TSLogPath = $tsenv.Value("_SMSTSLogPath")
	$logroot = "$TSLogPath"
	$logpath = "$logroot\$logname"
	Write-Log "Running from a TS Environment"
	Write-Log "Log path is $($logpath)"
}
else {
	# Running in a normal Operating System Environment
	$logroot = "$env:SystemDrive\Windows\Logs"
	$AppName = $script:MyInvocation.MyCommand.Name
	$AppName = $AppName -replace ".ps1", ""
	$AppName = $AppName -replace "Invoke-", "PS-Script-"
	$logname = "$AppName.log"
	$logpath = "$logroot\$logname"
	Write-Log "NOT Running from a TS Environment" -Type Warning
	Write-Log "Log path is : $($logpath)"
}
#endregion Variables & Setup

#region Gather Hardware Info
$HardwareInfo = Get-CimInstance -ClassName Win32_ComputerSystemProduct
$BIOSInfo = Get-CimInstance -ClassName Win32_BIOS

$Model = $HardwareInfo.Version
$BIOSversion = $BIOSInfo.SMBIOSBIOSVersion.Substring(0, $BIOSInfo.SMBIOSBIOSVersion.Length - 8)

Write-Log "=============================="
Write-Log "MAKE : $($HardwareInfo.Vendor)"
Write-Log "MODEL : $($Model)"
Write-Log "BIOS Version : $BIOSversion"
Write-Log "==============================`r`r"

if ($($HardwareInfo.Vendor) -ne 'LENOVO') {
	Write-Log -Type Error "NOT A LENOVO DEVICE"
	Write-Log -Type Error "EXITING"
	break
}
#endregion Gather

#region MODIFY HARDWARE LIST

#region Laptops

# Thinkpad T480
If ($Model -eq "THINKPAD T480" -and $BIOSversion -lt "N24ET59W") {
	
	Execute-BIOSupdate -FolderName 'T480'
}

# ThinkPad T490
If ($Model -eq "THINKPAD T490") {
	
	if ($BIOSversion -lt "N2IET71W") {
		Execute-BIOSupdate -FolderName 'T490_1'
		# 1.12 must be applied before any later version Setting Var to tell TS to update again
		$tsenv.Value("BIOS2REQ") = "TRUE" # Set this in TS as condition
	}
	elseif ($BIOSversion -lt "N2IET90W") {
		Execute-BIOSupdate -FolderName 'T490_1'
	}
}

# ThinkPad X390
	If ($Model -eq "THINKPAD X390" -and $BIOSversion -lt "N2JET89W") {
		Execute-BIOSupdate -FolderName "X390"
}

# ThinkPad P50
If ($Model -eq "THINKPAD_P50" -and $BIOSversion -lt "N1EET88W") {
	Execute-BIOSupdate -FolderName 'P50' 
}

#endregion Laptops	

#region Desktop
# Add desktop models here
#endregion Desktop

#endregion MODIFY HARDWARE LIST
