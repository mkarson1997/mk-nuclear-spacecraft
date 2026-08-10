#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import stat
from pathlib import Path

MANIFEST_NAME = "mk-runtime-tree-manifest.json"
SCHEMA = 1
LOGICAL_ROOT = "."


def fail(message: str) -> None:
    raise SystemExit(f"[BLOCK] {message}")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb", buffering=0) as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalized_root(raw: str) -> Path:
    root = Path(raw)
    if not root.is_absolute():
        fail("Runtime root must be absolute.")
    try:
        resolved = root.resolve(strict=True)
    except FileNotFoundError:
        fail(f"Runtime root does not exist: {root}")
    st = os.lstat(resolved)
    if not stat.S_ISDIR(st.st_mode):
        fail("Runtime root is not a directory.")
    return resolved


def relative_name(root: Path, path: Path) -> str:
    if path == root:
        return LOGICAL_ROOT
    return path.relative_to(root).as_posix()


def snapshot(root: Path):
    entries = []
    candidates = [root]
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        dirs.sort()
        files.sort()
        for name in dirs:
            candidates.append(current_path / name)
        for name in files:
            if name == MANIFEST_NAME and current_path == root:
                continue
            candidates.append(current_path / name)

    for path in sorted(candidates, key=lambda p: relative_name(root, p)):
        st = os.lstat(path)
        rel = relative_name(root, path)
        mode = stat.S_IMODE(st.st_mode)
        base = {
            "path": rel,
            "uid": st.st_uid,
            "gid": st.st_gid,
            "mode": format(mode, "04o"),
            "nlink": st.st_nlink,
        }
        if st.st_uid != 0 or st.st_gid != 0:
            fail(f"Runtime object is not root:root: {rel}")
        if mode & 0o222:
            fail(f"Runtime object has write permission bits: {rel} mode={mode:04o}")
        if stat.S_ISLNK(st.st_mode):
            fail(f"Runtime contains a symlink: {rel}")
        if stat.S_ISDIR(st.st_mode):
            base["type"] = "directory"
        elif stat.S_ISREG(st.st_mode):
            if st.st_nlink != 1:
                fail(f"Runtime file has multiple hard links: {rel}")
            base["type"] = "file"
            base["size"] = st.st_size
            base["sha256"] = sha256_file(path)
        else:
            fail(f"Runtime contains unsupported object type: {rel}")
        entries.append(base)
    return entries


def create_manifest(root: Path, output: Path) -> None:
    if output.resolve(strict=False).parent != root:
        fail("Runtime manifest must be written directly inside the runtime root.")
    if output.name != MANIFEST_NAME:
        fail(f"Runtime manifest name must be {MANIFEST_NAME}.")
    if os.path.lexists(output):
        fail("Runtime manifest already exists.")
    payload = {
        "schema": SCHEMA,
        "root": LOGICAL_ROOT,
        "entries": snapshot(root),
    }
    encoded = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
    try:
        os.write(fd, encoded.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chown(output, 0, 0, follow_symlinks=False)
    os.chmod(output, 0o444, follow_symlinks=False)
    print(f"[PASS] Runtime tree manifest created: {output}")


def verify_manifest(root: Path, manifest: Path) -> None:
    if manifest.parent.resolve(strict=True) != root or manifest.name != MANIFEST_NAME:
        fail("Runtime manifest path is not canonical.")
    st = os.lstat(manifest)
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
        fail("Runtime manifest is not a single-link regular file.")
    if st.st_uid != 0 or st.st_gid != 0 or stat.S_IMODE(st.st_mode) != 0o444:
        fail("Runtime manifest ownership/mode is not root:root 0444.")
    with manifest.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if payload.get("schema") != SCHEMA or payload.get("root") != LOGICAL_ROOT:
        fail("Runtime manifest schema/logical root is invalid.")
    expected = payload.get("entries")
    if not isinstance(expected, list):
        fail("Runtime manifest entries are invalid.")
    actual = snapshot(root)
    if actual != expected:
        fail("Runtime tree differs from the immutable installation manifest.")
    print("[PASS] Complete runtime tree ownership, modes, types, links and digests validated.")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("create")
    create.add_argument("root")
    create.add_argument("manifest")
    verify = sub.add_parser("verify")
    verify.add_argument("root")
    verify.add_argument("manifest")
    args = parser.parse_args()
    root = normalized_root(args.root)
    manifest = Path(args.manifest).resolve(strict=False)
    if args.command == "create":
        create_manifest(root, manifest)
    else:
        verify_manifest(root, manifest)


if __name__ == "__main__":
    main()
