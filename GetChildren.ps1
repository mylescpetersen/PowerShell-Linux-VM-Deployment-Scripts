# Script to get all child VMs of a specified Base(parent) VM
# Myles Petersen - Aug 19, 2021

# Get Input from user
Write-Host "`nEnter name of the parent FIRMWARE_NAME version that you would like to find children for:" -ForegroundColor Yellow
# Get name from prompt
$ParentName = Read-Host "(Ex: Release-34)"
# Convert to full Base VM name
$ParentNameFull = "Linux-FIRMWARE_NAME-$ParentName-BaseVM"

# Search for, and filter children of the specified parent
$ChildVMs = Get-VM | Get-Annotation -Name Parent | Where-Object {$_.value -eq $ParentNameFull}

# If no children exist --> print message, exit
if ($null -eq $ChildVMs) {
    Write-Host "`nNo child VMs of '$ParentNameFull' found." -BackgroundColor Red
    # For spacing
    Write-Host
    exit
}

# Print-out of results
Write-Host "`nAll children of $ParentNameFull`:" -ForegroundColor Yellow
# For spacing
Write-Host

# Print each child name
ForEach ($ChildName in $ChildVMs.AnnotatedEntity) {
    Write-Host $ChildName -ForegroundColor Yellow -BackgroundColor Black
}
# For spacing
Write-Host