# MK Cloud Workspace / Remote Command Center

Target architecture:

GitHub
  |
  +-- Codespaces: temporary browser development
  |
  +-- MK DevCloud: persistent Linux development
         |
         +-- Tailscale private access
         +-- tmux persistent sessions
         +-- Docker / Dev Containers
         +-- coding agents
         +-- tests and development services

Clients:

- Office PC
- Laptop
- Phone

All clients reach the same GitHub-backed development environment.

Production remains separate.

Current status:

PLANNED.

No server is provisioned during the governance phase.
