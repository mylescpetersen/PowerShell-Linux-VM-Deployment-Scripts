<# -------------------------------------------------------------------------------------------------------------------------

By: Myles Petersen
Date: Aug 19, 2021

NOTE: TEXT IN <> CONTAINS SENSITIVE INFO WHICH BEEN REMOVED. Ex: <DEFAULT_DEVICE_NUM>
  
Additions/Improvements:
    - Fixed: Bash script to set static IP
    - Added: Automatic starting of FIRMWARE_NAME application via bash script (through systemd service)
    - Improvement: Removed need for third-party cmdlets (Will now work with base PowerCLI)
    - Added: Informative print-offs to user throughout the program execution
    - Removed: Unnecessary update VMWare tools script/accompanying third-party cmdlet (Not needed due to new IP script)
    - Added: Ability to specify Port Group (Which VLAN) when creating VMs
    - Added: Ability to choose vSphere folder
    - Added: Ability to limit/reserve CPU, RAM usage
    - Added: Ability to add pre-existing database file by selection or by absolute/relative path
    - Added: Ability to add FIRMWARE_NAME boot arguments (device #, port #, serial #, database)
    - Added: Ability to set custom subnet mask, gateway

IF COPYING DATABASE FILES TO VM, requires Posh-SSH (for SCP connection), otherwise not needed.
'Install-Module -Name Posh-SSH' or https://github.com/darkoperator/Posh-SSH

----------------------------------------------------------------------------------------------------------------------------#>

# -------------- GLOBAL VARIABLES / CONSTANTS --------------

# Global Variables
$Global:HasDBFile = $false
$Global:FilePaths = ''
$Global:HasSkippedVM = $false
$Global:SkippedVMs = "("
$Global:BaseVMName = ""

# Constants
$MAX_FILENAME_LENGTH = 32768
$DEFAULT_PORT = <DEFAULT_PORT>
$DEFAULT_DEVICE_NUM = <DEFAULT_DEVICE_NUM>
$DEFAULT_DB_FILE = 'FIRMWARE_NAME.db'
$MIN_CPU_LIMIT_MHZ = 200
$MAX_PW_TRIES = 3
$GB = 1024
$RAM_DIVISIBILITY = 4
$VMWARE_TOOLS_TIMEOUT_SECONDS = 45

# ------------ END GLOBAL VARIABLES / CONSTANTS ------------

# ------------------ INFO FOR SKIPPED VMS ------------------

# Function to update flag for if a VM has skipped,
# Add skipped VM to Skipped VMs list (string)
Function SetSkippedVMInfo {
    # Parameters: Name of VM which is being skipped
    param (
        [Parameter(Mandatory)] $VMList,
        [Parameter(Mandatory)] $CurVM
    )

    $Global:HasSkippedVM = $true
    # First VM skipped
    if ($VMList -eq "(") {
        $VMList = $VMList + "$CurVM"
    }
    # Any other VM after the first
    else {
        $VMList = $VMList + ", $CurVM"
    }

    # List with added VM
    return $VMList
    
}

# ---------------- END INFO FOR SKIPPED VMS ----------------

# --------------- CREDENTIALS/ERROR CHECK + BASH SCRIPT CALL ---------------

# Function to exit after different errors
# Removes incomplete VM from vSphere
Function ExitFromError {
    # Parameters: Which error occurred
    param (
        [Parameter(Mandatory=$false)] $BadPW,
        [Parameter(Mandatory=$false)] $Skip
        )

    # Delete unfinished, errored VM
    Stop-VM $VMname -Confirm:$false -ErrorAction SilentlyContinue
    Remove-VM $VMname -DeletePermanently -Confirm:$false -ErrorAction SilentlyContinue

    # Just skip current VM and do not exit
    if ($Skip) {
        Write-Host $error -ForegroundColor Red
        Write-Host "Error occured. Deleting current (unfinished) VM and continuing..." -BackgroundColor Red
        # Return true to $ErrorSkip
        return $true
    }

    # Default error message
    $ExitMessage = "`nOther exception occurred. `nExiting..."

    if ($BadPW) {
        $ExitMessage = "`n3 invalid password attempts.`nDeleting current (unfinished) VM and exiting..." 
    }
    # Dont print error message if it is incorrect password
    else {Write-Host $error -ForegroundColor Red}

    # Print error message and exit
    Write-Host $ExitMessage -BackgroundColor Red
    exit
}

# Function to call bash scripts (for easier error checking)
# CallBashScript ($ScriptName)
Function CallBashScript {
    # Parameters: Which Script to call
    param (
        [Parameter(Mandatory)] $ScriptName,
        [Parameter(Mandatory=$false)] $DBPathTyped
        )

    # Initialize return value for if VM errored --> if true, skip VM
    $ErrorSkip = $false
    # Failed password count
    $FailedAttempts = 1

    do {
        $Failed = $false
        try {
            # When copying database files
            if ($ScriptName -eq 'SCP') {
                # Skip copying if current VM has 'Database' set to 'No
                if (!$Global:HasDBFile) {return}
                # If a path was entered for db file instead of file dialog box
                if ($DBPathTyped) {
                    Write-Host $ChosenDBFile
                    Set-SCPFile -ComputerName $IP -Credential $Global:Credentials -LocalFile $ChosenDBFile -RemotePath /root -ConnectionTimeout 120
                }
                # Y/Yes was entered and file was manually selected
                else {
                    foreach ($DBFilePath in $Global:FilePaths) {
                        Write-Host $DBFilePath
                        Set-SCPFile -ComputerName $IP -Credential $Global:Credentials -LocalFile $DBFilePath -RemotePath /root -ConnectionTimeout 120
                    }
                }
            }
            # All other bash scripts (IP, bootFIRMWARE_NAME, etc...)
            else {
                Write-Host "`nExecuting Bash Script..." -ForegroundColor Green
                Invoke-VMScript -VM $VMname -GuestCredential $Global:Credentials -ScriptText $ScriptName -ScriptType bash -ErrorAction Stop
            }
        }
        # Catch incorrect password
        catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidGuestLogin] {
            Write-Host "`nInvalid credentials: Attempt $FailedAttempts/$MAX_PW_TRIES" -BackgroundColor Red
            # Exits after 3 incorrect password attempts
            if ($FailedAttempts -eq $MAX_PW_TRIES) {ExitFromError -BadPW $true}
                $FailedAttempts = $FailedAttempts + 1
                $Failed = $true
                $Global:Credentials = Get-Credential -UserName root -Message "Enter password for VM (not vSphere)."
        }
        catch {
            # Print error information
            Write-Host $_.Exception.Message
            Write-Host $_.Exception.GetType().Name
            Write-Host $error
           
            # Exits program due to unexpected error
            $ErrorSkip = ExitFromError -Skip $true
            # Will be true here
            return $ErrorSkip
        }  
    }
    while ($Failed)

    # Will be false here
    return $ErrorSkip
}
       
