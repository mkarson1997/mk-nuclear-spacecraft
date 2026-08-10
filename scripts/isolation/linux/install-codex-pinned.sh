#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[BLOCK] Pinned Codex installer requires Linux." >&2
  exit 1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "[BLOCK] Pinned Codex installer requires x86_64." >&2
  exit 1
fi
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[BLOCK] Run as root so the runtime remains supervisor-owned." >&2
  exit 1
fi

for cmd in python3 curl sha256sum tar stat mv; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[BLOCK] Missing required command: $cmd" >&2; exit 1; }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
LOCK_PATH="$REPO_ROOT/registry/codex-linux-lock.json"
TREE_TOOL="$SCRIPT_DIR/runtime-tree-manifest.py"
[[ -f "$LOCK_PATH" && -f "$TREE_TOOL" ]] || { echo '[BLOCK] Installer trust files are missing.' >&2; exit 1; }

APPROVED_VERSION='0.146.0'
APPROVED_VERSION_OUTPUT='codex-cli 0.146.0'
APPROVED_TAG='rust-v0.146.0'
APPROVED_ROOT='/opt/mk-spacecraft/runtime/codex/0.146.0'
APPROVED_ENTRY='bin/codex'
APPROVED_PACKAGE='codex-package-x86_64-unknown-linux-musl.tar.gz'
APPROVED_PACKAGE_SHA='3c89125af1d7c98abec8beb551292ef99daca52e204e5852a9139feae2c467e5'
APPROVED_SUMS='codex-package_SHA256SUMS'
APPROVED_SUMS_SHA='e6b6a3f937c9cab532f25cca6d81529b44f122f028182b9715038bf15f94b105'
APPROVED_PACKAGE_URL="https://releases.openai.com/codex/releases/$APPROVED_VERSION/$APPROVED_PACKAGE"
APPROVED_SUMS_URL="https://releases.openai.com/codex/releases/$APPROVED_VERSION/$APPROVED_SUMS"
APPROVED_OPENAI_METADATA="https://releases.openai.com/codex/releases/$APPROVED_VERSION/release.json"
APPROVED_GITHUB_METADATA="https://api.github.com/repos/openai/codex/releases/tags/$APPROVED_TAG"

mapfile -t LOCK_VALUES < <(python3 - "$LOCK_PATH" <<'PY'
import json, pathlib, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
assert p['schema'] == 1
assert p['lock_version'] == '1.1.0'
assert p['platform'] == 'linux-amd64'
assert p['architecture'] == 'x86_64'
assert p['installation']['mutable_latest_forbidden'] is True
assert p['installation']['verify_version_only_as_unprivileged_probe'] is True
assert p['installation']['publish_no_target_directory'] is True
assert p['installation']['full_tree_manifest_required'] is True
entry=pathlib.PurePosixPath(p['installation']['entrypoint'])
assert not entry.is_absolute()
assert entry.parts and all(x not in ('', '.', '..') for x in entry.parts)
for value in (
    p['codex_version'], p['expected_version_output'], p['release_tag'],
    p['package']['asset'], p['package']['url'], p['package']['sha256'],
    p['checksum_manifest']['asset'], p['checksum_manifest']['url'], p['checksum_manifest']['sha256'],
    p['publisher_metadata']['openai_release_url'], p['publisher_metadata']['github_release_api_url'],
    str(p['publisher_metadata']['require_both_sources']).lower(),
    str(p['publisher_metadata']['require_asset_digest_match']).lower(),
    p['installation']['root'], p['installation']['entrypoint']
): print(value)
PY
)

