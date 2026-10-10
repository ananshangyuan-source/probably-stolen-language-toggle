[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('true','false')][string]$Enabled)
. (Join-Path $PSScriptRoot 'Common.ps1')
$manifest = Read-Installation
Assert-GameStopped $manifest.gameRoot
Assert-OwnedLoaders $manifest
$path = Join-Path $manifest.gameRoot 'doorstop_config.ini'
$config = [IO.File]::ReadAllText($path)
if (-not [regex]::IsMatch($config, '(?m)^\s*enabled\s*=.*$')) { throw 'Unexpected loader configuration.' }
$replacement = 'enabled = ' + $Enabled
$config = [regex]::Replace($config, '(?m)^\s*enabled\s*=.*$', $replacement)
[IO.File]::WriteAllText($path, $config, (New-Object Text.UTF8Encoding($false)))
foreach ($record in $manifest.addedFiles) {
    if ($record.name -eq 'doorstop_config.ini') { $record.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$manifest.enabled = $Enabled -eq 'true'
Write-Installation $manifest
Write-Host "MOD enabled: $($manifest.enabled). Start the game normally through Steam."
