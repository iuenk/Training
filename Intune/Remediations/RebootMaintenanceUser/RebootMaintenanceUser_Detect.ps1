#=============================================================================================================================
# Script Name:     RebootMaintenanceUser_Detect.ps1
# Description:     This script is designed to check the current uptime of a Windows Endpoint machine. If the value exceeds a minimum threshold
#                  an optional reminder prompt is sent to the employee asking them to reboot. If the value exceeds a maximum threshold, the machine will be forced to reboot after a chosen timer.
#   
# Notes      :     1. Load necessary assemblies and hide our script window (not that it's visible when ran from Intune anyways)
#				   2. Read our configurable variables
#				   3. Declare our functions (some of which rely on the variables we just declared)
#				   4. Create our logging directories and start logging
#				   5. Check for the existence of the image. If not present, download it or create it from Base64. If present, validate the hash and recreate or redownload as needed.
#				   6. Check the device uptime
#				   7. Declare our windows form and MOST components
#				   8. Determine if we need to now present a form/popup (yes this order is weird, leave it be). This uses our minimum and maximum defined times to determine if a popup should be thrown, and sets the final popup properties to configure which behaviour it will follow.
#				   9. Throw the popup if applicable
#				  10. The script ends when either the popup does not need to be presented, the user chooses to reboot, the user chooses to close the popup, the timeout ends, or the forced reboot countdown ends.
#
# Created by :     Ivo Uenk
# Date       :     17-07-2026
# Version    :     1.1
#=============================================================================================================================

#region Hide PowerShell Console (this is likely redundant when ran through Proactive Remedations)
#You may want to comment this out for manual testing as well.
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)
#endregion

# Interface Definitions & Assemblies (neded so you can do things like [System.Drawing.Color] in our variable section)
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
#endregion Hide PowerShell Console

#Region Variables
########################### Variables ###########################

#The minimum amount of uptime in days for the device to have which results in an optional prompt. This is greater than or equal to.
$MinimumUptime = "6"

#The maximum amount of uptime in days. Being at or breaking this threshold results in a forced prompt. This is greater than or equal to.
$MaximumUptime = "12"

#The amount of time in seconds after which the machine will forcibly reboot if it exceeded the Maximum-Uptime above. Default is 900 (15 minutes). Do NOT set this higher than the $TimeOutDuration.
$ForcedRebootTime = 900

#Testing value
#Use this to set a fake uptime in days (Example, 12 with NO QUOTES). This allows you to test the script and see the popup without having a machine that truly has that uptime, or without playing with the alert threshold logic. 
#When ran through ISE or visual studio code manual, this will tick down too fast. This does not happen when executed from Intune.
#To disable, set to $null
#$TestingMachineUptimeValue = 7
$TestingMachineUptimeValue = $null

#Automatic Timeout
#This autoclose is used on the OPTIONAL reboot as a means to avoid the 60 minute remediation timeout. It is automatically hidden if the machine exceeds the maximum value as having two timers would be confusing.
#Show Auto Close Timer (only applicable to optional reboot popup)
$AutoCloseVisible = $false

#timeout period in seconds
$TimeOutDuration = 2700 #default is 2700 (45 minutes). Do NOT set it higher than 55 minutes. When ran through ISE or visual studio code manual, this will tick down too fast. This does not happen when executed from Intune.

