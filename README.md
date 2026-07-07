# daemonless porting toolkit

Shared Claude Code configuration for porting upstream apps to FreeBSD daemonless OCI images.

**Testing the toolkit itself:** see [TESTING.md](TESTING.md) — the weak-model test protocol (can Sonnet complete a port on these docs alone?).

## What's in here

| Path | Purpose |
|---|---|
| `.claude/skills/port-package/` | Full porting workflow: research, scaffold, build, CIT + smoke, harden, audit, PR |
| `.claude/skills/bump-upstream/` | Bump a pinned upstream version and re-validate |
| `.claude/agents/` | Subagents: upstream research, stubborn-error deep-dives, pre-PR port audit (provenance gate) |
| `.claude/hooks/` | Guardrails: block Containerfile edits, block foreground builds, auto-journal every command, warn on README rewrites, enforce CIT before PR |
| `.claude/reference/` | Cookbook (error-signature-keyed fixes) and CIT log capture guide |
| `templates/` | BUILD-NOTES, PR body (provenance + viva), PROCESS-LOG, PORT-BRIEF, smoke-test, and per-image CLAUDE.md templates |
| `scripts/` | `build.sh` (the only sanctioned build entry), `cit-with-logs.sh` (CIT + smoke + log capture), `lint-compose.sh` (metadata + quality floors), `pre-push.git-hook` (agent-agnostic CIT rail) |
| `install.sh` | Copy toolkit files into an image repo (also installs the git pre-push rail) |

## Usage

### Install into a new image repo

```sh
# From the image repo root:
/path/to/porting-toolkit/install.sh

# Or with an env var:
TOOLKIT=/path/to/porting-toolkit $TOOLKIT/install.sh
```

This copies `.claude/`, `templates/`, and `scripts/` into the image repo. The cookbook is copied (not symlinked) so it's available offline. After a port, PR any new cookbook entries back to this repo.

### Refresh an existing image repo

```sh
/path/to/porting-toolkit/install.sh --refresh
```

Overwrites `.claude/` with the latest toolkit versions. Preserves any local files not managed by the toolkit (e.g. image-specific hooks).

### Port a new app

```sh
cd /path/to/image-repo
claude
# then: /port-package <upstream-repo-url>
```

### Bump an upstream version

```sh
cd /path/to/image-repo
claude
# then: /bump-upstream
```

## Cookbook workflow

The cookbook (`.claude/reference/freebsd-porting-cookbook.md`) becomes more valuable over time as a reference that grows with every port:

1. During a port, the skill appends new error-signature entries to the local copy
2. After the port ships, PR those entries back to this toolkit repo
3. Next `install.sh --refresh` distributes them to all image repos

This is what makes the Nth port fast.
