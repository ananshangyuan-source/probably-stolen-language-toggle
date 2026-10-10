[CmdletBinding()]
param([string]$GamePath, [string]$DependencyCache, [switch]$NoPrompt, [switch]$AllowUntestedBuild)
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
Assert-NoReparsePoint $script:PackageRoot
if (Test-Path -LiteralPath $script:ManifestPath) {
    $existing = Read-Installation
    Assert-OwnedLoaders $existing
    foreach ($record in $existing.addedFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $existing.gameRoot $record.name))) { throw 'Installation is incomplete. Run Uninstall.cmd before reinstalling.' }
    }
    Write-Host 'Already installed. Use Enable.cmd or Uninstall.cmd from this folder.'
    exit 0
}
$gameRoot = Get-GameRoot $GamePath -NoPrompt:$NoPrompt
Assert-Game $gameRoot
Assert-GameStopped $gameRoot
foreach ($name in $script:LoaderNames) {
    if (Test-Path -LiteralPath (Join-Path $gameRoot $name)) { throw "Existing loader detected ($name). This installer will not overwrite another MOD. Uninstall it first." }
}
$appManifest = Join-Path (Split-Path (Split-Path $gameRoot -Parent) -Parent) 'appmanifest_4349200.acf'
$build = 'unknown'
if (Test-Path -LiteralPath $appManifest) {
    $match = [regex]::Match([IO.File]::ReadAllText($appManifest), '"buildid"\s*"([^"]+)"')
    if ($match.Success) { $build = $match.Groups[1].Value }
}
if ($build -ne '25382790' -and -not $AllowUntestedBuild) {
    if ($NoPrompt) { throw "Untested game build: $build. See docs/INSTALL.md before using -AllowUntestedBuild." }
    Write-Warning "This MOD was tested on Demo build 25382790. Detected: $build."
    if ((Read-Host 'Try this untested build? Type YES to continue') -cne 'YES') { throw 'Installation cancelled.' }
}
$dependencies = Get-Content -LiteralPath (Join-Path $script:PackageRoot 'dependencies.json') -Raw | ConvertFrom-Json
$plugin = Join-Path $script:PackageRoot 'dist\QuickLanguage.dll'
if ((Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash -ne $dependencies.plugin.sha256) { throw 'The packaged plugin does not match dependencies.json.' }
$runtime = Join-Path $script:PackageRoot '.runtime'
if (Test-Path -LiteralPath $runtime) { throw 'A runtime folder already exists without a valid installation record. Move it aside before retrying.' }
$stage = Join-Path $script:PackageRoot ('.runtime-stage-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$stage = Assert-ChildPath $script:PackageRoot $stage
$originalHashes = Get-OriginalHashes $gameRoot
$createdLoaders = New-Object 'System.Collections.Generic.List[string]'
$runtimeMoved = $false
$committed = $false
$oldUvCache = $env:UV_CACHE_DIR
$oldUvPythonDownloads = $env:UV_PYTHON_DOWNLOADS
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$installTempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$installTemp = Join-Path $installTempParent ('psq-install-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$installTemp = Assert-ChildPath $installTempParent $installTemp
try {
    Assert-NoReparsePoint $installTempParent
    New-Item -ItemType Directory -Path $stage,(Join-Path $stage 'downloads'),$installTemp | Out-Null
    $env:UV_CACHE_DIR = Join-Path $installTemp 'uv-cache'
    $env:UV_PYTHON_DOWNLOADS = 'never'
    $env:TEMP = $installTemp
    $env:TMP = $env:TEMP
    foreach ($name in @('bepinex', 'python', 'uv')) {
        $archiveName = if ($name -eq 'python') { 'python.tar.gz' } else { $name + '.zip' }
        $archive = Join-Path $stage ('downloads\' + $archiveName)
        Get-VerifiedArchive $name $dependencies.$name $archive $DependencyCache
        if ($name -eq 'python') {
            $tar = Join-Path $env:WINDIR 'System32\tar.exe'
            if (-not (Test-Path -LiteralPath $tar)) { throw 'Windows built-in tar.exe is required (Windows 10 1803 or newer).' }
            & $tar -xzf $archive -C $stage
            if ($LASTEXITCODE -ne 0) { throw 'Python runtime extraction failed.' }
        } else { Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $stage $name) }
    }
    $python = Join-Path $stage 'python\python.exe'
    $uv = @(Get-ChildItem -LiteralPath (Join-Path $stage 'uv') -Filter uv.exe -Recurse)[0].FullName
    Write-Host 'Installing the localization reader in this folder only...'
    Copy-Item -LiteralPath (Join-Path $script:PackageRoot 'build-requirements.txt') -Destination (Join-Path $stage 'build-requirements.txt')
    Push-Location -LiteralPath $stage
    try {
        & $uv --no-config pip install --python $python --target (Join-Path $stage 'pydeps') --build-constraint 'build-requirements.txt' --index-url 'https://pypi.org/simple' -r (Join-Path $script:PackageRoot 'requirements.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Localization reader installation failed. Check your connection to PyPI.' }
    } finally { Pop-Location }
    $pluginDirectory = Join-Path $stage 'bepinex\BepInEx\plugins'
    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    Write-Host 'Reading English/Chinese tables from YOUR installed game...'
    & $python (Join-Path $script:PackageRoot 'src\extract_languages.py') --game $gameRoot --output (Join-Path $pluginDirectory 'language-pairs.json') --pydeps (Join-Path $stage 'pydeps')
    if ($LASTEXITCODE -ne 0) { throw 'Localization extraction failed. No loader was installed.' }
    Copy-Item -LiteralPath $plugin -Destination (Join-Path $pluginDirectory 'QuickLanguage.dll')
    foreach ($name in @('downloads', 'uv', 'uv-cache', 'temp')) { Remove-OwnedDirectory (Join-Path $stage $name) }
    Move-Item -LiteralPath $stage -Destination $runtime
    $runtimeMoved = $true
    $bepinex = Join-Path $runtime 'bepinex'
    $config = [IO.File]::ReadAllText((Join-Path $bepinex 'doorstop_config.ini'))
    $settings = @{
        target_assembly = Join-Path $bepinex 'BepInEx\core\BepInEx.Unity.IL2CPP.dll'
        coreclr_path = Join-Path $bepinex 'dotnet\coreclr.dll'
        corlib_dir = Join-Path $bepinex 'dotnet'
        enabled = 'true'
    }
    foreach ($key in $settings.Keys) {
        if (-not [regex]::IsMatch($config, "(?m)^\s*$key\s*=.*$")) { throw "Unexpected Doorstop configuration: $key missing." }
        $value = $settings[$key]
        $config = [regex]::Replace($config, "(?m)^\s*$key\s*=.*$", [System.Text.RegularExpressions.MatchEvaluator]{ param($match) "$key = $value" })
    }
    [IO.File]::WriteAllText((Join-Path $bepinex 'doorstop_config.ini'), $config, (New-Object Text.UTF8Encoding($false)))
    Assert-GameStopped $gameRoot
    Assert-OriginalHashes $gameRoot $originalHashes
    # CreateNew refuses races with another installer; never overwrite existing files.
    foreach ($name in $script:LoaderNames) {
        $destination = Join-Path $gameRoot $name
        $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $createdLoaders.Add($destination)
        try {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $bepinex $name))
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
    $records = @($script:LoaderNames | ForEach-Object { @{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $gameRoot $_) -Algorithm SHA256).Hash} })
    Write-Installation @{
        owner='probably-stolen-language-toggle'; version=$dependencies.plugin.version
        packageRoot=$script:PackageRoot; runtimeRoot=$runtime; gameRoot=$gameRoot
        gameBuild=$build; addedFiles=$records; originalHashes=$originalHashes; enabled=$true
    }
    $committed = $true
    Write-Host 'Installed! Start the game normally through Steam, wait about 5 seconds, then press Q.' -ForegroundColor Green
    Write-Host 'Keep this extracted folder here. Use Uninstall.cmd before moving/deleting it.'
} catch {
    if (-not $committed) {
        foreach ($path in $createdLoaders) {
            $resolved = Assert-ChildPath $gameRoot $path
            Assert-NoReparsePoint $resolved
            if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Force }
        }
        if ($runtimeMoved) { Remove-OwnedDirectory $runtime }
    }
    throw
} finally {
    $env:UV_CACHE_DIR = $oldUvCache
    $env:UV_PYTHON_DOWNLOADS = $oldUvPythonDownloads
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    if (Test-Path -LiteralPath $stage) { Remove-OwnedDirectory $stage }
    if (Test-Path -LiteralPath $installTemp) { Remove-OwnedDirectory $installTemp $installTempParent }
}
