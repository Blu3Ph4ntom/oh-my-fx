# omfx installer (Windows PowerShell)
# Usage: irm https://blu3ph4ntom.github.io/oh-my-fx/install.ps1 | iex
[CmdletBinding()]
param(
    [string]$Repo = $(if ($env:OMFX_REPO) { $env:OMFX_REPO } else { "blu3ph4ntom/oh-my-fx" }),
    [string]$InstallDir = $(if ($env:OMFX_INSTALL_DIR) { $env:OMFX_INSTALL_DIR } else { Join-Path $HOME ".omfx\bin" })
)

$ErrorActionPreference = "Stop"

function Get-LatestWindowsAsset {
    $api = "https://api.github.com/repos/$Repo/releases/latest"
    $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "omfx-installer" }
    $asset = $release.assets | Where-Object {
        $_.name -match 'omfx-windows' -and ($_.name -match '\.zip$' -or $_.name -match 'omfx\.exe$')
    } | Select-Object -First 1
    if ($null -eq $asset) {
        throw @"
No Windows omfx asset found on the latest GitHub Release.
Publish a release asset named like omfx-windows-x86_64.zip (containing omfx.exe),
or download the Actions artifact 'omfx-windows-x86_64' manually.
Repo: https://github.com/$Repo
"@
    }
    return [pscustomobject]@{
        Tag = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
    }
}

Write-Host "Resolving latest omfx Windows release..."
$info = Get-LatestWindowsAsset
Write-Host "Downloading $($info.Tag) ($($info.Name))..."

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("omfx-install-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $downloadPath = Join-Path $tmp $info.Name
    Invoke-WebRequest -Uri $info.Url -OutFile $downloadPath -UseBasicParsing

    $exeSource = $null
    if ($info.Name -like "*.zip") {
        Expand-Archive -LiteralPath $downloadPath -DestinationPath (Join-Path $tmp "out") -Force
        $exeSource = Get-ChildItem -Path (Join-Path $tmp "out") -Recurse -Filter "omfx.exe" | Select-Object -First 1
    } elseif ($info.Name -like "*.exe") {
        $exeSource = Get-Item -LiteralPath $downloadPath
    }

    if ($null -eq $exeSource) {
        throw "Downloaded asset did not contain omfx.exe."
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $dest = Join-Path $InstallDir "omfx.exe"
    Copy-Item -LiteralPath $exeSource.FullName -Destination $dest -Force
    Write-Host "Installed $dest"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $InstallDir), "User")
        $env:Path = $InstallDir + ";" + $env:Path
        Write-Host "Added $InstallDir to your user PATH."
    }

    & $dest --version
    Write-Host "Run: omfx"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
