#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DETECT = ROOT / "scripts" / "factory" / "detect_project.py"
BOOTSTRAP = ROOT / "scripts" / "factory" / "bootstrap_project.py"


def run(args: list[str], expected: int = 0) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != expected:
        raise SystemExit(
            f"command failed expected={expected} actual={proc.returncode}\n"
            f"{' '.join(args)}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc


def json_prefix(output: str, marker: str) -> dict:
    return json.loads(output.split(marker, 1)[0])


def make_fixture(project: Path) -> Path:
    (project / "package.json").write_text(
        json.dumps({
            "scripts": {"test": "echo test", "lint": "echo lint", "build": "echo build"},
            "dependencies": {"next": "16.0.0", "react": "19.0.0"},
        }) + "\n",
        encoding="utf-8",
    )
    (project / "package-lock.json").write_text("{}\n", encoding="utf-8")
    (project / "wrangler.toml").write_text("name = 'fixture'\n", encoding="utf-8")
    (project / ".github" / "workflows").mkdir(parents=True)
    (project / ".github" / "workflows" / "ci.yml").write_text("name: ci\n", encoding="utf-8")

    marker = project / "FS_MONITOR_EXECUTED"
    monitor = project / "evil-fsmonitor.sh"
    monitor.write_text(f"#!/bin/sh\nprintf pwned > '{marker}'\nexit 0\n", encoding="utf-8")
    monitor.chmod(0o755)
    git_dir = project / ".git"
    git_dir.mkdir()
    (git_dir / "config").write_text(
        "[core]\n"
        f"\tfsmonitor = {monitor}\n"
        "[filter \"evil\"]\n"
        f"\tclean = {monitor}\n",
        encoding="utf-8",
    )
    return marker


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="mk-factory-") as tmp:
        base = Path(tmp)
        project = base / "sample"
        project.mkdir()
        execution_marker = make_fixture(project)

        detected = json_prefix(run([sys.executable, str(DETECT), str(project)]).stdout, "\n[PASS]")
        expected_tags = {"nextjs", "node", "cloudflare", "github-actions"}
        if not expected_tags.issubset(set(detected["tags"])):
            raise SystemExit(f"missing tags: {sorted(expected_tags - set(detected['tags']))}")
        if detected["lockfiles"] != ["package-lock.json"]:
            raise SystemExit(f"unexpected lockfiles: {detected['lockfiles']}")
        if execution_marker.exists():
            raise SystemExit("read-only detector executed repository-controlled Git configuration")

        unsupported = run([sys.executable, str(DETECT), str(project), "--json-out", str(project / "package.json")], expected=2)
        if "unrecognized arguments" not in unsupported.stderr.lower():
            raise SystemExit("detector unexpectedly retained a file-output mutation option")
        original_package = (project / "package.json").read_text(encoding="utf-8")

        plan = run([sys.executable, str(BOOTSTRAP), str(project)]).stdout
        manifest_plan = json_prefix(plan, "\n[PLAN]")
        if manifest_plan["execution"] != {
            "autonomous_project_writer_enabled": False,
            "production_write_enabled": False,
            "production_secrets_allowed": False,
        }:
            raise SystemExit("bootstrap planning lost fail-closed execution state")
        if manifest_plan["skills"]["publication_enabled"] is not False:
            raise SystemExit("bootstrap planning enabled skill publication")
        if manifest_plan["security"]["target_git_config_execution_allowed"] is not False:
            raise SystemExit("bootstrap planning permits target Git config execution")
        if (project / ".mk-spacecraft").exists() or execution_marker.exists():
            raise SystemExit("bootstrap planning mode mutated or executed target repository")

        run([sys.executable, str(BOOTSTRAP), str(project), "--apply"])
        manifest_path = project / ".mk-spacecraft" / "project.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest["project"]["git_cleanliness"] != "not-inspected-by-bootstrap":
            raise SystemExit("bootstrap falsely claimed Git cleanliness")
        if execution_marker.exists():
            raise SystemExit("bootstrap executed repository-controlled Git configuration")
        if (project / "package.json").read_text(encoding="utf-8") != original_package:
            raise SystemExit("detector/bootstrap overwrote an existing user file")

        second = run([sys.executable, str(BOOTSTRAP), str(project), "--apply"], expected=1)
        if "already exists" not in (second.stdout + second.stderr).lower():
            raise SystemExit("repeat bootstrap did not fail closed on existing manifest")

        alias_project = base / "alias-project"
        alias_project.mkdir()
        external = base / "external-state"
        external.mkdir()
        try:
            os.symlink(external, alias_project / ".mk-spacecraft", target_is_directory=True)
        except (OSError, NotImplementedError):
            pass
        else:
            alias = run([sys.executable, str(BOOTSTRAP), str(alias_project), "--apply"], expected=1)
            if "physical directory" not in (alias.stdout + alias.stderr).lower():
                raise SystemExit("state-directory symlink was not rejected")

    print("[PASS] MK App Factory Core offline adversarial qualification passed.")


if __name__ == "__main__":
    main()
