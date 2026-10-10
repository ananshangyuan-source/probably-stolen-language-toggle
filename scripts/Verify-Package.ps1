[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dependencies = Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath (Join-Path $root 'dist\QuickLanguage.dll') -Algorithm SHA256).Hash -ne $dependencies.plugin.sha256) { throw 'Plugin checksum mismatch.' }
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1') {
    $parseErrors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors) { throw "PowerShell syntax error in $($file.Name): $($parseErrors[0].Message)" }
}
$publicFiles = @(
    Get-ChildItem -LiteralPath $root -File | Where-Object Name -notlike '.*'
    foreach ($directory in @('src','scripts','docs','tests','.github','dist')) { Get-ChildItem -LiteralPath (Join-Path $root $directory) -File -Recurse }
)
foreach ($file in $publicFiles) {
    if ($file.Extension -eq '.dll' -and $file.FullName -ne (Join-Path $root 'dist\QuickLanguage.dll')) {
        throw "Only our own plugin DLL may be distributed: $($file.Name)"
    }
    if ($file.Extension -in @('.bundle','.assets','.dat','.pdb','.zip','.7z')) { throw "Unexpected binary/archive in public source: $($file.Name)" }
    if ($file.Name -match '^(language-pairs\.json|Assembly-CSharp\.dll|GameAssembly\.dll|UnityPlayer\.dll|global-metadata\.dat|dump\.cs|installation\.json|original-game-hashes\.json)$') {
        throw "Forbidden game/private file in public package: $($file.Name)"
    }
    if ($file.Extension -in @('.cs','.py','.ps1','.md','.json','.txt','.yml','.cmd')) {
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text -match '(?i)[A-Z]:[\\/]Users[\\/][^\\/\r\n]+') { throw "Personal absolute path in $($file.Name)" }
        if ($text -match '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,})') { throw "Possible credential in $($file.Name)" }
    }
}
Write-Host 'Public package checks passed: plugin hash, PowerShell syntax, no game tables/binaries or personal paths.'
