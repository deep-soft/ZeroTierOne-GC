function Download-GitHub
{
    param (
        $tag
    )

    # We're assuming a 64-bit system here. Hopefully no one tries to run this on a 32-bit Windows.
    $download = "https://github.com/GermanCoding/ZeroTierOne/releases/download/$tag/x64.zip"
    $zip = "$Env:tmp\zerotier-$tag.zip"
    Write-Host "Dowloading GermanCoding's ZeroTier fork from GitHub"
    Invoke-WebRequest -UseBasicParsing $download -Out $zip
    Write-Host "Download complete"
}

function Install-GitHub
{
    param (
        $tag
    )

    $dest = "$Env:programdata\ZeroTier\One\zerotier-one_x64.exe"
    $zip = "$Env:tmp\zerotier-$tag.zip"
    $dir = "$Env:tmp\zerotier-$tag"
    $subpath = "x64\Release\zerotier-one_x64.exe"

    Write-Host "Installing GermanCoding's ZeroTier fork"

    Expand-Archive -Path $zip -Force -DestinationPath $dir

    # Moving from temp dir to target dir
    Move-Item $dir\$subpath -Destination $dest -Force

    # Removing temp files
    Remove-Item $zip -Force
    Remove-Item $dir -Recurse -Force

    Write-Host "Installation done"
}

$ErrorActionPreference = "Stop"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{
    echo "This script must be run as admin from ZeroTier-upgrade.bat!"
    pause
    exit;
}

# This is actually just a proxy for the GitHub API. Due to GitHub API limits we relay this through our cache.
$releases = "https://cache.germancoding.com/zerotier-fork/releases"
$zt_official_prefix = "https://download.zerotier.com/RELEASES/"
$zt_official_suffix = "/dist/ZeroTier One.msi"
$local_version_path = "HKLM:\SOFTWARE\WOW6432Node\ZeroTier, Inc.\ZeroTier One"
$local_release = (Get-ItemProperty -Path $local_version_path).Version
$local_update_msi = "$Env:tmp\ZeroTierOne.msi"
$win_service = "ZeroTierOneService"
$desktop_ui = "zerotier_desktop_ui"

function Stop-ZeroTier
{
    Write-Host "Stopping ZeroTier"
    try
    {
        Stop-Service $win_service -Force
    }
    catch
    {
        # Try again, sometimes takes two attempts
        Write-Host "Trying again..."
        Stop-Service $win_service -Force
    }
}

function Cleanup
{
    Start-Service $win_service -ErrorAction SilentlyContinue
    Remove-Item $local_update_msi -ErrorAction SilentlyContinue
}

Write-Host "Currently installed version:" $local_release
$tag = (Invoke-WebRequest -UseBasicParsing $releases | ConvertFrom-Json)[0].tag_name
$fork_release = $tag.split("-fork")[0]
Write-Host "Latest fork version:" $fork_release

if ([System.Version]$fork_release -gt [System.Version]$local_release)
{
    $title = 'ZeroTier Upgrade'
    $question = "ZeroTier upgrade to version " + $fork_release + " available. Do you want to upgrade now?"
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",   `
      ("Upgrades ZeroTier to version " + $fork_release + " from GermanCoding's ZeroTier fork.")
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",   `
      "The upgrade will be aborted. Your ZeroTier installation remains unchanged."
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
    if ($decision -eq 0)
    {
        Write-Host 'Downloading official ZeroTier release for overall package upgrade...'
        Invoke-WebRequest -UseBasicParsing ($zt_official_prefix + $fork_release + $zt_official_suffix) -Out $local_update_msi
        Download-Github -tag $tag
        # Remember what settings the service had prior to install
        $starttype = (Get-Service $win_service).StartType
        if (Get-Process -Name $desktop_ui -ErrorAction SilentlyContinue)
        {
            $kill = $False
        }
        else
        {
            $kill = $True
        }
        try
        {
            Stop-ZeroTier
            Write-Host "Instaling official ZeroTier One.msi"
            $status = (Start-Process -FilePath "$local_update_msi" -PassThru -Wait).ExitCode
            if ($status -ne 0)
            {
                Throw "Upgrading ZeroTier via official msi failed: $status"
            }
            Write-Host "Deleting temp files"
            Remove-Item $local_update_msi
            Write-Host "Applying GermanCoding's ZeroTier fork"
            # Ensure there is no auto-restart going on
            Stop-ZeroTier
            Install-GitHub -tag $tag
            Write-Host "Install complete, restarting service"
            Start-Service $win_service
            Write-Host "Restoring settings"
            Set-Service $win_service -StartupType $starttype
            if ($kill)
            {
                Stop-Process -Name $desktop_ui -ErrorAction SilentlyContinue
            }
            Write-Host "ZeroTier succesfully upgraded to version $fork_release"
        }
        finally
        {
            # Just to double check
            Cleanup
        }
    }
    else
    {
        Write-Host "Aborting upgrade. You may be prompted again when re-running this script."
    }
}
else
{
    Write-Host "Your ZeroTier(-fork) version is up to date."
}
