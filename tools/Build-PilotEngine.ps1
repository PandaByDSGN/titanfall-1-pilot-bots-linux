# Build-only recipe for the matching R1Delta v3.0.4 pilot-bot engine.
# Adapted from the successful clean Windows build; this public-input entry
# point has not yet been run on Windows. No game launch/installation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EngineSource,
    [Parameter(Mandatory=$true)][string]$EosSource,
    [Parameter(Mandatory=$true)][string]$BuildRoot,
    [Parameter(Mandatory=$true)][string]$VisualStudioRoot,
    [Parameter(Mandatory=$true)][string]$VcpkgRoot,
    [ValidateRange(1,8)][int]$Jobs=2
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$Prepared=(Resolve-Path -LiteralPath $EngineSource).Path.TrimEnd('\')
$EosSource=(Resolve-Path -LiteralPath $EosSource).Path.TrimEnd('\')
$BuildRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildRoot).TrimEnd('\')
if ($BuildRoot -match '[\s";$\r\n]' -or $BuildRoot -notmatch '^[A-Za-z]:\\.+') { throw 'Use a new absolute build root without spaces or shell metacharacters.' }
if (Test-Path -LiteralPath $BuildRoot) { throw 'Build root must not exist.' }
$VisualStudioRoot=(Resolve-Path -LiteralPath $VisualStudioRoot).Path.TrimEnd('\')
$VcpkgRoot=(Resolve-Path -LiteralPath $VcpkgRoot).Path.TrimEnd('\')
$Toolset='14.50.35717'
$Sdk='10.0.26100.0'
$Triplet='x64-windows-fix-cmake'
$IndexPath=Join-Path $PSScriptRoot '..\install-manifest.json'
$IndexHash=(Get-FileHash -LiteralPath $IndexPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Index=Get-Content -Raw -LiteralPath $IndexPath | ConvertFrom-Json
foreach ($row in $Index.engine) {
    $p=Join-Path $Prepared ([string]$row.path)
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.prepared_sha256) { throw "Unexpected engine file: $($row.path)" }
}
foreach ($row in $Index.eos) {
    $p=Join-Path $EosSource ([string]$row.path)
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.sha256) { throw "Unexpected EOS SDK file: $($row.path)" }
}
if (Test-Path -LiteralPath (Join-Path $Prepared 'thirdparty/eos/SDK')) { throw 'Use the pinned release archive and pass the EOS SDK separately.' }
$MSBuild=Join-Path $VisualStudioRoot 'MSBuild/Current/Bin/amd64/MSBuild.exe'
$VsDevCmd=Join-Path $VisualStudioRoot 'Common7/Tools/VsDevCmd.bat'
$MsvcBin=Join-Path $VisualStudioRoot "VC/Tools/MSVC/$Toolset/bin/Hostx64/x64"
foreach ($path in @($MSBuild,$VsDevCmd,(Join-Path $MsvcBin 'cl.exe'),(Join-Path $MsvcBin 'ml64.exe'),(Join-Path $MsvcBin 'link.exe'),(Join-Path $MsvcBin 'lib.exe'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing installed Microsoft tool: $path" }
}
foreach ($relative in @('vcpkg.exe','scripts/buildsystems/msbuild/vcpkg.props','scripts/buildsystems/msbuild/vcpkg.targets','scripts/toolchains/windows.cmake')) {
    if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot $relative) -PathType Leaf)) { throw "Missing installed vcpkg input: $relative" }
}
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
$BuildSource=Join-Path $BuildRoot 'source'
$Bin=Join-Path $BuildRoot 'bin'
$Obj=Join-Path $BuildRoot 'obj'
$Tools=Join-Path $BuildRoot 'tools'
$Cache=Join-Path $BuildRoot 'cache'
$BuildTrees=Join-Path $BuildRoot 'dependency-buildtrees'
$Packages=Join-Path $BuildRoot 'dependency-packages'
$EmptyUserProps=Join-Path $BuildRoot 'empty-user-props'
foreach ($dir in @($Bin,$Obj,$Tools,$Cache,$BuildTrees,$Packages,$EmptyUserProps,(Join-Path $Cache 'downloads'),(Join-Path $Cache 'binary'),(Join-Path $Cache 'registries'),(Join-Path $Cache 'nuget-http'),(Join-Path $Cache 'nuget-packages'),(Join-Path $Cache 'nuget-plugins'),(Join-Path $BuildRoot 'temp'))) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$Log=Join-Path $BuildRoot 'build-transcript.log'
function Set-Stage([string]$Stage) {
    $message=[DateTime]::UtcNow.ToString('o')+' '+$Stage
    Set-Content -LiteralPath (Join-Path $BuildRoot 'build-status.txt') -Value $message -Encoding UTF8
    Add-Content -LiteralPath $Log -Value $message -Encoding UTF8
    Write-Host $message
}
function Invoke-LoggedNative([string]$Executable,[string[]]$Arguments) {
    $ErrorActionPreference='Continue'
    & $Executable @Arguments 2>&1 | ForEach-Object { $line=$_.ToString(); Write-Host $line; Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 }
    $nativeCode=$LASTEXITCODE
    if ($nativeCode -ne 0) { throw "Native command failed ($nativeCode): $Executable; see $Log" }
}
function Read-NativeText([string]$Executable,[string[]]$Arguments) {
    $ErrorActionPreference='Continue'
    $result=(& $Executable @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Version/preflight command failed: $Executable" }
    return $result
}
function CmakePath([string]$Value) { return $Value.Replace('\','/').Replace('"','\"') }
Set-Stage 'INPUTS VERIFIED; staging isolated source copy'
Copy-Item -LiteralPath $Prepared -Destination $BuildSource -Recurse
$EosDestination=Join-Path $BuildSource 'thirdparty/eos'
foreach ($folder in @('SDK/Include','SDK/Lib','SDK/Bin')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $EosDestination $folder) | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $EosSource 'SDK/Include') -Force | Copy-Item -Destination (Join-Path $EosDestination 'SDK/Include') -Recurse
foreach ($row in $Index.eos) {
    Copy-Item -LiteralPath (Join-Path $EosSource $row.path) -Destination (Join-Path $EosDestination $row.path)
}
# Import only normal compiler/SDK variables from Microsoft's approved helper.
# No execution-policy command, global environment setting, or wrapper copying.
$ToolEnvNames=@('PATH','INCLUDE','LIB','LIBPATH','VCToolsInstallDir','VCToolsRedistDir','VCToolsVersion','WindowsSdkDir','WindowsSDKVersion','WindowsSdkBinPath','WindowsSdkVerBinPath','WindowsLibPath','UniversalCRTSdkDir','UCRTVersion','VSINSTALLDIR','VCINSTALLDIR','VisualStudioVersion','VSCMD_ARG_TGT_ARCH','VSCMD_ARG_HOST_ARCH','VSCMD_ARG_APP_PLAT','VSCMD_VER','FrameworkDir','FrameworkVersion','FrameworkDir64','FrameworkVersion64','DevEnvDir','NETFXSDKDir','ExtensionSdkDir','CommandPromptType','Platform')
$ChangedEnv=@($ToolEnvNames)+@('CI','VCPKG_ROOT','VCPKG_DOWNLOADS','VCPKG_DEFAULT_BINARY_CACHE','X_VCPKG_REGISTRIES_CACHE','VCPKG_MAX_CONCURRENCY','NUGET_HTTP_CACHE_PATH','NUGET_PACKAGES','NUGET_PLUGINS_CACHE_PATH','NUGET_PLUGIN_PATHS','TEMP','TMP','_CL_')
$PreviousEnv=@{}
foreach ($name in $ChangedEnv) { $PreviousEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
    Set-Stage 'INITIALIZING Microsoft MSVC 14.50 environment'
    $Cmd=Join-Path $env:SystemRoot 'System32/cmd.exe'
    $SetupCommand='call "'+$VsDevCmd+'" -no_logo -arch=x64 -host_arch=x64 -vcvars_ver=14.50 >nul && set'
    $EnvironmentLines=& $Cmd /d /s /c $SetupCommand
    if ($LASTEXITCODE -ne 0) { throw 'Microsoft developer environment setup failed.' }
    foreach ($line in $EnvironmentLines) {
        if ($line -match '^([^=]+)=(.*)$' -and $ToolEnvNames -contains $Matches[1]) { [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process') }
    }
    if ($env:VCToolsVersion.TrimEnd('\') -ne $Toolset -or $env:WindowsSDKVersion.TrimEnd('\') -ne $Sdk) { throw 'The developer environment did not select the reviewed compiler and SDK.' }
    if ((Get-Command cl.exe -ErrorAction Stop).Source -ne (Join-Path $MsvcBin 'cl.exe')) { throw 'Unexpected compiler on PATH.' }
    $SdkBin=Join-Path $env:WindowsSdkDir "bin/$Sdk/x64"
    foreach ($tool in @('rc.exe','mt.exe')) { if (-not (Test-Path -LiteralPath (Join-Path $SdkBin $tool) -PathType Leaf)) { throw "Missing SDK tool: $tool" } }
    $env:CI='1'
    $env:VCPKG_ROOT=$VcpkgRoot
    $env:VCPKG_DOWNLOADS=Join-Path $Cache 'downloads'
    $env:VCPKG_DEFAULT_BINARY_CACHE=Join-Path $Cache 'binary'
    $env:X_VCPKG_REGISTRIES_CACHE=Join-Path $Cache 'registries'
    $env:VCPKG_MAX_CONCURRENCY=[string]$Jobs
    $env:NUGET_HTTP_CACHE_PATH=Join-Path $Cache 'nuget-http'
    $env:NUGET_PACKAGES=Join-Path $Cache 'nuget-packages'
    $env:NUGET_PLUGINS_CACHE_PATH=Join-Path $Cache 'nuget-plugins'
    $env:NUGET_PLUGIN_PATHS=''
    $env:TEMP=Join-Path $BuildRoot 'temp'
    $env:TMP=$env:TEMP
    $env:_CL_='/MP'+$Jobs
    $Chainload=Join-Path $BuildSource 'custom-triplets/pilot-msvc.cmake'
    $ChainLines=@('# Isolated pinned tools. Include official Windows toolchain for CRT/linkage defaults.')
    foreach ($pair in @(@('CMAKE_C_COMPILER','cl.exe'),@('CMAKE_CXX_COMPILER','cl.exe'),@('CMAKE_ASM_MASM_COMPILER','ml64.exe'),@('CMAKE_LINKER','link.exe'),@('CMAKE_AR','lib.exe'))) {
        $ChainLines+='set('+$pair[0]+' "'+(CmakePath (Join-Path $MsvcBin $pair[1]))+'" CACHE FILEPATH "" FORCE)'
    }
    $ChainLines+='set(CMAKE_RC_COMPILER "'+(CmakePath (Join-Path $SdkBin 'rc.exe'))+'" CACHE FILEPATH "" FORCE)'
    $ChainLines+='set(CMAKE_MT "'+(CmakePath (Join-Path $SdkBin 'mt.exe'))+'" CACHE FILEPATH "" FORCE)'
    $ChainLines+='include("'+(CmakePath (Join-Path $VcpkgRoot 'scripts/toolchains/windows.cmake'))+'")'
    Set-Content -LiteralPath $Chainload -Value $ChainLines -Encoding ASCII
    $TripletPath=Join-Path $BuildSource 'custom-triplets/x64-windows-fix-cmake.cmake'
    @'
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_PLATFORM_TOOLSET v145)
set(VCPKG_PLATFORM_TOOLSET_VERSION 14.50.35717)
set(VCPKG_BUILD_TYPE release)
set(VCPKG_CMAKE_SYSTEM_VERSION 10.0.26100.0)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/pilot-msvc.cmake")
set(VCPKG_LOAD_VCVARS_ENV OFF)
set(VCPKG_ENV_PASSTHROUGH PATH INCLUDE LIB LIBPATH VCToolsInstallDir VCToolsVersion WindowsSdkDir WindowsSDKVersion UniversalCRTSdkDir UCRTVersion VSINSTALLDIR VCINSTALLDIR VisualStudioVersion VSCMD_ARG_TGT_ARCH VSCMD_ARG_HOST_ARCH)
'@ | Set-Content -LiteralPath $TripletPath -Encoding ASCII
    $RootForXml=[Security.SecurityElement]::Escape((CmakePath $VcpkgRoot)+'/')
    $Props=@'
<Project>
  <PropertyGroup>
    <VcpkgRoot>__ROOT__</VcpkgRoot>
    <VcpkgEnabled>true</VcpkgEnabled>
    <VcpkgEnableManifest>true</VcpkgEnableManifest>
    <VcpkgManifestRoot>$(MSBuildThisFileDirectory)</VcpkgManifestRoot>
    <VcpkgManifestInstalledBaseDir>$(MSBuildThisFileDirectory)vcpkg_installed/</VcpkgManifestInstalledBaseDir>
    <VcpkgInstalledDir>$(MSBuildThisFileDirectory)vcpkg_installed/</VcpkgInstalledDir>
    <VcpkgTriplet>x64-windows-fix-cmake</VcpkgTriplet>
    <VcpkgHostTriplet>x64-windows-fix-cmake</VcpkgHostTriplet>
    <VcpkgApplocalDeps>false</VcpkgApplocalDeps>
    <VCToolsVersion>14.50.35717</VCToolsVersion>
  </PropertyGroup>
  <Import Project="$(VcpkgRoot)scripts/buildsystems/msbuild/vcpkg.props" />
</Project>
'@
    $PropsPath=Join-Path $BuildSource 'Directory.Build.props'
    $TargetsPath=Join-Path $BuildSource 'Directory.Build.targets'
    Set-Content -LiteralPath $PropsPath -Value $Props.Replace('__ROOT__',$RootForXml) -Encoding ASCII
    $NuGet=Join-Path $Tools 'nuget-7.9.0.exe'
    Set-Stage 'ACQUIRING official NuGet 7.9; checking Microsoft signature before execution'
    if (-not (Test-Path -LiteralPath $NuGet)) { Invoke-WebRequest -UseBasicParsing -Uri 'https://dist.nuget.org/win-x86-commandline/v7.9.0/nuget.exe' -OutFile $NuGet }
    $Signature=Get-AuthenticodeSignature -LiteralPath $NuGet
    if ($Signature.Status -ne 'Valid' -or $Signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'NuGet is not validly signed by Microsoft; it will not be executed.' }
    if ((Get-Item -LiteralPath $NuGet).VersionInfo.FileVersion -notlike '7.9.*') { throw 'Unexpected NuGet CLI version.' }
    $NugetConfig=Join-Path $BuildRoot 'NuGet.Config'
    Set-Content -LiteralPath $NugetConfig -Encoding ASCII -Value '<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>'
    $MSBuildVersion=Read-NativeText $MSBuild @('-version','-nologo')
    $VcpkgVersion=Read-NativeText (Join-Path $VcpkgRoot 'vcpkg.exe') @('version')
    Set-Stage 'RESTORING the two pinned NuGet packages'
    Invoke-LoggedNative $NuGet @('restore',(Join-Path $BuildSource 'packages.config'),'-PackagesDirectory',(Join-Path $BuildSource 'packages'),'-ConfigFile',$NugetConfig,'-NonInteractive','-NoCache')
    $SourceSlash=(CmakePath $BuildSource)+'/'
    $Additional='--overlay-ports='+$SourceSlash+'overlays/ports --overlay-triplets='+$SourceSlash+'custom-triplets --x-buildtrees-root='+(CmakePath $BuildTrees)+' --x-packages-root='+(CmakePath $Packages)+' --clean-buildtrees-after-build --clean-packages-after-build'
    # Ordinary project properties survive this bundled integration's child-MSBuild
    # global-property removal. Apply options at target time after late project groups.
    $Targets=@'
<Project>
  <Target Name="PilotLocalVcpkgArguments" BeforeTargets="VcpkgInstallManifestDependencies">
    <PropertyGroup>
      <VcpkgTriplet>x64-windows-fix-cmake</VcpkgTriplet>
      <VcpkgAdditionalInstallOptions>__ADDITIONAL__</VcpkgAdditionalInstallOptions>
    </PropertyGroup>
  </Target>
  <Import Project="$(VcpkgRoot)scripts/buildsystems/msbuild/vcpkg.targets" />
</Project>
'@
    Set-Content -LiteralPath $TargetsPath -Value $Targets.Replace('__ADDITIONAL__',[Security.SecurityElement]::Escape($Additional)) -Encoding ASCII
    $Arguments=@((Join-Path $BuildSource 'Dll1.vcxproj'),('/m:'+$Jobs),'/t:Rebuild','/p:CI=1','/p:Configuration=Release','/p:Platform=x64',('/p:VCToolsVersion='+$Toolset),('/p:WindowsTargetPlatformVersion='+$Sdk),('/p:SolutionDir='+$SourceSlash),('/p:OutDir='+(CmakePath $Bin)+'/'),('/p:IntDir='+(CmakePath $Obj)+'/'),('/p:UserRootDir='+(CmakePath $EmptyUserProps)+'/'),('/bl:'+(Join-Path $BuildRoot 'build.binlog')))
    $GeneratedFiles=@(@($TripletPath,$Chainload,$PropsPath,$TargetsPath) | ForEach-Object {@{path=$_.Substring($BuildRoot.Length).TrimStart('\');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}})
    @{executable=$MSBuild;arguments=$Arguments;toolset=$Toolset;sdk=$Sdk;input_index_sha256=$IndexHash;generated_files=$GeneratedFiles} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $BuildRoot 'build-invocation.json') -Encoding UTF8
    Set-Stage 'BUILDING Release x64 DLL and pinned vcpkg dependencies'
    Invoke-LoggedNative $MSBuild $Arguments
    $Dll=Join-Path $Bin 'tier0.dll'
    if (-not (Test-Path -LiteralPath $Dll -PathType Leaf)) { throw 'Build succeeded without the expected tier0.dll output.' }
    # Preserve the exact new release dependency DLL set as data for later import review.
    $Installed=Join-Path $BuildSource 'vcpkg_installed'
    Set-Stage 'COLLECTING release dependency DLLs as data for later import review'
    foreach ($dependency in @(Get-ChildItem -LiteralPath $Installed -Recurse -File -Filter '*.dll' | Where-Object { $_.FullName -match '[\\/]bin[\\/]' -and $_.FullName -notmatch '[\\/]debug[\\/]' })) {
        $destination=Join-Path $Bin $dependency.Name
        if ((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $dependency.FullName -Algorithm SHA256).Hash) { throw "Conflicting release DLL filename: $($dependency.Name)" }
        if (-not (Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $dependency.FullName -Destination $destination }
    }
    $Artifacts=@(Get-ChildItem -LiteralPath $Bin -File | ForEach-Object {@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
    $PackageHashes=@(Get-ChildItem -LiteralPath (Join-Path $BuildSource 'packages') -Recurse -File -Filter '*.nupkg' | ForEach-Object {@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
    $RecipeHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    @{status='Built only; no resulting DLL or game was loaded.';engine_release='c48f0003cddc5ba3af99baa415cb5b885764f84f';engine_pr44='3d98929d9c34cfb3926c8220019f360ed5bef4aa';core_pr71='b7ba836567258362306f8e544d66237edc1d2303';eos_commit='920fea818b8f995cb781e52d2a57a24a7c0023da';vcpkg_registry_baseline='78b61582c9e093fda56a01ebb654be15a0033897';input_index_sha256=$IndexHash;recipe_sha256=$RecipeHash;compiler_toolset=$Toolset;compiler_file_version=(Get-Item -LiteralPath (Join-Path $MsvcBin 'cl.exe')).VersionInfo.FileVersion;sdk=$Sdk;msbuild_version=$MSBuildVersion;vcpkg_version=$VcpkgVersion;vcpkg_executable_sha256=(Get-FileHash -LiteralPath (Join-Path $VcpkgRoot 'vcpkg.exe') -Algorithm SHA256).Hash.ToLowerInvariant();nuget_version=(Get-Item -LiteralPath $NuGet).VersionInfo.FileVersion;nuget_sha256=(Get-FileHash -LiteralPath $NuGet -Algorithm SHA256).Hash.ToLowerInvariant();nuget_signature_status=[string]$Signature.Status;nuget_signer=$Signature.SignerCertificate.Subject;nuget_packages=$PackageHashes;artifacts=$Artifacts} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $BuildRoot 'artifact-provenance.json') -Encoding UTF8
    Set-Stage 'COMPLETE; local bin output available; no game installed or launched'
} catch {
    Set-Stage ('FAILED; '+$_.Exception.Message)
    throw
} finally {
    foreach ($name in $ChangedEnv) { [Environment]::SetEnvironmentVariable($name,$PreviousEnv[$name],'Process') }
}
