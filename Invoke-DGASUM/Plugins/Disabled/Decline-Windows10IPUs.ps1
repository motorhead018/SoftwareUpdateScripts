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
Decline updates for Windows 10 inplace upgrades to Windows 11.
.DESCRIPTION
Decline updates for Windows 10 inplace upgrades to Windows 11.
.NOTES
Written By: Bryan Dam
Modified By: William Bluhm
Version 1.0: 07/25/18
Version 1.1: 04/1/2025
#>

Function Invoke-SelectUpdatesPlugin {
    $DeclineUpdates = @{}
    if ($null -eq $ActiveUpdates -or $ActiveUpdates.Count -eq 0) {
        Write-Warning "No updates found in \$ActiveUpdates."
        Return $DeclineUpdates
    }

    $WindowsFeatureUpdates = ($ActiveUpdates | Where-Object {$_.Title -ilike "Feature update to Windows 10*"})

    if ($WindowsFeatureUpdates.Count -eq 0) {
        Write-Warning "No Windows 10 feature updates found."
    } else {
        ForEach ($Update in $WindowsFeatureUpdates) {
            $DeclineUpdates.Set_Item($Update.Id.UpdateId, "Windows 10 Feature Update")
        }
    }

    Return $DeclineUpdates
}