#Storage and cache locations
$LogFileFolder = $($env:LOCALAPPDATA + "\" + "RebootMaintenanceUser")
$LogFileName = "RebootMaintenanceUser.Log"

#Branding and Customization
#The URL to your image IF you are using $UseImageDownload (by default the image should be 175x175)
$Imageurl = "https://<storageAccountName>.blob.core.windows.net/<containerName>/Logo.png"
$LogoName = $ImageUrl.Split("/")[-1]
$ImageHash = "1DC3D6B50B17C0BB6646AFC8CBD978338BC068B0A7DE50050D8B5DCA6A70BDCA" # Can be completely different this is just an example

#The main background color (does not include text box). This is Alpha, Red, Green, Blue numeric. Leave the alpha at 255. Plenty of online tools like https://rgbacolorpicker.com/
$RebootPromptFormBackgroundColor = [System.Drawing.Color]::FromArgb(255,211,211,211)

#Button Background Color
$ButtonBackgroundColor = [System.Drawing.Color]::FromArgb(255,0,198,243)

#Button text color
$ButtonTextColor = [System.Drawing.Color]::FromArgb(255,0,0,0)

#Text box background color
$TextBoxBackgroundColor = [System.Drawing.Color]::FromArgb(255,211,211,211)

#Text Box text color
$TextBoxTextColor = [System.Drawing.Color]::FromArgb(255,0,0,0)
	
#endregion Variables

#Region Functions
########################### Functions ###########################

function RebootPrompt {
	#Calls our form to execute
	[System.Windows.Forms.Application]::EnableVisualStyles()
	[System.Windows.Forms.Application]::Run($RebootPromptForm)
}

function Get-SuperFileHash {
#Since get-filehash doesn't work in all PS versions...

param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the path to file.")]
        [ValidateNotNullOrEmpty()]
        [string]$HashFilePath
    )

	#Try the normal way
	$ReturnedValue = Get-FileHash $HashFilePath -ErrorAction SilentlyContinue
	$ReturnedValue = $ReturnedValue.Hash

	#If its null, do this madness.
	if ($null -eq $ReturnedValue){
		#Write-Error "get-filehash failed"
	$item = Get-ChildItem $HashFilePath
	$stream = new-object system.IO.FileStream($item.fullname, "Open", "Read", "ReadWrite")
			if ($stream)
					{
						$sha = new-object -type System.Security.Cryptography.SHA256Managed
						$bytes = $sha.ComputeHash($stream)
						$stream.Dispose()
						$stream.Close()
						$sha.Dispose()
						$checksum = [System.BitConverter]::ToString($bytes).Replace("-", [String]::Empty).ToLower();
						$ReturnedValue = $checksum
					}
	}
	return $ReturnedValue
}

function button_click {
	#What our close button does
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): $($env:USERNAME) closing popup without rebooting." -Force
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's report
}

function button2_click {
	#What our reboot now button does
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): $($env:USERNAME) has chosen the optional reboot. This unit will reboot in one minute." -Force
	shutdown /r /t 60 /C "Chosen reboot - This device will restart in one minute." #Fun fact, this shutdown comment will show in the event log
	exit
}

function New-Directory {
	#Used to create our storage paths if they do not exist

	param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the path to create.")]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

	#Only Create our folders if they don't exist to avoid errors
	if (Test-Path $Path){
		write-host "Log File Location folder Folder exists already."
    } 
    else {
        New-Item $Path -ItemType Directory -force -ErrorAction SilentlyContinue > $null 
        $folder = Get-Item "$Path" 
        $folder.Attributes = 'Directory' 
    }
}

function CountDown {
    #Ticks the text down by one
    $timeRemaining.text = $timeRemaining.text - 1
    #Update HHMMSS
    $HHMMSS = [timespan]::fromseconds($timeremaining.text)
    #set the label text back

	#Testing to see just how long it can really go without a timeout.
	#Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Timer is still ticking, now at $($HHMMSS)" -Force

	if ($AutoCloseVisible -eq $true){
        $Countdown_Label.Text = "Auto Close: $("{0:mm\:ss}" -f $HHMMSS)"
	}
    
	if ($timeRemaining.Text -eq 0){
        $timer.Stop()
        Timer_Over
	}
}

function Timer_Over {
	# this is used to gracefully close the popup if it times out.
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Popup is timing out." -Force
	write-error "$(get-date): Popup is timing out." #write this so the info returns to proactive remediation (visible in device detailed run export)
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's
}

function ForcedRebootCountDown {
    #Ticks the text down by one
    $timeRemainingForcedReboot.text = $timeRemainingForcedReboot.text - 1
    #Update HHMMSS
    $HHMMSS = [timespan]::fromseconds($timeRemainingForcedReboot.text)
    #set the label text back

    $Countdown_Label2.Text = "Time remaining before forced reboot: $("{0:mm\:ss}" -f $HHMMSS)"
    
	If ($timeRemainingForcedReboot.Text -eq 0){
        $timer.Stop()
        ForcedRebootCountDown_Over
	}
}