VERSION="${LOCK_VALUES[0]}"
EXPECTED_VERSION="${LOCK_VALUES[1]}"
RELEASE_TAG="${LOCK_VALUES[2]}"
PACKAGE_ASSET="${LOCK_VALUES[3]}"
PACKAGE_URL="${LOCK_VALUES[4]}"
PACKAGE_SHA="${LOCK_VALUES[5]}"
SUMS_ASSET="${LOCK_VALUES[6]}"
SUMS_URL="${LOCK_VALUES[7]}"
SUMS_SHA="${LOCK_VALUES[8]}"
OPENAI_METADATA_URL="${LOCK_VALUES[9]}"
GITHUB_METADATA_URL="${LOCK_VALUES[10]}"
REQUIRE_BOTH="${LOCK_VALUES[11]}"
REQUIRE_DIGEST="${LOCK_VALUES[12]}"
INSTALL_ROOT="${LOCK_VALUES[13]}"
ENTRY_REL="${LOCK_VALUES[14]}"

[[ "$VERSION" == "$APPROVED_VERSION" && "$EXPECTED_VERSION" == "$APPROVED_VERSION_OUTPUT" && "$RELEASE_TAG" == "$APPROVED_TAG" ]] || { echo '[BLOCK] Lock version/tag changed from the independently approved constants.' >&2; exit 1; }
[[ "$PACKAGE_ASSET" == "$APPROVED_PACKAGE" && "$PACKAGE_URL" == "$APPROVED_PACKAGE_URL" && "$PACKAGE_SHA" == "$APPROVED_PACKAGE_SHA" ]] || { echo '[BLOCK] Package lock changed from approved constants.' >&2; exit 1; }
[[ "$SUMS_ASSET" == "$APPROVED_SUMS" && "$SUMS_URL" == "$APPROVED_SUMS_URL" && "$SUMS_SHA" == "$APPROVED_SUMS_SHA" ]] || { echo '[BLOCK] Checksum lock changed from approved constants.' >&2; exit 1; }
[[ "$OPENAI_METADATA_URL" == "$APPROVED_OPENAI_METADATA" && "$GITHUB_METADATA_URL" == "$APPROVED_GITHUB_METADATA" && "$REQUIRE_BOTH" == true && "$REQUIRE_DIGEST" == true ]] || { echo '[BLOCK] Publisher metadata trust policy changed.' >&2; exit 1; }
[[ "$INSTALL_ROOT" == "$APPROVED_ROOT" && "$ENTRY_REL" == "$APPROVED_ENTRY" ]] || { echo '[BLOCK] Installation root/entrypoint changed from approved constants.' >&2; exit 1; }
[[ "$PACKAGE_SHA" =~ ^[0-9a-f]{64}$ && "$SUMS_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo '[BLOCK] Invalid SHA-256 lock value.' >&2; exit 1; }

assert_no_symlink_ancestors() {
  python3 - "$1" <<'PY'
import os, pathlib, stat, sys
p=pathlib.PurePosixPath(sys.argv[1])
if not p.is_absolute(): raise SystemExit('[BLOCK] Managed path must be absolute.')
cur=pathlib.Path('/')
for part in p.parts[1:]:
    cur=cur/part
    if os.path.lexists(cur):
        st=os.lstat(cur)
        if stat.S_ISLNK(st.st_mode): raise SystemExit(f'[BLOCK] Managed path has symlink ancestor: {cur}')
        if cur != pathlib.Path(sys.argv[1]) and not stat.S_ISDIR(st.st_mode):
            raise SystemExit(f'[BLOCK] Managed path ancestor is not a directory: {cur}')
PY
}

RUNTIME_PARENT="$(dirname -- "$INSTALL_ROOT")"
assert_no_symlink_ancestors "$RUNTIME_PARENT"
mkdir -p "$RUNTIME_PARENT"
assert_no_symlink_ancestors "$RUNTIME_PARENT"
chown root:root "$RUNTIME_PARENT"
chmod 0755 "$RUNTIME_PARENT"

if [[ -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ]]; then
  echo "[BLOCK] Runtime version path already exists or is symlinked: $INSTALL_ROOT" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d /tmp/mk-codex-install.XXXXXX)"
STAGING="$RUNTIME_PARENT/.staging-$VERSION-$$-$RANDOM"
PACKAGE_FILE="$TMP_ROOT/$PACKAGE_ASSET"
SUMS_FILE="$TMP_ROOT/$SUMS_ASSET"
OPENAI_METADATA_FILE="$TMP_ROOT/openai-release.json"
GITHUB_METADATA_FILE="$TMP_ROOT/github-release.json"
PUBLISHED=0

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  set +e
  rm -rf --one-file-system "$TMP_ROOT" >/dev/null 2>&1 || true
  rm -rf --one-file-system "$STAGING" >/dev/null 2>&1 || true
  if [[ "$PUBLISHED" -eq 1 && ( -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ) ]]; then
    chmod -R u+rwX "$INSTALL_ROOT" >/dev/null 2>&1 || true
    rm -rf --one-file-system "$INSTALL_ROOT" >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$PACKAGE_URL" -o "$PACKAGE_FILE"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$SUMS_URL" -o "$SUMS_FILE"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$OPENAI_METADATA_URL" -o "$OPENAI_METADATA_FILE"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 -H 'Accept: application/vnd.github+json' -H 'User-Agent: MK-Spacecraft-Qualification' "$GITHUB_METADATA_URL" -o "$GITHUB_METADATA_FILE"

ACTUAL_PACKAGE_SHA="$(sha256sum "$PACKAGE_FILE" | awk '{print $1}')"
ACTUAL_SUMS_SHA="$(sha256sum "$SUMS_FILE" | awk '{print $1}')"
[[ "$ACTUAL_PACKAGE_SHA" == "$PACKAGE_SHA" ]] || { echo '[BLOCK] Codex package digest mismatch.' >&2; exit 1; }
[[ "$ACTUAL_SUMS_SHA" == "$SUMS_SHA" ]] || { echo '[BLOCK] Codex checksum-manifest digest mismatch.' >&2; exit 1; }
MANIFEST_PACKAGE_SHA="$(awk -v asset="$PACKAGE_ASSET" '$2 == asset {print $1; exit}' "$SUMS_FILE")"
[[ "$MANIFEST_PACKAGE_SHA" == "$PACKAGE_SHA" ]] || { echo '[BLOCK] Checksum manifest disagrees with package lock.' >&2; exit 1; }

python3 - "$OPENAI_METADATA_FILE" "$GITHUB_METADATA_FILE" "$RELEASE_TAG" "$PACKAGE_ASSET" "$PACKAGE_SHA" "$SUMS_ASSET" "$SUMS_SHA" <<'PY'
import json, sys
openai_path, github_path, tag, package, package_sha, sums, sums_sha = sys.argv[1:]
for label, path in [('OpenAI releases', openai_path), ('GitHub release API', github_path)]:
    data=json.load(open(path, encoding='utf-8'))
    if data.get('tag_name') != tag:
        raise SystemExit(f'[BLOCK] {label} tag mismatch.')
    assets={a.get('name'): a.get('digest') for a in data.get('assets', [])}
    expected={package: 'sha256:'+package_sha, sums: 'sha256:'+sums_sha}
    for name, digest in expected.items():
        if assets.get(name) != digest:
            raise SystemExit(f'[BLOCK] {label} digest mismatch for {name}: {assets.get(name)!r}')
print('[PASS] Two independent publisher metadata surfaces agree with the pinned asset digests.')
PY

python3 - "$PACKAGE_FILE" <<'PY'
import pathlib, tarfile, sys
archive=sys.argv[1]
with tarfile.open(archive, 'r:gz') as tf:
    for m in tf.getmembers():
        p=pathlib.PurePosixPath(m.name)
        if p.is_absolute() or not p.parts or any(x in ('', '.', '..') for x in p.parts):
            raise SystemExit(f'[BLOCK] Unsafe archive path: {m.name}')
        if m.issym() or m.islnk() or m.isdev() or m.isfifo() or not (m.isdir() or m.isfile()):
            raise SystemExit(f'[BLOCK] Unsafe archive object type: {m.name}')
print('[PASS] Archive contains only normalized regular files/directories; aliases and special files are absent.')
PY

mkdir "$STAGING"
tar -xzf "$PACKAGE_FILE" -C "$STAGING" --no-same-owner --no-same-permissions
ENTRYPOINT="$STAGING/$ENTRY_REL"
[[ -f "$ENTRYPOINT" && -x "$ENTRYPOINT" && ! -L "$ENTRYPOINT" ]] || { echo '[BLOCK] Expected Codex entrypoint missing or aliased after extraction.' >&2; exit 1; }
ENTRY_PHYSICAL="$(python3 - "$ENTRYPOINT" "$STAGING" <<'PY'
import pathlib, sys
entry=pathlib.Path(sys.argv[1]).resolve(strict=True)
root=pathlib.Path(sys.argv[2]).resolve(strict=True)
try: entry.relative_to(root)
except ValueError: raise SystemExit('[BLOCK] Entrypoint escaped staging root.')
print(entry)
PY
)"
[[ "$ENTRY_PHYSICAL" == "$ENTRYPOINT" ]] || { echo '[BLOCK] Entrypoint physical path differs from canonical locked path.' >&2; exit 1; }

