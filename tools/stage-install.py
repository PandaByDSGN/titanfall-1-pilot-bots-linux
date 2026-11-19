#!/usr/bin/env python3
"""Validate a stock R1Delta root and prepare a new, hash-checked install overlay."""
import argparse
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(root, name):
    root = root.resolve(strict=True)
    path = root.joinpath(name)
    if not path.resolve().is_relative_to(root):
        raise SystemExit(f"Path escapes its input directory: {name}")
    return path


def stock_check(root, row):
    name = row["path"]
    path = read(root, name)
    expected = row["stock_sha256"]
    if expected is None:
        if path.exists() or path.is_symlink():
            raise SystemExit(f"Expected stock file to be absent: {name}")
    elif not path.is_file() or sha(path.read_bytes()) != expected:
        raise SystemExit(f"Unexpected stock file: {name}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("manifest", type=Path)
    p.add_argument("stock_root", type=Path, help="Isolated stock app-3.0.4/r1delta directory")
    p.add_argument("core_overlay", type=Path)
    p.add_argument("windows_build", type=Path, help="New local Windows build directory")
    p.add_argument("output", type=Path, help="New output directory outside every input tree")
    args = p.parse_args()
    lock = json.loads(args.manifest.read_text(encoding="utf-8"))
    build = json.loads((args.windows_build / "artifact-provenance.json").read_text(encoding="utf-8-sig"))
    if build["engine_release"] != "c48f0003cddc5ba3af99baa415cb5b885764f84f" or (
        build["engine_pr44"] != "3d98929d9c34cfb3926c8220019f360ed5bef4aa"
    ):
        raise SystemExit("Unexpected build source pins")
    native_hashes = {item["name"]: item["sha256"] for item in build["artifacts"]}
    payload = {}
    for row in lock["core"] + lock["native"]:
        name = row["path"]
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or name in payload:
            raise SystemExit(f"Invalid manifest path: {name}")
        stock_check(args.stock_root, row)
        if row.get("action") == "retain":
            continue
        if row.get("action") == "build":
            content = read(args.windows_build / "bin", path.name).read_bytes()
            expected = native_hashes.get(path.name)
        else:
            content = read(args.core_overlay, name).read_bytes()
            expected = row["sha256"]
        if sha(content) != expected:
            raise SystemExit(f"Unexpected payload file: {name}")
        payload[name] = content
    if len(payload) != 38:
        raise SystemExit("Expected 26 CORE files and 12 locally built DLLs")
    output = args.output.resolve()
    if any(output.is_relative_to(root.resolve()) for root in (
        args.stock_root, args.windows_build, args.core_overlay
    )):
        raise SystemExit("Use a separate output directory")
    args.output.mkdir()
    for name, content in payload.items():
        target = args.output / name
        target.parent.mkdir(exist_ok=True, parents=True)
        with target.open("xb") as handle:
            handle.write(content)
    print(f"Staged {len(payload)} files; stock install and platform DLLs left unchanged")


if __name__ == "__main__":
    main()