function ForcedRebootCountDown_Over {
	# This is used to forcefully reboot the machine
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Forced reboot countdown reached. The device will restart in one minute." -Force
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	shutdown /r /t 60 /C "Forced reboot - This device will restart in one minute." #Fun fact, this shutdown comment will show in the event log
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's
}

#endregion functions

#Region logging
########################### Create log locations ###########################

#Clear any running form (mostly a testing problem). We don't need to actually catch anything, ignoring errors just doesn't work on this command.
try { $RebootPromptForm.Close(); $RebootPromptForm.Dispose() } catch {}

#Before anything else, including starting logging, our storage paths must exist.
write-host "Calling for path creation: $($LogFileFolder)"
New-Directory -Path $LogFileFolder


#Start our log now that folders/paths have been declared and created
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Reboot Maintenance running as $($env:USERNAME) on $($env:COMPUTERNAME)" -Force
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Timeout is set to $($TimeOutDuration) seconds." -Force
#endregion logging

#region image
########################### Image ###########################

#Check if the image is present
if (Test-Path "$($LogFileFolder)\$LogoName"){
    #If yes, check the hash.
    $CalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\$LogoName"

    #Check if the hash matches
    if ($CalculatedImageHash -eq $ImageHash){
    #The hash does match
    Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\$LogoName - is present and has a matching hash." -Force

    } 
    else {
        #The hash does not match
        Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - is present but the hash does not match, fixing!" -Force
        Write-Warning "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - is present but the hash does not match, fixing!"

        #This automatically overrides existing files
        Invoke-WebRequest $Imageurl -OutFile "$($LogFileFolder)\$LogoName"

        #Check that it worked
        $RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\$LogoName"

        if ((Test-Path "$($LogFileFolder)\$LogoName") -and $RecheckCalculatedImageHash -eq $ImageHash){
            Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image - $($LogFileFolder)\$LogoName - file download completed and hash corrected."
        } 
        else {
            Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - file creation completed but the file was not detected and/or hash is still not correct!
            Detected hash: $($RecheckCalculatedImageHash)
            Expected hash: $($ImageHash)"
            Write-Warning "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - file creation completed but the file was not detected and/or hash is still not correct!
            Detected hash: $($RecheckCalculatedImageHash)
            Expected hash: $($ImageHash)"
        }
    }
} 
else {
    #False - Image is not present, download the image
    write-host "Image not present, downloading" -ForegroundColor Yellow
    Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image - $($LogFileFolder)\$LogoName - is NOT present, downloading." -Force
    
    #Download
    Invoke-WebRequest $Imageurl -OutFile "$($LogFileFolder)\$LogoName"

    #Check that it worked
    $RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\$LogoName"
    $Checkpath = Test-Path "$($LogFileFolder)\$LogoName" #It does not like having this combined with -and directly

    if ($Checkpath -eq $true -and $RecheckCalculatedImageHash -eq $ImageHash){
        Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image - $($LogFileFolder)\$LogoName - file download completed and hash correct."
    } 
    else {
        Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - file creation completed but the file was not detected and/or hash is still not correct!"
        Write-Warning "$(get-date): Warning: Image - $($LogFileFolder)\$LogoName - file creation completed but the file was not detected and/or hash is still not correct!"
    }
}
#endregion image

#Region testing
#This is used to override the free space we just calculated for testing purposes. See $TestingMachineUptimeValue in the variables region.
#if ($null -ne $TestingMachineUptimeValue){
#	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Testing value is enabled and set to: $($TestingMachineUptimeValue) days" -Force
#	Write-Warning "Testing value is enabled!"
#	$MachineUptimeDays = $TestingMachineUptimeValue
#}
#endregion

#region main
########################### Main ###########################

$MachineUptimeDays = (((get-date) - (gcim Win32_OperatingSystem).LastBootUpTime).Days)
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine $($env:COMPUTERNAME) has been up for ($MachineUptimeDays) days." -Force
$starttime = get-date #used by the script to reference in text the end of the forced reboot timer.

