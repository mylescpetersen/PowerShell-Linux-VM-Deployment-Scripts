<# -------------------------------------------------------------------------------------------------------------------------
Name: FIRMWARE_NAME VM Template Creation Script
Description: Script to automate creation of new FIRMWARE_NAME VM Templates.
Created By: Myles Petersen
Date: Aug 19, 2021, 2021

Requires: Posh-SSH (For SCP connection) https://github.com/darkoperator/Posh-SSH or 'Install-Module -Name Posh-SSH'
----------------------------------------------------------------------------------------------------------------------------#>

# -------------- CONSTANTS --------------

$MAX_PW_TRIES = 3

# ------------ END CONSTANTS ------------

# ------------------ GET FIRMWARE_NAME FILE ------------------

# Called if $IsManual is true
# Gets user to select a compatible FIRMWARE_NAME file the FIRMWARE_NAME archive folder
Function GetManualFile {

    # Ask user for full filepath
    Write-Host "`nChoose the FIRMWARE_NAME file you would like to create a template from:" -ForegroundColor yellow
    #$FIRMWARE_NAMELocation = Read-Host -Prompt "Enter path"

    # << Based on https://thomasrayner.ca/open-file-dialog-box-in-powershell/ >>
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.InitialDirectory = "<NETWORK_DRIVE_FIRMWARE_LOCATION>"

    # Prompt to determine whether to automatically get latest FIRMWARE_NAME, or specific version
    $FileChosen = $false
    while (!$FileChosen) {
        # Excludes ARM versions of FIRMWARE_NAME (only shows x86)
        $OpenFileDialog.Filter = "x86 (*x86*.*) |*x86*.*"
        $OpenFileDialog.ShowDialog() | Out-Null
        $FIRMWARE_NAMEFilePath = $OpenFileDialog.FileName
        Write-Host "$($FIRMWARE_NAMEFilePath)"
        if (!$FIRMWARE_NAMEFilePath) {
            $Prompt = $false
            while ($Prompt -eq $false) {
                Write-Host "`nNo file selected. Would you like to exit?" -BackgroundColor red
                $answer = Read-Host -Prompt "Enter (y/n)"
                if (($answer -like 'y') -or ($answer -like 'yes')) {
                    $Prompt  = $true
                    exit
                }
                elseif (($answer -like 'n') -or ($answer -like 'no')) {
                    $Prompt  = $true
                }
                else {
                    Write-Host "`nInvalid response. Please enter (y/n)" -BackgroundColor Red
                }
            }
        }
        else {$FileChosen = $true}
    }
    return $FIRMWARE_NAMEFilePath
}

# ------------------ END GET FIRMWARE_NAME FILE ------------------

# ------------ EXIT AFTER ERROR ----------------------
Function ExitFromError {
    param (
        [Parameter(Mandatory=$false)] $BadPW
        )

    # Print error
    Write-Host $error -ForegroundColor Red
    Write-Host

    # Remove VM
    Stop-VM $TemplateName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-VM $TemplateName -DeletePermanently -Confirm:$false -ErrorAction SilentlyContinue
    # Remove Temporary VM
    try {
    Stop-VM "$TemplateName-tmp" -Confirm:$false -ErrorAction Stop
    Remove-VM "$TemplateName-tmp" -DeletePermanently -Confirm:$false -ErrorAction Stop
    }
    catch {
        # Do nothing if tmp VM doesn't exist, and continue
    }

    # Default error message
    $ExitMessage = "`nOther exception occurred. `nDeleting current (unfinished) Template VM and exiting......"

    if ($BadPW) {
        $ExitMessage = "`n$MAX_PW_TRIES invalid password attempts.`nDeleting current (unfinished) Template VM and exiting..." 
    }

    # Print error message and exit
    Write-Host $ExitMessage -BackgroundColor Red
    exit
}

# ------------ END EXIT AFTER ERROR ----------------------

# -------------------- MAKE TEMPLATE --------------------