# --------------- END CREDENTIALS/ERROR CHECK + BASH SCRIPT CALL ---------------

# -------------------------- SELECT FILE (CSV/DB) -------------------------------

# Must be called with either -CSV $true, or -Database $true
Function SelectFile {
    # Which type of file to select
    param (
        [Parameter(Mandatory=$false)] $CSV,
        [Parameter(Mandatory=$false)] $Database
        )

    # Ask user for full filepath
    if ($Database) {Write-Host "`nSelect ALL the desired database files. `n<database>, <database>-trend, <database>-trend-shm, <database>-trend-wal:" -ForegroundColor yellow}
    elseif ($CSV) {Write-Host "Select the desired .CSV file for VM creation" -ForegroundColor Yellow}

    # << Based on https://thomasrayner.ca/open-file-dialog-box-in-powershell/ >>
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    
    # Open File Dialog in current directory
    $CurDirectory = Get-Location
    $OpenFileDialog.InitialDirectory = $CurDirectory

    # Prompt to select a file (CSV/Database files)
    $FileChosen = $false
    while (!$FileChosen) {

        # Filetype filter (all files)
        If ($CSV) {
            $OpenFileDialog.Filter = "CSV files (*.csv)|*.csv"
            $OpenFileDialog.Multiselect = $false
            $OpenFIleDialog.Title = "CSV File Selection"
            $OpenFileDialog.ShowDialog() | Out-Null
            $FilePaths = $OpenFileDialog.FileNames
        }
        elseif ($Database) {
            $OpenFileDialog.Filter = "All files (*.*)|*.*"
            # Allow selecting multiple files
            $OpenFileDialog.Multiselect = $True
            $OpenFIleDialog.Title = "FIRMWARE_NAME Database File Selection"
            $OpenFileDialog.ShowDialog() | Out-Null
            $Global:FilePaths = $OpenFileDialog.FileNames
            foreach ($path in $FilePaths) {Write-Host $path}
        }

        # Prompt for retry if user exits the file selection window
        if ($null -eq $FilePaths) {
            
            $Prompt = $false
            while ($Prompt -eq $false) {
                # TODO: For DB, add "Would you like to skip selecting database files for this VM?" when failed.
                Write-Host "`nNo file selected. Would you like to exit?" -BackgroundColor red
                $answer = Read-Host -Prompt "Enter (y/n)"
                if ( ($answer -like 'y') -or ($answer -like 'yes') ) {
                    $Prompt  = $true
                    exit
                }
                elseif ( ($answer -like 'n') -or ($answer -like 'no') ) {
                    $Prompt  = $true
                }
                else {
                    Write-Host "`nInvalid response. Please enter (y/n)" -BackgroundColor Red
                }
            }
        }
        else {
            $FileChosen = $true
        }
    }
    return $FilePaths
}

# ------------------------ END SELECT FILE (CSV/DB) ----------------------------