########################### Main form ###########################

# This is where our new Windows Form popup is defined in terms of overall style and dimension.
$RebootPromptForm = New-Object System.Windows.Forms.Form
#$RebootPromptForm.MaximumSize = New-Object System.Drawing.Size(800, 450) #This is defined individually in the two sections that determine what variant of the popup should be tossed as they are not the same size.
#$RebootPromptForm.MinimumSize = New-Object System.Drawing.Size(800, 450) #This is defined individually in the two sections that determine what variant of the popup should be tossed as they are not the same size.
$RebootPromptForm.MaximizeBox = $false
$RebootPromptForm.MinimizeBox = $false
$RebootPromptForm.TopMost = $True
$RebootPromptForm.TopLevel = $True
$RebootPromptForm.StartPosition = "CenterScreen"
$RebootPromptForm.Text = "Reboot Maintenance"

$RebootPromptForm.BackColor = $RebootPromptFormBackgroundColor

#We don't want this to be closeable in non-logging ways. So, we will hide the normal means of closing such a popup such that employees are forced to click our close button which does log the action.
#Hide the X out option.
$RebootPromptForm.ControlBox = $false
#Hide on taskbar such that it cannot be closed by right-clicking it on the task bar and hitting close
$RebootPromptForm.ShowInTaskbar = $false

########################### Main close button ###########################

#This defines our close button, where it is, and what options it has. What it does when clicked is defined by "function button_click".
$btn1 = New-Object System.Windows.Forms.Button
$btn1.DataBindings.DefaultDataSourceUpdateMode = 0
$btn1.Font = New-Object System.Drawing.Font("Aptos",12,[System.Drawing.FontStyle]::Bold)
$btn1.Name = "btn1"
$btn1.Size = New-Object System.Drawing.Size(250, 50)
$btn1.TabIndex = 0
$btn1.TabStop = $False
$btn1.Text = "Sluiten"
$btn1.UseVisualStyleBackColor = $True
$btn1.BackColor = $ButtonBackgroundColor #See the variables region to change me!
$btn1.ForeColor = $ButtonTextColor #See the variables region to change me!
# On click call function to close popup
$btn1.add_Click{
    button_click
}

########################### Main reboot now optional ###########################
#This defines our reboot now optional button
$btn2 = New-Object System.Windows.Forms.Button
$btn2.DataBindings.DefaultDataSourceUpdateMode = 0
$btn2.Font = New-Object System.Drawing.Font("Aptos",12,[System.Drawing.FontStyle]::Bold)
$btn2.Name = "btn2"
$btn2.Size = New-Object System.Drawing.Size(250, 50)
$btn2.TabIndex = 0
$btn2.TabStop = $False
$btn2.Text = "Herstarten"
$btn2.UseVisualStyleBackColor = $True
$btn2.BackColor = $ButtonBackgroundColor #See the variables region to change me!
$btn2.ForeColor = $ButtonTextColor #See the variables region to change me!
# On click call function to reboot now
$btn2.add_Click{
    button2_click
}

$richTextBox1 = New-Object System.Windows.Forms.RichTextBox
#background color. Only works if enabled. (see $richTextBox1.Enabled)

$richTextBox1.BackColor = $TextBoxBackgroundColor #See the variables region to change me!
$richTextBox1.ForeColor = $TextBoxTextColor #See the variables region to change me!
$richTextBox1.DataBindings.DefaultDataSourceUpdateMode = 0

#If you enable this ($true), make sure you also leave "ReadOnly" enabled otherwise you can edit the text in the box.
#The upside to enabling this is that you can control the fields background color, otherwise it will just be the default grey.
$richTextBox1.Enabled = $true

#readonly prevents changes. Read only is really only needed if the above is false.
$richTextBox1.ReadOnly = $true 

#Sets the border of our text box to none
$richTextBox1.BorderStyle = "none"