# Function 2 (Name, IsManual)
Function MakeTemplate {
    # Parameters
    param (
        [Parameter(Mandatory)] $Name,
        [Parameter(Mandatory)] $IsManual
        )
        
    # Checks if template with given version already exists
    $error.clear()
    try {Get-Template -Name $TemplateName -ErrorAction 'silentlycontinue'}
    catch {}
    if (!$error) {
        Write-Host "Template with the specified FIRMWARE_NAME version already exists." -BackgroundColor Red -ForegroundColor White
        Write-Host "Exiting..." -BackgroundColor Red -ForegroundColor White
        exit
    }

    # Get FIRMWARE_NAME VM password from user
    Write-Host "`nPlease enter linux VM credentials (root/<password>) to change IP and start FIRMWARE_NAME`n" -ForegroundColor Yellow
    $Credentials = Get-Credential -UserName root -Message "Enter password for VM (not vSphere)."

    # --------------- GET TEMPORARY IP -----------------

    # Get temporary IP from user
    Write-Host "`nEnter a temporary IP address for creation of the VM (Subnet 19 recommended. Will be overwritten afterwards)" -ForegroundColor Yellow

    # Asks for IP and checks its validity 
    $IPMatch = $false
    do {
        # IP address regex taken from https://stackoverflow.com/a/5284410
        $IP = Read-Host -Prompt "Ex: 192.168.x.x"
        $IPMatch = ($IP) -match '\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}\b'
        if (!$IPMatch) {Write-Host "`nEnter a valid IP address. ('ctrl+c' to exit)" -BackgroundColor Red}
    }
    while (!$IPMatch)

    # --------------- END GET TEMPORARY IP ---------------

    # ---------------- CREATE TEMPLATE -------------------

    # Prints out template name
    Write-Host "`nTemplate name: $($TemplateName)" -ForegroundColor Yellow

    # Template creation variables
    $OldTemplate = Get-Template -Name FIRMWARE_NAME-Clone-Script
    $VMHost = Get-VMHost 
    $Folder = Get-Folder -Name 'FIRMWARE_NAME Linux'
    $Notes = "Credentials: root / ROOT_PASSWORD (Won't ask for password change)
    Minimal PhotonOS install via OVA.
    FIRMWARE_NAME app running."

    # Create and start VM
    New-VM -VMHost $VMHost -Name $TemplateName -Template $OldTemplate -Location $Folder -Notes $Notes
    Get-VM -Name $TemplateName | Start-VM

    # Further setup info
    Write-Host "`nVM Started." -ForegroundColor Yellow

# Temporarily sets static IP so that SCP can connect to VM
$IPconfig = @"
cd /etc/systemd/network
echo "[Match]" >> 10-eth0.network
echo "Name=eth0" >> 10-eth0.network
echo "[Network]" >> 10-eth0.network
echo "LinkLocalAddressing=no" >> 10-eth0.network
echo "Address=$IP<Subnet>" >> 10-eth0.network
echo "Gateway=<Gateway>" >> 10-eth0.network
chmod 644 10-eth0.network
systemctl restart systemd-networkd
"@
    Write-Host "`nChanging IP (Can take a little while)...`n" -ForegroundColor Yellow

    $FailedAttempts = 1
    do {
        $Failed = $false
        try {
            Invoke-VMScript -VM $TemplateName -GuestCredential $Credentials -ScriptText $IPconfig -ScriptType bash -ErrorAction Stop
        }
        # Catch incorrect password
        catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidGuestLogin] {
            Write-Host "`nInvalid credentials: Attempt $FailedAttempts/$MAX_PW_TRIES" -BackgroundColor Red
            # Exits after 3 incorrect password attempts
            if ($FailedAttempts -eq $MAX_PW_TRIES) {ExitFromError -BadPW $true}
                $FailedAttempts = $FailedAttempts + 1
                $Failed = $true
                $Credentials = Get-Credential -UserName root -Message "Enter password for VM (not vSphere)."
        }
        catch {
            Write-Host $_.Exception.Message
            Write-Host $_.Exception.GetType().Name
        
            # Exits program due to unexpected error
            ExitFromError
        }
            
    }
    while ($Failed)

    # Calls CopyFIRMWARE_NAME
    Write-Host "IP: $($IP), Location: $($FIRMWARE_NAMELocation)"
    CopyFIRMWARE_NAME -IP $IP -Credentials $Credentials -Location $FIRMWARE_NAMELocation

    # Calls Cleanup
    Cleanup -TemplateName $TemplateName -Credentials $Credentials -Folder $Folder

    # ---------------- END CREATE TEMPLATE -------------------
}

# ----------------END MAKE TEMPLATE ------------------

# ------------------ COPY FIRMWARE_NAME -----------------------

# Function 2 ($IP, $Credentials, $Location)
Function CopyFIRMWARE_NAME {
    # Parameters
    param (
        [Parameter(Mandatory)] $IP,
        [Parameter(Mandatory)] $Credentials,
        [Parameter(Mandatory)] $Location
        )

    Write-Host "`nWaiting up to 1 minute for VM to connect to network, then copying FIRMWARE_NAME file...`n" -ForegroundColor Yellow
    # Clear errors before try block
    $Error.Clear()
    try {
        Set-SCPFile -ComputerName $IP -Credential $Credentials -LocalFile $Location -RemotePath /root -ConnectionTimeout 60 -ErrorAction Stop
        Write-Host "FIRMWARE_NAME file copied successfully" -ForegroundColor Yellow
    }
    catch {
        # Exits program due to unexpected error
        ExitFromError
    }
}

