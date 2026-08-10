#!/usr/bin/env python3
"""Plan or create a minimal fail-closed MK project manifest without executing target Git configuration."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import stat
import sys
from pathlib import Path

# Planning mode must not mutate the control-plane checkout through import caches.
sys.dont_write_bytecode = True

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from detect_project import detect  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"[BLOCK] {message}")


def manifest_for(target: Path) -> dict:
    found = detect(target)
    return {
        "schema": 1,
        "spacecraft": {
            "source": "mk-nuclear-spacecraft",
            "source_commit_recording": "omitted-until-trusted-runtime",
            "source_commit_is_authorization": False,
        },
        "project": {
            "root_name": target.name,
            "tags": found["tags"],
            "lockfiles": found["lockfiles"],
            "existing_package_scripts": found["existing_package_scripts"],
            "candidate_verification_commands": found["candidate_verification_commands"],
            "git_cleanliness": "not-inspected-by-bootstrap",
            "git_cleanliness_reason": "target-git-config-is-never-executed-by-app-factory-core",
        },
        "skills": {
            "canonical_source": "skills/canonical",
            "recommended": found["recommended_skills"],
            "publication_enabled": False,
            "publication_blocker": "trusted-runtime-publisher-not-yet-qualified",
        },
        "security": {
            "quick_gate": True,
            "full_gate_before_merge": True,
            "nuclear_gate_on_sensitive_release": True,
            "command_guard_required": True,
            "target_git_config_execution_allowed": False,
            "manifest_publish_model": "posix-dirfd-atomic-no-replace",
        },
        "execution": {
            "autonomous_project_writer_enabled": False,
            "production_write_enabled": False,
            "production_secrets_allowed": False,
        },
    }


def assert_physical_directory(path: Path) -> None:
    if path.is_symlink() or not path.is_dir():
        fail(f"Path is not a physical directory: {path}")
    try:
        if path.resolve(strict=True) != path:
            fail(f"Path is not canonical/physical: {path}")
    except FileNotFoundError:
        fail(f"Directory disappeared during bootstrap: {path}")


def require_secure_apply_platform() -> None:
    if os.name != "posix" or not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        fail("Secure --apply currently requires POSIX dirfd/O_NOFOLLOW support. Planning mode remains available on this platform.")


def open_directory(path: Path) -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        fail(f"Could not bind target directory securely: {exc}")
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        os.close(fd)
        fail("Bound target is not a directory.")
    return fd


def open_state_directory(target_fd: int) -> int:
    try:
        os.mkdir(".mk-spacecraft", 0o755, dir_fd=target_fd)
        os.fsync(target_fd)
    except FileExistsError:
        pass
    except OSError as exc:
        fail(f"Could not create state directory: {exc}")

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        state_fd = os.open(".mk-spacecraft", flags, dir_fd=target_fd)
    except OSError as exc:
        fail(f"State path is not a physical directory: {exc}")
    st = os.fstat(state_fd)
    if not stat.S_ISDIR(st.st_mode):
        os.close(state_fd)
        fail("Bound state path is not a directory.")
    return state_fd


def assert_state_binding(target_fd: int, state_fd: int) -> None:
    try:
        named = os.stat(".mk-spacecraft", dir_fd=target_fd, follow_symlinks=False)
    except OSError as exc:
        fail(f"State directory path disappeared or changed: {exc}")
    bound = os.fstat(state_fd)
    if not stat.S_ISDIR(named.st_mode) or (named.st_dev, named.st_ino) != (bound.st_dev, bound.st_ino):
        fail("State directory pathname no longer references the bound physical directory.")


def publish_manifest(state_fd: int, data: bytes) -> None:
    temp_name = f".project.json.tmp-{os.getpid()}-{secrets.token_hex(8)}"
    final_name = "project.json"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    temp_fd: int | None = None
    linked = False
    try:
        temp_fd = os.open(temp_name, flags, 0o644, dir_fd=state_fd)
        with os.fdopen(temp_fd, "wb", closefd=False) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.close(temp_fd)
        temp_fd = None

        try:
            os.link(
                temp_name,
                final_name,
                src_dir_fd=state_fd,
                dst_dir_fd=state_fd,
                follow_symlinks=False,
            )
        except FileExistsError:
            fail("Project manifest already exists; refusing overwrite.")
        linked = True
        try:
            os.fsync(state_fd)
        except OSError:
            # Do not leave a newly visible manifest if its directory entry could
            # not be made durable. Best-effort rollback is still fd-bound.
            try:
                os.unlink(final_name, dir_fd=state_fd)
                os.fsync(state_fd)
                linked = False
            except OSError as rollback_exc:
                fail(f"Manifest publish durability failed and rollback was incomplete: {rollback_exc}")
            fail("Manifest publish durability check failed; publication rolled back.")

        os.unlink(temp_name, dir_fd=state_fd)
        os.fsync(state_fd)
    finally:
        if temp_fd is not None:
            os.close(temp_fd)
        try:
            os.unlink(temp_name, dir_fd=state_fd)
        except FileNotFoundError:
            pass
        except OSError:
            if not linked:
                raise


def apply(target: Path, text: str) -> None:
    # App Factory Core deliberately does not invoke Git in the target repository.
    # Repository-local Git configuration can name executable fsmonitor/filter
    # commands, so Git cleanliness belongs to a later trusted-control-plane gate.
    require_secure_apply_platform()
    target_fd = open_directory(target)
    state_fd: int | None = None
    try:
        state_fd = open_state_directory(target_fd)
        assert_state_binding(target_fd, state_fd)
        publish_manifest(state_fd, text.encode("utf-8"))
        assert_state_binding(target_fd, state_fd)
    finally:
        if state_fd is not None:
            os.close(state_fd)
        os.close(target_fd)

    print(f"[PASS] Created fd-bound atomic fail-closed project manifest: {target / '.mk-spacecraft' / 'project.json'}")
    print("[PASS] Target Git config was not executed or inspected.")
    print("[PASS] Autonomous writer, skill publication, production writes, and production secrets remain disabled.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    target = Path(args.root).resolve()
    if not target.is_dir():
        fail(f"Project root does not exist: {target}")
    assert_physical_directory(target)
    text = json.dumps(manifest_for(target), indent=2, ensure_ascii=False) + "\n"
    if args.apply:
        apply(target, text)
    else:
        print(text, end="")
        print("[PLAN] No files changed. Use --apply only after reviewing this manifest.")


if __name__ == "__main__":
    main()
