<#
.SYNOPSIS
    Installs the BepInEx client plugins into a local SPT client install:
    the Fika client plugin, SAIN + its dependencies (BigBrain, Waypoints -
    Expanded Navmesh), Dynamic Maps, Temporary Fixes, ABPS, HandsAreNotBusy,
    WTT - Content Backport + WTT-CommonLib, Content Backport - Prestiges,
    and Show Me The Money.

.DESCRIPTION
    The mod list itself (names + download URLs) lives in mods-manifest.json
    next to this script, not in this file - edit that to bump a version or
    add/remove a mod, both this script and install-client-mods.sh read it.

    These are BepInEx client plugins - they must be installed on every client
    that renders a raid (human players AND headless clients), not just on the
    dedicated server. Pure server-side mods (Server Value Modifier, Better
    Keys NG, Lacy's PvE Tweaks, APBS) are intentionally NOT included here -
    they're installed server-side only via the egg's INSTALL_OTHER_MODS /
    MOD_URLS_TO_DOWNLOAD mechanism. SVM's config GUI (Greed.exe) has its own
    setup steps documented in MODS-GUIDE.md section 6.

    NOTE: WTT - Content Backport alone is ~3.5GB - this script's total
    download is large. Make sure SptPath has several GB free before running.

    Mods already installed into a given SptPath (tracked by URL in
    SptPath\.spt-mod-installer\installed-urls.txt) are skipped on re-runs
    instead of being re-downloaded. Bumping a mod's version in the manifest
    changes its URL, so it's correctly picked up as a fresh install.

.PARAMETER SptPath
    Root of the SPT client install (contains BepInEx\ and SPT\). If omitted,
    you will be prompted for it interactively.

.PARAMETER Manifest
    Local path or http(s) URL to a mods-manifest.json. Defaults to
    mods-manifest.json next to this script.

.EXAMPLE
    .\install-client-mods.ps1 -SptPath "C:\Games\SPT"
#>

[CmdletBinding()]
param(
    [string]$SptPath,
    [string]$Manifest = (Join-Path $PSScriptRoot "mods-manifest.json")
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SptPath)) {
    $SptPath = Read-Host "Path to your SPT client install (folder containing BepInEx\)"
}

if ($Manifest -match '^https?://') {
    Write-Host "Fetching manifest from $Manifest"
    $ManifestJson = (Invoke-WebRequest -UseBasicParsing -Uri $Manifest).Content | ConvertFrom-Json
}
else {
    if (-not (Test-Path $Manifest)) {
        Write-Error "FATAL: manifest '$Manifest' not found."
        exit 1
    }
    $ManifestJson = Get-Content -Raw $Manifest | ConvertFrom-Json
}
if (-not $ManifestJson.mods) {
    Write-Error "FATAL: '$Manifest' has no top-level 'mods' array."
    exit 1
}
$Mods = $ManifestJson.mods | ForEach-Object { @{ Name = $_.name; Url = $_.url } }

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "FATAL: curl.exe is required but was not found (ships with Windows 10 1803+ / Windows 11)."
    exit 1
}

$SevenZip = $null
foreach ($candidate in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
    if (Test-Path $candidate) { $SevenZip = $candidate; break }
}
if (-not $SevenZip -and (Get-Command 7z.exe -ErrorAction SilentlyContinue)) {
    $SevenZip = "7z.exe"
}
if (-not $SevenZip) {
    Write-Error "FATAL: 7-Zip (7z.exe) is required but was not found. Install it from https://www.7-zip.org/ and re-run."
    exit 1
}

if (-not (Test-Path $SptPath)) {
    Write-Error "FATAL: '$SptPath' does not exist."
    exit 1
}
$SptPath = (Resolve-Path $SptPath).Path

if (-not (Test-Path (Join-Path $SptPath "BepInEx"))) {
    Write-Error "FATAL: '$SptPath' does not look like an SPT client install (no BepInEx\ found)."
    exit 1
}

