---
name: port-package
description: 'Port a new upstream application to a FreeBSD daemonless OCI image and open a PR. Use when asked to "add <app> to daemonless", "build a daemonless image for <repo>", "port <app> to FreeBSD/daemonless", or to fix/refresh an existing daemonless image build. Drives the full loop — research, scaffold, build, CIT test, debug, harden, PR with build notes — then stops for human review.'
---

# Port a package to daemonless

You are porting an upstream app to a FreeBSD `daemonless` container image built with `dbuild`. Work autonomously through the phases below, but **stop at the gates** and **never self-merge**. The reviewer reads `BUILD-NOTES.md`, not the diff — keep it accurate.

**First, always read `.claude/reference/freebsd-porting-cookbook.md`.** It is keyed by error signature and turns multi-hour discoveries into instant fixes. Consult it BEFORE guessing at any build/runtime error, and APPEND to it whenever you solve something new (this is the point of the system).

**Check for `WIP.md`:** if one exists, a previous session failed mid-port. Read it to understand which phase you're resuming from, what was tried, and what the last error was. Skip completed phases and pick up where it left off.

## Operating rules (these are where ports go wrong)
1. **Edit `Containerfile.j2` only**, never the generated `Containerfile`. After any `.j2` change run `dbuild generate`.
2. **`dbuild build` exit 0 ≠ success.** Its wrapper can exit 0 while the inner build failed. Grep the log for `error:`/`Failed`/`gyp ERR`.
3. **A green build ≠ a working image.** Always `dbuild test` (CIT). Apps crash at config-parse / migrations after building fine.
4. **`dbuild test` truncates logs on failure** — use `scripts/cit-with-logs.sh` for full log capture, or see `.claude/reference/cit-and-logs.md` for manual capture.
5. **Pin the upstream release tag.** Never build `main`.
6. **Branch off `upstream/main`** for the PR so the diff is just your files (no fork-URL/sbom noise). If `dbuild generate` rewrote `README.md` with fork URLs, restore it before committing.

## Phase 0 — Intake
- Check for `WIP.md` — resume from there if it exists.
- Identify the upstream repo, app name, and target category/port.
- Check the registry + sibling images for a near-twin to copy.
- Resolve and pin the latest upstream **release tag**.

## Phase 1 — Research (spawn the `upstream-researcher` subagent)
Get a written **port plan** before touching a Containerfile. Must answer:
- Runtime + exact version (`.nvmrc`, `go.mod`, …) and how upstream's own Dockerfile runs it (flags, `CMD`).
- Build system (pnpm/npm/yarn, vite/esbuild, monorepo workspaces).
- **Native modules** — the decisive question. List every dep with prebuilt platform binaries (`@libsql/*`, `better-sqlite3`, `sharp`, `@napi-rs/*`, `@img/*`, …). For each: does a FreeBSD prebuilt exist? Does it build from source on FreeBSD? (See cookbook — this is 80% of the work.)
- Database driver + whether it works on FreeBSD (libsql does NOT).
- **Base image shape** — long-running **service** or **one-shot CLI / non-daemon tool**? Service → `ghcr.io/daemonless/base:<tag>` (s6-supervised). CLI/tool → `ghcr.io/daemonless/base-core:<tag>` (minimal, **no** service supervision; lighter, still ships `pkg`). Tells it's a CLI: no listening port, no health endpoint, runs-and-exits, upstream ships a `bin`/command not a server. On a minimal base, add `ca_root_nss` if the build fetches over HTTPS (npm/pip/curl).
- **Base version = LOWEST supported minor, not the build host's.** FreeBSD ABI compat is backward-only: a 15.0-userland image runs on 15.0 **and** 15.1 kernels, but a 15.1 image is **not** guaranteed on 15.0. So use the rolling `15-pkg` (currently 15.0) for portability; only pin `15.1-pkg` if a 15.1-only feature is required (rare). Containers run on the host kernel, so this is a real runtime gate, not cosmetic.
- License + CIT: a **service** → smallest health endpoint (`health`/`port` mode); a **CLI** → `command`-mode CIT running the command to completion (e.g. `<tool> --version`) and asserting exit 0 + an `expect_output` regex (a run-and-exit tool has no live process for `shell`/`port`/`health`/`screenshot`).

