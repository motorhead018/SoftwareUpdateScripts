<#
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
#>

<#
.SYNOPSIS
Decline updates for defined versions of Windows 10.
.DESCRIPTION
Decline updates for defined versions of Windows 10.
.NOTES
You must un-comment the $UnsupportedVersions variable and add the versions your organization does not support.
Written By: Bryan Dam
Version 1.0: 10/25/17
Version 2.4: 07/20/18
    Added support for Win 7 and 8.1 in place upgrade updates.
Version 2.4.6: 12/20/19
    Add 1903+ and Insider product categories.
Version 2.5.0: 05/20/25 
	Converted script to support Windows 11 editions.
#>

#Un-comment and add elements to this array for versions you no longer support.
$UnsupportedVersions = @("21H2","22H2")
Function Invoke-SelectUpdatesPlugin{

    $DeclineUpdates = @{}
    If (!$UnsupportedVersions){Return $DeclineUpdates}

    $Windows11Updates = ($ActiveUpdates | Where{$_.ProductTitles.Contains('Windows 11')})

    #Loop through the updates and decline any that match the version.
    ForEach ($Update in $Windows11Updates){

        #If the title contains a version number.
        If ($Update.Title -match "Version \d\d\d\d" -and (! (Test-Exclusions $Update))){

            #Capture the version number.
            $Version = $matches[0].Substring($matches[0].Length - 4)

            #If the version number is in the list then decline it.
            If ($UnsupportedVersions.Contains($Version)){
                $DeclineUpdates.Set_Item($Update.Id.UpdateId,"Windows 11 Version: $($Version)")
            }
        }
    }
    Return $DeclineUpdates
}
