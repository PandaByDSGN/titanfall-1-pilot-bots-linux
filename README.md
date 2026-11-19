# How I got Titanfall 1 pilot bots running on Linux: experimental setup notes

These notes cover the setup behind my Titanfall 1 pilot-bot video, which showed friendly and enemy pilot teams. The smoke test below uses one bot on purpose so it's easy to see whether it spawns and fights.

**Status:** The patched build worked on my Linux setup. I haven't yet reproduced the install from scratch using only shareable files. Stock R1Delta alone won't give you the setup shown in the video.

## What the demo used

- A legitimately obtained PC copy of **Titanfall (2014)**.
- [R1Delta v3.0.4](https://github.com/r1delta/r1delta/releases/tag/v3.0.4), engine baseline `c48f0003cddc5ba3af99baa415cb5b885764f84f`.
- [R1Delta CORE baseline](https://github.com/r1delta/CORE/tree/581fe1dd18500a658cde931e78987fe015a6f6ba).
- A local adaptation of **lcvb1997**'s [engine pilot-bot changes](https://github.com/r1delta/r1delta/pull/44) and [CORE script changes](https://github.com/r1delta/CORE/pull/71). Neither PR was merged upstream. This setup is separate from Frontier Overhaul and from the author's standalone Windows installer.
- A dedicated Wine prefix on Linux. The matching engine component was built for Windows and run through Wine.

## Smoke test after the compatible patched build is installed

1. In R1Delta, choose **Play → Private Match**.
2. Select **Angel City** and **Attrition**.
3. Set **Pilot Bots Count** to **1**, **Lethality** to **Low**, and **AI Type** to **None**. This lets you check the pilot bot separately from regular AI infantry.
4. Apply the settings, start the match, and finish selecting your loadout.
5. Check for the second pilot slot on the scoreboard, then confirm the bot spawns and fights.

The small test passed in two isolated runs, including a bot kill and a human death. It checks one configuration, not every map, mode, or team size.

## What still needs verification

- Rebuild from pinned sources and repeat the test with a fresh Wine prefix and owned game install.
- Document the exact build, install, and rollback steps.
- Verify a larger private match with friendly and enemy pilot teams separately from the smoke test.
- Review what patches can be shared and how to preserve required licenses and notices. No game files, modified binaries, third-party runtime DLLs, or Wine prefixes are included here.

Thanks to the R1Delta contributors and lcvb1997 for the original pilot-bot work.
