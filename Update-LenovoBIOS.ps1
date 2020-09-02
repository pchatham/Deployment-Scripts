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
		Add this script to root of extracted Lenovo BIOS update folder.
		Create package for SCCM / MDT (if required)
		Adapted from VB script from windowstech.net https://windowstech.net/lenovo-bios-update-script
		
	.USAGE
	    powershell.exe -executionpolicy bypass -file "Update-LenovoBIOS.ps1"
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
	param
	(
		[Parameter(Position = 1)]
		[ValidateSet('winuptp', 'Flash', IgnoreCase = $true)]
		[Alias('u')]
		$updateType
	)
	
	switch ($updateType) {
		'Flash' {
			$cmdPath = "$($currentDir)\flash.cmd"
			$args = "/quiet /sccm"
		}
		'winuptp' {
			$cmdPath = "$($currentDir)\winuptp.exe"
			$args = '-s'
		}
	}
	
	Write-Log "Executing BIOS Update with [$($updateType)] updater"
	
	if (Test-Path "$($currentDir)\phlash.ini") {
		Write-Log "Removing 'phlash.ini'`r" -Type Warning
		Remove-Item "$($currentDir)\phlash.ini"
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
Write-Output "Current Directory : $($currentDir)"
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
$PowerOnline = (Get-CimInstance -ClassName BatteryStatus -Namespace root/wmi).PowerOnline

$Model = $HardwareInfo.Version
$BIOSversion = $BIOSInfo.SMBIOSBIOSVersion.Substring(0, $BIOSInfo.SMBIOSBIOSVersion.Length - 8)

Write-Log "=============================="
Write-Log "MAKE : $($HardwareInfo.Vendor)"
Write-Log "MODEL : $($Model)"
Write-Log "BIOS Version : $BIOSversion"
Write-Log "Power Online : $($PowerOnline)"
Write-Log "==============================`r`r"

if (!($PowerOnline)) {
	Write-Log "NO AC POWER DETECTED. UPDATE MAY NOT EXECUTE" -Type Warning
}

if ($($HardwareInfo.Vendor) -ne 'LENOVO') {
	Write-Log -Type Error "NOT A LENOVO DEVICE"
	Write-Log -Type Error "EXITING"
	break
}
#endregion Gather

#region Determine if WINUPTP or FLASH Updater
if (Get-ChildItem -Path $currentDir -File winuptp.exe) {
	Write-Log "Found Winuptp.exe updater"
	$updateType = 'winuptp'
}
elseif (Get-ChildItem -Path $currentDir -File Flash.cmd) {
	Write-Log "Found Flash.cmd updater"
	$updateType = 'Flash'
}
#endregion Determine if WINUPTP or FLASH Updater

#region WINUPTP Logic for Version comparison
if ($updateType -eq 'winuptp') {
	$updateFolder = Get-ChildItem -Path $($currentDir) | Where-Object -Property Name -Like $BIOSversion
	if (Test-Path -Path $updateFolder) {
		$updateVersion = $($updateFolder.Name)
		Write-Log "Current BIOS Version : $($BIOSversion)"
		Write-Log "Update Folder BIOS Version : $($updateVersion)"
		
		if ($BIOSversion -lt $updateVersion) {
			
			Write-Log "Update Required" -Type Warning
			$updateRequired = $true
		}
		else {
			Write-Log "Update NOT Required" -Type Warning
			$updateRequired = $false
		}
		
	}
	else {
		Write-Log "Unable to find update folder" -Type Error
		Break
	}
}
#endregion WINUPTP Logic for Version comparison

#region FLASH Logic for Version comparison
if ($updateType -eq 'Flash') {
	if (Test-Path -Path "$($currentDir)\Changes.txt") {
		Write-Log "Found 'Changes.txt'"
		Write-Log "Parsing file for latest update.."
		$updateFile = Get-Content -Path "$($currentDir)\Changes.txt" | Select-String -SimpleMatch "CHANGES for" | Select-Object -First 1
		$updateVersion = $updateFile.Substring($updateVersion.Length - 8)
		
		Write-Log "Update Folder BIOS Version : $($updateVersion)" -Type Warning
		Write-Log "Current BIOS Version : $($BIOSversion)" -Type Warning
		
		if ($BIOSversion -lt $updateVersion) {
			
			Write-Log "Update Required" -Type Warning
			$updateRequired = $true
		}
		else {
			Write-Log "Update NOT Required" -Type Warning
			$updateRequired = $false
		}
	}
	else {
		Write-Log "Unable to find update 'Changes.txt'" -Type Error
		Break
	}
}
#endregion FLASH Logic for Version comparison

#region Execute Update
if ($updateRequired) {
	Write-Log "Begining BIOS Upate"
	Execute-BIOSupdate -updateType $updateType
}
#endregion Execute Update
