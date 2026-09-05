#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-static}"
[[ "$MODE" == "static" || "$MODE" == "--installed" ]] || { echo "Usage: qualification-preflight.sh [--installed]" >&2; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
LOCK_PATH="$REPO_ROOT/registry/codex-linux-lock.json"
POLICY_PATH="$REPO_ROOT/registry/writer-qualification-v1.json"
ISOLATION_PATH="$REPO_ROOT/registry/writer-isolation-v1.json"
RULESET_PATH="$REPO_ROOT/policies/github/main-ruleset.json"
INSTALLER_PATH="$SCRIPT_DIR/install-codex-pinned.sh"
CREDENTIAL_TEST_PATH="$SCRIPT_DIR/credential-boundary-test.sh"
COMPOSED_TEST_PATH="$SCRIPT_DIR/composed-fake-canary-test.sh"
SANDBOX_PATH="$SCRIPT_DIR/writer-sandbox-exec.sh"
PROBE_PATH="$SCRIPT_DIR/probe-codex-pinned.sh"
TREE_TOOL="$SCRIPT_DIR/runtime-tree-manifest.py"

for path in "$LOCK_PATH" "$POLICY_PATH" "$ISOLATION_PATH" "$RULESET_PATH" "$INSTALLER_PATH" "$CREDENTIAL_TEST_PATH" "$COMPOSED_TEST_PATH" "$SANDBOX_PATH" "$PROBE_PATH" "$TREE_TOOL"; do
  [[ -f "$path" ]] || { echo "[BLOCK] Required qualification file missing: $path" >&2; exit 1; }
done
for cmd in python3 sha256sum stat; do command -v "$cmd" >/dev/null 2>&1 || { echo "[BLOCK] Missing command: $cmd" >&2; exit 1; }; done

mapfile -t VALUES < <(python3 - "$LOCK_PATH" "$POLICY_PATH" "$ISOLATION_PATH" "$RULESET_PATH" <<'PY'
import json, pathlib, sys
lock=json.load(open(sys.argv[1], encoding='utf-8'))
policy=json.load(open(sys.argv[2], encoding='utf-8'))
isolation=json.load(open(sys.argv[3], encoding='utf-8'))
ruleset=json.load(open(sys.argv[4], encoding='utf-8'))

assert lock['schema'] == 1
assert lock['lock_version'] == '1.1.0'
assert lock['platform'] == 'linux-amd64'
assert lock['architecture'] == 'x86_64'
assert lock['codex_version'] == '0.146.0'
assert lock['expected_version_output'] == 'codex-cli 0.146.0'
assert lock['release_tag'] == 'rust-v0.146.0'
assert lock['package']['asset'] == 'codex-package-x86_64-unknown-linux-musl.tar.gz'
assert lock['package']['sha256'] == '3c89125af1d7c98abec8beb551292ef99daca52e204e5852a9139feae2c467e5'
assert lock['checksum_manifest']['sha256'] == 'e6b6a3f937c9cab532f25cca6d81529b44f122f028182b9715038bf15f94b105'
assert lock['publisher_metadata']['openai_release_url'] == 'https://releases.openai.com/codex/releases/0.146.0/release.json'
assert lock['publisher_metadata']['github_release_api_url'] == 'https://api.github.com/repos/openai/codex/releases/tags/rust-v0.146.0'
assert lock['publisher_metadata']['require_both_sources'] is True
assert lock['publisher_metadata']['require_asset_digest_match'] is True
assert lock['installation']['root'] == '/opt/mk-spacecraft/runtime/codex/0.146.0'
assert lock['installation']['entrypoint'] == 'bin/codex'
assert lock['installation']['verify_version_only_as_unprivileged_probe'] is True
assert lock['installation']['publish_no_target_directory'] is True
assert lock['installation']['full_tree_manifest_required'] is True
entry=pathlib.PurePosixPath(lock['installation']['entrypoint'])
assert not entry.is_absolute() and entry.parts and all(x not in ('', '.', '..') for x in entry.parts)

assert policy['schema'] == 1
assert policy['policy_version'] == '1.3.0'
assert policy['status'] == 'preflight-only'
assert policy['project_writer_execution_enabled'] is False
assert policy['real_writer_canary_enabled'] is False
assert policy['requires']['required_main_checks'] == ['security-gate','spacecraft-trust-gate','writer-isolation-gate','writer-qualification-gate']
assert policy['credential_boundary']['status'] == 'not-yet-qualified'
assert policy['credential_boundary']['strategy'] == 'separate-controller-from-writer'
assert policy['credential_boundary']['writer_must_not_read_codex_auth_storage'] is True
assert policy['credential_boundary']['concurrent_controller_required'] is True
assert policy['credential_boundary']['private_pid_namespace'] is True
assert policy['credential_boundary']['private_network_namespace'] is True
assert policy['credential_boundary']['private_ipc_namespace'] is True
assert policy['credential_boundary']['controller_socket_must_be_unreachable'] is True
assert policy['credential_boundary']['first_real_canary_blocked_until_credential_boundary_passes'] is True
assert policy['writer_environment']['sandbox_runner'] == 'scripts/isolation/linux/writer-sandbox-exec.sh'
assert policy['writer_environment']['root_filesystem_read_only'] is True
assert policy['writer_environment']['inherited_mounts_read_only_recursive'] is True
assert policy['writer_environment']['sandbox_fails_if_recursive_mount_attributes_unavailable'] is True
assert policy['writer_environment']['capabilities_dropped'] is True
assert policy['writer_environment']['no_new_privileges'] is True
assert policy['writer_environment']['private_host_tmp'] is True
assert policy['writer_environment']['private_dev_shm'] is True
assert policy['canary']['composed_fake_end_to_end_required_before_real_canary'] is True
assert policy['merge_controls']['required_check_integration_id'] == 15368
assert policy['merge_controls']['committed_ruleset_must_preserve_app_binding'] is True
assert policy['merge_controls']['security_control_approval_gate_status'] == 'activation-required-not-preflight-merge-required'
assert policy['activation']['requires_composed_fake_end_to_end_gate'] is True
assert policy['activation']['requires_independent_review'] is True
assert policy['activation']['requires_zero_critical_high_blockers'] is True
assert policy['activation']['project_execution_must_remain_disabled'] is True

assert isolation['schema'] == 1
assert isolation['policy_version'] == '1.0.0'
assert isolation['project_writer_execution_enabled'] is False
assert isolation['writer_qualification_enabled'] is False
assert isolation['execution_model'] == 'separate-principal-disposable'

checks=[]
for rule in ruleset['rules']:
    if rule.get('type') == 'required_status_checks':
        checks.extend((x['context'], x.get('integration_id')) for x in rule['parameters']['required_status_checks'])
assert sorted(checks) == [
    ('security-gate', 15368),
    ('spacecraft-trust-gate', 4571234),
    ('writer-isolation-gate', 15368),
    ('writer-qualification-gate', 15368),
]

print(lock['installation']['root'])
print(lock['installation']['entrypoint'])
print(lock['expected_version_output'])
print(lock['package']['sha256'])
print(lock['checksum_manifest']['sha256'])
PY
)

INSTALL_ROOT="${VALUES[0]}"
ENTRY_REL="${VALUES[1]}"
EXPECTED_VERSION="${VALUES[2]}"
PACKAGE_SHA="${VALUES[3]}"
SUMS_SHA="${VALUES[4]}"

if grep -Eq 'curl[^\n|]*\|[[:space:]]*(ba)?sh|wget[^\n|]*\|[[:space:]]*(ba)?sh' "$INSTALLER_PATH"; then echo '[BLOCK] Pipe-to-shell installer pattern detected.' >&2; exit 1; fi
if grep -Eq 'releases/(latest|stable)|/latest/' "$INSTALLER_PATH" "$LOCK_PATH"; then echo '[BLOCK] Mutable latest release reference detected.' >&2; exit 1; fi
if grep -Eq '\$ENTRYPOINT[" ]+--version|\$ENTRY[" ]+--version' "$INSTALLER_PATH"; then echo '[BLOCK] Installer may not execute downloaded Codex code.' >&2; exit 1; fi
if ! grep -Fq 'SYS_mount_setattr = 442' "$SANDBOX_PATH" || ! grep -Fq 'AT_RECURSIVE = 0x8000' "$SANDBOX_PATH" || ! grep -Fq 'MOUNT_ATTR_RDONLY' "$SANDBOX_PATH"; then echo '[BLOCK] Writer sandbox lacks recursive mount_setattr read-only enforcement.' >&2; exit 1; fi
if ! grep -Fq 'Inherited writable mount' "$SANDBOX_PATH"; then echo '[BLOCK] Writer sandbox lacks fail-closed writable mount audit.' >&2; exit 1; fi
if ! grep -Fq -- '--writable-file' "$SANDBOX_PATH" || ! grep -Fq 'exact-file writable mount_setattr' "$SANDBOX_PATH"; then echo '[BLOCK] Writer sandbox lacks exact-file-only writable qualification support.' >&2; exit 1; fi
if ! grep -Fq 'host-writable-submount' "$CREDENTIAL_TEST_PATH"; then echo '[BLOCK] Credential boundary lacks nested writable host submount adversarial test.' >&2; exit 1; fi
if ! grep -Fq 'Composed fake end-to-end writer qualification held' "$COMPOSED_TEST_PATH" || ! grep -Fq -- '--writable-file "$TARGET"' "$COMPOSED_TEST_PATH"; then echo '[BLOCK] Composed fake canary test is incomplete.' >&2; exit 1; fi

echo '[PASS] Writer Qualification v1 remains preflight-only.'
echo '[PASS] Codex lock has exact version, path, dual publisher digest and immutable-tree requirements.'
echo '[PASS] GitHub policy model preserves four app-bound required checks: three from GitHub Actions and the operator-approved trust gate.'
echo '[PASS] Controller/writer policy requires private PID/network/IPC namespaces and the reusable sandbox runner.'
echo '[PASS] Writer sandbox recursively freezes inherited mounts with mount_setattr and tests an adversarial writable nested submount.'
echo '[PASS] Exact-file-only writable exception and composed fake end-to-end canary are statically required.'
echo '[PASS] First real writer canary remains blocked pending credential-boundary activation and independent review.'

if [[ "$MODE" == '--installed' ]]; then
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo '[BLOCK] Installed runtime validation requires Linux x86_64.' >&2; exit 1; }
  [[ -d "$INSTALL_ROOT" && ! -L "$INSTALL_ROOT" ]] || { echo "[BLOCK] Pinned runtime missing or aliased: $INSTALL_ROOT" >&2; exit 1; }
  ENTRY="$INSTALL_ROOT/$ENTRY_REL"
  MANIFEST="$INSTALL_ROOT/mk-install-manifest.txt"
  TREE_MANIFEST="$INSTALL_ROOT/mk-runtime-tree-manifest.json"
  [[ -f "$ENTRY" && -x "$ENTRY" && ! -L "$ENTRY" && -f "$MANIFEST" && -f "$TREE_MANIFEST" ]] || { echo '[BLOCK] Installed runtime is incomplete or aliased.' >&2; exit 1; }
  python3 "$TREE_TOOL" verify "$INSTALL_ROOT" "$TREE_MANIFEST"
  grep -Fxq "package_sha256=$PACKAGE_SHA" "$MANIFEST" || { echo '[BLOCK] Install manifest package digest mismatch.' >&2; exit 1; }
  grep -Fxq "checksum_manifest_sha256=$SUMS_SHA" "$MANIFEST" || { echo '[BLOCK] Install manifest checksum digest mismatch.' >&2; exit 1; }
  grep -Fxq 'publisher_metadata=openai+github' "$MANIFEST" || { echo '[BLOCK] Install manifest publisher trust marker missing.' >&2; exit 1; }
  RECORDED_BINARY_SHA="$(awk -F= '$1 == "entrypoint_sha256" {print $2; exit}' "$MANIFEST")"
  ACTUAL_BINARY_SHA="$(sha256sum "$ENTRY" | awk '{print $1}')"
  [[ "$RECORDED_BINARY_SHA" =~ ^[0-9a-f]{64}$ && "$ACTUAL_BINARY_SHA" == "$RECORDED_BINARY_SHA" ]] || { echo '[BLOCK] Installed Codex entrypoint digest changed.' >&2; exit 1; }
  echo '[PASS] Installed pinned Codex runtime tree validated without root execution.'
  echo "[PASS] Expected version remains locked for unprivileged probe only: $EXPECTED_VERSION"
fi

printf '%s\n' \
  'Qualification status : PREFLIGHT ONLY' \
  'Codex root execution : BLOCKED' \
  'Real writer canary   : BLOCKED' \
  'Project execution    : BLOCKED'
