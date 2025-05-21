[CmdletBinding(SupportsShouldProcess=$True)]
Param(

    #The automatic deployment rule ID to run.
    [int[]] $Id,
		
    #Array of names of automatic deployment rules to run.
    [string[]] $Name,

    #Use wildcard handline for the name.
    [switch] $ForceWildcardHandling,

    #Run each rule consecutively.
    [switch] $Consecutive,

    #Only run the script within a week of Patch Tuesday.
    [switch] $WeekOfPatchTuesday,

    #Number of minutes to wait for each ADR to run.
    [int] $Timeout=60,

    #Set the log file.
    [string] $LogFile,

    #The maximum size of the log in bytes.
    [int]$MaxLogSize = 2621440,

    #Define the sitecode.
    [string] $SiteCode

)

#Taken from https://gallery.technet.microsoft.com/scriptcenter/Add-TextToCMLog-Function-ea238b85
Function Add-TextToCMLog {

##########################################################################################################
<#
.SYNOPSIS
   Log to a file in a format that can be read by Trace32.exe / CMTrace.exe 

.DESCRIPTION
   Write a line of data to a script log file in a format that can be parsed by Trace32.exe / CMTrace.exe

   The severity of the logged line can be set as:

        1 - Information
        2 - Warning
        3 - Error

   Warnings will be highlighted in yellow. Errors are highlighted in red.

   The tools to view the log:

   SMS Trace - http://www.microsoft.com/en-us/download/details.aspx?id=18153
   CM Trace - Installation directory on Configuration Manager 2012 Site Server - <Install Directory>\tools\

.EXAMPLE
   Add-TextToCMLog c:\output\update.log "Application of MS15-031 failed" Apply_Patch 3

   This will write a line to the update.log file in c:\output stating that "Application of MS15-031 failed".
   The source component will be Apply_Patch and the line will be highlighted in red as it is an error 
   (severity - 3).

#>
##########################################################################################################

#Define and validate parameters
[CmdletBinding()]
Param(
      #Path to the log file
      [parameter(Mandatory=$True)]
      [String]$LogFile,

      #The information to log
      [parameter(Mandatory=$True)]
      [String]$Value,

      #The source of the error
      [parameter(Mandatory=$True)]
      [String]$Component,

      #The severity (1 - Information, 2- Warning, 3 - Error)
      [parameter(Mandatory=$True)]
      [ValidateRange(1,3)]
      [Single]$Severity
      )


#Obtain UTC offset
$DateTime = New-Object -ComObject WbemScripting.SWbemDateTime 
$DateTime.SetVarDate($(Get-Date))
$UtcValue = $DateTime.Value
$UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)


