# Build and install the v3.0.4 pilot-bot port

**Passed:** Fresh public GitHub downloads reproduced all 11 changed engine and 26 CORE files byte for byte. Separately, a clean Windows x64 build of those source bytes ran in a fresh Linux prefix and passed the one-bot Attrition smoke test. **Pending:** A second Windows build and Linux test driven solely by this checked-in recipe, native Windows gameplay, and Steam Deck.

## 1. Reconstruct from pinned source

Use Git and Python 3.10+. Download the [pinned engine source ZIP](https://codeload.github.com/r1delta/r1delta/zip/c48f0003cddc5ba3af99baa415cb5b885764f84f) from upstream and check SHA-256 `1c7dba0a503f91096a9180ab261ed28da49f71342afe15d70bc6dfef70aad4fc`. Stop on mismatch. Extract it into a disposable directory and rename the extracted engine root to `engine-src`. From the guide root:

```text
python tools/reconstruct-engine.py install-manifest.json engine-src engine-overlay
python tools/reconstruct-core.py install-manifest.json core-overlay
```

Copy the **contents** of `engine-overlay` into `engine-src`, keeping relative paths. In PowerShell: `Copy-Item -Path .\engine-overlay\* -Destination .\engine-src -Recurse -Force`. On Linux: `cp -R engine-overlay/. engine-src/`. Keep the CORE overlay separate until runtime staging. The reconstruction scripts fetch only the named files at pinned commits, use three-way merges and check all output hashes. The result is the exact modified source, not a stock R1Delta install. See [source provenance and notices](NOTICES.md).

## 2. Build on Windows x64

Use Visual Studio 2026 Build Tools, x64 C++, MSVC v145 **14.50.35717**, Windows SDK **10.0.26100.0**, MASM, MSBuild **18.11.1**, and the bundled vcpkg (tested executable revision `98d7cb0cf1f4686a3e43aa5672b6230c1d56bce8`, registry baseline `78b61582c9e093fda56a01ebb654be15a0033897`). The engine [pins EOS SDK revision 920fea8](https://github.com/19h/EOS-SDK/tree/920fea818b8f995cb781e52d2a57a24a7c0023da) via submodule. Obtain compatible SDK files separately under the SDK terms. The helper expects `SDK/Include`, `SDK/Lib/EOSSDK-Win64-Shipping.lib`, and `SDK/Bin/EOSSDK-Win64-Shipping.dll` inside your SDK directory and checks the library and DLL hashes.

```powershell
$vs = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools'
.\tools\Build-PilotEngine.ps1 -EngineSource .\engine-src -EosSource .\eos-sdk -BuildRoot C:\R1DeltaPilotBuild -VisualStudioRoot $vs -VcpkgRoot (Join-Path $vs 'VC\vcpkg') -Jobs 4
```

Adjust for your installed tools. Use a **new** absolute build root with no spaces. The helper sets up x64 `VsDevCmd`, verifies the compiler and SDK, checks signed NuGet 7.9.0, restores minhook 1.3.3 and YY-Thunks 1.1.9, and builds the pinned vcpkg manifest/overlay ports with a pinned release x64 dynamic triplet. The test used `Dll1.vcxproj /t:Rebuild /p:CI=1 /p:Configuration=Release /p:Platform=x64`, with isolated intermediate, output and package-cache dirs. On success inspect `build-invocation.json`, `artifact-provenance.json` and `bin/`. Do not redistribute the build folder. This helper is adapted from the passed build; its new public-input entry point hasn't run on Windows yet.

## 3. Stage the runtime on either OS

Use the official [R1Delta v3.0.4 release](https://github.com/r1delta/r1delta/releases/tag/v3.0.4) and a separate copy of your owned Titanfall (2014) install. The verified installer SHA-256 was `506ee85cb1f431ab5fcf362dc0de012694baae3e5685a78eb9073ceb25af18d6`. Point the staging helper at the **`r1delta` directory inside your isolated app-3.0.4 install**, not the game's asset directory or your everyday install:

```text
python tools/stage-install.py install-manifest.json <isolated-app-3.0.4/r1delta> core-overlay <windows-build-root> staged-overlay
```

This checks stock file hashes, then prepares 38 files in a new folder: 26 CORE files, the rebuilt `tier0.dll`, and 11 rebuilt dependencies. It checks but does not copy the stock EOS and Discord DLLs. Review the result, close the isolated game, then copy the **contents** of `staged-overlay` into that same isolated `r1delta` directory with relative paths preserved. If stock hashes differ, stop. To roll back, discard or restore only the disposable install. On Windows, the intended launch is through the normal R1Delta entry point, but native gameplay isn't verified.

## 4. Linux runtime used in the verified test

- Start with a fresh dedicated 64-bit `WINEPREFIX` and a separate owned Titanfall asset copy. The test used [GE-Proton11-12](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-12)'s **bundled Wine directly**: `$GE/files/bin/wine`, matching `$GE/files/bin/wineserver`, with `WINELOADER` and `WINESERVER` pointing there, `WINEARCH=win64`, the bundled bin directory on `PATH`, and independent temp/cache/Wine socket directories. Steam, Proton's wrapper and umu were not used.
- Initialize with bundled Wine and `wineboot.exe -u`. In the new prefix, use the matching GE ICU trio (`icuin68.dll`, `icuuc68.dll`, `icudt68.dll` under `files/lib/wine/icu/<arch>`), VKD3D trio (`libvkd3d-1.dll`, `libvkd3d-shader-1.dll`, `libvkd3d-utils-1.dll` under `files/lib/vkd3d/<arch>`), and DXVK pair (`d3d11.dll`, `dxgi.dll` under `files/lib/wine/dxvk/<arch>`). Put `x86_64-windows` files under prefix `drive_c/windows/system32` and `i386-windows` files under prefix `drive_c/windows/syswow64`. The tested environment used `WINEDLLOVERRIDES='winemenubuilder.exe=d;d3d11,dxgi=n'`.
- Run the official R1Delta installer with that direct Wine invocation and stage the overlay from step 3. The test gave the runtime access to its own app directories and mapped its separate owned game data copy to a Wine drive. The game executable was invoked through bundled Wine's `cmd.exe` from that game data directory.
- In the actual run, Bubblewrap wrapped the direct Wine invocation with a read-only host filesystem view, writable mounts just for the disposable prefix/temp/sockets/asset copy, and `--unshare-net`. The test probe communicated via private stdio rather than a host listener. The automation probe is separate from the manual spawn/scoreboard check in the README.

**Steam Deck / SteamOS:** No Deck was tested. The successful desktop run does not establish support for the Steam launch path, Gaming Mode, Deck controls, or Deck performance. For an experimental Deck attempt, build the DLLs on Windows first and start in SteamOS Desktop Mode in a separate prefix. Do not disable SteamOS protections to force the desktop recipe to work.
