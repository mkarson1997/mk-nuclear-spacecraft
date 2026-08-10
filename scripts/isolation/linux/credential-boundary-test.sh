#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(id -u)" -ne 0 ]]; then
  echo "[BLOCK] Credential boundary test requires Linux root supervisor." >&2
  exit 1
fi

for cmd in useradd userdel runuser id stat sha256sum python3 timeout mount umount mountpoint; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[BLOCK] Required command missing: $cmd" >&2
    exit 1
  }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SANDBOX_RUNNER="$SCRIPT_DIR/writer-sandbox-exec.sh"
[[ -f "$SANDBOX_RUNNER" ]] || { echo "[BLOCK] Missing writer sandbox runner." >&2; exit 1; }

RUN_TOKEN="$$-$RANDOM-$(date +%s)"
CONTROLLER_USER="mk-controller-q-${RUN_TOKEN: -8}"
WRITER_USER="mk-writer-q-${RUN_TOKEN: -8}"
STATE_PARENT="/var/lib/mk-spacecraft"
mkdir -p "$STATE_PARENT"
chown root:root "$STATE_PARENT"
chmod 0755 "$STATE_PARENT"
ROOT_DIR="$(mktemp -d "$STATE_PARENT/credential-boundary.XXXXXX")"
AUTH_ROOT="$ROOT_DIR/controller-auth"
WRITER_HOME="$ROOT_DIR/writer-home"
WRITER_TMP="$ROOT_DIR/writer-tmp"
HOST_NESTED="$ROOT_DIR/host-writable-submount"
SECRET_FILE="$AUTH_ROOT/auth.canary"
SOCKET_PATH="$AUTH_ROOT/controller.sock"
PID_FILE="$AUTH_ROOT/controller.pid"
WRITER_PROBE="$ROOT_DIR/writer-probe.sh"
SECRET_VALUE="MK_FAKE_AUTH_DO_NOT_EXPOSE_$RANDOM"
CONTROLLER_PID=""
CONTROLLER_LAUNCH_PID=""

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

  if mountpoint -q "$HOST_NESTED" >/dev/null 2>&1; then
    umount "$HOST_NESTED" >/dev/null 2>&1 || cleanup_failed=1
  fi

  if id "$WRITER_USER" >/dev/null 2>&1; then
    userdel "$WRITER_USER" >/dev/null 2>&1 || cleanup_failed=1
  fi
  if id "$CONTROLLER_USER" >/dev/null 2>&1; then
    userdel "$CONTROLLER_USER" >/dev/null 2>&1 || cleanup_failed=1
  fi

  chmod -R u+rwX "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1
  rm -rf --one-file-system "$ROOT_DIR" >/dev/null 2>&1 || cleanup_failed=1

  id "$WRITER_USER" >/dev/null 2>&1 && cleanup_failed=1
  id "$CONTROLLER_USER" >/dev/null 2>&1 && cleanup_failed=1
  [[ ! -e "$ROOT_DIR" ]] || cleanup_failed=1

  if [[ "$cleanup_failed" -ne 0 ]]; then
    echo "[BLOCK] Credential-boundary cleanup left residue." >&2
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

[[ "$CONTROLLER_UID" -ne 0 && "$WRITER_UID" -ne 0 && "$CONTROLLER_UID" -ne "$WRITER_UID" ]] || {
  echo "[BLOCK] Controller and writer must be distinct non-root principals." >&2
  exit 1
}

chown root:root "$ROOT_DIR"
chmod 0711 "$ROOT_DIR"
mkdir -p "$AUTH_ROOT" "$WRITER_HOME" "$WRITER_TMP" "$HOST_NESTED"
chown "$CONTROLLER_UID:$CONTROLLER_GID" "$AUTH_ROOT"
chmod 0700 "$AUTH_ROOT"
printf '%s\n' "$SECRET_VALUE" > "$SECRET_FILE"
chown "$CONTROLLER_UID:$CONTROLLER_GID" "$SECRET_FILE"
chmod 0400 "$SECRET_FILE"
chown "$WRITER_UID:$WRITER_GID" "$WRITER_HOME" "$WRITER_TMP"
chmod 0700 "$WRITER_HOME" "$WRITER_TMP"

