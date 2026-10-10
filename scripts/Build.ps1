[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BepInExPath, [string]$CompilerPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$bepinex = [IO.Path]::GetFullPath($BepInExPath)
$interop = Join-Path $bepinex 'BepInEx\interop'
if (-not (Test-Path -LiteralPath (Join-Path $interop 'Assembly-CSharp.dll'))) {
    throw 'Local game interop is missing. Launch your own game once with BepInEx installed first.'
}
$work = Join-Path $script:PackageRoot '.local-only\build'
New-Item -ItemType Directory -Path $work -Force | Out-Null
if (-not $CompilerPath) {
    $compilerRoot = Join-Path $work 'roslyn'
    if (-not (Test-Path -LiteralPath (Join-Path $compilerRoot 'tasks\net472\csc.exe'))) {
        $archive = Join-Path $work 'roslyn.zip'
        $dependency = [pscustomobject]@{
            version='4.8.0'
            url='https://api.nuget.org/v3-flatcontainer/microsoft.net.compilers.toolset/4.8.0/microsoft.net.compilers.toolset.4.8.0.nupkg'
            sha256='37333f4f1e2ce55e621355d6da651dc23d4cb5f94a8f76b9478816e87f110ad9'
        }
        Get-VerifiedArchive 'roslyn' $dependency $archive ''
        Expand-Archive -LiteralPath $archive -DestinationPath $compilerRoot
    }
    $CompilerPath = Join-Path $compilerRoot 'tasks\net472\csc.exe'
}
$output = Join-Path $work 'QuickLanguage.dll'
$arguments = New-Object 'System.Collections.Generic.List[string]'
foreach ($option in @('/nologo', '/target:library', '/langversion:latest', '/nostdlib+', '/unsafe+', '/optimize+', ('/out:"' + $output + '"'))) { $arguments.Add($option) }
$assemblyNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($directory in @((Join-Path $bepinex 'dotnet'), (Join-Path $bepinex 'BepInEx\core'), $interop)) {
    foreach ($dll in Get-ChildItem -LiteralPath $directory -Filter '*.dll' | Sort-Object Name) {
        if ($dll.Name -in @('coreclr.dll','clrjit.dll','mscordaccore.dll','mscordbi.dll','Microsoft.DiaSymReader.Native.amd64.dll')) { continue }
        try { $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($dll.FullName).Name }
        catch { continue }
        if (-not $assemblyNames.Add($assemblyName)) { continue }
        $arguments.Add('/reference:"' + $dll.FullName + '"')
    }
}
$arguments.Add('"' + (Join-Path $script:PackageRoot 'src\QuickLanguage.cs') + '"')
$responseFile = Join-Path $work 'build.rsp'
[IO.File]::WriteAllLines($responseFile, $arguments, (New-Object Text.UTF8Encoding($false)))
& $CompilerPath ('@' + $responseFile)
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
Write-Host "Built: $output"
Write-Host 'The installed plugin and dist/QuickLanguage.dll have NOT been replaced.'
