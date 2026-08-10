#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" || "$(id -u)" -ne 0 ]]; then
  echo '[BLOCK] Composed fake canary requires Linux x86_64 root supervisor.' >&2
  exit 1
fi

for cmd in git useradd userdel runuser id stat sha256sum python3 pgrep pkill; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[BLOCK] Missing command: $cmd" >&2; exit 1; }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_SOURCE="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
SANDBOX_RUNNER="$SCRIPT_DIR/writer-sandbox-exec.sh"
LOCK_PATH="$REPO_SOURCE/registry/codex-linux-lock.json"
[[ -f "$SANDBOX_RUNNER" && -f "$LOCK_PATH" ]] || { echo '[BLOCK] Composed canary prerequisites missing.' >&2; exit 1; }

mapfile -t LOCK_VALUES < <(python3 - "$LOCK_PATH" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
assert p['schema'] == 1
assert p['codex_version'] == '0.146.0'
assert p['installation']['root'] == '/opt/mk-spacecraft/runtime/codex/0.146.0'
assert p['installation']['entrypoint'] == 'bin/codex'
assert p['expected_version_output'] == 'codex-cli 0.146.0'
print(p['installation']['root'])
print(p['installation']['entrypoint'])
print(p['expected_version_output'])
PY
)
INSTALL_ROOT="${LOCK_VALUES[0]}"
ENTRY_REL="${LOCK_VALUES[1]}"
EXPECTED_VERSION="${LOCK_VALUES[2]}"
CODEX_ENTRY="$INSTALL_ROOT/$ENTRY_REL"
[[ -f "$CODEX_ENTRY" && -x "$CODEX_ENTRY" && ! -L "$CODEX_ENTRY" ]] || { echo '[BLOCK] Pinned Codex runtime is not installed.' >&2; exit 1; }
[[ "$(stat -c '%u:%g' "$CODEX_ENTRY")" == '0:0' ]] || { echo '[BLOCK] Pinned Codex entrypoint is not supervisor-owned.' >&2; exit 1; }

RUN_TOKEN="$$-$RANDOM-$(date +%s)"
CONTROLLER_USER="mk-controller-q-${RUN_TOKEN: -8}"
WRITER_USER="mk-writer-q-${RUN_TOKEN: -8}"
STATE_PARENT="/var/lib/mk-spacecraft"
mkdir -p "$STATE_PARENT"
chown root:root "$STATE_PARENT"
chmod 0755 "$STATE_PARENT"
ROOT_DIR="$(mktemp -d "$STATE_PARENT/composed-canary.XXXXXX")"
AUTH_ROOT="$ROOT_DIR/controller-auth"
CONTROL_ROOT="$ROOT_DIR/control"
REPO_ROOT="$ROOT_DIR/repo"
HOME_ROOT="$ROOT_DIR/home"
TMP_ROOT="$ROOT_DIR/tmp"
TARGET_REL="qualification/agent-canary/writer-output.txt"
TARGET="$REPO_ROOT/$TARGET_REL"
SIBLING="$REPO_ROOT/qualification/agent-canary/forbidden.txt"
CONTROL_MARKER="$CONTROL_ROOT/runtime.marker"
SECRET_FILE="$AUTH_ROOT/auth.canary"
SOCKET_PATH="$AUTH_ROOT/controller.sock"
PID_FILE="$AUTH_ROOT/controller.pid"
PROBE="$ROOT_DIR/composed-probe.sh"
SECRET_VALUE="MK_FAKE_COMPOSED_AUTH_$RANDOM"
CONTROLLER_PID=""
CONTROLLER_LAUNCH_PID=""
WRITER_UID=""
WRITER_GID=""