$TempDir = Join-Path $env:TEMP ("spt-mod-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TempDir | Out-Null

# Tracks which mod URLs have already been installed into this specific
# SptPath, so re-running the script skips mods that are already present
# instead of re-downloading everything every time. Keyed by URL (not name)
# so bumping a mod's version in the manifest - which changes its URL - is
# correctly treated as "not yet installed" and gets pulled in.
$InstalledMarkerDir = Join-Path $SptPath ".spt-mod-installer"
$InstalledMarkerFile = Join-Path $InstalledMarkerDir "installed-urls.txt"
New-Item -ItemType Directory -Path $InstalledMarkerDir -Force | Out-Null
if (-not (Test-Path $InstalledMarkerFile)) { New-Item -ItemType File -Path $InstalledMarkerFile | Out-Null }
$InstalledUrls = @(Get-Content $InstalledMarkerFile -ErrorAction SilentlyContinue)

$Installed = @()
$Skipped = @()

try {
    foreach ($mod in $Mods) {
        if ($InstalledUrls -contains $mod.Url) {
            Write-Host "=== $($mod.Name) === already installed, skipping"
            $Skipped += $mod.Name
            continue
        }

        Write-Host "=== $($mod.Name) ==="
        $ModDir = Join-Path $TempDir $mod.Name
        $DownloadDir = Join-Path $ModDir "download"
        $ExtractDir = Join-Path $ModDir "extract"
        New-Item -ItemType Directory -Path $DownloadDir, $ExtractDir -Force | Out-Null

        Write-Host "  Downloading..."
        Push-Location $DownloadDir
        try {
            & curl.exe -f -S -L --progress-bar -A "Mozilla/5.0" -J -O $mod.Url
            if ($LASTEXITCODE -ne 0) { throw "curl failed downloading $($mod.Url)" }
        }
        finally {
            Pop-Location
        }

        $Archive = Get-ChildItem $DownloadDir | Select-Object -First 1
        if (-not $Archive) { throw "download produced no file for $($mod.Name)" }

        Write-Host "  Extracting..."
        & $SevenZip x -y $Archive.FullName ("-o" + $ExtractDir)
        if ($LASTEXITCODE -ne 0) { throw "extraction failed for $($mod.Name)" }

        Write-Host "  Installing..."
        $BepInExSrc = Join-Path $ExtractDir "BepInEx\plugins"
        if (Test-Path $BepInExSrc) {
            $DestPlugins = Join-Path $SptPath "BepInEx\plugins"
            New-Item -ItemType Directory -Path $DestPlugins -Force | Out-Null
            Copy-Item (Join-Path $BepInExSrc "*") $DestPlugins -Recurse -Force
        }

        $PatchersSrc = Join-Path $ExtractDir "BepInEx\patchers"
        if (Test-Path $PatchersSrc) {
            $DestPatchers = Join-Path $SptPath "BepInEx\patchers"
            New-Item -ItemType Directory -Path $DestPatchers -Force | Out-Null
            Copy-Item (Join-Path $PatchersSrc "*") $DestPatchers -Recurse -Force
        }

        $ModsSrc = Join-Path $ExtractDir "SPT\user\mods"
        if (Test-Path $ModsSrc) {
            $DestMods = Join-Path $SptPath "SPT\user\mods"
            New-Item -ItemType Directory -Path $DestMods -Force | Out-Null
            Copy-Item (Join-Path $ModsSrc "*") $DestMods -Recurse -Force
        }

        $ManagedSrc = Join-Path $ExtractDir "EscapeFromTarkov_Data\Managed"
        if (Test-Path $ManagedSrc) {
            $ManagedDest = Join-Path $SptPath "EscapeFromTarkov_Data\Managed"
            if (Test-Path $ManagedDest) {
                Copy-Item (Join-Path $ManagedSrc "*.dll") $ManagedDest -Force
            }
            else {
                Write-Host "  Note: $($mod.Name) ships EscapeFromTarkov_Data\Managed DLLs, but '$SptPath' has no such folder - skipped."
            }
        }

        Write-Host "  $($mod.Name) installed."
        Add-Content -Path $InstalledMarkerFile -Value $mod.Url
        $Installed += $mod.Name
    }
}
finally {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Installed: $(if ($Installed) { $Installed -join ', ' } else { 'none' })"
if ($Skipped) { Write-Host "Already up to date, skipped: $($Skipped -join ', ')" }
if ($Installed) { Write-Host "Restart the game client so BepInEx picks up the new plugins." }
