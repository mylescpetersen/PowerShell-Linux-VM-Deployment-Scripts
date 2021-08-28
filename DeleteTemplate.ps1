# Script to easily remove Templates after deployment
# Myles Petersen - Aug 19

Write-Host "This Script is used to a delete multiple Templates that are named similarly. (Wildcards can be used)" -ForegroundColor Yellow
Write-Host "Take extra caution not to delete other people's Templates, and double check the confirmation messages!" -BackgroundColor Red -ForegroundColor White

# Get Input from user
Write-Host "`nEnter the version of the FIRMWARE_NAME template you would like to remove." -ForegroundColor Yellow
$Template = "Linux-FIRMWARE_NAME-"
$TemplateVersion = Read-Host "Enter FIRMWARE_NAME version (Ex: 'Release-33')"
$Template = $Template + $TemplateVersion

$Error.Clear()
# If Get-VM fails, then no VMs exist with that name, so exit
$ToBeDeleted = Get-Template $Template -ErrorAction SilentlyContinue
if ($error) {
    Write-Host "`nNo Template found. Exiting..." -ForegroundColor Red
    exit
}

Write-Host "`nTemplates to be deleted: ($ToBeDeleted)" -BackgroundColor Red -ForegroundColor White

# Stop and remove VMs
$ToBeDeleted | Remove-Template -DeletePermanently -ErrorAction SilentlyContinue