cleanup() {
  local original_rc=$?
  local cleanup_failed=0
  trap - EXIT INT TERM
  set +e

  if [[ -n "$CONTROLLER_PID" ]]; then
    kill "$CONTROLLER_PID" >/dev/null 2>&1 || true
    sleep 0.1
    kill -KILL "$CONTROLLER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$CONTROLLER_LAUNCH_PID" ]]; then
    kill "$CONTROLLER_LAUNCH_PID" >/dev/null 2>&1 || true
    wait "$CONTROLLER_LAUNCH_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WRITER_UID" ]] && pgrep -u "$WRITER_UID" >/dev/null 2>&1; then
    pkill -KILL -u "$WRITER_UID" >/dev/null 2>&1 || true
    sleep 0.1
  fi

  if id "$WRITER_USER" >/dev/null 2>&1; then userdel "$WRITER_USER" >/dev/null 2>&1 || cleanup_failed=1; fi
  if id "$CONTROLLER_USER" >/dev/null 2>&1; then userdel "$CONTROLLER_USER" >/dev/null 2>&1 || cleanup_failed=1; fi

  chmod -R u+rwX "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1
  rm -rf --one-file-system "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1

  id "$WRITER_USER" >/dev/null 2>&1 && cleanup_failed=1
  id "$CONTROLLER_USER" >/dev/null 2>&1 && cleanup_failed=1
  [[ ! -e "$ROOT_DIR" ]] || cleanup_failed=1
  if [[ "$cleanup_failed" -ne 0 ]]; then
    echo '[BLOCK] Composed fake canary cleanup left residue.' >&2
    exit 1
  fi
  exit "$original_rc"
}
trap cleanup EXIT INT TERM

useradd --system --no-create-home --shell /usr/sbin/nologin "$CONTROLLER_USER"
useradd --system --no-create-home --shell /usr/sbin/nologin "$WRITER_USER"
CONTROLLER_UID="$(id -u "$CONTROLLER_USER")"
CONTROLLER_GID="$(id -g "$CONTROLLER_USER")"
WRITER_UID="$(id -u "$WRITER_USER")"
WRITER_GID="$(id -g "$WRITER_USER")"
[[ "$CONTROLLER_UID" -ne 0 && "$WRITER_UID" -ne 0 && "$CONTROLLER_UID" -ne "$WRITER_UID" ]] || { echo '[BLOCK] Distinct non-root principals are required.' >&2; exit 1; }

chown root:root "$ROOT_DIR"
chmod 0711 "$ROOT_DIR"
mkdir -p "$AUTH_ROOT" "$CONTROL_ROOT" "$REPO_ROOT/qualification/agent-canary" "$HOME_ROOT" "$TMP_ROOT"

printf '%s\n' "$SECRET_VALUE" > "$SECRET_FILE"
chown "$CONTROLLER_UID:$CONTROLLER_GID" "$AUTH_ROOT" "$SECRET_FILE"
chmod 0700 "$AUTH_ROOT"
chmod 0400 "$SECRET_FILE"
printf '%s\n' 'ROOT_OWNED_CONTROL_PLANE' > "$CONTROL_MARKER"
printf '%s\n' 'MK_WRITER_CANARY=UNTOUCHED' > "$TARGET"

# Build the disposable repository before locking its administration surface.
git -C "$REPO_ROOT" init -q
git -C "$REPO_ROOT" config user.name 'MK Composed Qualification'
git -C "$REPO_ROOT" config user.email 'composed-qualification@invalid.local'
git -C "$REPO_ROOT" add -- "$TARGET_REL"
git -C "$REPO_ROOT" commit -qm 'composed qualification baseline'
BASE_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)"
[[ -z "$(git -C "$REPO_ROOT" remote)" ]] || { echo '[BLOCK] Disposable repository unexpectedly has a remote.' >&2; exit 1; }

chown -R root:root "$CONTROL_ROOT" "$REPO_ROOT"
chmod -R a-w "$CONTROL_ROOT" "$REPO_ROOT"
chmod -R a+rX "$CONTROL_ROOT" "$REPO_ROOT"
chown "$WRITER_UID:$WRITER_GID" "$TARGET"
chmod 0644 "$TARGET"
chown "$WRITER_UID:$WRITER_GID" "$HOME_ROOT" "$TMP_ROOT"
chmod 0700 "$HOME_ROOT" "$TMP_ROOT"

