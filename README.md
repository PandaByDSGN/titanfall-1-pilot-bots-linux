# How I got Titanfall 1 pilot bots running on Linux: experimental setup notes

These notes cover the setup behind my Titanfall 1 pilot-bot video, which showed friendly and enemy pilot teams. The smoke test below uses one bot on purpose so it's easy to see whether it spawns and fights.

**Status:** The Windows x64 engine rebuilt successfully from pinned sources plus a reviewed local adaptation. That new build passed a private in-game smoke test on Linux. Native Windows gameplay and a public-files-only rebuild have not been verified. Stock R1Delta alone won't give you the setup shown in the video.

## What the demo used

- A legitimately obtained PC copy of **Titanfall (2014)**. Start with a separate install or copy so that the original and its saves stay untouched.
- [R1Delta v3.0.4 release](https://github.com/r1delta/r1delta/releases/tag/v3.0.4), with [engine baseline `c48f0003`](https://github.com/r1delta/r1delta/tree/c48f0003cddc5ba3af99baa415cb5b885764f84f) and [CORE baseline `581fe1dd`](https://github.com/r1delta/CORE/tree/581fe1dd18500a658cde931e78987fe015a6f6ba).
- A local adaptation of **lcvb1997**'s [engine PR #44 at `3d98929d`](https://github.com/r1delta/r1delta/pull/44/commits/3d98929d9c34cfb3926c8220019f360ed5bef4aa) and [CORE PR #71 at `b7ba8365`](https://github.com/r1delta/CORE/pull/71/commits/b7ba836567258362306f8e544d66237edc1d2303). Neither change was merged into the release. These references are not drop-in patches for v3.0.4.
- This setup is separate from Frontier Overhaul and from [lcvb1997's standalone Windows installer](https://github.com/lcvb1997/R1Delta-PilotBots-Mod/releases). Neither is required for the setup shown here.

## Windows: build and proposed install

1. Install [R1Delta v3.0.4](https://github.com/r1delta/r1delta/releases/tag/v3.0.4) from its official release and point it at your own Titanfall files. Back up the stock R1Delta files before applying any changes.
2. For the engine build, use the two baseline revisions above and the **matching v3.0.4 adaptations of both PRs**. The Windows build used MSBuild 18.11.1, MSVC v145 (14.50.35717), Windows SDK 10.0.26100.0, and the pinned NuGet/vcpkg dependencies. Use the Windows MSBuild route and select **Release | x64**. The clean rebuild produced `tier0.dll`.
3. In the isolated R1Delta installation, stage the rebuilt `tier0.dll` under `r1delta/bin_delta/`, with the matching open-source dependency DLLs and the matching CORE overlay. Keep R1Delta's original platform DLLs unchanged. Apply the engine and CORE changes together; replacing only `tier0.dll` isn't this setup.
4. A native Windows check would launch that patched R1Delta installation and follow the smoke test below. To roll back, restore the backed-up R1Delta files or discard the isolated copy rather than modifying your main install.

**What passed:** A clean Windows x64 source rebuild with no reused dependency cache. **What hasn't been tested:** Launching the patched game or completing a match on native Windows. The reviewed adaptation, exact overlay manifest, and build helper are not included here. If you have only the public links above, the exact build and install recipe is not yet complete.

## Linux: run the Windows build in an isolated Wine prefix

1. Start with a **fresh, dedicated 64-bit Wine prefix**, your own separate Titanfall asset copy, and the official v3.0.4 installer. The tested runtime was [GE-Proton11-12](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-12). The test initialized the prefix with Wineboot, set up ICU/VKD3D/DXVK inside it, and installed R1Delta there.
2. Stage the same matching Windows build and CORE overlay from the Windows section into that R1Delta installation. Don't copy an old Wine prefix or replace the stock platform DLLs.
3. Launch the patched install using **GE-Proton11-12's bundled Wine directly** (`files/bin/wine` with its matching `files/bin/wineserver` and the dedicated `WINEPREFIX`). The verified run used Bubblewrap with network isolation, writable mounts for disposable test data only, and a local stdio probe. **Steam, the Proton wrapper, and umu were not used.** Their launch paths are untested here. The small test used assets copied from an existing owned installation, not a new game download.
4. Run the smoke test below. Restore the backed-up files or discard the isolated prefix and separate asset copy to undo the setup.

This describes the route that passed, not a public one-command installer. The private patch recipe is still needed to reproduce the exact build.

## Smoke test after the compatible patched build is installed

1. In R1Delta, choose **Play → Private Match**.
2. Select **Angel City** and **Attrition**.
3. Set **Pilot Bots Count** to **1**, **Lethality** to **Low**, and **AI Type** to **None**. This lets you check the pilot bot separately from regular AI infantry.
4. Apply the settings, start the match, and finish selecting your loadout.
5. Check for the second pilot slot on the scoreboard, then confirm the bot spawns and fights.

The patched build passed this small test in two isolated Linux installs, including a 90-second run with the freshly rebuilt engine. That run loaded one pilot bot, the bot moved and fought, and it registered two pilot kills. This checks one map and mode with one bot, not the larger friendly and enemy teams shown in the video.

## What still needs verification

- Play the private-match test on native Windows.
- Rebuild and install from a shareable recipe using only public dependencies and an independently obtained owned game install.
- Verify a larger private match with friendly and enemy pilot teams, and other maps and modes.
- Review what patches can be shared and how to preserve required licenses and notices. No game files, modified binaries, third-party runtime DLLs, or Wine prefixes are included here.

Thanks to the R1Delta contributors and **lcvb1997** for the original pilot-bot work.
