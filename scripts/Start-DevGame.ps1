<#
.SYNOPSIS
Launch Remastered and automatically load a selected local save.
.EXAMPLE
.\scripts\Start-DevGame.ps1 -ListSaves
.EXAMPLE
.\scripts\Start-DevGame.ps1 -SaveFile 'ManualSave_8559a_7ea51800_2abde4e.sav'
.EXAMPLE
.\scripts\Start-DevGame.ps1 -SaveFile 'ManualSave_8559a_7ea51800_2abde4e.sav' -WhatIf
.NOTES
Keep this PowerShell session open until the game exits. A temporary script mod
selects the save through the game's menu loading code and is removed on exit.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SaveFile,
    [string] $GameDirectory = 'D:\SteamLibrary\steamapps\common\The Witcher 3',
    [string] $SaveDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'The Witcher 3\gamesaves'),
    [switch] $ListSaves
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ListSaves) {
    Get-ChildItem -LiteralPath $SaveDirectory -File -Filter '*.sav' |
        Sort-Object LastWriteTime -Descending |
        Select-Object Name, LastWriteTime
    return
}

if ([string]::IsNullOrWhiteSpace($SaveFile)) {
    throw 'Specify -SaveFile with a save filename or full path. Use -ListSaves to see your saves.'
}

$savePath = $SaveFile
if (-not [IO.Path]::IsPathRooted($savePath)) {
    $savePath = Join-Path $SaveDirectory $savePath
}
$save = Get-Item -LiteralPath $savePath
if ($save.PSIsContainer -or $save.Extension -ine '.sav' -or $save.Length -eq 0) {
    throw 'The selected file must be a non-empty .sav file.'
}
$resolvedSaveDirectory = (Resolve-Path -LiteralPath $SaveDirectory).ProviderPath
if ($save.DirectoryName -ine $resolvedSaveDirectory.TrimEnd('\', '/')) {
    throw 'The save must be inside -SaveDirectory so the game can find it. External saves are not copied automatically.'
}
# Filenames are embedded as WitcherScript literals in the temporary mod.
if ($save.Name -notmatch '^[A-Za-z0-9_. -]+\.sav$') {
    throw 'The save filename contains unsupported characters for the development launcher.'
}

$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
$executable = Join-Path $gameRoot 'bin\x64_dx12\witcher3.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Remastered executable not found at $executable"
}

if (-not $PSCmdlet.ShouldProcess($executable, "Launch and load $($save.Name) using a temporary startup mod")) {
    return
}
if (Get-Process -Name witcher3 -ErrorAction SilentlyContinue) {
    throw 'Exit the running game before using this launcher.'
}

$modRoot = Join-Path $gameRoot 'mods\modWitcherOnlineDevLauncher'
if (Test-Path -LiteralPath $modRoot) {
    throw "A launcher mod already exists at $modRoot. Close any previous launcher session and inspect that folder before retrying."
}
$modScripts = Join-Path $modRoot 'content\scripts'
$hookPath = Join-Path $modScripts 'devLauncher.ws'
$templatePath = Join-Path $PSScriptRoot 'devLauncher.ws.template'
$hook = [IO.File]::ReadAllText($templatePath).
    Replace('__SAVE_FILENAME__', $save.Name).
    Replace('__SAVE_STEM__', $save.BaseName)

try {
    New-Item -ItemType Directory -Path $modScripts -Force | Out-Null
    [IO.File]::WriteAllText($hookPath, $hook, [Text.UTF8Encoding]::new($false))
    Write-Host "Starting Remastered with $($save.Name)"
    Write-Host 'Keep this terminal open. The temporary launcher mod is removed when the game exits.'
    $game = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable) -WindowStyle Normal -PassThru
    $game.WaitForExit()
}
finally {
    # Remove only the generated file when its contents still match this launch.
    if ((Test-Path -LiteralPath $hookPath) -and [IO.File]::ReadAllText($hookPath) -ceq $hook) {
        Remove-Item -LiteralPath $hookPath
        foreach ($folder in @($modScripts, (Join-Path $modRoot 'content'), $modRoot)) {
            if (@(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) {
                Remove-Item -LiteralPath $folder
            }
        }
    }
}