# ---------------- END COPY FIRMWARE_NAME ---------------------

# ------------------ CLEANUP -------------------------

# Function 4 (TemplateName, Credentials, Folder)
Function Cleanup {
    # Parameters
    param (
        [Parameter(Mandatory)] $TemplateName,
        [Parameter(Mandatory)] $Credentials,
        [Parameter(Mandatory)] $Folder
        )

# Resets network configuration and gives FIRMWARE_NAME execute permission
$FIRMWARE_NAMEPermission = @"
cd /etc/systemd/network
> 10-eth0.network
systemctl restart systemd-networkd
cd /root
chmod +x FIRMWARE_NAME-x86-*
"@
    # Run bash script to change permissions
    Write-Host "`nChanging FIRMWARE_NAME file permissions and resetting network settings...`n" -ForegroundColor Yellow
    Invoke-VMScript -VM $TemplateName -GuestCredential $Credentials -ScriptText $FIRMWARE_NAMEPermission -ScriptType bash

    # Temporarily changes VM name (so no duplicate name conflict)
    $TmpName = $TemplateName + "-tmp"
    Get-VM -Name $TemplateName | Set-VM -Name $TmpName -Confirm:$false

    # Creates Template from VM
    New-Template -Name $TemplateName -VM $TmpName -Location $Folder -Confirm:$false 

    # Deletes temporary VM
    Write-Host "`nDeleting temporary VM...`n" -ForegroundColor Yellow
    Stop-VM $TmpName -Confirm:$false; Remove-VM $TmpName -DeletePermanently -Confirm:$false
}

# ---------------- END CLEANUP -----------------------

# ---------------- GET TEMPLATE NAME -----------------------

# Function 1 (FIRMWARE_NAMELocation)
Function GetTemplateName {
    # Parameters
    param (
        [Parameter(Mandatory)] $FIRMWARE_NAMELocation
        )

    # Get FIRMWARE_NAME filename and remove all but version the filename
    $FIRMWARE_NAMEFileName = Get-ChildItem $FIRMWARE_NAMELocation *x86* | Select-Object -ExpandProperty BaseName
    $FIRMWARE_NAMEFileName = $FIRMWARE_NAMEFileName.Substring(9)
    $FIRMWARE_NAMEFileName = $FIRMWARE_NAMEFileName.Substring(0,1).toupper()+$FIRMWARE_NAMEFileName.substring(1).tolower()
    
    # Get template name from the shortened FIRMWARE_NAME filename
    $FIRMWARE_NAMEFileName = [System.IO.Path]::GetFileName($FIRMWARE_NAMEFileName)
    $TemplateName = "Linux-FIRMWARE_NAME-" + $FIRMWARE_NAMEFileName

    return $TemplateName
}

# -------------- END GET TEMPLATE NAME ------------------

# ------------- START OF PROGRAM EXECUTION --------------

# Get file manually
$Prompt = $false
while ($Prompt -eq $false) {
    # Clear errors
    $error.clear()

    Write-Host "`nAutomatically get latest FIRMWARE_NAME version? (No: Manually specify a FIRMWARE_NAME filepath)" -ForegroundColor Yellow
    $answer = Read-Host -Prompt "Enter (y/n)"
    if (($answer -like 'y') -or ($answer -like 'yes')) {
        $IsManual = $false
        # Network location for latest FIRMWARE_NAME file
        $FIRMWARE_NAMELocation = "<NETWORK_DRIVE_FIRMWARE_LOCATION>"

        # Get name of latest file name
        $LatestFIRMWARE_NAMEFileName = Get-ChildItem $FIRMWARE_NAMELocation *x86* | Select-Object -ExpandProperty BaseName
        # Append to end of filepath
        $FIRMWARE_NAMELocation = $FIRMWARE_NAMELocation + $LatestFIRMWARE_NAMEFileName
        Write-Host $FIRMWARE_NAMELocation

        $TemplateName = GetTemplateName -FIRMWARE_NAMELocation $FIRMWARE_NAMELocation
        $Prompt  = $true
    }
    elseif (($answer -like 'n') -or ($answer -like 'no')) {
        $IsManual = $true
        $FIRMWARE_NAMELocation = GetManualFile
        $TemplateName = GetTemplateName -FIRMWARE_NAMELocation $FIRMWARE_NAMELocation
        $Prompt  = $true
    }
    else {
        Write-Host "`nInvalid response. Please enter (y/n)" -BackgroundColor Red
    }
}

# Calls MakeTemplate
MakeTemplate -Name $TemplateName -IsManual $IsManual

# Finished
Write-Host "`n-- Finished --`n" -ForegroundColor Yellow -BackgroundColor Black; Write-Host ""

# ------------- END OF PROGRAM EXECUTION --------------