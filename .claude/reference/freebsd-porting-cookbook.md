# FreeBSD daemonless porting cookbook

Error-signature-keyed fixes for porting apps to FreeBSD daemonless images. **Look here BEFORE guessing. Append a new entry every time you solve something new** — that's what makes the Nth port fast. Each entry: *signature → root cause → fix → why*.

---

## Node / JavaScript

### `pkg install nodeXX` → "No packages available" / not found
**Cause:** the requested node (e.g. `node26`) is only in FreeBSD's **`latest`** pkg branch; the base image is on **`quarterly`**, which lags (tops out at e.g. node25).
**Fix:** switch the branch before install, in **every** stage that installs it:
```dockerfile
RUN sed -i '' -e 's,/quarterly,/latest,' /etc/pkg/FreeBSD.conf && \
    pkg update && pkg install -y node26 npm-node26 corepack ...
```
**Why:** quarterly is a frozen snapshot; new major runtimes land in latest first. #1 cause of "package not found".

### Runtime crash: `ReferenceError: Temporal is not defined`
**Cause:** FreeBSD's `node26` is compiled **without** the TC39 Temporal global. Official Node 26 ships it; on the FreeBSD build even `--harmony-temporal` is a no-op.
**Fix:** add a polyfill dep and preload it (the s6 run script already uses `--import` for tsx):
```
# inject dep:  p.dependencies['temporal-polyfill']='0.3.2'
# run script:  NODE_FLAGS="--import temporal-polyfill/global"
```
**Why:** Temporal is gated behind a V8 build flag the FreeBSD port doesn't enable. (Worth a ports PR.)

### `better-sqlite3` build fails: `no member named 'GetPrototype'`/`'GetIsolate'`/`'This'`
**Cause:** node26's V8 removed those APIs; `better-sqlite3` ≤11.x uses them.
**Fix:** inject **better-sqlite3 ≥12.x** (version-gates via `V8_MAJOR_VERSION>=13` / `NODE_MODULE_VERSION>=140`). 11.x only works up to node24.
**Why:** native addons must track the V8 ABI; pin to a version supporting your node major.

### `@libsql/client` crashes on import: `Cannot find module '@libsql/freebsd-x64'`
**Cause:** the native `libsql` package ships **no FreeBSD prebuilt and no source build**; merely *importing* `@libsql/client` loads the native binding and crashes.
**Fix (cleanest first):**
1. **`node:sqlite`** (built into node ≥22, usable in 26) via `drizzle-orm/sqlite-proxy` — **drops the whole C toolchain**. Use `StatementSync.setReturnArrays(true)` for positional rows; `.columns().length` to detect readers.
2. **`better-sqlite3`** (≥12 on node26) — proven, but pulls node-gyp + toolchain.
Both need a small `database.ts` shim reproducing libsql semantics:
- a custom `db.batch([...])` (tolerates eagerly-executed `db.run()` results),
- libsql-shaped `db.run/all/get(sql)` returning **row objects** (migrations read by column name; the bare proxy returns positional arrays).
Also drop any static import of a libsql *task/queue* driver — it eval-loads the native module and crashes even when unused.
**Why:** Turso/libsql ships Rust napi prebuilds for linux/darwin/win32 only.

### `sharp` fails to load at boot (no FreeBSD prebuilt)
**Fix:** add `@img/sharp-wasm32` as a direct dep, **pinned to sharp's exact version**, + a post-install drift guard that fails the build if sharp moves off the pin. sharp auto-loads the wasm runtime.
**Why:** sharp requires its platform package to match its own version exactly.

### `@napi-rs/canvas` (or similar optional native) has no FreeBSD build
**Fix:** patch the importer to **lazy-load**: `async () => (await import('@napi-rs/canvas')).default`. Then it only fails if a code path needs it.
**Why:** a static import crashes the whole process at boot even if unused.

### pnpm fetches Linux-only binaries / refuses native build scripts
**Fix:**
- `.npmrc`: `supportedArchitectures.os[]=current`, `cpu[]=current`, `cpu[]=wasm32`.
- `pnpm-workspace.yaml`: add needed packages to `allowBuilds` (pnpm v11 treats an ignored build script as a hard error).
**Why:** upstream lockfiles assume Linux/macOS only.

### `tsx: not found` / tsx fails under `/bin/sh`
**Cause:** tsx's bin wrapper is a bash script. **Fix:** `node --import tsx script.ts`.

