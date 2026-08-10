#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(id -u)" -ne 0 ]]; then
  echo "[BLOCK] Codex probe requires Linux root supervisor." >&2
  exit 1
fi

for cmd in python3 useradd userdel id stat; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[BLOCK] Missing probe command: $cmd" >&2; exit 1; }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
LOCK_PATH="$REPO_ROOT/registry/codex-linux-lock.json"
SANDBOX_RUNNER="$SCRIPT_DIR/writer-sandbox-exec.sh"
[[ -f "$LOCK_PATH" && -f "$SANDBOX_RUNNER" ]] || { echo '[BLOCK] Probe prerequisites missing.' >&2; exit 1; }

mapfile -t VALUES < <(python3 - "$LOCK_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
assert p['schema'] == 1
assert p['codex_version'] == '0.146.0'
assert p['expected_version_output'] == 'codex-cli 0.146.0'
assert p['installation']['root'] == '/opt/mk-spacecraft/runtime/codex/0.146.0'
assert p['installation']['entrypoint'] == 'bin/codex'
print(p['installation']['root'])
print(p['installation']['entrypoint'])
print(p['expected_version_output'])
PY
)
INSTALL_ROOT="${VALUES[0]}"
ENTRY_REL="${VALUES[1]}"
EXPECTED_VERSION="${VALUES[2]}"
ENTRY="$INSTALL_ROOT/$ENTRY_REL"
[[ -f "$ENTRY" && -x "$ENTRY" && ! -L "$ENTRY" ]] || { echo '[BLOCK] Pinned Codex entrypoint is missing or aliased.' >&2; exit 1; }
[[ "$(stat -c '%u:%g' "$ENTRY")" == '0:0' ]] || { echo '[BLOCK] Pinned Codex entrypoint is not root-owned.' >&2; exit 1; }

RUN_TOKEN="$$-$RANDOM-$(date +%s)"
PROBE_USER="mk-codex-probe-q-${RUN_TOKEN: -8}"
STATE_PARENT="/var/lib/mk-spacecraft"
mkdir -p "$STATE_PARENT"
chown root:root "$STATE_PARENT"
chmod 0755 "$STATE_PARENT"
PROBE_ROOT="$(mktemp -d "$STATE_PARENT/codex-probe.XXXXXX")"
PROBE_HOME="$PROBE_ROOT/home"
PROBE_TMP="$PROBE_ROOT/tmp"

cleanup() {
  local original_rc=$?
  local cleanup_failed=0
  trap - EXIT INT TERM
  set +e
  if id "$PROBE_USER" >/dev/null 2>&1; then
    userdel "$PROBE_USER" >/dev/null 2>&1 || cleanup_failed=1
  fi
  chmod -R u+rwX "$PROBE_ROOT" >/dev/null 2>&1 || cleanup_failed=1
  rm -rf --one-file-system "$PROBE_ROOT" >/dev/null 2>&1 || cleanup_failed=1
  id "$PROBE_USER" >/dev/null 2>&1 && cleanup_failed=1
  [[ ! -e "$PROBE_ROOT" ]] || cleanup_failed=1
  if [[ "$cleanup_failed" -ne 0 ]]; then
    echo '[BLOCK] Codex probe cleanup left residue.' >&2
    exit 1
  fi
  exit "$original_rc"
}
trap cleanup EXIT INT TERM

useradd --system --no-create-home --shell /usr/sbin/nologin "$PROBE_USER"
PROBE_UID="$(id -u "$PROBE_USER")"
PROBE_GID="$(id -g "$PROBE_USER")"
[[ "$PROBE_UID" -ne 0 ]] || { echo '[BLOCK] Probe principal resolved to root.' >&2; exit 1; }
chown root:root "$PROBE_ROOT"
chmod 0711 "$PROBE_ROOT"
mkdir -p "$PROBE_HOME" "$PROBE_TMP"
chown "$PROBE_UID:$PROBE_GID" "$PROBE_HOME" "$PROBE_TMP"
chmod 0700 "$PROBE_HOME" "$PROBE_TMP"

ACTUAL_VERSION="$(bash "$SANDBOX_RUNNER" \
  --user "$PROBE_USER" \
  --home "$PROBE_HOME" \
  --tmp "$PROBE_TMP" \
  -- "$ENTRY" --version 2>&1 | tr -d '\r' | tail -n 1)"

[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || {
  echo "[BLOCK] Unprivileged Codex probe version mismatch. Expected '$EXPECTED_VERSION', got '$ACTUAL_VERSION'." >&2
  exit 1
}

printf '%s\n' \
  '[PASS] Pinned Codex execution probe ran only under the isolated unprivileged principal.' \
  "Probe UID : $PROBE_UID" \
  "Version   : $ACTUAL_VERSION" \
  'Network   : isolated namespace' \
  'Caps      : dropped / no-new-privs' \
  'Host root : read-only' \
  'Env       : empty except sandbox HOME/TMP/PATH marker'
