# Script to easily remove multiple VMs after deployment
# Myles Petersen - Aug 19, 2021

Write-Host "`nThis Script is used to a delete multiple VMs that are named similarly. (Wildcards can be used)" -ForegroundColor Yellow
Write-Host "Enter the search string for the VMs you would like to delete. (For deleting only one VM, just enter its name)" -ForegroundColor Yellow
Write-Host "Ex: 'test-*' would delete every vm starting with 'test-'" -ForegroundColor Yellow
Write-Host "Take extra caution not to delete other people's VMs, and double check the confirmation messages!" -BackgroundColor Red -ForegroundColor White

# Get Input from user
$vms = Read-Host "Enter String (Not case-sensitive)"

# Check in case user enters JUST a wildcard
if ($vms -eq '*') {
    Write-Host "Entering this term would delete ALL VMs! Exiting..." -ForegroundColor Red
    exit
}

$Error.Clear()
# If Get-VM fails, then no VMs exist with that name, so exit
$ToBeDeleted = Get-VM $vms -ErrorAction SilentlyContinue
if ($error) {
    Write-Host "`nNo VMs found. Exiting..." -ForegroundColor Red
    exit
}

Write-Host "`nFor each VM, you will be prompted to confirm stopping the VM, then to confirm removing the VM.`n" -ForegroundColor Yellow
Write-Host "VMs to be deleted: ($ToBeDeleted)" -BackgroundColor Red -ForegroundColor White
Write-Host

# Stop and remove VMs
Stop-VM $vms  -ErrorAction SilentlyContinue
Remove-VM $vms -DeletePermanently -ErrorAction SilentlyContinue