[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
$manifest = Read-Installation
Assert-GameStopped $manifest.gameRoot
Assert-OwnedLoaders $manifest
# Check everything before removing any file. Missing owned files are harmless.
Assert-NoReparsePoint $manifest.runtimeRoot
if (Test-Path -LiteralPath $manifest.runtimeRoot) {
    $longRuntime = if ($manifest.runtimeRoot.StartsWith('\\')) { '\\?\UNC\' + $manifest.runtimeRoot.Substring(2) } else { '\\?\' + $manifest.runtimeRoot }
    Assert-DirectoryTreeWithoutLinks $longRuntime
}
foreach ($record in $manifest.addedFiles) {
    $path = Assert-ChildPath $manifest.gameRoot (Join-Path $manifest.gameRoot $record.name)
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
Remove-OwnedDirectory $manifest.runtimeRoot
Remove-Item -LiteralPath $script:ManifestPath -Force
Write-Host 'Uninstalled. Owned loaders, runtime, generated tables and caches were removed.' -ForegroundColor Green
Write-Host 'Original game files and saves were not deleted. You may now delete this extracted folder.'
