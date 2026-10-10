Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[AppContext]::SetSwitch('Switch.System.IO.UseLegacyPathHandling', $false)
[AppContext]::SetSwitch('Switch.System.IO.BlockLongPaths', $false)
$script:PackageRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$script:ManifestPath = Join-Path $script:PackageRoot '.installation.json'
$script:LoaderNames = @('winhttp.dll', 'doorstop_config.ini', '.doorstop_version')

function Assert-ChildPath([string]$Parent, [string]$Path) {
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    $pathFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $pathFull.StartsWith($parentFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected folder: $pathFull"
    }
    return $pathFull
}

function Assert-NoReparsePoint([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Symbolic links/junctions are not supported: $cursor"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Remove-OwnedDirectory([string]$Path, [string]$Parent = $script:PackageRoot) {
    $resolved = Assert-ChildPath $Parent $Path
    Assert-NoReparsePoint $resolved
    if (Test-Path -LiteralPath $resolved) {
        $longPath = if ($resolved.StartsWith('\\')) { '\\?\UNC\' + $resolved.Substring(2) } else { '\\?\' + $resolved }
        Assert-DirectoryTreeWithoutLinks $longPath
        [IO.Directory]::Delete($longPath, $true)
    }
}

function Assert-DirectoryTreeWithoutLinks([string]$Path) {
    foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($Path)) {
        $attributes = [IO.File]::GetAttributes($entry)
        if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Preserving directory containing a symbolic link: $entry" }
        if ($attributes -band [IO.FileAttributes]::Directory) { Assert-DirectoryTreeWithoutLinks $entry }
    }
}

function Get-GameRoot([string]$GamePath, [switch]$NoPrompt) {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($GamePath) { $candidates.Add($GamePath) }
    else {
        $steamRoots = New-Object 'System.Collections.Generic.List[string]'
        foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
            $value = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($null -ne $value) {
                foreach ($property in @('SteamPath', 'InstallPath')) {
                    if ($value.PSObject.Properties.Name -contains $property) { $steamRoots.Add([string]$value.$property) }
                }
            }
        }
        if (${env:ProgramFiles(x86)}) { $steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }
        foreach ($steam in @($steamRoots | Select-Object -Unique)) {
            $libraries = New-Object 'System.Collections.Generic.List[string]'
            $libraries.Add($steam)
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s*"([^"]+)"')) {
                    $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
                }
            }
            foreach ($library in $libraries) {
                $appManifest = Join-Path $library 'steamapps\appmanifest_4349200.acf'
                if (Test-Path -LiteralPath $appManifest) {
                    $match = [regex]::Match([IO.File]::ReadAllText($appManifest), '"installdir"\s*"([^"]+)"')
                    if ($match.Success) { $candidates.Add((Join-Path $library ('steamapps\common\' + $match.Groups[1].Value))) }
                }
                $candidates.Add((Join-Path $library 'steamapps\common\Probably Stolen Demo'))
            }
        }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'Probably Stolen.exe')) { return [IO.Path]::GetFullPath($candidate).TrimEnd('\') }
    }
    if ($GamePath -or $NoPrompt) { throw 'Probably Stolen Demo was not found. Pass -GamePath with its installation folder.' }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the Probably Stolen Demo folder containing Probably Stolen.exe'
    try {
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Installation cancelled.' }
        return Get-GameRoot $dialog.SelectedPath -NoPrompt
    } finally { $dialog.Dispose() }
}

function Assert-Game([string]$GameRoot) {
    Assert-NoReparsePoint $GameRoot
    foreach ($name in @('Probably Stolen.exe', 'GameAssembly.dll', 'UnityPlayer.dll', 'Probably Stolen_Data\il2cpp_data\Metadata\global-metadata.dat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $GameRoot $name) -PathType Leaf)) { throw "Unsupported game layout: $name is missing." }
    }
}

function Assert-GameStopped([string]$GameRoot) {
    $expected = Join-Path $GameRoot 'Probably Stolen.exe'
    foreach ($process in @(Get-Process -Name 'Probably Stolen' -ErrorAction SilentlyContinue)) {
        try { $executable = $process.Path } catch { $executable = $null }
        # A hidden process path is treated as in use rather than guessed.
        if (-not $executable -or $executable -eq $expected) {
            throw 'Save and close Probably Stolen before installing, disabling, or uninstalling.'
        }
    }
}

function Get-OriginalHashes([string]$GameRoot) {
    $hashes = @{}
    foreach ($name in @('Probably Stolen.exe', 'GameAssembly.dll', 'UnityPlayer.dll', 'Probably Stolen_Data\il2cpp_data\Metadata\global-metadata.dat')) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $GameRoot $name) -Algorithm SHA256).Hash
    }
    return $hashes
}

