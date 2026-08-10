#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(id -u)" -ne 0 ]]; then
  echo "[BLOCK] Writer sandbox requires Linux root supervisor." >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "[BLOCK] Writer sandbox recursive mount hardening is pinned to linux-amd64." >&2
  exit 1
fi

for cmd in unshare mount setpriv stat readlink awk python3 findmnt dirname; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[BLOCK] Required sandbox command missing: $cmd" >&2
    exit 1
  }
done

WRITER_USER=""
WRITER_HOME=""
WRITER_TMP=""
WRITABLE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      WRITER_USER="${2:-}"
      shift 2
      ;;
    --home)
      WRITER_HOME="${2:-}"
      shift 2
      ;;
    --tmp)
      WRITER_TMP="${2:-}"
      shift 2
      ;;
    --writable-file)
      WRITABLE_FILE="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "[BLOCK] Unknown sandbox argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "$WRITER_USER" && -n "$WRITER_HOME" && -n "$WRITER_TMP" && $# -gt 0 ]] || {
  echo "Usage: writer-sandbox-exec.sh --user USER --home ABS --tmp ABS [--writable-file ABS] -- COMMAND [ARGS...]" >&2
  exit 2
}

WRITER_UID="$(id -u "$WRITER_USER")"
WRITER_GID="$(id -g "$WRITER_USER")"
[[ "$WRITER_UID" -ne 0 ]] || { echo "[BLOCK] Sandbox writer may not be root." >&2; exit 1; }