### `npm install -g` CLI fails as unprivileged user: `ocijail: error executing container command: No such file or directory`
**Signature:** image runs (no hang), but the entrypoint immediately errors with `No such file or directory`, even though `/usr/local/bin/<tool>` exists. As `--user root` it works fine.
**Cause:** npm run as root under the base image's restrictive umask installs the global tree **mode 700 / root-only** (`drwx------ /usr/local/lib/node_modules/@scope`). A container running as the unprivileged `bsd` user can't traverse into it to reach the bin — exec returns ENOENT.
**Fix:** make the global modules world-readable/searchable after install, in a **late** layer so the expensive npm `RUN` stays cache-valid:
```dockerfile
RUN chmod -R a+rX /usr/local/lib/node_modules
```
**Why:** `a+rX` adds read for all and search/execute on dirs (and already-exec files) only — exactly what an unprivileged `USER` needs to run a root-installed CLI.

### node-gyp: `cc: not found` / `ar: not found` / missing headers
**Cause:** the base jail ships no C toolchain and no `/usr/include`.
**Fix (builder stage only):** `pkg install -y FreeBSD-clang FreeBSD-lld FreeBSD-toolchain FreeBSD-clibs-dev pkgconf python3 gmake`. Better: avoid native compiles (prefer `node:sqlite`, wasm sharp) and drop the toolchain.

---

## Python / FastAPI

### `pip install -r requirements.txt` fails building Rust/C deps
**Cause:** compiled deps (pydantic-core, cryptography, orjson, watchfiles = Rust; pillow, argon2-cffi, uvloop, httptools = C) have **no FreeBSD wheels**; pip builds them from source (needs rust/cargo + C toolchain).
**Fix:** install them prebuilt from `pkg` as `py3XX-*` and skip pip entirely (most FastAPI deps are packaged). No toolchain in the image.
**Verify names first:** `pkg rquery '%v' <name>` — FreeBSD naming surprises: `py311-Jinja2` (capitalized), `py311-sqlalchemy20`, `py311-pydantic2` (the v2 pkg), `py311-pillow` (lowercase).

### `fastapi run` not available
`fastapi-cli` is usually not packaged. Run `python3.XX -m uvicorn <pkg.module>:app --host 0.0.0.0 --port <p>` (`py3XX-uvicorn` exists).

### `SyntaxError: f-string expression part cannot include a backslash` (or other syntax errors)
**Cause:** the app uses **Python 3.12+** syntax (PEP 701) but FreeBSD's **default Python is 3.11**, and FreeBSD packages the deps only for the default flavor (no `py312-*` yet — tracked by **FreeBSD bug 285957**).
**Fix:** scope it with `python3.11 -m compileall <pkg>` (lists every syntax error). A few lines → patch them to 3.11-compatible forms (self-guarding patch that fails on drift). Pervasive → documented blocker until 285957 lands.

### `uvicorn: Could not import module "X"`
Masks the **real** import exception. Reproduce: `python3.XX -c "import X"` (as the runtime user) to get the true traceback (missing dep, permission, or syntax).

### App imports fail for no obvious reason — check permissions
Cloned/COPY'd source often lands as `root:wheel 700`; the unprivileged runtime user (`bsd`) can't import it. `chown -R bsd:bsd /app`.

---

## General daemonless / dbuild patterns

### Catalog metadata: set `x-daemonless: class:` — and where the config lives depends on it
**Cause:** the daemonless catalog/README generator reads metadata from an `x-daemonless:` block, but *where* that block lives and which files an image ships depend on its **class**. dbuild's `VALID_IMAGE_CLASSES` = `service` | `cli` | `base` (default `service`). Easy to forget the field entirely, or to give a run-and-exit CLI a `compose.yaml` it should never have.
**Fix — pick the class, then follow its layout:**
- **`service`** (persistent daemon, e.g. papra, sparky, trip): `x-daemonless:` block lives in **`compose.yaml`**; also ship `.daemonless/config.yaml` (`build:` variants + `cit:` screenshot/port/health) and a `.daemonless/baseline-*.png`. Set `class: "service"` explicitly even though it's the default.
- **`cli`** (run-and-exit tool, e.g. immich-cli): **no `compose.yaml`**. Put everything in `.daemonless/config.yaml`:
  ```yaml
  x-daemonless:
    class: cli
  build:
    variants:
      - tag: latest
        containerfile: Containerfile
  cit:
    mode: command            # runs to completion, asserts exit 0 + output regex
    expect_output: '\d+\.\d+\.\d+'   # keep generic, don't pin the exact version
  ```
- **`base`** (image for `FROM`): no deployment docs.
**Also:** `category:` must be one of dbuild's `VALID_CATEGORIES` (Base, Databases, Development, Downloaders, Infrastructure, Media Management, Media Servers, Monitoring, Network, Photos & Media, Productivity, Security, Utilities). `"Apps"` is **not** valid and won't slot into the catalog.
**Why:** the catalog and README layout branch on `class`; a CLI rendered as a service (or vice-versa) generates wrong deployment docs. Schema source of truth: `dbuild/dbuild/config.py` (`Metadata`, `VALID_IMAGE_CLASSES`, `VALID_CATEGORIES`).