function Assert-OriginalHashes([string]$GameRoot, $Expected) {
    foreach ($name in $Expected.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $GameRoot $name) -Algorithm SHA256).Hash -ne $Expected[$name]) { throw "An original game file changed: $name" }
    }
}

function Read-Installation {
    if (-not (Test-Path -LiteralPath $script:ManifestPath)) { throw 'No installation record found in this extracted folder.' }
    $manifest = [IO.File]::ReadAllText($script:ManifestPath) | ConvertFrom-Json
    if ($manifest.owner -ne 'probably-stolen-language-toggle' -or $manifest.packageRoot -ne $script:PackageRoot) {
        throw 'Installation ownership/path does not match. Keep the extracted folder in its original location.'
    }
    $expectedRuntime = Join-Path $script:PackageRoot '.runtime'
    if ($manifest.runtimeRoot -ne $expectedRuntime) { throw 'Unexpected runtime path in installation record.' }
    if (@($manifest.addedFiles).Count -ne 3 -or @($manifest.addedFiles.name | Select-Object -Unique).Count -ne 3) {
        throw 'Installation record must contain exactly three owned loader files.'
    }
    foreach ($record in $manifest.addedFiles) {
        if ($script:LoaderNames -notcontains $record.name -or $record.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid owned loader record.' }
    }
    Assert-NoReparsePoint $script:PackageRoot
    Assert-NoReparsePoint $manifest.gameRoot
    return $manifest
}

function Assert-OwnedLoaders($Manifest) {
    foreach ($record in $Manifest.addedFiles) {
        if ($script:LoaderNames -notcontains $record.name) { throw 'Unexpected loader file in installation record.' }
        $path = Join-Path $Manifest.gameRoot $record.name
        Assert-NoReparsePoint $path
        if (Test-Path -LiteralPath $path) {
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record.sha256) {
                throw "A loader has been changed by another installation; preserving it: $path"
            }
        }
    }
}

function Write-Installation($Manifest) {
    $temporary = $script:ManifestPath + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $script:ManifestPath -Force
}

function Get-VerifiedArchive([string]$Name, $Dependency, [string]$Destination, [string]$DependencyCache) {
    $archiveName = if ($Dependency.PSObject.Properties.Name -contains 'archiveName') { $Dependency.archiveName } else { $Name + '.zip' }
    $cached = if ($DependencyCache) { Join-Path $DependencyCache $archiveName } else { $null }
    if ($cached -and (Test-Path -LiteralPath $cached)) {
        Copy-Item -LiteralPath $cached -Destination $Destination
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $downloaded = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "Downloading $Name $($Dependency.version) (attempt $attempt/3)..."
                Invoke-WebRequest -Uri $Dependency.url -OutFile $Destination -UseBasicParsing -TimeoutSec 300
                $downloaded = $true
                break
            } catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 2 }
        }
        if (-not $downloaded) { throw "Download failed: $Name" }
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Dependency.sha256) {
        throw "SHA256 verification failed for $Name. No game files have been installed."
    }
}