# Create an intentionally writable inherited host submount owned by the writer.
# A non-recursive read-only bind of / would leave this writable; the sandbox
# must freeze it recursively before the writer starts.
mount -t tmpfs -o rw,nodev,nosuid,noexec,size=4m tmpfs "$HOST_NESTED"
chown "$WRITER_UID:$WRITER_GID" "$HOST_NESTED"
chmod 0700 "$HOST_NESTED"
runuser -u "$WRITER_USER" -- env -i PATH=/usr/bin:/bin /bin/bash -c \
  'printf host-writable > "$1/pre-sandbox"; rm -f "$1/pre-sandbox"' _ "$HOST_NESTED"
echo "[PASS] Adversarial nested host submount is writable by the writer before isolation."

cat > "$WRITER_PROBE" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
SECRET_FILE="$1"
CONTROLLER_PID="$2"
SOCKET_PATH="$3"
EXPECTED_UID="$4"
HOST_NESTED="$5"

[[ "$(id -u)" == "$EXPECTED_UID" ]] || { echo '[FAIL] Sandbox did not drop to writer UID.' >&2; exit 1; }
[[ "${MK_WRITER_SANDBOX:-}" == "1" ]] || { echo '[FAIL] Sandbox marker missing.' >&2; exit 1; }

if cat "$SECRET_FILE" >/dev/null 2>&1; then
  echo '[FAIL] Writer read controller auth storage.' >&2
  exit 1
fi

if env | grep -Eq '^(OPENAI_API_KEY|CODEX_API_KEY|CODEX_ACCESS_TOKEN|GH_TOKEN|GITHUB_TOKEN|SSH_AUTH_SOCK)='; then
  echo '[FAIL] Sensitive credential variable reached writer environment.' >&2
  exit 1
fi

[[ ! -e "/proc/$CONTROLLER_PID" ]] || {
  echo '[FAIL] Controller process is visible inside writer PID namespace.' >&2
  exit 1
}
[[ ! -e "/proc/$CONTROLLER_PID/fd" ]] || {
  echo '[FAIL] Controller descriptors are visible inside writer PID namespace.' >&2
  exit 1
}

CAP_EFF="$(awk '/^CapEff:/ {print $2}' /proc/self/status)"
CAP_AMB="$(awk '/^CapAmb:/ {print $2}' /proc/self/status)"
NO_NEW_PRIVS="$(awk '/^NoNewPrivs:/ {print $2}' /proc/self/status)"
[[ "$CAP_EFF" == "0000000000000000" && "$CAP_AMB" == "0000000000000000" && "$NO_NEW_PRIVS" == "1" ]] || {
  echo "[FAIL] Writer retained capabilities or privilege gain: CapEff=$CAP_EFF CapAmb=$CAP_AMB NoNewPrivs=$NO_NEW_PRIVS" >&2
  exit 1
}

python3 - "$SOCKET_PATH" <<'PY'
import socket, sys
path=sys.argv[1]
s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(path)
except OSError:
    raise SystemExit(0)
raise SystemExit('[FAIL] Writer connected to controller Unix socket.')
PY

python3 - <<'PY'
import socket
names={name for _, name in socket.if_nameindex()}
if names - {'lo'}:
    raise SystemExit(f'[FAIL] Writer network namespace exposed interfaces: {sorted(names)}')
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(1.0)
try:
    s.connect(('1.1.1.1', 443))
except OSError:
    pass
else:
    raise SystemExit('[FAIL] Writer obtained outbound network access.')
PY

if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  echo '[FAIL] Writer escalated through sudo.' >&2
  exit 1
fi

