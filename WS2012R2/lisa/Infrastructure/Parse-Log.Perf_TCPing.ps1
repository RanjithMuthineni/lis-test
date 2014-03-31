########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################



<#
.Synopsis
    Parse the network bandwidth data from the TCPing test log.

.Description
    Parse the network bandwidth data from the TCPing test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_TCPing.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_TCPing.xml

#>

param( [string]$LogFolder, [string]$XMLFileName, [string]$LisaInfraFolder )


#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript "$LogFolder\Parse-Log.Perf_TCPing.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-Log.Perf_TCPing.ps1]..." -foregroundcolor cyan
Write-Host "`$LogFolder        = $LogFolder" 
Write-Host "`$XMLFileName      = $XMLFileName" 
Write-Host "`$LisaInfraFolder  = $LisaInfraFolder" 

#----------------------------------------------------------------------------
# Verify required parameters
#----------------------------------------------------------------------------
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}

# check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
else
{
    if (! (test-path $XMLFileName))
    {
        write-host -f Red "Error: XML config file '$XMLFileName' does not exist."
        Throw "Parameter XmlFilename is required."
    }
}

$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    return $false
}

if ($LisaInfraFolder -eq $null -or $LisaInfraFolder -eq "")
{
    Throw "Parameter LisaInfraFolder is required."
}

#----------------------------------------------------------------------------
# The log file pattern produced by the TCPing tool
#----------------------------------------------------------------------------
$TCPingLofFile = "*_tcping.log"

#----------------------------------------------------------------------------
# Read the TCPing log file
#----------------------------------------------------------------------------
$latencyInMS = "0"

$icaLogs = Get-ChildItem "$LogFolder\$TCPingLofFile" -Recurse
Write-Host "Number of Log files found: "
Write-Host $icaLogs.Count

# should only have one file. but in case there are more than one files, just use the last one simply
foreach ($logFile  in $icaLogs)
{
    Write-Host "One log file has been found: $logFile" 
    
    #we should find the result in the last line
    #use the "min" as the factor
    #result example:   min = 1.213, avg = 1.778, max = 1.923
    $resultFound = $false
    $iTry=1
    while (($resultFound -eq $false) -and ($iTry -lt 3))
    {
        $line = (Get-Content $logFile)[-1* $iTry]
        Write-Host $line

        if ($line.Trim() -eq "")
        {
            $iTry++
            continue
        }
        elseif ( ($line.StartsWith("min") -eq $false) -or ($line.Contains("avg") -eq $false) -or ($line.Contains("max") -eq $false))
        {
            $iTry++
            continue
        }
        else
        {
            $element = $line.Split(',')
            $latencyInMS = $element[0].Replace("min","").Replace("=","").Trim()
            Write-Host "The min latency is: " $latencyInMS  "(ms)"
            break
        }
    }
}

#----------------------------------------------------------------------------
# Read TCPing configuration from XML file
#----------------------------------------------------------------------------
# define the test params we need to find from the XML file
$VMName = [string]::Empty
$numberOfVMs = $xmlConfig.config.VMs.ChildNodes.Count
Write-Host "Number of VMs defined in the XML file: $numberOfVMs"
if ($numberOfVMs -eq 0)
{
    Throw "No VM is defined in the LISA XML file."
}
elseif ($numberOfVMs -gt 1)
{
    foreach($node in $xmlConfig.config.VMs.ChildNodes)
    {
        if (($node.role -eq $null) -or ($node.role.ToLower() -ne "nonsut"))
        {
            #just use the 1st SUT VM name
            $VMName = $node.vmName
            break
        }
    }
}
else
{
    $VMName = $xmlConfig.config.VMs.VM.VMName
}
if ($VMName -eq [string]::Empty)
{
    Write-Host "!!! No VM is found from the LISA XML file."
}
Write-Host "VMName: " $VMName

#
# --Nothing to do here anymore
#

#----------------------------------------------------------------------------
# Call LisaRecorder to log data into database
#----------------------------------------------------------------------------
# LisPerfTest_TCPing hostos:Windows hostname:lisinter-hp2 guestos:Linux linuxdistro:RHEL6.4X64 testcasename:Perf_TCPing latencyInMS:1.2345
$LisaRecorder = "$LisaInfraFolder\LisaLogger\LisaRecorder.exe"
$params = "LisPerfTest_TCPing"
$params = $params+" "+"hostos:`"" + (Get-WmiObject -class Win32_OperatingSystem).Caption + "`""
$params = $params+" "+"hostname:`"" + "$env:computername.$env:userdnsdomain" + "`""
$params = $params+" "+"guestos:`"" + "Linux" + "`""
$params = $params+" "+"linuxdistro:`"" + "$VMName" + "`""
$params = $params+" "+"testcasename:`"" + "Perf_TCPing" + "`""
$params = $params+" "+"latencyinms:`"" + $latencyInMS + "`""

Write-Host "Executing LisaRecorder to record test result into database"
Write-Host $params

Start-Process -FilePath $LisaRecorder -Wait -ArgumentList $params -RedirectStandardOutput "$LogFolder\LisaRecorderOutput.log" -RedirectStandardError "$LogFolder\LisaRecorderError.log"

Write-Host "Executing LisaRecorder finished."

Stop-Transcript
exit 0
