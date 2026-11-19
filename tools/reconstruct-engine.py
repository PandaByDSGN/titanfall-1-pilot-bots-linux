#!/usr/bin/env python3
"""Reconstruct the v3.0.4 pilot-bot engine changes from public source snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.request import urlopen

ANCESTOR = "4e9d1ddba1224d42750bb22d60a389c74173adb6"
PR_HEAD = "3d98929d9c34cfb3926c8220019f360ed5bef4aa"
# The three local resolutions keep the release conflict side, then insert a
# bot-specific include/registration. All non-conflicting changes survive.
RESOLVE = {
    "engine/core/load.cpp": (
        '\t\t\t"Dump R2 provider counters and filtered filesystem trace.", FCVAR_NONE);\n',
        '\t\tRegisterBotControlConVars();\n',
    ),
    "engine/cvar.cpp": ('#include "p2p/p2p.h"\n', '#include "bot_control.h"\n'),
    "shared/squirrel.cpp": ('#include "localize.h"\n', '#include "bot_control.h"\n'),
}


def fetch(repo, rev, path):
    with urlopen(f"https://raw.githubusercontent.com/{repo}/{rev}/{path}",
                 timeout=30) as handle:
        return handle.read()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def lf(data):
    return data.replace(b"\r\n", b"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("source", type=Path, help="Fresh extracted v3.0.4 engine tree")
    parser.add_argument("output", type=Path, help="New directory for 11 overlaid files")
    args = parser.parse_args()
    entries = json.loads(args.manifest.read_text(encoding="utf-8"))["engine"]
    if len(entries) != 11 or args.output.exists() or args.output.is_symlink():
        raise SystemExit("Require the 11-file manifest and a new output directory")
    result = {}
    with tempfile.TemporaryDirectory() as scratch:
        inputs = [Path(scratch) / item for item in ("release", "ancestor", "pr")]
        for row in entries:
            name = row["path"]
            if not re.fullmatch(r"[A-Za-z0-9_./-]+", name) or any(
                p in ("", ".", "..") for p in name.split("/")
            ) or name in result:
                raise SystemExit(f"Invalid engine path: {name!r}")
            p = args.source / name
            pr = fetch("lcvb1997/r1delta", PR_HEAD, name)
            if row["source_sha256"] is None:
                if p.exists() or p.is_symlink():
                    raise SystemExit(f"Unexpected baseline file: {name}")
                content = pr
            else:
                release = p.read_bytes()
                if sha(release) != row["source_sha256"]:
                    raise SystemExit(f"Unexpected baseline bytes: {name}")
                base = fetch("r1delta/r1delta", ANCESTOR, name)
                for path, data in zip(inputs, (release, base, pr)):
                    path.write_bytes(lf(data))
                mode = "--ours" if name in RESOLVE else "--diff3"
                content = subprocess.run(
                    ["git", "merge-file", "-p", mode, *(str(p) for p in inputs)],
                    check=True, capture_output=True,
                ).stdout
                if name in RESOLVE:
                    anchor, addition = (s.encode() for s in RESOLVE[name])
                    if content.count(anchor) != (2 if name == "engine/core/load.cpp" else 1):
                        raise SystemExit(f"Unexpected merge anchor: {name}")
                    before, after = content.rsplit(anchor, 1)
                    content = before + anchor + addition + after
                if b"\r\n" in release:
                    content = content.replace(b"\n", b"\r\n")
            if sha(content) != row["prepared_sha256"]:
                raise SystemExit(f"Engine hash mismatch: {name}: {sha(content)}")
            result[name] = content
    args.output.mkdir()
    for name, content in result.items():
        target = args.output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as handle:
            handle.write(content)
    print(f"Verified and wrote {len(result)} engine files to {args.output}")


if __name__ == "__main__":
    main()