for forbidden in /etc/mk-writer-escape /var/tmp/mk-writer-escape /run/mk-writer-escape; do
  if printf x > "$forbidden" 2>/dev/null; then
    echo "[FAIL] Writer wrote outside disposable roots: $forbidden" >&2
    exit 1
  fi
done

if printf x > "$HOST_NESTED/escape" 2>/dev/null; then
  echo '[FAIL] Writer modified an inherited writable host submount.' >&2
  exit 1
fi

echo '[PASS] Adversarial inherited host submount became read-only inside writer namespace.'

printf '%s\n' writer-home-ok > "$HOME/state"
printf '%s\n' writer-tmp-ok > "$TMPDIR/state"
printf '%s\n' private-tmp-ok > /tmp/mk-writer-private
printf '%s\n' private-shm-ok > /dev/shm/mk-writer-private

[[ "$(cat "$HOME/state")" == writer-home-ok && "$(cat "$TMPDIR/state")" == writer-tmp-ok ]] || {
  echo '[FAIL] Disposable HOME/TMP roots are unusable.' >&2
  exit 1
}

echo '[PASS] Writer mount/network/process sandbox blocked credential, process, IPC, network and privilege escape attempts.'
PROBE
chown root:root "$WRITER_PROBE"
chmod 0555 "$WRITER_PROBE"

# Keep a credential-bearing controller process alive concurrently. It retains the
# secret in its environment, an open descriptor and a private Unix socket.
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

for _ in $(seq 1 50); do
  [[ -s "$PID_FILE" && -S "$SOCKET_PATH" ]] && break
  sleep 0.1
done
[[ -s "$PID_FILE" && -S "$SOCKET_PATH" ]] || { echo '[BLOCK] Controller process did not become ready.' >&2; exit 1; }
CONTROLLER_PID="$(cat "$PID_FILE")"
kill -0 "$CONTROLLER_PID" >/dev/null 2>&1 || { echo '[BLOCK] Controller process is not alive.' >&2; exit 1; }

echo "[PASS] Credential-bearing controller is alive concurrently under a distinct principal."

bash "$SANDBOX_RUNNER" \
  --user "$WRITER_USER" \
  --home "$WRITER_HOME" \
  --tmp "$WRITER_TMP" \
  -- "$WRITER_PROBE" "$SECRET_FILE" "$CONTROLLER_PID" "$SOCKET_PATH" "$WRITER_UID" "$HOST_NESTED"

# Private /tmp and /dev/shm mounts must vanish with the namespace.
[[ ! -e /tmp/mk-writer-private && ! -e /dev/shm/mk-writer-private ]] || {
  echo '[FAIL] Writer temporary state escaped its mount namespace.' >&2
  exit 1
}
[[ ! -e "$HOST_NESTED/escape" ]] || {
  echo '[FAIL] Writer mutation escaped through inherited nested host submount.' >&2
  exit 1
}

[[ "$(stat -c '%u:%g:%a' "$SECRET_FILE")" == "$CONTROLLER_UID:$CONTROLLER_GID:400" ]] || {
  echo "[BLOCK] Auth canary ownership/mode changed." >&2
  exit 1
}
SECRET_HASH="$(sha256sum "$SECRET_FILE" | awk '{print $1}')"
[[ -n "$SECRET_HASH" ]] || { echo "[BLOCK] Could not hash auth canary." >&2; exit 1; }

echo
printf '%s\n' \
  "[PASS] Concurrent controller/writer credential boundary held." \
  "Controller UID : $CONTROLLER_UID" \
  "Writer UID     : $WRITER_UID" \
  "Controller auth: live env + open FD + Unix socket" \
  "Writer PID view: private" \
  "Writer IPC     : private" \
  "Writer network : isolated" \
  "Writer caps    : none / no-new-privs" \
  "Host /tmp/shm  : hidden by private tmpfs" \
  "Host submounts : recursively read-only" \
  "Root filesystem: recursively read-only to writer" \
  "Credential read: BLOCKED"