# ------------------------ SET TOTAL VM MEMORY ---------------------------------

# Checks if user input is valid (is divisible by 4), corrects it if not valid, then sets it
function SetTotalMemory { 
    # Parameters: How much RAM to set, Which VM to set
    param (
        [Parameter(Mandatory)] $MemoryEntry,
        [Parameter(Mandatory)] $VM
    )

    # Do not set memory if field is blank or 0
    if (($MemoryEntry -eq '') -or ($MemoryEntry -eq '0')) {
        return 
    }
    # Valid value is entered for memory
    else {
        # Converts Memory string to double (in MB)
        $MemoryConfig = [double]$MemoryEntry * $GB
        # Round to nearest int
        $MemoryConfig = [int]$MemoryConfig

        # Adds 1 until number is divisible by 4
        if ($MemoryConfig % $RAM_DIVISIBILITY -ne 0) {
            for ($i = 1; $i -le $RAM_DIVISIBILITY; $i++) {
                if ( ($MemoryConfig + $i) % $RAM_DIVISIBILITY -eq 0) {
                    $MemoryConfig = $MemoryConfig + $i
                    break
                }
            }
        }
        # Return decimal value (in GB) for TotalRAMGB
        $MemoryConfigParam = ($MemoryConfig / $GB)
        Write-Host "Total VM Memory: $MemoryConfigParam GB" -ForegroundColor Yellow
        Get-VM -name $VM | Set-VM -MemoryGB $MemoryConfigParam -Confirm:$false
        }
    }

    # ---------------------- END SET TOTAL VM MEMORY -------------------------------

# ------------------ LINKED CLONES PROMPT  ------------------

# Clear errors
$error.clear()

# Get 'Owner' name from user 
Write-Host "`nEnter name for 'Owner' field of the VMs (Your name)." -ForegroundColor Yellow
$UserName = Read-Host -Prompt "Enter name (Press 'Enter' to skip)"

# Determine which type of clones to use from user 
$Prompt = $false

# Loop infinitely until user chooses an option 
while ($Prompt -eq $false) {

    Write-Host "`nUse linked clones to save disk space?" -ForegroundColor Yellow
    $answer = Read-Host -Prompt "Enter (y/n)"

    # Check user answer
    if ( ($answer -like 'y') -or ($answer -like 'yes') ) {
        $isLinked = $true
        $Prompt  = $true
    }
    elseif ( ($answer -like 'n') -or ($answer -like 'no') ) {
        $isLinked = $false
        $Prompt  = $true
    }
    else {
        Write-Host "`nInvalid response. Please enter (y/n)" -BackgroundColor Red
    }
}

# ---------------- END LINKED CLONES PROMPT ----------------

# ------------------ CSV + Credentials  ------------------ 

Function GetInfo {
# Parameters: If the VM is using linked clones or not
    param (
        [Parameter(Mandatory)] $isLinked
        )

# Location of CSV file for VM settings
$CSVPath = SelectFile -CSV $true
$vms = Import-CSV -Path $CSVPath
 
# Credentials found in "Notes" of the template that is being used, and on Confluence
Write-Host "`nPlease enter linux VM credentials (root/<password>) to change IP and start FIRMWARE_NAME`n" -ForegroundColor Yellow

# Get VM root password from user prompt
$Global:Credentials = Get-Credential -UserName root -Message "Enter password for VM (not vSphere)."

# Calls main function of program
MainFunction -vms $vms -Credentials $Global:Credentials -isLinked $isLinked
}

