# How I got Titanfall 1 pilot bots running on Linux: experimental setup notes

These notes cover the setup behind my Titanfall 1 pilot-bot video. I tested friendly and enemy pilot teams in private Attrition matches across multiple maps. The video shows that larger-team setup. The smoke test below uses one bot on purpose so it's easy to see whether it spawns and fights.

**Status:** I reproduced the exact engine and CORE source changes from pinned public downloads. A clean Windows x64 build of those sources passed the one-bot Linux smoke test below. The new public-input build recipe has not yet been run end to end. Stock R1Delta alone won't give you the setup shown in the video.

[![Watch the Titanfall 1 pilot-bot gameplay demo](https://i.ytimg.com/vi/xJE6C8UFrIc/hqdefault.jpg)](https://youtube.com/live/xJE6C8UFrIc)

[Watch the gameplay demo on YouTube](https://youtube.com/live/xJE6C8UFrIc)

## What the demo used

- A legitimately obtained PC copy of **Titanfall (2014)**. Start with a separate install or copy so that the original and its saves stay untouched.
- [R1Delta v3.0.4 release](https://github.com/r1delta/r1delta/releases/tag/v3.0.4), with [engine baseline `c48f0003`](https://github.com/r1delta/r1delta/tree/c48f0003cddc5ba3af99baa415cb5b885764f84f) and [CORE baseline `581fe1dd`](https://github.com/r1delta/CORE/tree/581fe1dd18500a658cde931e78987fe015a6f6ba).
- A local adaptation of **lcvb1997**'s [engine PR #44 at `3d98929d`](https://github.com/r1delta/r1delta/pull/44/commits/3d98929d9c34cfb3926c8220019f360ed5bef4aa) and [CORE PR #71 at `b7ba8365`](https://github.com/r1delta/CORE/pull/71/commits/b7ba836567258362306f8e544d66237edc1d2303). Neither change was merged into the release. These references are not drop-in patches for v3.0.4.
- This setup is separate from Frontier Overhaul and from [lcvb1997's standalone Windows installer](https://github.com/lcvb1997/R1Delta-PilotBots-Mod/releases). Neither is required for the setup shown here.

## Windows: build and proposed install

Follow the [Windows x64 build and staging guide](BUILD.md#2-build-on-windows-x64). It includes the pinned reconstruction steps, MSBuild toolchain, and a hash-checked [install manifest](install-manifest.json). Use a separate copy of your owned Titanfall files. The Windows build passed; launching and playing the patched game natively on Windows has not been verified.

## Linux: run the Windows build in an isolated Wine prefix

Follow the [Linux runtime steps](BUILD.md#4-linux-runtime-used-in-the-verified-test) to stage the matching build and use GE-Proton11-12’s Wine and wineserver directly in a fresh isolated prefix. Steam, the Proton wrapper and umu were not used. **Steam Deck / SteamOS has not been tested.** The guide describes what passed on desktop Linux, not a verified Deck install.

## Smoke test after the compatible patched build is installed

1. In R1Delta, choose **Play → Private Match**.
2. Select **Angel City** and **Attrition**.
3. Set **Pilot Bots Count** to **1**, **Lethality** to **Low**, and **AI Type** to **None**. This lets you check the pilot bot separately from regular AI infantry.
4. Apply the settings, start the match, and finish selecting your loadout.
5. Check for the second pilot slot on the scoreboard, then confirm the bot spawns and fights.

The patched build passed this small test in two isolated Linux installs, including a 90-second run with the freshly rebuilt engine. That run loaded one pilot bot, the bot moved and fought, and it registered two pilot kills. This fresh-install check covered one bot on Angel City. The larger friendly and enemy teams were verified separately in my private Attrition matches across multiple maps.

## What still needs verification

- Play the private-match test on native Windows.
- Run the newly documented public-input recipe through Windows compilation and a fresh Linux runtime test with independently obtained owned game files.
- Verify Steam Deck / SteamOS and alternative Linux launch routes.
- Test friendly and enemy pilot teams in modes beyond Attrition.
- See [source provenance and notices](NOTICES.md). This repository does not include game files, compiled binaries, upstream CORE scripts, third-party runtime DLLs, or Wine prefixes.

Thanks to the R1Delta contributors and **lcvb1997** for the original pilot-bot work.