for path in "$WRITER_HOME" "$WRITER_TMP"; do
  [[ "$path" == /* ]] || { echo "[BLOCK] Sandbox writable root must be absolute: $path" >&2; exit 1; }
  [[ -d "$path" && ! -L "$path" ]] || { echo "[BLOCK] Sandbox writable root missing or symlinked: $path" >&2; exit 1; }
  [[ "$(stat -c '%u:%g' "$path")" == "$WRITER_UID:$WRITER_GID" ]] || {
    echo "[BLOCK] Sandbox writable root ownership mismatch: $path" >&2
    exit 1
  }
done

HOME_PHYSICAL="$(readlink -f -- "$WRITER_HOME")"
TMP_PHYSICAL="$(readlink -f -- "$WRITER_TMP")"
[[ "$HOME_PHYSICAL" == "$WRITER_HOME" && "$TMP_PHYSICAL" == "$WRITER_TMP" ]] || {
  echo "[BLOCK] Sandbox writable roots must already be canonical physical paths." >&2
  exit 1
}
[[ "$WRITER_HOME" != "$WRITER_TMP" ]] || { echo "[BLOCK] HOME and TMP roots must be distinct." >&2; exit 1; }

if [[ -n "$WRITABLE_FILE" ]]; then
  [[ "$WRITABLE_FILE" == /* ]] || { echo '[BLOCK] Exact writable file must be absolute.' >&2; exit 1; }
  [[ -f "$WRITABLE_FILE" && ! -L "$WRITABLE_FILE" ]] || { echo '[BLOCK] Exact writable file must be an existing regular non-symlink file.' >&2; exit 1; }
  WRITABLE_PHYSICAL="$(readlink -f -- "$WRITABLE_FILE")"
  [[ "$WRITABLE_PHYSICAL" == "$WRITABLE_FILE" ]] || { echo '[BLOCK] Exact writable file must already be canonical.' >&2; exit 1; }
  [[ "$(stat -c '%u:%g' "$WRITABLE_FILE")" == "$WRITER_UID:$WRITER_GID" ]] || { echo '[BLOCK] Exact writable file ownership mismatch.' >&2; exit 1; }
  [[ "$(stat -c '%h' "$WRITABLE_FILE")" == '1' ]] || { echo '[BLOCK] Exact writable file must have one hard link.' >&2; exit 1; }

  WRITABLE_PARENT="$(dirname -- "$WRITABLE_FILE")"
  PARENT_PHYSICAL="$(readlink -f -- "$WRITABLE_PARENT")"
  [[ "$PARENT_PHYSICAL" == "$WRITABLE_PARENT" ]] || { echo '[BLOCK] Exact writable file parent must be canonical.' >&2; exit 1; }
  PARENT_UID="$(stat -c '%u' "$WRITABLE_PARENT")"
  PARENT_GID="$(stat -c '%g' "$WRITABLE_PARENT")"
  PARENT_MODE="$(stat -c '%a' "$WRITABLE_PARENT")"
  PARENT_MODE_DEC=$((8#$PARENT_MODE))
  if (( (PARENT_UID == WRITER_UID && (PARENT_MODE_DEC & 0200) != 0) ||
        (PARENT_GID == WRITER_GID && (PARENT_MODE_DEC & 0020) != 0) ||
        ((PARENT_MODE_DEC & 0002) != 0) )); then
    echo '[BLOCK] Exact writable file parent is writer-writable.' >&2
    exit 1
  fi
fi

export MK_SANDBOX_USER="$WRITER_USER"
export MK_SANDBOX_UID="$WRITER_UID"
export MK_SANDBOX_GID="$WRITER_GID"
export MK_SANDBOX_HOME="$WRITER_HOME"
export MK_SANDBOX_TMP="$WRITER_TMP"
export MK_SANDBOX_WRITABLE_FILE="$WRITABLE_FILE"

unshare \
  --mount \
  --pid \
  --fork \
  --mount-proc \
  --net \
  --ipc \
  --uts \
  --kill-child=KILL \
  /bin/bash -s -- "$@" <<'INNER'
set -euo pipefail

mount --make-rprivate /

# Freeze every inherited VFS mount in this private mount namespace with the
# mount_setattr(2) recursive attribute API. linux-amd64 syscall number 442 is
# mount_setattr; any unsupported kernel/API or permission error blocks launch.
python3 - <<'PY'
import ctypes
import os

SYS_mount_setattr = 442  # x86_64
AT_FDCWD = -100
AT_RECURSIVE = 0x8000
MOUNT_ATTR_RDONLY = 0x00000001

class MountAttr(ctypes.Structure):
    _fields_ = [
        ("attr_set", ctypes.c_uint64),
        ("attr_clr", ctypes.c_uint64),
        ("propagation", ctypes.c_uint64),
        ("userns_fd", ctypes.c_uint64),
    ]

libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long
attr = MountAttr(MOUNT_ATTR_RDONLY, 0, 0, 0)
rc = libc.syscall(
    SYS_mount_setattr,
    AT_FDCWD,
    ctypes.c_char_p(b"/"),
    AT_RECURSIVE,
    ctypes.byref(attr),
    ctypes.sizeof(attr),
)
if rc != 0:
    err = ctypes.get_errno()
    raise SystemExit(f"[BLOCK] recursive mount_setattr(MOUNT_ATTR_RDONLY) failed: errno={err} {os.strerror(err)}")
PY

# Prove there is no inherited read-write mount left before exposing controlled
# writable overlays. Field 6 in mountinfo is the per-mount VFS option set.
if awk '$6 ~ /(^|,)rw(,|$)/ { print "[BLOCK] Inherited writable mount: " $5 " options=" $6 > "/dev/stderr"; bad=1 } END { exit bad ? 0 : 1 }' /proc/self/mountinfo; then
  exit 1
fi

# Hide host runtime sockets and shared temporary state from the tool principal.
mount -t tmpfs -o nodev,nosuid,noexec,mode=0555,size=4m tmpfs /run
mount -t tmpfs -o nodev,nosuid,noexec,mode=0700,uid="$MK_SANDBOX_UID",gid="$MK_SANDBOX_GID",size=16m tmpfs /tmp
mount -t tmpfs -o nodev,nosuid,noexec,mode=0700,uid="$MK_SANDBOX_UID",gid="$MK_SANDBOX_GID",size=16m tmpfs /dev/shm
mount -t tmpfs -o nodev,nosuid,noexec,mode=0700,uid="$MK_SANDBOX_UID",gid="$MK_SANDBOX_GID",size=16m tmpfs "$MK_SANDBOX_HOME"
mount -t tmpfs -o nodev,nosuid,noexec,mode=0700,uid="$MK_SANDBOX_UID",gid="$MK_SANDBOX_GID",size=16m tmpfs "$MK_SANDBOX_TMP"

# Qualification may expose exactly one pre-existing file as writable. Parent
# directories remain on the recursively read-only tree, so rename/create and
# sibling writes remain impossible. The writable VFS exception exists only in
# this mount namespace and disappears when the sandbox exits.
if [[ -n "$MK_SANDBOX_WRITABLE_FILE" ]]; then
  mount --bind "$MK_SANDBOX_WRITABLE_FILE" "$MK_SANDBOX_WRITABLE_FILE"
  python3 - "$MK_SANDBOX_WRITABLE_FILE" <<'PY'
import ctypes
import os
import sys

SYS_mount_setattr = 442
AT_FDCWD = -100
MOUNT_ATTR_RDONLY = 0x00000001

class MountAttr(ctypes.Structure):
    _fields_ = [
        ("attr_set", ctypes.c_uint64),
        ("attr_clr", ctypes.c_uint64),
        ("propagation", ctypes.c_uint64),
        ("userns_fd", ctypes.c_uint64),
    ]

libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long
path = os.fsencode(sys.argv[1])
attr = MountAttr(0, MOUNT_ATTR_RDONLY, 0, 0)
rc = libc.syscall(
    SYS_mount_setattr,
    AT_FDCWD,
    ctypes.c_char_p(path),
    0,
    ctypes.byref(attr),
    ctypes.sizeof(attr),
)
if rc != 0:
    err = ctypes.get_errno()
    raise SystemExit(f"[BLOCK] exact-file writable mount_setattr failed: errno={err} {os.strerror(err)}")
PY

  FILE_VFS_OPTIONS="$(findmnt -n -T "$MK_SANDBOX_WRITABLE_FILE" -o VFS-OPTIONS | head -n 1)"
  [[ ",$FILE_VFS_OPTIONS," == *,rw,* ]] || { echo '[BLOCK] Exact writable file did not become a writable VFS mount.' >&2; exit 1; }
  PARENT_VFS_OPTIONS="$(findmnt -n -T "$(dirname -- "$MK_SANDBOX_WRITABLE_FILE")" -o VFS-OPTIONS | head -n 1)"
  [[ ",$PARENT_VFS_OPTIONS," == *,ro,* ]] || { echo '[BLOCK] Exact writable file parent is not read-only in sandbox.' >&2; exit 1; }
fi

exec setpriv \
  --reuid="$MK_SANDBOX_UID" \
  --regid="$MK_SANDBOX_GID" \
  --clear-groups \
  --no-new-privs \
  --bounding-set=-all \
  --inh-caps=-all \
  --ambient-caps=-all \
  env -i \
    HOME="$MK_SANDBOX_HOME" \
    TMPDIR="$MK_SANDBOX_TMP" \
    PATH=/usr/bin:/bin \
    MK_WRITER_SANDBOX=1 \
    "$@"
INNER
