Adds a FreeBSD daemonless image for **<app>** (`<owner/repo>` @ `<tag>`).

## What & why
<one paragraph: what the app is, and the key FreeBSD-specific decisions — runtime, DB strategy, why any swap was needed>

## FreeBSD notes
- `<e.g. node26 from the latest pkg branch; Temporal via polyfill>`
- `<e.g. libsql swapped for node:sqlite (no FreeBSD native build) — see BUILD-NOTES>`

## Tested
`dbuild build` + `dbuild test` against `ghcr.io/daemonless/base:<tag>`: <migrations run, /health 200, CIT screenshot matches baseline>.

## Tradeoffs / limitations
<e.g. local file DB only; uses a release-candidate API>

See `BUILD-NOTES.md` for the full rationale, patches, and drift guards.