find "$STAGING" -xdev -exec chown root:root {} +
find "$STAGING" -xdev -type d -exec chmod 0555 {} +
find "$STAGING" -xdev -type f -exec chmod a-w {} +
chmod 0555 "$ENTRYPOINT"

BINARY_SHA="$(sha256sum "$ENTRYPOINT" | awk '{print $1}')"
printf '%s\n' \
  'schema=2' \
  "codex_version=$VERSION" \
  "package_asset=$PACKAGE_ASSET" \
  "package_sha256=$PACKAGE_SHA" \
  "checksum_manifest_sha256=$SUMS_SHA" \
  "publisher_metadata=openai+github" \
  "entrypoint=$ENTRY_REL" \
  "entrypoint_sha256=$BINARY_SHA" \
  > "$STAGING/mk-install-manifest.txt"
chown root:root "$STAGING/mk-install-manifest.txt"
chmod 0444 "$STAGING/mk-install-manifest.txt"

python3 "$TREE_TOOL" create "$STAGING" "$STAGING/mk-runtime-tree-manifest.json"
python3 "$TREE_TOOL" verify "$STAGING" "$STAGING/mk-runtime-tree-manifest.json"

assert_no_symlink_ancestors "$INSTALL_ROOT"
[[ ! -e "$INSTALL_ROOT" && ! -L "$INSTALL_ROOT" ]] || { echo '[BLOCK] Runtime destination appeared before publication.' >&2; exit 1; }
mv -T -- "$STAGING" "$INSTALL_ROOT"
PUBLISHED=1
assert_no_symlink_ancestors "$INSTALL_ROOT"
python3 "$TREE_TOOL" verify "$INSTALL_ROOT" "$INSTALL_ROOT/mk-runtime-tree-manifest.json"
[[ "$(stat -c '%u:%g' "$INSTALL_ROOT")" == '0:0' ]] || { echo '[BLOCK] Installed runtime root is not root-owned.' >&2; exit 1; }
[[ "$(stat -c '%u:%g' "$INSTALL_ROOT/$ENTRY_REL")" == '0:0' ]] || { echo '[BLOCK] Installed Codex entrypoint is not root-owned.' >&2; exit 1; }

# Installation never executes downloaded Codex code. Version execution is a
# separate unprivileged/no-network probe after immutable publication.
PUBLISHED=0
trap - EXIT INT TERM
rm -rf --one-file-system "$TMP_ROOT"

printf '%s\n' \
  '[PASS] Pinned Codex Linux runtime installed without root execution of downloaded code.' \
  "Version lock    : $EXPECTED_VERSION" \
  "Runtime root    : $INSTALL_ROOT" \
  "Package SHA     : $PACKAGE_SHA" \
  "Entrypoint SHA  : $BINARY_SHA" \
  'Publisher digest: OpenAI releases + GitHub release API matched' \
  'Runtime manifest: complete tree verified' \
  'Downloaded code : NOT EXECUTED by installer'
