#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[BLOCK] Writer Isolation v1 boundary test requires Linux." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[BLOCK] Run the boundary test as root so ownership can form the security boundary." >&2
  exit 1
fi

for cmd in git runuser useradd userdel stat find sha256sum pgrep pkill; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[BLOCK] Required command missing: $cmd" >&2
    exit 1
  }
done

RUN_ID="$(date +%s)-$$-$RANDOM"
WRITER_USER="mk-writer-q-${RUN_ID: -8}"
ROOT_DIR="$(mktemp -d /tmp/mk-writer-isolation-v1.XXXXXX)"
CONTROL_ROOT="$ROOT_DIR/control"
REPO_ROOT="$ROOT_DIR/repo"
HOME_ROOT="$ROOT_DIR/home"
TMP_ROOT="$ROOT_DIR/tmp"
TARGET_REL="qualification/agent-canary/writer-output.txt"
TARGET="$REPO_ROOT/$TARGET_REL"
SIBLING="$REPO_ROOT/qualification/agent-canary/forbidden.txt"
WRITER_UID=""
WRITER_GID=""

cleanup() {
  local original_status=$?
  trap - EXIT INT TERM
  set +e
  set +u
  local cleanup_failed=0

  if [[ -n "${WRITER_UID:-}" ]] && pgrep -u "$WRITER_UID" >/dev/null 2>&1; then
    echo "[FAIL] Writer process residue detected during cleanup." >&2
    cleanup_failed=1
    pkill -KILL -u "$WRITER_UID" >/dev/null 2>&1 || true
    sleep 0.2
  fi

  if id "$WRITER_USER" >/dev/null 2>&1; then
    if ! userdel "$WRITER_USER" >/dev/null 2>&1; then
      echo "[FAIL] Failed to delete disposable writer principal: $WRITER_USER" >&2
      cleanup_failed=1
    fi
  fi
  if id "$WRITER_USER" >/dev/null 2>&1; then
    echo "[FAIL] Disposable writer principal still exists after cleanup: $WRITER_USER" >&2
    cleanup_failed=1
  fi

  if [[ -e "$ROOT_DIR" ]]; then
    chmod -R u+rwX "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1
    rm -rf --one-file-system "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1
  fi
  if [[ -e "$ROOT_DIR" ]]; then
    echo "[FAIL] Disposable filesystem residue remains: $ROOT_DIR" >&2
    cleanup_failed=1
  fi

  if [[ "$cleanup_failed" -ne 0 ]]; then
    echo "[FAIL] Writer Isolation cleanup was not residue-free." >&2
    exit 1
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

useradd --system --no-create-home --shell /usr/sbin/nologin "$WRITER_USER"
WRITER_UID="$(id -u "$WRITER_USER")"
WRITER_GID="$(id -g "$WRITER_USER")"

mkdir -p "$CONTROL_ROOT" "$REPO_ROOT/qualification/agent-canary" "$HOME_ROOT" "$TMP_ROOT"
printf '%s\n' 'ROOT_OWNED_CONTROL_PLANE' > "$CONTROL_ROOT/runtime.marker"
printf '%s\n' 'MK_WRITER_CANARY=UNTOUCHED' > "$TARGET"

# mktemp creates the run root as 0700. The writer needs traversal only, never
# write ownership, so expose traversal/read access while keeping root ownership.
chown root:root "$ROOT_DIR"
chmod 0755 "$ROOT_DIR"

# Build an independent disposable repository while the supervisor owns all Git metadata.
git -C "$REPO_ROOT" init -q
git -C "$REPO_ROOT" config user.name 'MK Isolation Gate'
git -C "$REPO_ROOT" config user.email 'isolation-gate@invalid.local'
git -C "$REPO_ROOT" add -- "$TARGET_REL"
git -C "$REPO_ROOT" commit -qm 'qualification baseline'
BASE_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)"

chown -R root:root "$CONTROL_ROOT" "$REPO_ROOT"
chmod -R a-w "$CONTROL_ROOT" "$REPO_ROOT"
chmod -R a+rX "$CONTROL_ROOT" "$REPO_ROOT"

# Only the existing canary file is writable by the writer principal. Its parent stays root-owned/non-writable.
chown "$WRITER_UID:$WRITER_GID" "$TARGET"
chmod 0644 "$TARGET"
chown -R "$WRITER_UID:$WRITER_GID" "$HOME_ROOT" "$TMP_ROOT"
chmod 0700 "$HOME_ROOT" "$TMP_ROOT"

run_writer() {
  runuser -u "$WRITER_USER" -- env -i \
    HOME="$HOME_ROOT" \
    TMPDIR="$TMP_ROOT" \
    PATH="/usr/bin:/bin" \
    "$@"
}

expect_writer_failure() {
  local label="$1"
  shift
  if run_writer "$@" >/dev/null 2>&1; then
    echo "[FAIL] $label unexpectedly succeeded." >&2
    exit 1
  fi
  echo "[PASS] $label blocked."
}

