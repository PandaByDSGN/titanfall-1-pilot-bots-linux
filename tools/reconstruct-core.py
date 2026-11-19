#!/usr/bin/env python3
"""Create the matched pilot-bot CORE files locally, without redistributing CORE."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.request import urlopen

RELEASE = ("r1delta/CORE", "581fe1dd18500a658cde931e78987fe015a6f6ba")
ANCESTOR = ("r1delta/CORE", "cb35180c6ba17c0f85f292b770a2d51104dd1303")
PR = ("lcvb1997/CORE", "b7ba836567258362306f8e544d66237edc1d2303")


def fetch(repo, commit, path):
    url = f"https://raw.githubusercontent.com/{repo}/{commit}/{path}"
    with urlopen(url, timeout=30) as handle:
        return handle.read()


def merge(release, ancestor, feature, encoding, temporary):
    inputs = [temporary / name for name in ("release", "ancestor", "pr")]
    for raw, path in zip((release, ancestor, feature), inputs):
        data = raw.decode(encoding).replace("\r\n", "\n").replace("\r", "\n")
        path.write_bytes(data.encode("utf-8"))
    output = subprocess.run(
        ["git", "merge-file", "-p", "--diff3", *(str(p) for p in inputs)],
        check=True, capture_output=True,
    ).stdout
    if encoding == "utf-16":
        return b"\xff\xfe" + output.decode("utf-8").encode("utf-16-le")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path, help="New directory, not a game install")
    args = parser.parse_args()
    entries = json.loads(args.manifest.read_text(encoding="utf-8"))["core"]
    if len(entries) != 26 or args.output.exists() or args.output.is_symlink():
        raise SystemExit("Require the 26-file manifest and a new output directory")
    results = {}
    with tempfile.TemporaryDirectory() as work:
        for entry in entries:
            name = entry["path"]
            if not re.fullmatch(r"[A-Za-z0-9_./-]+", name) or any(
                part in ("", ".", "..") for part in name.split("/")
            ) or name in results:
                raise SystemExit(f"Invalid/duplicate manifest path: {name!r}")
            feature = fetch(*PR, name)
            result = feature
            if "encoding" in entry:
                result = merge(
                    fetch(*RELEASE, name), fetch(*ANCESTOR, name),
                    feature, entry["encoding"], Path(work),
                )
            calculated = hashlib.sha256(result).hexdigest()
            if calculated != entry["sha256"]:
                raise SystemExit(f"Hash mismatch: {name}: {calculated}")
            results[name] = result
    args.output.mkdir()
    for name, data in results.items():
        target = args.output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(data)
    print(f"Verified and wrote {len(results)} CORE files to {args.output}")


if __name__ == "__main__":
    main()
