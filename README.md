# daemonless porting toolkit

Shared Claude Code configuration for porting upstream apps to FreeBSD daemonless OCI images.

## What's in here

| Path | Purpose |
|---|---|
| `.claude/skills/port-package/` | Full porting workflow: research, scaffold, build, CIT, harden, PR |
| `.claude/skills/bump-upstream/` | Bump a pinned upstream version and re-validate |
| `.claude/agents/` | Subagents for upstream research and stubborn-error deep-dives |
| `.claude/hooks/` | Guardrails: block Containerfile edits, warn on README rewrites, enforce CIT before PR |
| `.claude/reference/` | Cookbook (error-signature-keyed fixes) and CIT log capture guide |
| `templates/` | BUILD-NOTES, PR body, PROCESS-LOG, and per-image CLAUDE.md templates |
| `scripts/` | `cit-with-logs.sh` (automated log capture), `lint-compose.sh` (metadata cross-check) |
| `install.sh` | Copy toolkit files into an image repo |

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

The cookbook (`.claude/reference/freebsd-porting-cookbook.md`) is the crown jewel. It grows with every port:

1. During a port, the skill appends new error-signature entries to the local copy
2. After the port ships, PR those entries back to this toolkit repo
3. Next `install.sh --refresh` distributes them to all image repos

This is what makes the Nth port fast.