$richTextBox1.Font = New-Object System.Drawing.Font("Aptos",12, [System.Drawing.FontStyle]::Bold)
$richTextBox1.Location = New-Object System.Drawing.Point(60, 195)
$richTextBox1.Size = New-Object System.Drawing.Size(670, 220)
#$richTextBox1.Location = $System_Drawing_Point
$richTextBox1.Name = "richTextBox1"
#$richTextBox1.Size = $System_Drawing_Size
$richTextBox1.TabIndex = 2

#Enable URL detection such that URLS can be inserted and clickable in the text box.
#You can use this if you want however, it requires an ugly full URL in the box and, you will have no logging that they clicked it. This is why we use a button to launch or URL instead. (More so angled towards the original disk space alerts which had a help button that launched a URL)
$richTextBox1.DetectUrls = $True

#center text
$richTextBox1.SelectionAlignment= "Center"

########################### Main picture ###########################

#Check our image dimensions for some automatic math
$imageFile = "$($LogFileFolder)\$LogoName"
Add-Type -AssemblyName System.Drawing
$image = New-Object System.Drawing.Bitmap $imageFile
$imageWidth = $image.Width
$imageHeight = $image.Height

if ($imageWidth -gt 500 -or $imageHeight -gt 175){
	Write-Warning "This image may be too large for the default form layout."
}

$pictureBox1 = New-Object System.Windows.Forms.PictureBox
$pictureBox1.BackgroundImage = [System.Drawing.Image]::FromFile("$($LogFileFolder)\$LogoName")
$pictureBox1.BackgroundImageLayout = 2
$pictureBox1.DataBindings.DefaultDataSourceUpdateMode = 0
$pictureBox1.Location = New-Object System.Drawing.Point(((800/2)-($imageWidth/2)), 10) #To get a centered result, this is your page width (800 by default) divided by two, minus half your image width.
$pictureBox1.Size = New-Object System.Drawing.Size(175, 175)
#$picturebox1.SizeMode = "centerimage"
$pictureBox1.Name = "pictureBox1"
$pictureBox1.TabIndex = 1
$pictureBox1.TabStop = $False

########################### Main time countdown ###########################

#Converts the time-remaning seconds value into a tracked time remaining. This is easier to pass through a in-between variable than to pipe directly to the countdown text.
$HHMMSS = [timespan]::fromseconds($timeremaining.text)

#Create the countdown label for the timeout
$Countdown_Label = New-Object System.Windows.Forms.Label
$Countdown_Label.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$Countdown_Label.Location = New-Object System.Drawing.Point(0, 0)
$Countdown_Label.Size = New-Object System.Drawing.Size(250, 50)
$Countdown_Label.Font = [System.Drawing.Font]::new("Segoe UI","12",[System.Drawing.FontStyle]::Bold)
$Countdown_Label.ForeColor = "#E64F4F"

#Create the countdown label for the forced restart
$Countdown_Label2 = New-Object System.Windows.Forms.Label
$Countdown_Label2.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$Countdown_Label2.Location = New-Object System.Drawing.Point(100, 325)
$Countdown_Label2.Size = New-Object System.Drawing.Size(250, 50)
$Countdown_Label2.Font = [System.Drawing.Font]::new("Segoe UI","12",[System.Drawing.FontStyle]::Bold)
$Countdown_Label2.ForeColor = "#FF0000"
$Countdown_Label2.TextAlign = "TopCenter"

#The content of the text is set as part of the function CountDown as setting a text value or not determines it's visibility (See $AutoCloseVisible)

#This will cause it to align to the center of your drawing size window, which will not be aligned to the top left.
#$Countdown_Label.TextAlign = "TopCenter"

#This must be stored as a label otherwise it will tick once and freeze. It is VERY important you declare this new object AFTER the form has been created.
$TimeRemaining = New-Object System.Windows.Forms.Label #Don't touch this.
$timeRemaining.text = $TimeOutDuration #See the variables region to change me!

# Countdown is decremented every seconde using a timer
# The tick rate is 1000 MS or 1 second. You can drop it to 100 or 10 for testing.
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=1000
$timer.add_Tick({CountDown})
$timer.Start()

