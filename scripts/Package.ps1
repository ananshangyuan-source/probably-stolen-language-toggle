[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
& (Join-Path $PSScriptRoot 'Verify-Package.ps1')
$dependency = Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json
$release = Join-Path $root '.local-only\releases'
New-Item -ItemType Directory -Path $release -Force | Out-Null
$name = 'ProbablyStolen-LanguageToggle-v' + $dependency.plugin.version + '-Windows-x64'
$stageParent = Join-Path $release ('.stage-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageParent $name
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    foreach ($file in @('Install.cmd','Uninstall.cmd','Enable.cmd','Disable.cmd','README.md','LICENSE','CHANGELOG.md','THIRD_PARTY_NOTICES.md','dependencies.json','requirements.txt','build-requirements.txt')) {
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
    }
    foreach ($directory in @('scripts','src','dist','docs')) {
        Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $stage -Recurse
    }
    $zip = Join-Path $release ($name + '.zip')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $release 'SHA256SUMS.txt'), ($sha + '  ' + [IO.Path]::GetFileName($zip) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Host "Release ZIP: $zip"
    Write-Host "SHA256: $sha"
} finally {
    $fullStage = [IO.Path]::GetFullPath($stageParent)
    if (-not $fullStage.StartsWith($release.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected staging path.' }
    if (Test-Path -LiteralPath $fullStage) { Remove-Item -LiteralPath $fullStage -Recurse -Force }
}
