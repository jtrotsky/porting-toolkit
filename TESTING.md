# Weak-model testing — can the toolkit carry a port without a strong pilot?

*2026-07-04. Status: first test staged, not yet run.*

## The claim being tested

A port succeeds or fails on **procedure, not cleverness**. If that's true, the
toolkit's docs should let a mid-tier model (Sonnet) complete a real port
unaided. If Sonnet can't, the docs — not the model — get patched. The docs are
done when the weakest model we'd realistically use stops needing rescue.

## Design principles (what "weak-model-proof" means)

A weaker model doesn't lack knowledge — the cookbook holds the knowledge. It
fails in four predictable ways, each answered by a doc layer:

| Failure mode | Countermeasure | Where |
|---|---|---|
| Theorises instead of looking up | Binding rule: first action on ANY error is a literal `grep -F` of the cookbook (exact command in the skill) | `port-package/SKILL.md` "Execution discipline" |
| Batches speculative fixes | One change per build cycle, verify each phase gate | same |
| Invents names/versions/fixes | `pkg rquery` every name; no fix not in the cookbook after 1 failed attempt → `freebsd-port-solver` subagent → `WIP.md` and STOP. "A clean WIP.md is a success state; a repo of speculative hacks is not." | same |
| Burns judgement it doesn't have | **`PORT-BRIEF.md` pattern**: a strong-model session does Phase 0/1 once — verified deps, pinned tag, base/CIT decisions, traps pre-mapped to cookbook entries, scope fenced. The skill detects the brief and skips research. Strong model plans; weak model executes. | brief at image-repo root |

Plus rails that must actually exist: the PreToolUse hooks (block Containerfile
edits, enforce CIT before PR). **Found 2026-07-04:** `install.sh` silently
dropped every hook on GNU-cp systems (BSD trailing-slash `cp -R dir/` semantics
don't port; now `dir/.`). Weak-model safety depends on rails installing — the
only symptom was an ignorable chmod warning. Lesson: verify the rails installed
(`ls .claude/hooks/*.sh`) before starting a run.

## Test protocol

1. Stage an image repo: `install.sh` from this toolkit + a `PORT-BRIEF.md`
   authored by a strong-model session. Verify hooks landed and are executable.
2. Run **cold**: fresh session, weaker model, zero conversational context —
   that's what "the docs are sufficient" means, and it's how third-party users
   experience the toolkit. **Do not coach mid-run.**
   ```
   cd <image-repo> && claude --model sonnet
   > /port-package <upstream-url>
   ```
3. **`JOURNAL.log` is the measuring instrument; `PROCESS-LOG.md` is the
   narrative.** The journal hook records every command automatically, so the
   instrument no longer depends on the discipline of the model being measured
   (run 1 wrote zero PROCESS-LOG entries in 121 turns). Afterwards, a
   strong-model session grades the run — journal + transcript + PROCESS-LOG:
   every hesitation, wrong turn, invented fix, ignored rule, or rescue is a
   DOC GAP, not a model failure. Patch the docs from that evidence.
   Test → rewrite, never rewrite → hope.
4. Outcomes: PASS (PR open, CIT green, no rescue) · PASS-WITH-GAPS (done, but
   the log shows doc friction — patch docs) · CLEAN FAIL (WIP.md written per
   the rules — patch docs, rerun) · DIRTY FAIL (flailed, broke discipline —
   the discipline section itself needs strengthening) · HARNESS FAIL (killed
   by the harness — tool-timeout SIGKILL, crash — before discipline could
   apply; fix the trap in TOOLING, not prose, and rerun).

## Test ladder

| Rung | Port | Why | Status |
|---|---|---|---|
| 1 | `immich-public-proxy` | Pure-JS, zero native modules, no DB — isolates *process* from *gnarl*. Brief pins v3.0.1. | RUN 1: HARNESS FAIL (see log); port finished by a strong model. **Cold re-run pending** to validate the patches. |
| 2 | `ffmpeg` (staged in `~/workspace/ffmpeg`) | CLI class + pkg-based port — tests the `cli` layout (no compose.yaml, command-mode CIT) and the brief's don't-copy discipline (twin has an invalid category label). First run on the post-run-1 rails. | STAGED 2026-07-04 |
| 3 | something with one native module (sharp- or sqlite-class) | Tests cookbook lookup under real pressure | — |
| 4 | a Python/FastAPI app | Tests the second runtime section cold | — |

## Log of runs

*(append per run: date, model, port, outcome, gaps found → doc patches made)*

### Run 1 — 2026-07-04 · Sonnet · immich-public-proxy (rung 1) · HARNESS FAIL
- **Good (procedure held):** cookbook read first; trusted the brief and skipped
  research per the rules; re-verified only the pinned tag; `pkg rquery`'d every
  package name; `.j2`-only edits; generate → lint gates in order; correct
  `/`-vs-`/healthcheck` CIT call. The scaffold it wrote later built and passed
  CIT unchanged.
- **Killed:** foreground `dbuild build` SIGKILLed at the Bash tool's 600s
  ceiling (turn 121, mid-`npm ci`); session died; no WIP.md possible.
- **Model-attributable gaps → patches made:** zero PROCESS-LOG writes in 121
  turns (→ `journal.sh` auto-journal hook); spawned 7 harness tasks it never
  used (→ operating rule 9 forbids); ~40 turns touring 4 sibling repos because
  the brief said "check the registry" (→ mandatory **Crib** section in
  `templates/PORT-BRIEF.md`); "one change per build cycle" ambiguous for the
  initial scaffold (→ scoped to build 2+).
- **Tooling patches:** foreground builds now hook-blocked +
  `scripts/build.sh` wrapper; `cit-with-logs.sh` doas fix; `cit.ready` entry;
  git pre-push rail; smoke-test gate; `port-auditor` PR gate.
- **Caveat:** all patches since the kill are strong-model-authored and
  weak-model-UNVALIDATED. Rung 1 must be re-run cold (fresh easy port, or this
  one from scratch in a throwaway dir) before the toolkit's claim is credible.