CONTROL_HASH_BEFORE="$(sha256sum "$CONTROL_MARKER" | awk '{print $1}')"
GIT_CONFIG_HASH_BEFORE="$(sha256sum "$REPO_ROOT/.git/config" | awk '{print $1}')"
TARGET_LINKS_BEFORE="$(stat -c '%h' "$TARGET")"

cat > "$PROBE" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
SIBLING="$2"
REPO_ROOT="$3"
CONTROL_MARKER="$4"
SECRET_FILE="$5"
CONTROLLER_PID="$6"
SOCKET_PATH="$7"
CODEX_ENTRY="$8"
EXPECTED_VERSION="$9"
EXPECTED_UID="${10}"
TARGET_REL="${11}"

[[ "$(id -u)" == "$EXPECTED_UID" ]] || { echo '[FAIL] Composed probe is not running as writer principal.' >&2; exit 1; }
[[ "${MK_WRITER_SANDBOX:-}" == '1' ]] || { echo '[FAIL] Sandbox marker missing.' >&2; exit 1; }

ACTUAL_VERSION="$("$CODEX_ENTRY" --version 2>&1 | tr -d '\r' | head -n 1)"
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || { echo "[FAIL] Pinned Codex version mismatch: $ACTUAL_VERSION" >&2; exit 1; }

if cat "$SECRET_FILE" >/dev/null 2>&1; then echo '[FAIL] Writer read controller secret.' >&2; exit 1; fi
if env | grep -Eq '^(OPENAI_API_KEY|CODEX_API_KEY|CODEX_ACCESS_TOKEN|GH_TOKEN|GITHUB_TOKEN|SSH_AUTH_SOCK)='; then echo '[FAIL] Credential variable reached writer environment.' >&2; exit 1; fi
[[ ! -e "/proc/$CONTROLLER_PID" ]] || { echo '[FAIL] Controller process visible in writer PID namespace.' >&2; exit 1; }

python3 - "$SOCKET_PATH" <<'PY'
import socket, sys
s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(sys.argv[1])
except OSError:
    raise SystemExit(0)
raise SystemExit('[FAIL] Writer connected to controller socket.')
PY

python3 - <<'PY'
import socket
names={name for _, name in socket.if_nameindex()}
if names - {'lo'}:
    raise SystemExit(f'[FAIL] Network namespace exposed interfaces: {sorted(names)}')
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.5)
try:
    s.connect(('1.1.1.1', 443))
except OSError:
    pass
else:
    raise SystemExit('[FAIL] Writer obtained outbound network access.')
PY

printf '%s\n' 'MK_WRITER_CANARY_OK' > "$TARGET"
[[ "$(cat "$TARGET")" == 'MK_WRITER_CANARY_OK' ]] || { echo '[FAIL] Exact canary write failed.' >&2; exit 1; }

if printf x > "$SIBLING" 2>/dev/null; then echo '[FAIL] Sibling creation succeeded.' >&2; exit 1; fi
if printf '\nmalicious=true\n' >> "$REPO_ROOT/.git/config" 2>/dev/null; then echo '[FAIL] Git admin mutation succeeded.' >&2; exit 1; fi
if printf pwned > "$CONTROL_MARKER" 2>/dev/null; then echo '[FAIL] Control-plane mutation succeeded.' >&2; exit 1; fi
if mv "$TARGET" "$TARGET.tmp" 2>/dev/null; then echo '[FAIL] Canary rename succeeded.' >&2; exit 1; fi
if rm -f "$TARGET" 2>/dev/null && ln -s /etc/passwd "$TARGET" 2>/dev/null; then echo '[FAIL] Canary replacement succeeded.' >&2; exit 1; fi
if git -c "safe.directory=$REPO_ROOT" -C "$REPO_ROOT" add -- "$TARGET_REL" >/dev/null 2>&1; then echo '[FAIL] Git staging succeeded.' >&2; exit 1; fi

printf '%s\n' home-ok > "$HOME/composed-state"
printf '%s\n' tmp-ok > "$TMPDIR/composed-state"
echo '[PASS] Composed fake writer performed only the exact canary mutation.'
PROBE
chown root:root "$PROBE"
chmod 0555 "$PROBE"