#This must be stored as a label otherwise it will tick once and freeze. It is VERY important you declare this new object AFTER the form has been created.
$timeRemainingForcedReboot = New-Object System.Windows.Forms.Label #Don't touch this.
$timeRemainingForcedReboot.text = $ForcedRebootTime #See the variables region to change me!

# Countdown is decremented every seconde using a timer
# The tick rate is 1000 MS or 1 second. You can drop it to 100 or 10 for testing.
$timer2=New-Object System.Windows.Forms.Timer
$timer2.Interval=1000
$timer2.add_Tick({ForcedRebootCountDown})

########################### Main assign ###########################

#Assign our timer, picture, two buttons, and help message to our form.
$RebootPromptForm.Controls.Add($Countdown_Label)
$RebootPromptForm.Controls.Add($Countdown_Label2)
$RebootPromptForm.Controls.Add($btn1) #order matters here! Don't put me under the textbook or I will layer under it (and not just where there is text but the full invisible box size)!
$RebootPromptForm.Controls.Add($btn2)
$RebootPromptForm.Controls.Add($pictureBox1)
$RebootPromptForm.controls.add($richTextBox1)

#Region check popup applicability
#This is where we truly check if the device should be prompted or not. This is done last because you really need to declare the form itself along with all content before attempting to call to it.

#If you break the maximum uptime (Greater than or equal to)
if ($MachineUptimeDays -ge $MaximumUptime){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is greater than or equal to the configured MAXIMUM threshold of $($MaximumUptime) days - prompting for FORCED reboot." -Force

	#Set form size of the form
	$RebootPromptForm.ClientSize = New-Object System.Drawing.Size(800, 450)

	#Set button heights
	$btn1.Location = New-Object System.Drawing.Point(0, 900) #Throw me off screen
	$btn2.Location = New-Object System.Drawing.Point(425, 325)

	#Set the timeout to invisible
	$AutoCloseVisible = $false

	#Start the forced countdown timer
	$timer2.Start()

	#Set our message for our text box
	$richTextBox1.Text = "Deze computer is niet opnieuw opgestart in de afgelopen $($MachineUptimeDays) dagen. De computer wordt automatisch opnieuw opgestart in 15 minuten vanaf $($starttime). Zorg ervoor dat u uw werk opslaat en sluit voordat u opnieuw opstart!"

	RebootPrompt #Yes they both call the same thing
	exit #Yes, this really should go here for when the form exits.
}
#endregion check popup applicability

#If you break the minimum uptime (Greater than or equal to)
if ($MachineUptimeDays -ge $MinimumUptime){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is greater than or equal to the configured MINIMUM threshold of $($MinimumUptime) days - prompting for OPTIONAL reboot." -Force
	
	#Region Configure form options for a optional reboot

	#Set form size
	$RebootPromptForm.ClientSize = New-Object System.Drawing.Size(800, 475)

	#Set button heights
	$btn1.Location = New-Object System.Drawing.Point(425, 375)
	$btn2.Location = New-Object System.Drawing.Point(100, 375)

	#Move the reboot timer off view (it's not active)
	$Countdown_Label2.Location = New-Object System.Drawing.Point(800, 325)

	#Set our message for our text box
	
	$richTextBox1.Text = "Uw computer is niet opnieuw opgestart in de afgelopen $($MachineUptimeDays) dagen. Gelieve uw computer zo snel mogelijk opnieuw op te starten. Zorg ervoor dat u uw werk opslaat en sluit voordat u opnieuw opstart! Als dit moment niet geschikt is, klik dan op de knop Sluiten en u wordt later opnieuw herinnerd."

    RebootPrompt #Yes they both call the same thing
	exit #Yes, this really should go here for when the function exits.
}
else {
	#You did not violate either value - good job!
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is not greater than the maximum uptime of $($MaximumUptime) days, or the minimum uptime of $($MinimumUptime) days - exiting." -Force
	write-host "$(get-date): Machine uptime of $($MachineUptimeDays) days is not greater than the maximum uptime of $($MaximumUptime) days, or the minimum uptime of $($MinimumUptime) days - exiting."
	exit    
}