# ----------------- END CSV + Credentials  ------------------ 

 # ---------------- SET CPU + RAM AMOUNTS, LIMITS, RESERVATIONS  -----------------

 function SetResourceSettings {

    # ----- CPU LIMIT, RESERVATION -----

    # Converts CPU limit to int for comparison
    [int]$IntCPULimitMHz = $vm.CPULimitMHz

    # Sets CPU limit to 'Unlimited' (null) if no limit, or 0 is entered
    if (($vm.CPULimitMHz -eq '') -or ($vm.CPULimitMHz -eq '0')) {$CPULimitParam = $null}

    # Warns user if CPU limit is set very low
    elseif ($IntCPULimitMHz -lt $MIN_CPU_LIMIT_MHZ) {
        Write-Host "Warning: CPU Limit is set below 200MHz, this can cause issues when deploying the VM. Please enter a new limit or confirm current limit." -ForegroundColor White -BackgroundColor Red
        Write-Host "Current CPU Limit: $($vm.CPULimitMHz)MHz." -ForegroundColor White -BackgroundColor Red
        $NewCPULimit = Read-Host "`nEnter new limit in MHz: (ex: 500) (Press 'Enter' to keep current limit)`n"
       
        # Check if user skipped new limit (Pressed enter) 
        if ($NewLimit -ne '') {
            $CPULimitParam = $NewCPULimit
        } 
    }
    # Set CPU Limit after checks
    else {
        $CPULimitParam = $vm.CPULimitMHz
    }
    # Print out CPU Limit
    if ($null -ne $CPULimitParam) {Write-Host "CPU Limit: $($CPULimitParam)MHz" -ForegroundColor Yellow}

     # Set CPU Reservation (Blank = No reservation)
     if (($vm.CPUReservedMHz -eq '') -or ($vm.CPUReservedMHz -eq '0')) {$CPUResParam = 0}
     else {
         $CPUResParam = $vm.CPUReservedMHz
         Write-Host "CPU Reservation: $($CPUResParam)MHz" -ForegroundColor Yellow
    }
    
    # ----- END CPU LIMIT, RESERVATION -----

    # ----- RAM RESERVATION -----

    # Check if either field is blank, if so: skip
    if ( ($vm.PercentRAMReserved -ne '') -and ($vm.TotalRAMGB -ne '') ) {
        $PercentRAMReserved = ([double]$vm.PercentRAMReserved)
        # Ex: Value entered as 50
        if (($PercentRAMReserved -ge 1) -and ($PercentRAMReserved -le 100)) {
            $RAMReserved = ( ([int]$PercentRAMReserved / 100) * [double]$vm.TotalRAMGB)
        }
        # Ex: Value entered as 0.50
        elseif (($PercentRAMReserved -lt 1) -and ($PercentRAMReserved -gt 0)) {
            $RAMReserved = $PercentRAMReserved * [double]$vm.TotalRAMGB
        }
        # Invalid percentage entry Ex: 101, -1
        else {
            if ($PercentRAMReserved -ne 0) {
                Write-Host "Invalid entry: Defaulting to no reservation" -ForegroundColor White -BackgroundColor Red
            }
            $RAMReserved = 0
        }
        Write-Host "RAM Reserved: $RAMReserved GB" -ForegroundColor Yellow
    }

    # At least one field is blank
    else {
        $RAMReserved = 0
    }

    # ----- SET CPU/RAM -----

    # Set CPU Limit, CPU/RAM Reservation
    Get-VM -name $VMname | Get-VMResourceConfiguration | `
    # Set-VMResourceConfiguration -MemLimitGB $MemLimitParam -CpuLimitMhz $CPULimitParam -MemReservationGB $MemResParam -CpuReservationMhz $CPUResParam 
    Set-VMResourceConfiguration -CpuLimitMhz $CPULimitParam -CpuReservationMhz $CPUResParam -MemReservationGB $RAMReserved

    # ----- END SET CPU/RAM -----
}

# ---------------- END SET CPU + RAM AMOUNTS, LIMITS, RESERVATIONS -----------------

# ------------------- MAIN FUNCTION -------------------------

Function MainFunction {
    # All entries in the CSV, # User credentials for VMs, If linked clones are being used
    param (
        [Parameter(Mandatory)] $vms,
        [Parameter(Mandatory)] $Credentials,
        [Parameter(Mandatory)] $isLinked
        )

    # Following 2 variables for "Showing current VM and total VMs (1/3)"
    # Current VM number
    $count = 0
    # Gets total number of VMs to create from CSV
    $numVMs = $vms | Measure-Object

    # Loop through each VM in CSV file
    foreach($vm in $vms){

        # ------------------ GET VM INFO  ------------------    
        
        # Increment count of current VM
        $count = $count + 1

        #### Can be implemented if different templates have different credentials (Currently are the same)
        #$Template = Get-Template -name $vm.template
        #if ($PrevTemplate -ne $Template) {$Credentials = Get-Credential -UserName root -Message "Enter password for VM (not vSphere)."}

        # Get VM Template, Host, Datastore from CSV file
        $Template = Get-Template -name $vm.template
        $VMHost = Get-VMHost -name $vm.host
        $Datastore = Get-Datastore -name $vm.datastore

        # ------------------ GET NETWORK INFO  ------------------ 

        # Get IP from column in csv
        $IP = $vm.IpAddr

        # Get gateway if specified
        # Default = <Gateway>
        if ($vm.Gateway -eq '') {$Gateway = '<Gateway>'}
        else {
            $Gateway = $vm.Gateway
            Write-Host "Gateway: $Gateway" -ForegroundColor Yellow
        }
        
        # Get subnet mask (ex: /24) if specified
        # Default = <Subnet>
        if ($vm.SubnetMask -ne '') {
            # Add '/' if user did not include it
            if ($vm.SubnetMask.SubString(0,1) -ne '/') {
                $SubnetMask = "/$($vm.SubnetMask)"
            }
            else {$SubnetMask = $vm.SubnetMask}
            Write-Host "Subnet Mask: $SubnetMask" -ForegroundColor Yellow
        }
        # Set to default <Subnet>
        else {$SubnetMask = '/<Subnet>'}

        # ------------------ END GET NETWORK INFO  ------------------ 
        
        # Get VM name for creation
        $VMname = $vm.name

        # See if vSphere errors when accessing VM. If no --> VM already exists
        $error.clear()
        Get-VM -Name $VMname -ErrorAction SilentlyContinue

        # VM name already exists --> Skip VM
        if (!$error) {
            Write-Host
            Write-Host "VM with this name already exists.`nSkipping to next VM." -BackgroundColor Red -ForegroundColor White
            $error.clear()
            # Delete and skip current VM
            $Global:SkippedVMs = SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
            continue
        }

        # Flag for if the VM has a folder specified --> for use in Make-VM
        $HasFolder = $false

        # Creates folder if specified folder does not exist 
        if ($vm.Folder -ne '') {
            $HasFolder = $true

            # Not used, but could be in future
            $Datacenter = Get-Datacenter

            # See if vSphere errors when accessing folder. If yes --> folder doesn't exist
            $error.clear()
            try {Get-Folder -Name $vm.Folder -ErrorAction 'silentlycontinue'}
            catch {}

            # Folder does not exist --> make new folder
            if ($error) {
                Write-Host "`nCreating new folder: $($vm.Folder)" -ForegroundColor Yellow
                $Folder = New-Folder -Name $vm.Folder -Location (Get-Folder vm)
            }
            # Folder does exist
            else {
                $Folder = $vm.Folder
                }
        }

        # Get Port Group Name (Sets to "VM Network" if blank)
        if ($vm.PortGroup -eq '') {$PGroup = Get-VirtualPortGroup -Name "VM Network"}
        else {$PGroup = Get-VirtualPortGroup -Name $vm.portgroup}

        # Sets folder variable
        $Folder = $vm.Folder

        # ------------------ END GET VM INFO ------------------  

        # ------------------ FIRMWARE_NAME ARGUMENTS ------------------

        # Initialize/reset bools
        $IsSerialNum = $false

        # Checks for blank FIRMWARE_NAME args
        if ($vm.Device -eq '') {$DeviceNum = $DEFAULT_DEVICE_NUM}
        else {$DeviceNum = $vm.Device}
        
        # B/IP port
        if ($vm.Port -eq '') {$Port = 0}
        else {$Port = $vm.Port}

        # Serial Number
        if ($vm.SerialNum -eq '') {$IsSerialNum = $false}
        else {
            $SerialNum = $vm.SerialNum
            $IsSerialNum = $true
            }

        # Database file flags initialization
        $IsPathTyped = $false
        $Global:HasDBFile = $false

        # Database file
        if ( ($vm.Database -like 'y') -or ($vm.Database -like 'yes') ) {

            # File explorer prompt for database file
            Write-Host "Select database file(s) for VM $VMname..." -ForegroundColor Yellow
            $DBPath = SelectFile -Database $true
            $Global:HasDBFile = $true

            # Find shortest file name (Main DB file)
            $ShortestPathLength = $MAX_FILENAME_LENGTH
            $MainDBFile = $null
            foreach ($name in $DBPath) {
                if ($name.length -lt $ShortestPathLength) {
                    $ShortestPathLength = $name.length
                    $MainDBFile = $name
                }
            }
            # Removes path from filename
            $DBPath = Split-Path $MainDBFile -Leaf
            Write-Host `n$MainDBFile
        }
        elseif ( ($vm.Database -like 'n') -or ($vm.Database -like 'no') -or ($vm.Database -eq '') ) {
            Write-Host "`nNo database chosen." -ForegroundColor Yellow
            # Sets blank db file for persistent storage
            $DBPath = $DEFAULT_DB_FILE
        }
        # Invalid entry in 'Database' column
        else {
            Write-Host "`nSearching for database file at the filepath entered..." -ForegroundColor Yellow
            # Check if path is valid, if so set as db path
            $IsDBValid = Test-Path $vm.Database
            if ($IsDBValid -eq $true) {
                $Global:HasDBFile = $true
                $ChosenDBFile = $vm.Database
                $DBPath = Split-Path $ChosenDBFile -Leaf
                $IsPathTyped = $true

            }
            # Path is not valid, do not set a db path
            else {
                Write-Host "`n'Database' in CSV contains invalid filepath. Would you like to select a db file?" -BackgroundColor Red
                $DBErrorPropmpt = Read-Host -Prompt "(y/n)"
                if ( ($DBErrorPropmpt -like 'y') -or ($DBErrorPropmpt -like 'yes') )  {

                # File explorer prompt for database file
                Write-Host "Select database file(s) for VM $VMname..." -ForegroundColor Yellow
                $DBPath = SelectFile -Database $true
                $Global:HasDBFile = $true
    
                # Find shortest file name (Main DB file)
                $ShortestPathLength = $MAX_FILENAME_LENGTH
                $MainDBFile = $null
                foreach ($name in $DBPath) {
                    if ($name.length -lt $ShortestPathLength) {
                        $ShortestPathLength = $name.length
                        $MainDBFile = $name
                    }
                }
                # Removes path from filename
                $DBPath = Split-Path $MainDBFile -Leaf
                Write-Host `n$MainDBFile        

                }
                # After first fail, do not select a database file
                elseif ( ($DBErrorPropmpt -like 'n') -or ($DBErrorPropmpt -like 'no') -or ($DBErrorPropmpt -eq '')) {
                    Write-Host "No database chosen." -ForegroundColor Yellow
                    # Sets blank db file for persistent storage
                    $DBPath = $DEFAULT_DB_FILE
                }
                # Anything other than y/yes/n/no entered
                else {
                    Write-Host "`nInvalid response. Adding blank" -BackgroundColor Red
                    $DBPath = $DEFAULT_DB_FILE
                }
            }
        }

        # ---------------- END FIRMWARE_NAME ARGUMENTS -----------------

        # ---------------- CREATE VM, SNAPSHOT -----------------

        # Creates linked clone VMs if run from linked clone script
        if ($isLinked) {
            Write-Host "`nCreating linked clone..." -ForegroundColor Yellow
            MakeLinkedVM -VMname $VMname -Template $Template -Datastore $Datastore -VMHost $VMHost -PGroup $PGroup -HasFolder $HasFolder

            # Make new custom attribute 'Parent' if it does not exist
            try {
                New-CustomAttribute -Name "Parent" -TargetType VirtualMachine -ErrorAction Stop
            }
            # Catch error if it does exist, and do nothing
            catch {}

            # Set 'Parent' Attribute to name of Base VM
            Get-VM $VMname | Set-Annotation -CustomAttribute Parent -Value $Global:BaseVMName
        }
        # Else creates regular VM clones
        else {
            Write-Host "Creating regular clone..." -ForegroundColor Yellow
            MakeVM -VMname $VMname -Template $Template -Datastore $Datastore -VMHost $VMHost -PGroup $PGroup -HasFolder $HasFolder
        }
    
        # ---------------- END CREATE VM, SNAPSHOT -----------------

    # ------------------ BASH SCRIPTS ------------------