#Create the line to be logged
$LogLine =  "<![LOG[$Value]LOG]!>" +`
            "<time=`"$(Get-Date -Format HH:mm:ss.fff)$($UtcOffset)`" " +`
            "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
            "component=`"$Component`" " +`
            "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
            "type=`"$Severity`" " +`
            "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
            "file=`"`">"

#Write the line to the passed log file
Out-File -InputObject $LogLine -Append -NoClobber -Encoding Default -FilePath $LogFile -WhatIf:$False

}
##########################################################################################################

#Note: This function is provided in 1706 so this is just a stop-gab until that version has reached critical mass.
Function Get-CMSoftwareUpdateSyncStatus {
##########################################################################################################
<#
.SYNOPSIS
   Returns the sync status for each software update point in the site.
#>
##########################################################################################################

$SyncStatus = Get-WmiObject -Namespace "ROOT\SMS\site_$($SiteCode)" -Query "Select * from SMS_SUPSyncStatus"
$Results = @()

#Cretae a new object to convert WMI's CIM_DATETIME to PowerShell DateTime
ForEach ($status in $SyncStatus){
    If ($status.LastReplicationLinkCheckTime){ $LastReplicationLinkCheckTime = [Management.ManagementDateTimeConverter]::ToDateTime($status.LastReplicationLinkCheckTime)}
    If ($status.LastSuccessfulSyncTime){ $LastSuccessfulSyncTime = [Management.ManagementDateTimeConverter]::ToDateTime($status.LastSuccessfulSyncTime)}
    If ($status.LastSyncStateTime){ $LastSyncStateTime = [Management.ManagementDateTimeConverter]::ToDateTime($status.LastSyncStateTime)}


    $properties = @{'LastReplicationLinkCheckTime'=$LastReplicationLinkCheckTime;
                'LastSuccessfulSyncTime'=$LastSuccessfulSyncTime;
                'LastSyncErrorCode'=$status.LastSyncErrorCode;
                'LastSyncState'=$status.LastSyncState;
                'LastSyncStateTime'=$LastSyncStateTime;
                'ReplicationLinkStatus'=$status.ReplicationLinkStatus;
                'SiteCode'=$status.SiteCode;
                'SyncCatalogVersion'=$status.SyncCatalogVersion;
                'WSUSServerName'=$status.WSUSServerName;
                'WSUSSourceServer'=$status.WSUSSourceServer}

    $Results+= New-Object �TypeName PSObject �Prop $properties
}


Return $Results

}
##########################################################################################################

Function Invoke-SyncCheck {
##########################################################################################################
<#
.SYNOPSIS
   Invoke a syncronization check on all software update points.

.DESCRIPTION
   When ran this function will wait for the software update point syncronization process to complete
   successfully before continuing.

.EXAMPLE
   Invoke-SyncCheck

#>
##########################################################################################################
    [CmdletBinding()]
    Param(
        #The number of minutes to wait after the last sync to run the wizard.
        [int]$SyncLeadTime = 5
    )

    $WaitInterval = 0 #Used to skip the initial wait cycle if it isn't necessary.
    Do{
    
        #Wait until the loop has iterated once.
        If ($WaitInterval -gt 0){
            Add-TextToCMLog $LogFile "Waiting $TimeToWait minutes for lead time to pass before executing." $component 1
            Start-Sleep -Seconds ($WaitInterval)  
        }    

        #Loop through each SUP and wait until they are all done syncing.
        Do {
            #If syncronizing then wait.
            If($Syncronizing){
                Add-TextToCMLog $LogFile "Waiting for software update points to stop syncing." $component 1  
                Start-Sleep -Seconds (300)  
            }

            $Syncronizing = $False
            ForEach ($softwareUpdatePointSyncStatus in Get-CMSoftwareUpdateSyncStatus){
                If($softwareUpdatePointSyncStatus.LastSyncState -eq 6704){$Syncronizing = $True}
            }
        } Until(!$Syncronizing)


        #Loop through each SUP, calculate the last sync time, and make sure that they all synced successfully.
        $syncTimeStamp = Get-Date "1/1/2001 12:00 AM"
        ForEach ($softwareUpdatePointSyncStatus in Get-CMSoftwareUpdateSyncStatus){
            If ($softwareUpdatePointSyncStatus.LastSyncErrorCode -ne 0){
                Add-TextToCMLog $LogFile "The software update point $($softwareUpdatePointSyncStatus.WSUSServerName) failed its last syncronization with error code $($softwareUpdatePointSyncStatus.LastSyncErrorCode).  Syncronize successfully before running $component." $component 2
                Return
            }

            If ($syncTimeStamp -lt $softwareUpdatePointSyncStatus.LastSyncStateTime) {
                $syncTimeStamp = $softwareUpdatePointSyncStatus.LastSyncStateTime
            }
        }

 
        #Calculate the remaining time to wait for the lead time to expire.
        $TimeToWait = ($syncTimeStamp.AddMinutes($SyncLeadTime) - (Get-Date)).Minutes

        #Set the wait interval in seconds for subsequent loops.
        $WaitInterval = 300
    } Until ($TimeToWait -le 0)

    Add-TextToCMLog $LogFile "Software update point syncronization states confirmed." $component 1
}
##########################################################################################################
##########################################################################################################
function Test-RegistryValue {

    Param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Path,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Value
    )

    Try {
        Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Value -ErrorAction Stop | Out-Null
        Return $true
    } catch {
        Return $false
    }
}


##########################################################################################################


##########################################################################################################
Function Get-SiteCode {

    #See if a PSDrive exists with the CMSite provider
    $PSDriveExists = $False
    Try {
        Get-PSDrive -PSProvider CMSite -ErrorAction Stop | Out-Null
        $PSDriveExists = $False
    } catch {
        $PSDriveExists = $True
    }

    #If PSDrive exists then get the site code from it.  Otherwise, try to create the drive.
    If ($PSDriveExists) {        
        $SiteCode = Get-PSDrive -PSProvider CMSite
    } Else {
        #Try to determine the site code if none was passed in.
        If (-Not ($SiteCode) ) {
            If (Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" -Value "Site Code"){
                $SiteCode =  Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" | Select-Object -ExpandProperty "Site Code"
            } ElseIf (Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client" -Value "AssignedSiteCode") {            
                $SiteCode =  Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client" | Select-Object -ExpandProperty "AssignedSiteCode"
            } Else {
                Return
            }
        }
    }

    Return $SiteCode
}
##########################################################################################################

$cmSiteVersion = [version]"5.00.8540.1000"

#If log file is null then set it to the default and then make the provider type explicit.
If (!$LogFile){$LogFile = Join-Path $PSScriptRoot "invokeadr.log"}
$LogFile = "filesystem::$($LogFile)"


#Generate the compnent used for loggins based on the script name.
$component = (Split-Path $PSCommandPath -Leaf).Replace(".ps1", "")

#If the log file exists and is larger then the maximum then roll it over.
If (Test-path  $LogFile -PathType Leaf) {    
    If ((Get-Item $LogFile).length -gt $MaxLogSize){
        Move-Item -Force $LogFile ($LogFile -replace ".$","_") -WhatIf:$False
    }
}

Add-TextToCMLog $LogFile "$component started." $component 1

#Make sure the last Patch Tuesday was less than a week away.
If ($WeekOfPatchTuesday){    
    #Care of: http://www.madwithpowershell.com/2014/10/calculating-patch-tuesday-with.html
    $BaseDate = ( Get-Date -Day 12 ).Date
    $PatchTuesday = $BaseDate.AddDays( 2 - [int]$BaseDate.DayOfWeek )
    If (((Get-Date) -lt $PatchTuesday) -or ((Get-Date) -gt $PatchTuesday.AddDays(7))){
        Add-TextToCMLog $LogFile "Patch Tuesday is over a week ago. Exiting." $component 2
        Return
    } Else {
        Add-TextToCMLog $LogFile "Patch Tuesday was this week." $component 1
    }
}


#Make sure at least one action parameter was given.
If (!$Id -and !$Name) {
    Add-TextToCMLog $LogFile "You must provide either the ID or name(s) of the ADRs to run." $component 2
    Return
}

#If the Name parameter has only one element with commas in it then try to split it.
If ($Name){
    If ($Name.Count -eq 1){
        If ($Name[0] -like '*,*'){            
            $Name = $Name[0].Split(",")
            Add-TextToCMLog $LogFile "The Name parameter only had one element that contained commas.  It has been split into $($Name.Count) separate elements." $component 2
        }
    }
}

#If the Configuration Manager module exists then load it.
If (! $env:SMS_ADMIN_UI_PATH)
{
    Add-TextToCMLog $LogFile "The SMS_ADMIN_UI_PATH environment variable is not set.  Make sure the SCCM console it installed." $component 3
    Return
}
$configManagerCmdLetpath = Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) "ConfigurationManager.psd1"
If (! (Test-Path $configManagerCmdLetpath -PathType Leaf) )
{
    Add-TextToCMLog $LogFile "The ConfigurationManager Module file could not be found.  Make sure the SCCM console it installed." $component 3
    Return
}

#You can't pass whatif to the Import-Module function and it spits out a lot of text, so work around it.
$WhatIf = $WhatIfPreference
$WhatIfPreference = $False
Import-Module $configManagerCmdLetpath -Force
$WhatIfPreference = $WhatIf

#Get the site code
If (!$SiteCode){$SiteCode = Get-SiteCode}

#If the PS drive doesn't exist then try to create it.
If (! (Test-Path "$($SiteCode):")) {
    Try{
        Add-TextToCMLog $LogFile "Trying to create the PS Drive $($SiteCode)" $component 1
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root "." -WhatIf:$False | Out-Null   
    } Catch {
        Add-TextToCMLog $LogFile "The site's PS drive doesn't exist nor could it be created." $component 3
        Add-TextToCMLog $LogFile "Error: $($_.Exception.Message)" $component 3
        Add-TextToCMLog $LogFile "$($_.InvocationInfo.PositionMessage)" $component 3    
        Return
    }
}

#Change the directory to the site location.
$OriginalLocation = Get-Location

#Set and verify the location.
Try{
    Add-TextToCMLog $LogFile "Connecting to site: $($SiteCode)" $component 1        
    Set-Location "$($SiteCode):"  | Out-Null
} Catch {
    Add-TextToCMLog $LogFile "Could not set location to site: $($SiteCode)." $component 3
    Add-TextToCMLog $LogFile "Error: $($_.Exception.Message)" $component 3
    Add-TextToCMLog $LogFile "$($_.InvocationInfo.PositionMessage)" $component 3
    Return
}

#Make sure the site code matches the PS drive's site code.
If ($SiteCode -ne (Get-CMSite).SiteCode) {
    Add-TextToCMLog $LogFile "The site code $($SiteCode) does not match the current site $((Get-CMSite).SiteCode)." $component 3
    Return
}

#Verify the version of configuration manager.
If ((Get-CMSite).Version -lt $cmSiteVersion){
    Write-Warning "$($ModuleName) requires configuration manager cmdlets $($cmSiteVersion.ToString()) or greater."
}

Invoke-SyncCheck 

#Create the list of ADRs to run.
$ADRList = @()
Try{
    If ($Id){        
        #Get the ADR and if it exists add it to the list.
        $ADR = Get-CMSoftwareUpdateAutoDeploymentRule -Id $Id -Fast
        If ($ADR){
            If (! $ADR.AutoDeploymentEnabled) {
                Add-TextToCMLog $LogFile "The '$($ADR.Name)' automatic deployment rule is disabled and was not added to the list." $component 2
            } Else {
                $ADRList+=$ADR
                Add-TextToCMLog $LogFile "Added the '$($ADR.Name)' automatic deployment rule to the list." $component 1
            }
        }

    } ElseIf ($Name){
        #Loop through each name string.
        ForEach ($searchString in $Name){
            #Get the ADRs            
            Add-TextToCMLog $LogFile "Searching for ADRs matching '$($searchString)'." $component 1
            $ADRs = Get-CMSoftwareUpdateAutoDeploymentRule -Name $searchString -ForceWildcardHandling:$ForceWildcardHandling -Fast
            #Add each ADR to the list.
            ForEach ($ADR in $ADRs) {
                If (! $ADR.AutoDeploymentEnabled) {
                    Add-TextToCMLog $LogFile "The '$($ADR.Name)' automatic deployment rule is disabled and was not added to the list." $component 2
                } Else {
                    $ADRList+=$ADR
                    Add-TextToCMLog $LogFile "Added the '$($ADR.Name)' automatic deployment rule to the list." $component 1
                }
            }
        }

    } Else {
        Add-TextToCMLog $LogFile "Error: invalid parameters sent in find routine." $component 3
    }

    Add-TextToCMLog $LogFile "Found $($ADRList.Count) automatic deployment rule(s) to run." $component 1

} Catch {
    Add-TextToCMLog $LogFile "Failed to find automatic deployment rules." $component 3
    Add-TextToCMLog $LogFile "Error: $($_.Exception.Message)" $component 3
    Add-TextToCMLog $LogFile "$($_.InvocationInfo.PositionMessage)" $component 3
}

#If ADRs were found then run them.
If ($ADRList.Count -gt 0){
    ForEach ($ADR in $ADRList){
        Try{
            Invoke-CMSoftwareUpdateAutoDeploymentRule -Id $ADR.AutoDeploymentID -WhatIf:$WhatIfPreference
            Add-TextToCMLog $LogFile "Running the '$($ADR.Name)' automatic deployment rule." $component 1

            #If running consecutively, wait for the ADR to finish.
            If ($Consecutive){
                $EndTime = (Get-Date).AddMinutes($Timeout)
                $AutoDeploymentID = $ADR.AutoDeploymentID

                #If WhatIf was used then game the last runtime value.
                If ($WhatIfPreference){
                    $LastRunTime = (Get-Date).AddMinutes(($Timeout * -1))
                    $SleepSeconds=0
                } Else {
                    $LastRunTime=$ADR.LastRunTime
                    $SleepSeconds=30
                }

                #Wait for the ADR last run time to change or the timeout period to end.
                Add-TextToCMLog $LogFile "Waiting for the '$($ADR.Name)' automatic deployment rule to complete." $component 1                
                Do {
                    Start-Sleep -Seconds $SleepSeconds
                    $ADR = Get-CMSoftwareUpdateAutoDeploymentRule -Id $AutoDeploymentID -Fast                    

                } While (($LastRunTime -ge $ADR.LastRunTime) -and ($EndTime -gt (Get-Date)))

                #Determine if we timed out and if not see if the ADR ran successfully or not.
                If ($EndTime -lt (Get-Date)){
                    Add-TextToCMLog $LogFile "Timed out while waiting for the '$($ADR.Name)' automatic deployment rule to complete." $component 2
                } Else {
                    If ($ADR.LastErrorCode -ne 0){
                        Add-TextToCMLog $LogFile "The '$($ADR.Name)' automatic deployment rule failed with error $($ADR.LastErrorCode)." $component 1
                    } Else {
                        Add-TextToCMLog $LogFile "The '$($ADR.Name)' automatic deployment rule ran successfully." $component 1
                    }                    
                }
            }

        } Catch {
            Add-TextToCMLog $LogFile "Failed to run the '$($ADR.Name)' automatic deployment rule." $component 3
            Add-TextToCMLog $LogFile "Error: $($_.Exception.Message)" $component 3
            Add-TextToCMLog $LogFile "$($_.InvocationInfo.PositionMessage)" $component 3
        }    
    }

}

Add-TextToCMLog $LogFile "$component finished." $component 1
Set-Location $OriginalLocation
Return
