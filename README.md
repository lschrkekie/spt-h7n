# spt-h7n Client Mod Installer

Installs the BepInEx client plugins required to play on the h7n SPT-Fika
server — for human players and headless clients alike. `mods-manifest.json`
is the single source of truth for mod names/versions/URLs; both installer
scripts read it, so nothing is hardcoded twice.

## Quick start (no manual download)

### Windows (PowerShell)

```powershell
$Installer = irm https://raw.githubusercontent.com/lschrkekie/spt-h7n/main/install-client-mods.ps1
& ([scriptblock]::Create($Installer)) -Manifest https://raw.githubusercontent.com/lschrkekie/spt-h7n/main/mods-manifest.json
```

You'll be prompted for the path to your SPT client install.

### Linux (bash)

```bash
curl -fsSL https://raw.githubusercontent.com/lschrkekie/spt-h7n/main/install-client-mods.sh | MANIFEST=https://raw.githubusercontent.com/lschrkekie/spt-h7n/main/mods-manifest.json bash
```

Same here — you'll be prompted for the install path.

## Requirements

- **Windows:** curl.exe (ships with Windows 10 1803+ / Windows 11), 7-Zip
- **Linux:** curl, unzip, jq, 7z or 7zz

## Manual / local use

Clone the repo instead of using the one-liners above if you want to inspect
or edit the scripts first, or point at a local manifest copy.

```powershell
.\install-client-mods.ps1 -SptPath "C:\Games\SPT"
```

If that fails with "running scripts is disabled on this system", run it via:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-client-mods.ps1 -SptPath "C:\Games\SPT"
```

This bypasses the policy for just that one process — no admin rights needed,
no permanent system change.

```bash
./install-client-mods.sh /path/to/SPT
```

Both scripts default to `mods-manifest.json` next to themselves; pass a path
or URL as the second argument (or set the `MANIFEST` env var / `-Manifest`
param) to use a different one.
