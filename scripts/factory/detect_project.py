#!/usr/bin/env python3
"""Read-only project detector used by MK App Factory routing."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def exists_any(root: Path, names: list[str]) -> bool:
    return any((root / name).exists() for name in names)


def detect(root: Path) -> dict:
    if not root.is_dir():
        raise SystemExit(f"[BLOCK] Project root does not exist: {root}")

    package = read_json(root / "package.json") if (root / "package.json").is_file() else {}
    deps: dict[str, object] = {}
    for key in ("dependencies", "devDependencies", "peerDependencies"):
        value = package.get(key)
        if isinstance(value, dict):
            deps.update(value)
    scripts = package.get("scripts") if isinstance(package.get("scripts"), dict) else {}

    pubspec_text = (root / "pubspec.yaml").read_text(encoding="utf-8", errors="replace") if (root / "pubspec.yaml").is_file() else ""
    pyproject_text = (root / "pyproject.toml").read_text(encoding="utf-8", errors="replace").lower() if (root / "pyproject.toml").is_file() else ""
    requirements_text = (root / "requirements.txt").read_text(encoding="utf-8", errors="replace").lower() if (root / "requirements.txt").is_file() else ""
    python_deps = pyproject_text + "\n" + requirements_text

    tags: list[str] = []
    skills: set[str] = {"git-safe-workflow", "repo-audit", "test-strategy"}

    if (root / "pubspec.yaml").is_file() and ("flutter:" in pubspec_text or (root / "android").is_dir()):
        tags.append("flutter")
        skills.update({"flutter-architecture", "flutter-test", "mobile-api-security", "mobile-permissions-review"})

    if "next" in deps or exists_any(root, ["next.config.js", "next.config.mjs", "next.config.ts"]):
        tags.append("nextjs")
        skills.update({"nextjs-review", "react-review", "web-accessibility", "web-performance", "security-headers", "csp-review"})
    elif "react" in deps:
        tags.append("react")
        skills.update({"react-review", "web-accessibility", "web-performance"})

    if package:
        tags.append("node")
        skills.update({"dependency-audit", "secure-code-review"})

    if (root / "pyproject.toml").is_file() or (root / "requirements.txt").is_file():
        tags.append("python")
        skills.update({"dependency-audit", "secure-code-review"})
        if "fastapi" in python_deps:
            tags.append("fastapi")
            skills.update({"api-security-review", "auth-session-review"})
        if "django" in python_deps:
            tags.append("django")
            skills.update({"api-security-review", "auth-session-review"})

    if exists_any(root, ["Dockerfile", "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]):
        tags.append("container")
        skills.update({"docker-review", "docker-security", "deployment-review"})
    if exists_any(root, ["wrangler.toml", "wrangler.json", "wrangler.jsonc"]):
        tags.append("cloudflare")
        skills.update({"cloudflare-review", "deployment-review"})
    if (root / "supabase" / "config.toml").is_file():
        tags.append("supabase")
        skills.update({"supabase-review", "postgres-review", "database-migration-safety", "auth-session-review"})
    if (root / ".github" / "workflows").is_dir():
        tags.append("github-actions")
        skills.add("github-actions-review")

    verification: list[str] = []
    if package:
        for name in ("test", "lint", "typecheck", "check", "build"):
            if name in scripts:
                verification.append(f"npm run {name}")
    if "flutter" in tags:
        verification.extend(["flutter analyze", "flutter test"])
    if "python" in tags and ((root / "pytest.ini").exists() or "pytest" in python_deps or (root / "tests").is_dir()):
        verification.append("pytest")

    lockfiles = [name for name in (
        "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb",
        "pubspec.lock", "poetry.lock", "uv.lock", "Cargo.lock"
    ) if (root / name).is_file()]

    return {
        "schema": 1,
        "root": str(root.resolve()),
        "tags": sorted(set(tags)),
        "recommended_skills": sorted(skills),
        "existing_package_scripts": dict(sorted(scripts.items())) if scripts else {},
        "candidate_verification_commands": verification,
        "lockfiles": lockfiles,
        "has_git": (root / ".git").exists(),
        "has_agents_md": (root / "AGENTS.md").is_file(),
        "has_env_example": (root / ".env.example").is_file(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only MK App Factory project detection")
    parser.add_argument("root", nargs="?", default=".")
    args = parser.parse_args()
    result = detect(Path(args.root).resolve())
    print(json.dumps(result, indent=2, ensure_ascii=False))
    print("[PASS] MK App Factory project detection completed without writing files.")


if __name__ == "__main__":
    main()
