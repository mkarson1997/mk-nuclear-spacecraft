# MK Cloud Workspace Policy

## Architecture

GitHub is the canonical source of truth.

The development machine is replaceable infrastructure, not the source of truth.

## Access model

Primary IDE:
VS Code only.

Primary operation:
terminal-first.

Remote access:
private network only whenever practical.

Planned persistent access layer:
Tailscale.

## Development modes

### Local client

Office PC and laptop are development clients.

### GitHub Codespaces

Used for:

- browser access
- quick fixes
- temporary development
- emergency access

It is not the only persistent engine.

### MK DevCloud

Planned persistent Linux development environment.

Expected capabilities:

- Git
- GitHub CLI
- Docker
- project runtimes
- coding agents
- tmux
- testing
- development services

## Persistent sessions

tmux will preserve long-running terminal sessions.

## Rebuildability

Every project should eventually describe its environment as code.

Examples:

- devcontainers
- Docker Compose
- setup scripts
- verify scripts
- documented runtime versions

## Secrets

Never synchronize secret files through chat applications or source control.

## Production separation

MK DevCloud is not a production server.

Production credentials and production write access remain separately controlled.
