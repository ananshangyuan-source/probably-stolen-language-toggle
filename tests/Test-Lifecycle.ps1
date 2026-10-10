# Run only against a disposable fixture. Never touches a real Steam game.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $repo ('.local-only\tests-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testRoot ('package ' + [char]0x4E2D + [char]0x6587)
$game = Join-Path $testRoot 'game'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts'),$game,(Join-Path $fixture '.runtime') -Force | Out-Null
Copy-Item -Path (Join-Path $repo 'scripts\*.ps1') -Destination (Join-Path $fixture 'scripts')

function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Fixture([string]$Script, [string[]]$Arguments = @(), [switch]$ExpectFailure) {
    $oldErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture ('scripts\' + $Script)) @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldErrorAction }
    if ($ExpectFailure) { Assert ($code -ne 0) "$Script should have rejected the unsafe fixture." }
    else { Assert ($code -eq 0) "$Script failed: $output" }
}

try {
    $names = @('winhttp.dll','doorstop_config.ini','.doorstop_version')
    [IO.File]::WriteAllText((Join-Path $game 'Probably Stolen.exe'), 'original-fixture-game')
    $originalHash = (Get-FileHash -LiteralPath (Join-Path $game 'Probably Stolen.exe')).Hash
    foreach ($name in $names) { [IO.File]::WriteAllText((Join-Path $game $name), 'fixture-loader-' + $name) }
    [IO.File]::WriteAllText((Join-Path $game 'doorstop_config.ini'), "[General]`nenabled = true`ntarget_assembly = fixture`n")
    [IO.File]::WriteAllText((Join-Path $fixture '.runtime\local-data.txt'), 'locally-generated')
    $manifest = @{
        owner='probably-stolen-language-toggle'; version='1.0.3'; packageRoot=$fixture
        runtimeRoot=(Join-Path $fixture '.runtime'); gameRoot=$game; gameBuild='fixture'; enabled=$true
        addedFiles=@($names | ForEach-Object { @{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $game $_)).Hash} })
    }
    $manifestPath = Join-Path $fixture '.installation.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Invoke-Fixture 'Set-Enabled.ps1' @('-Enabled','false')
    Assert (([IO.File]::ReadAllText((Join-Path $game 'doorstop_config.ini'))) -match 'enabled = false') 'Disable did not change loader state.'
    Invoke-Fixture 'Set-Enabled.ps1' @('-Enabled','true')
    Assert (([IO.File]::ReadAllText((Join-Path $game 'doorstop_config.ini'))) -match 'enabled = true') 'Enable did not change loader state.'
    # Changed loader must abort the whole uninstall before any other removal.
    [IO.File]::AppendAllText((Join-Path $game 'winhttp.dll'), 'changed-by-another-mod')
    Invoke-Fixture 'Uninstall.ps1' -ExpectFailure
    Assert (Test-Path -LiteralPath (Join-Path $game 'doorstop_config.ini')) 'Conflict deleted another owned file.'
    Assert (Test-Path -LiteralPath (Join-Path $fixture '.runtime')) 'Conflict removed the runtime.'
    [IO.File]::WriteAllText((Join-Path $game 'winhttp.dll'), 'fixture-loader-winhttp.dll')
    # Re-read manifest, since enable/disable changed its config checksum.
    $savedManifest = [IO.File]::ReadAllText($manifestPath)
    $malformed = $savedManifest | ConvertFrom-Json
    $malformed.runtimeRoot = $testRoot
    $malformed | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Invoke-Fixture 'Uninstall.ps1' -ExpectFailure
    Assert (Test-Path -LiteralPath (Join-Path $game 'Probably Stolen.exe')) 'Invalid runtime path escaped ownership checks.'
    [IO.File]::WriteAllText($manifestPath, $savedManifest)
    Invoke-Fixture 'Uninstall.ps1'
    foreach ($name in $names) { Assert (-not (Test-Path -LiteralPath (Join-Path $game $name))) "Loader remains: $name" }
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture '.runtime'))) 'Runtime remains after uninstall.'
    Assert (-not (Test-Path -LiteralPath $manifestPath)) 'Installation record remains after uninstall.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'Probably Stolen.exe')).Hash -eq $originalHash) 'Original fixture game was changed.'
    Write-Host 'Lifecycle passed: disable, enable, changed-loader preservation, path boundary, uninstall, original file unchanged.'
} finally {
    $absolute = [IO.Path]::GetFullPath($testRoot)
    $parent = [IO.Path]::GetFullPath((Join-Path $repo '.local-only')).TrimEnd('\')
    if (-not $absolute.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test cleanup path.' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