# Keep fake credential-bearing controller alive concurrently with the exact writer launch path.
runuser -u "$CONTROLLER_USER" -- env -i \
  HOME="$AUTH_ROOT" \
  OPENAI_API_KEY="$SECRET_VALUE" \
  PATH=/usr/bin:/bin \
  python3 - "$SECRET_FILE" "$SOCKET_PATH" "$PID_FILE" <<'PY' &
import os, socket, sys, time
secret_path, socket_path, pid_path = sys.argv[1:]
secret = open(secret_path, 'rb', buffering=0)
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(socket_path)
os.chmod(socket_path, 0o600)
sock.listen(1)
with open(pid_path, 'w', encoding='ascii') as handle:
    handle.write(str(os.getpid()))
while True:
    time.sleep(1)
PY
CONTROLLER_LAUNCH_PID=$!
for _ in $(seq 1 50); do [[ -s "$PID_FILE" && -S "$SOCKET_PATH" ]] && break; sleep 0.1; done
[[ -s "$PID_FILE" && -S "$SOCKET_PATH" ]] || { echo '[BLOCK] Fake controller did not become ready.' >&2; exit 1; }
CONTROLLER_PID="$(cat "$PID_FILE")"
kill -0 "$CONTROLLER_PID" >/dev/null 2>&1 || { echo '[BLOCK] Fake controller is not alive.' >&2; exit 1; }

bash "$SANDBOX_RUNNER" \
  --user "$WRITER_USER" \
  --home "$HOME_ROOT" \
  --tmp "$TMP_ROOT" \
  --writable-file "$TARGET" \
  -- "$PROBE" "$TARGET" "$SIBLING" "$REPO_ROOT" "$CONTROL_MARKER" "$SECRET_FILE" "$CONTROLLER_PID" "$SOCKET_PATH" "$CODEX_ENTRY" "$EXPECTED_VERSION" "$WRITER_UID" "$TARGET_REL"

[[ "$(cat "$TARGET")" == 'MK_WRITER_CANARY_OK' ]] || { echo '[FAIL] Final canary content is wrong.' >&2; exit 1; }
[[ ! -e "$SIBLING" ]] || { echo '[FAIL] Forbidden sibling escaped sandbox.' >&2; exit 1; }
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$BASE_HEAD" ]] || { echo '[FAIL] Disposable repository HEAD changed.' >&2; exit 1; }
STATUS="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
[[ "$STATUS" == " M $TARGET_REL" ]] || { echo "[FAIL] Unexpected repository mutation set: $STATUS" >&2; exit 1; }
[[ "$(sha256sum "$CONTROL_MARKER" | awk '{print $1}')" == "$CONTROL_HASH_BEFORE" ]] || { echo '[FAIL] Control plane changed.' >&2; exit 1; }
[[ "$(sha256sum "$REPO_ROOT/.git/config" | awk '{print $1}')" == "$GIT_CONFIG_HASH_BEFORE" ]] || { echo '[FAIL] Git administration changed.' >&2; exit 1; }
[[ "$TARGET_LINKS_BEFORE" == '1' && "$(stat -c '%h' "$TARGET")" == '1' ]] || { echo '[FAIL] Canary link count changed.' >&2; exit 1; }
[[ -z "$(git -C "$REPO_ROOT" remote)" ]] || { echo '[FAIL] Disposable repository gained a remote.' >&2; exit 1; }

printf '%s\n' \
  '[PASS] Composed fake end-to-end writer qualification held.' \
  "Codex runtime  : $EXPECTED_VERSION" \
  'Controller auth: concurrent fake secret / hidden from writer' \
  'Repository     : disposable / no remote' \
  'Git admin      : supervisor-owned / unchanged' \
  "Allowed write  : $TARGET_REL" \
  'Sibling/control/stage/replace: BLOCKED' \
  'Network/PID/IPC: isolated' \
  'Real AI prompt : NOT EXECUTED' \
  'Project writer : STILL DISABLED'
