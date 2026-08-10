# MK App Factory Core v2

The App Factory inspects an existing repository before generating or changing application code.

## Qualified core flow

```text
project
  ↓
detect_project.py          # stdout only, no writes, no Git execution
  ↓
stack tags + native scripts + lockfiles + recommended skills
  ↓
bootstrap_project.py       # plan by default
  ↓
.mk-spacecraft/project.json  # exclusive create only with --apply
```

## Safety defaults

- no framework reinitialization;
- no dependency installation;
- no skill publication;
- no autonomous project writer;
- no production write;
- no production secrets;
- detector has no file-output option;
- bootstrap never executes or inspects target repository Git configuration;
- Git cleanliness is explicitly reported as not inspected by this bootstrap layer;
- an existing project manifest is never overwritten;
- `.mk-spacecraft` must be a physical directory, not a symlink.

A later trusted control-plane layer is responsible for Git cleanliness and authorization before committing generated governance state.

## Detection profiles

Profiles are composable. A repository can be tagged with several capabilities at once:

- Flutter/mobile
- Next.js/React/Node
- Python/FastAPI/Django
- containers
- Cloudflare
- Supabase/Postgres
- GitHub Actions

The detector reports candidate native verification commands but never executes them.

## Next layer

After trusted Skills publication and command hooks are independently qualified, App Factory onboarding can compose:

1. this fail-closed project manifest,
2. reviewed canonical skills,
3. client-specific guard adapters,
4. stack-specific CI templates,
5. security posture and release gates.

Until then, App Factory Core remains an inspect, plan, and isolated-manifest foundation only.