### "Package X not found" generally
Check the base image's pkg branch first (`quarterly` vs `latest`).

### A patch silently does nothing / unpatched code ships
**Cause:** `COPY patches/x dest/x` **creates** `dest/x` if upstream moved/renamed it — unpatched source then ships and crashes.
**Fix:** guard before COPY:
```dockerfile
RUN for f in dest/a dest/b ; do test -f "$f" || { echo "PATCH DRIFT: $f gone upstream"; exit 1; }; done
```

### A `.patch` fails to apply: `Hunk #N FAILED`, `1 out of 1 hunks failed`, `.rej` saved
**Cause:** the patch's context lines (or `@@ -N` line numbers) don't match the real upstream file — usually a hand-written/reconstructed diff against the wrong version. `--fuzz=0` correctly refuses it.
**Critical:** `dbuild generate` + `lint-compose.sh` **never apply patches** — they pass on a broken patch. Only `dbuild build` catches this. Never call a patch done until a build applies it.
**Fix — generate the patch from a real diff against the *pinned* upstream, not from memory:**
```sh
git clone --depth 1 --branch <TAG> <upstream-url> /tmp/src
cp /tmp/src/<rel/path> /tmp/orig            # then edit /tmp/src/<rel/path>
diff -u --label a/<rel/path> --label b/<rel/path> /tmp/orig /tmp/src/<rel/path> > patches/foo.patch
patch -p1 --dry-run --fuzz=0 < patches/foo.patch   # must report "Hunk #1 succeeded"
```
Note the COPY-source path may differ from the `-p1` path (e.g. upstream `backend/trip/...` → image `/app/trip/...`); set the `diff` labels to the *in-image* path.

### `dbuild build` "succeeded" but the image is broken
Read the inner build log, not the wrapper exit code. Grep `error:` / `Failed` / `gyp ERR`.

### `dbuild generate` rewrote README.md (+ Containerfile) with the wrong registry org (your fork instead of `ghcr.io/daemonless`)
**Cause:** `dbuild` auto-derives the registry org from `git remote get-url origin` (`config.py:_detect_registry`). When you run from a fork, origin is your own account, so generated docs/image refs point at your fork's org instead of `ghcr.io/daemonless`.
**Fix:** force the upstream registry when generating from a fork:
```sh
dbuild generate --registry ghcr.io/daemonless      # or: export DBUILD_REGISTRY=ghcr.io/daemonless
```
Precedence: `--registry` / `DBUILD_REGISTRY` env → org from `origin` → fallback `ghcr.io/daemonless`.
Then restore any stray `README.md` to upstream before committing — only `Containerfile` + `.j2` + `patches/` belong in the PR.

### Build hangs for 10+ min AFTER the `RUN` finishes — `storage-applyLayer` pegged at 100% CPU
**Signature:** the last build output is the end of a `RUN` (e.g. `pkg clean` done), then minutes of silence; `ps` shows `storage-applyLayer .../zfs/graph/<hash> (podman)` in **R** state burning CPU, `podman ps` goes sluggish.
**Cause:** podman's **ZFS storage driver** commits a layer by unpacking it file-by-file into a per-layer ZFS dataset. A `node_modules`-heavy layer (node + npm + a JS app = thousands of tiny files) makes this O(files) commit grind for 10+ min. It's CPU-bound (R), not stuck (D), and not a disk-space issue.
**Fix:** nothing required — it finishes; just wait. To reduce it: keep the node layer lean, or use the overlay/vfs storage driver for build hosts. Disk: `df`/`zfs list` to rule out a full pool.
**Why:** ZFS driver = dataset-per-layer; file-count, not byte-count, dominates commit time.

### Two `dbuild build`s (or build + `podman pull`) at once wedge podman
**Signature:** everything hangs; `podman ps` times out; nothing is downloading (`sockstat` shows no registry connection).
**Cause:** podman serialises on a single image-store lock. Concurrent build/pull operations queue behind a held lock; a stuck one wedges the lot.
**Fix:** run builds **one at a time**, and not alongside a `podman-compose pull`. Recovery: stop the extra builds, kill any orphaned `buildah`/stuck `podman images` PIDs; running containers (`conmon`) are unaffected and keep serving.
**Why:** daemonless podman has no broker arbitrating concurrent store access — the lock is it.

---

## Go (stub — fill in as you port)
- Mostly static; watch cgo deps needing system libs.