## Phase 2 — Scaffold
- `dbuild init` or copy the nearest image. Set the **image class** (`x-daemonless: class:` — `service`/`cli`/`base`) explicitly. A **service** ships `compose.yaml` (with the `x-daemonless` block) + `.daemonless/config.yaml` (CIT mode, port, health). A **CLI** ships **no `compose.yaml`** — put `x-daemonless: class: cli` + `build:` + `cit: mode: command` in `.daemonless/config.yaml`. See the cookbook entry "Catalog metadata: set `x-daemonless: class:`".
- Write `Containerfile.j2`, then `dbuild generate`.
- **Verify `compose.yaml` metadata:** run `scripts/lint-compose.sh` to cross-check metadata against Containerfile LABELs. Fix mismatches before proceeding.
- **Pre-build verification:** `pkg rquery` every candidate package name before the first build. A wrong pkg name wastes a ~15-min build cycle.

## Phase 3 — Build loop
`dbuild generate → dbuild build → on failure: read the real error → look up its class in the cookbook → apply the documented fix → repeat.`
If one error resists 2 attempts, hand it to the `freebsd-port-solver` subagent.

## Phase 4 — Runtime test (CIT) + log capture
Run `scripts/cit-with-logs.sh` (or `dbuild test` with manual log capture per `.claude/reference/cit-and-logs.md`). Diagnose runtime failures (missing Temporal global, native-module load, DB driver shape) against the cookbook. Iterate.

## Phase 5 — Harden + complete the catalog
- **Patch-rot guard:** before every `COPY patches/x dest/x`, assert `test -f dest/x` (a COPY silently CREATES the file if upstream moved it → ships unpatched code).
- **Pin** injected native-dep versions; add a **drift guard** (e.g. sharp ↔ `@img/sharp-wasm32` must match exactly).
- **Lazy-load** optional natives with no FreeBSD build so they only fail if used.
- Keep build-only toolchains in the builder stage; discard from runtime.
- **Use standard patches where possible:** prefer `.patch` files with `patch -p1 --fuzz=0` over custom scripts. Reserve scripts for programmatic transformations. `--fuzz=0` is the drift guard (fails on context mismatch).
- **Catalog screenshots (easy to forget — do it every image):** `dbuild screenshot <upstream image URL>...` downloads the app's screenshots from its README/repo into `.daemonless/screenshots/` for the daemonless catalog. Find them in the upstream README (often a `.github/`, `assets/`, or `docs/` path). (Distinct from `dbuild baseline`, which captures the CIT *comparison* shot for screenshot-mode tests.)

## Phase 6 — PR (then STOP)
- `dbuild generate`; restore `README.md` if needed.
- Write `BUILD-NOTES.md` from `templates/BUILD-NOTES.md` — accurate, scannable.
- Fill in `PROCESS-LOG.md` from `templates/PROCESS-LOG.md` — record what happened at each phase.
- Branch off `upstream/main`, push to fork, open PR against `daemonless/<image>` using `templates/PR-BODY.md`.
- Record the verified result (build, CIT: migrations / health 200 / screenshot). **Stop for human review.**
- **Delete `WIP.md`** if one exists (the port is done).

## On failure — write WIP.md
If you hit a blocker you can't resolve, or the session is ending before the port is complete:
1. Write `WIP.md` at repo root with: current phase, last error (full signature), what you've tried, what to try next.
2. Append any new cookbook entries you discovered.
3. Tell the user where things stand.

The next session's Phase 0 will pick up from `WIP.md`.

## Definition of done
`dbuild build` + `dbuild test` (real CIT pass, not just a tagged image) AND patch-rot + drift guards in place AND `dbuild screenshot` run (catalog screenshots in `.daemonless/screenshots/`) AND `BUILD-NOTES.md` written AND `PROCESS-LOG.md` filled in AND `scripts/lint-compose.sh` passes AND a PR open for review. Append any new gotcha to the cookbook.