CONTROL_HASH_BEFORE="$(sha256sum "$CONTROL_ROOT/runtime.marker" | awk '{print $1}')"
GIT_CONFIG_HASH_BEFORE="$(sha256sum "$REPO_ROOT/.git/config" | awk '{print $1}')"
TARGET_LINKS_BEFORE="$(stat -c '%h' "$TARGET")"

# Positive capability: exactly the existing allowlisted file is writable.
run_writer /bin/bash -c 'printf "%s\n" "MK_WRITER_CANARY_OK" > "$1"' _ "$TARGET"
[[ "$(cat "$TARGET")" == "MK_WRITER_CANARY_OK" ]] || {
  echo "[FAIL] Writer could not perform the exact allowed write." >&2
  exit 1
}
echo "[PASS] Exact canary file write allowed."

# Negative capabilities: directory creation, Git administration, control-plane mutation and target replacement must fail.
expect_writer_failure 'Sibling file creation' /bin/bash -c 'printf x > "$1"' _ "$SIBLING"
expect_writer_failure 'Git config mutation' /bin/bash -c 'printf "\nmalicious=true\n" >> "$1"' _ "$REPO_ROOT/.git/config"
expect_writer_failure 'Control-plane mutation' /bin/bash -c 'printf pwned > "$1"' _ "$CONTROL_ROOT/runtime.marker"
expect_writer_failure 'Target rename' /bin/mv "$TARGET" "$TARGET.tmp"
expect_writer_failure 'Target symlink replacement' /bin/bash -c 'rm -f "$1" && ln -s /etc/passwd "$1"' _ "$TARGET"
expect_writer_failure 'Git staging' /usr/bin/git -c "safe.directory=$REPO_ROOT" -C "$REPO_ROOT" add -- "$TARGET_REL"

if command -v sudo >/dev/null 2>&1; then
  expect_writer_failure 'Privilege escalation through sudo' /usr/bin/sudo -n true
fi

[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$BASE_HEAD" ]] || {
  echo "[FAIL] Disposable repository HEAD changed." >&2
  exit 1
}

STATUS="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
EXPECTED_STATUS=" M $TARGET_REL"
[[ "$STATUS" == "$EXPECTED_STATUS" ]] || {
  echo "[FAIL] Unexpected repository mutation set: $STATUS" >&2
  exit 1
}

[[ "$(sha256sum "$CONTROL_ROOT/runtime.marker" | awk '{print $1}')" == "$CONTROL_HASH_BEFORE" ]] || {
  echo "[FAIL] Root-owned control plane changed." >&2
  exit 1
}
[[ "$(sha256sum "$REPO_ROOT/.git/config" | awk '{print $1}')" == "$GIT_CONFIG_HASH_BEFORE" ]] || {
  echo "[FAIL] Root-owned Git administration changed." >&2
  exit 1
}

TARGET_LINKS_AFTER="$(stat -c '%h' "$TARGET")"
[[ "$TARGET_LINKS_BEFORE" == "1" && "$TARGET_LINKS_AFTER" == "1" ]] || {
  echo "[FAIL] Canary target link count changed." >&2
  exit 1
}

if find "$REPO_ROOT" -xdev -type d \( -perm -0002 -o -perm -0020 \) -print -quit | grep -q .; then
  echo "[FAIL] Disposable repository contains writer-creatable directories." >&2
  exit 1
fi

WRITER_REPO_OWNERSHIP="$(find "$REPO_ROOT" -xdev -user "$WRITER_UID" ! -path "$TARGET" -print -quit)"
[[ -z "$WRITER_REPO_OWNERSHIP" ]] || {
  echo "[FAIL] Writer owns repository objects outside the canary target: $WRITER_REPO_OWNERSHIP" >&2
  exit 1
}

# Disposable writable roots are intentionally separate from the repository and control plane.
run_writer /bin/bash -c 'printf home > "$HOME/allowed-home-state"; printf temp > "$TMPDIR/allowed-temp-state"'
[[ -f "$HOME_ROOT/allowed-home-state" && -f "$TMP_ROOT/allowed-temp-state" ]] || {
  echo "[FAIL] Disposable HOME/TMP contract is broken." >&2
  exit 1
}

echo
printf '%s\n' \
  '[PASS] Writer Isolation v1 adversarial boundary held.' \
  "Supervisor UID : $(id -u)" \
  "Writer UID     : $WRITER_UID" \
  'Control plane  : root-owned / writer read-only' \
  'Git admin      : root-owned / writer read-only' \
  "Allowed write  : $TARGET_REL" \
  'Sibling create : BLOCKED' \
  'Stage/commit   : BLOCKED by Git admin ownership' \
  'Privilege      : separate non-root principal' \
  'HOME/TMP       : disposable writer-owned roots' \
  'Cleanup        : verified residue-free or gate fails closed'