# Script to change IP address to that specified in CSV
$IPconfig = @"
cd /etc/systemd/network
echo "[Match]" >> 10-eth0.network
echo "Name=eth0" >> 10-eth0.network
echo "[Network]" >> 10-eth0.network
echo "LinkLocalAddressing=no" >> 10-eth0.network
echo "Address=$IP$SubnetMask" >> 10-eth0.network
echo "Gateway=$Gateway" >> 10-eth0.network
chmod 644 10-eth0.network
systemctl restart systemd-networkd
"@

# Scripts to start FIRMWARE_NAME depending on given arguments
# Wildcard assumes only one FIRMWARE_NAME version is present

# Create FIRMWARE_NAME Service for FIRMWARE_NAME auto-start on VM reboot

# Has Serial Number
$CreateFIRMWARE_NAMEService_sn = @"
ls /root
touch $DEFAULT_DB_FILE
chmod 777 /root/*
cd /etc/systemd/system/
echo "[Unit]" >> bootFIRMWARE_NAME.service
echo "Description=Start FIRMWARE_NAME on boot" >> bootFIRMWARE_NAME.service
echo "[Service]" >> bootFIRMWARE_NAME.service
echo "Type=simple" >> bootFIRMWARE_NAME.service
echo "ExecStart=/bin/sh -c '/root/FIRMWARE_NAME-* <DEVICE_NUM_PARAMETER> $DeviceNum <DEVICE_PORT_NUM_PARAMETER> $Port <DATABASE_FILE_PARAMETER> /root/$DBPath <DEVICE_SERIAL_NUM_PARAMETER> $SerialNum'" >> bootFIRMWARE_NAME.service
echo "[Install]" >> bootFIRMWARE_NAME.service
echo "WantedBy=multi-user.target" >> bootFIRMWARE_NAME.service
chmod 777 /etc/systemd/system/bootFIRMWARE_NAME.service
systemctl daemon-reload
systemctl enable bootFIRMWARE_NAME.service
systemctl start bootFIRMWARE_NAME.service
systemctl status bootFIRMWARE_NAME.service
ls /root
"@

# No Serial Number
$CreateFIRMWARE_NAMEService = @"
ls /root
touch $DEFAULT_DB_FILE
chmod 777 /root/*
cd /etc/systemd/system/
echo "[Unit]" >> bootFIRMWARE_NAME.service
echo "Description=Start FIRMWARE_NAME on boot" >> bootFIRMWARE_NAME.service
echo "[Service]" >> bootFIRMWARE_NAME.service
echo "Type=simple" >> bootFIRMWARE_NAME.service
echo "ExecStart=/bin/sh -c '/root/FIRMWARE_NAME-* <DEVICE_NUM_PARAMETER> $DeviceNum <DEVICE_PORT_NUM_PARAMETER> $Port <DATABASE_FILE_PARAMETER> /root/$DBPath'" >> bootFIRMWARE_NAME.service
echo "[Install]" >> bootFIRMWARE_NAME.service
echo "WantedBy=multi-user.target" >> bootFIRMWARE_NAME.service
chmod 777 /etc/systemd/system/bootFIRMWARE_NAME.service
systemctl daemon-reload
systemctl enable bootFIRMWARE_NAME.service
systemctl start bootFIRMWARE_NAME.service
systemctl status bootFIRMWARE_NAME.service
ls /root
"@

    # --------------- END BASH SCRIPTS -----------------

        # ------------------ CALL SCRIPTS ------------------
    
        # Set network settings in VM
        Write-Host "`nVM $($count)/$($numVMs.Count): Starting VMware Tools, and changing IP (Can take a little while)...`n" -ForegroundColor Yellow
        
        # Measure how long VMware Tools takes to start
        $ToolsStartTime = Measure-Command {
            # Wait for VMware Tools to start before executing first script (45s max)
            Get-VM $VMname | Wait-Tools -TimeoutSeconds $VMWARE_TOOLS_TIMEOUT_SECONDS
        }
        # Print how long it takes to start
        Write-Host "VMware Tools time taken to start: $($ToolsStartTime.Seconds)s" 

        # Initialize skipped flag to false
        $VMSkipped = $false

        # Execute IPconfig script
        $VMSkipped = CallBashScript -ScriptName $IPconfig
        if ($VMSkipped -eq $true) {
            # Delete and skip current VM
            $Global:SkippedVMs = SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
            continue
        }

        # Set FIRMWARE_NAME autoboot settings in VM
        Write-Host "`nVM $($count)/$($numVMs.Count): Starting FIRMWARE_NAME...`n" -ForegroundColor Yellow

        # Execute FIRMWARE_NAME program depending on args

        # Has Serial Number
        if ($IsSerialNum) {
            Write-Host "Serial #: $($SerialNum), Database ($DEFAULT_DB_FILE=default): $DBPath, Port ($DEFAULT_PORT=default): $($Port), Device # ($DEFAULT_DEVICE_NUM=default): $($DeviceNum)" -ForegroundColor Yellow
            
            # Copy DB file over SCP, if no DB file selected: copies default blank file
            $VMSkipped = CallBashScript -ScriptName 'SCP' -DBPathTyped $IsPathTyped
            if ($VMSkipped -eq $true) {
                # Delete and skip current VM
                $Global:SkippedVMs = SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
                continue
            }

            # Start FIRMWARE_NAME with Serial Number
            $VMSkipped = CallBashScript -ScriptName $CreateFIRMWARE_NAMEService_sn
            if ($VMSkipped -eq $true) {
                # Delete and skip current VM
                SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
                continue
            }
        } 

        # No Serial Number
        else {
            Write-Host "Database ($DEFAULT_DB_FILE=default): $DBPath, Port ($DEFAULT_PORT=default): $($Port), Device # ($DEFAULT_DEVICE_NUM=default): $($DeviceNum)" -ForegroundColor Yellow
            
            # Copy DB file over SCP, if no DB file selected: copies default blank file
            $VMSkipped = CallBashScript -ScriptName 'SCP' -DBPathTyped $IsPathTyped
            if ($VMSkipped -eq $true) {
                # Delete and skip current VM
                $Global:SkippedVMs = SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
                continue
            }

            # Start FIRMWARE_NAME without Serial Number
            $VMSkipped = CallBashScript -ScriptName $CreateFIRMWARE_NAMEService
            if ($VMSkipped -eq $true) {
                # Delete and skip current VM
                $Global:SkippedVMs = SetSkippedVMInfo -VMList $Global:SkippedVMs -CurVM $VMname
                continue
            }
        }

        # ----------------- END CALL SCRIPTS ------------------

    Write-Host "`n-- VM $($count)/$($numVMs.Count) finished --`n" -ForegroundColor Yellow -BackgroundColor Black; Write-Host ""
    # End of ForEach loop
    }
}

# ----------------- END MAIN FUNCTION ----------------------

# ----------------- MAKE (LINKED) VM -----------------------

Function MakeLinkedVM {
    # Parameters: All VM basic info from CSV
    param (
        [Parameter(Mandatory)] $VMname,
        [Parameter(Mandatory)] $Template,
        [Parameter(Mandatory)] $Datastore,
        [Parameter(Mandatory)] $VMHost,
        [Parameter(Mandatory)] $PGroup,
        [Parameter(Mandatory)] $HasFolder
        )

    # Append "-BaseVM" on the new Base VM
    $BaseVMName = "$($Template)-BaseVM"
    $Global:BaseVMName = $BaseVMName

    # See if vSphere errors when accessing VM. If yes --> Base VM doesn't exist
    $error.clear()
    try {Get-VM -Name $BaseVMName -ErrorAction 'silentlycontinue'}
    catch {}

    # Base VM does not exist for given template --> Create Base VM
    if ($error) {
        Write-Host "`nCreating new base VM: $($BaseVMName)" -ForegroundColor Yellow
        New-VM -Name $BaseVMName -Template $Template -Datastore $Datastore -VMhost $VMHost -Location 'Clone VM Bases' -Notes "DO NOT DELETE"

        Start-VM $BaseVMName
        Get-VM $BaseVMName | Set-Annotation -CustomAttribute Owner -Value "FIRMWARE_NAME Scripts"
        Get-VM -name $BaseVMName | New-Snapshot -name "Clean Install - Base" -Description "Created $(Get-Date)"
        Get-VM -name $BaseVMName | Stop-VM -Confirm:$false
    }

    # Set VM's Folder
    if ($HasFolder) {
        New-VM -Name $VMname -VM $BaseVMName -Datastore $Datastore -VMhost $VMHost -Location $Folder -LinkedClone -ReferenceSnapshot "Clean Install - Base" -Notes "Credentials: root / reliablecontrols (Won't ask for password change)
        Minimal PhotonOS install via OVA.
        FIRMWARE_NAME app running." 
    }
    # No folder
    else {
        New-VM -Name $VMname -VM $BaseVMName -Datastore $Datastore -VMhost $VMHost -LinkedClone -ReferenceSnapshot "Clean Install - Base" -Notes "Credentials: root / reliablecontrols (Won't ask for password change)
        Minimal PhotonOS install via OVA.
        FIRMWARE_NAME app running."
    }

    # Set VM's "Owner" name
    if ($UserName -ne '') {
        Get-VM $VMname | Set-Annotation -CustomAttribute Owner -Value $UserName
    }

    # Set VM's total RAM
    SetTotalMemory -MemoryEntry $vm.TotalRAMGB -VM $VMname

    # Set CPU Limit, Total RAM, CPU/RAM reservations
    SetResourceSettings

    # Start VM
    Start-VM -VM $VMname
 
    # Ex: "VM 2/3: VM is being created..."
    Write-Host "`nVM $($count)/$($numVMs.Count): VM is being created...`n" -ForegroundColor Yellow

    #Create a snapshot of clean installation timestamped
    Get-VM -name $VMname | New-Snapshot -name "Clean Install" -Description "Created $(Get-Date)"

    # Get Port Group Name (Sets to "VM Network" if blank)
    if ($vm.PortGroup -eq '') {$PGroup = Get-VirtualPortGroup -Name "VM Network"}
    else {$PGroup = Get-VirtualPortGroup -Name $vm.portgroup}

    # Set VM's Port Group
    Get-VM -name $VMname | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $PGroup -Confirm:$false
}

Function MakeVM {
    # Parameters: All VM basic info from CSV
    param (
        [Parameter(Mandatory)] $VMname,
        [Parameter(Mandatory)] $Template,
        [Parameter(Mandatory)] $Datastore,
        [Parameter(Mandatory)] $VMHost,
        [Parameter(Mandatory)] $PGroup,
        [Parameter(Mandatory)] $HasFolder
        )

    #Create new VMs using values specified in VM.csv
    #Checks if a folder is chosen
    if ($HasFolder) {New-VM -Name $VMname -Template $Template -Datastore $Datastore -VMhost $VMHost -PortGroup $PGroup -Location $Folder}
    else {New-VM -Name $VMname -Template $Template -Datastore $Datastore -VMhost $VMHost -PortGroup $PGroup}

    # Set VM's total RAM
    SetTotalMemory -MemoryEntry $vm.TotalRAMGB -VM $VMname

    # Set CPU Limit, CPU/RAM reservations
    SetResourceSettings

    # Start VM
    Start-VM -VM $VMname
 
    # Added printoff to user while 10s pause is in effect
    Write-Host "`nVM $($count)/$($numVMs.Count): VM is being created...`n" -ForegroundColor Yellow
 
    #Create a snapshot of clean installation timestamped
    Get-VM -name $VMname | New-Snapshot -name "Clean Install" -Description "Created $(Get-Date)"
}

# -----------------END MAKE (LINKED) VM -----------------------

# -------------------- FUNCTION CALLS ------------------------

# Get CSV file location + Credentials
GetInfo -isLinked $isLinked

# ------------------ END FUNCTION CALLS -----------------------

# Print out skipped VM's if they exist
if ($Global:SkippedVMs.Length -gt 1) {
    # Close Parentheses in list of skipped VMs
    $Global:SkippedVMs = $Global:SkippedVMs + ")"

    # Print out final list of skipped VMs
    Write-Host
    Write-Host "VM(s) skipped due to duplicate name / error: $Global:SkippedVMs" -BackgroundColor Red -ForegroundColor White
}

# Finished
Write-Host "`n-- Finished --`n" -ForegroundColor Yellow -BackgroundColor Black; Write-Host ""

# ------------- END OF PROGRAM EXECUTION --------------
