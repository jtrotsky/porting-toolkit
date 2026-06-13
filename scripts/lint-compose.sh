#!/bin/sh
# Cross-checks compose.yaml metadata against Containerfile LABELs.
# Flags mismatches that would confuse the daemonless catalog or runtime.
#
# Usage: scripts/lint-compose.sh [compose.yaml] [Containerfile]

set -e

COMPOSE="${1:-compose.yaml}"
CONTAINERFILE="${2:-Containerfile}"
ERRORS=0

if [ ! -f "$COMPOSE" ]; then
  echo "ERROR: $COMPOSE not found" >&2
  exit 1
fi
if [ ! -f "$CONTAINERFILE" ]; then
  echo "ERROR: $CONTAINERFILE not found" >&2
  exit 1
fi

warn() {
  echo "MISMATCH: $1" >&2
  ERRORS=$((ERRORS + 1))
}

info() {
  echo "INFO: $1" >&2
}

# Extract values from Containerfile LABELs
label_port=$(grep 'io.daemonless.port=' "$CONTAINERFILE" | sed 's/.*io.daemonless.port="\([^"]*\)".*/\1/')
label_category=$(grep 'io.daemonless.category=' "$CONTAINERFILE" | sed 's/.*io.daemonless.category="\([^"]*\)".*/\1/')
label_volumes=$(grep 'io.daemonless.volumes=' "$CONTAINERFILE" | sed 's/.*io.daemonless.volumes="\([^"]*\)".*/\1/')
label_health=$(grep 'io.daemonless.healthcheck-url=' "$CONTAINERFILE" | sed 's/.*io.daemonless.healthcheck-url="\([^"]*\)".*/\1/')
label_title=$(grep 'org.opencontainers.image.title=' "$CONTAINERFILE" | sed 's/.*org.opencontainers.image.title="\([^"]*\)".*/\1/')
expose_port=$(grep '^EXPOSE' "$CONTAINERFILE" | awk '{print $2}')

# Extract values from compose.yaml (basic grep — no yaml parser needed)
compose_port=$(grep -E '^\s+- [0-9]+:[0-9]+' "$COMPOSE" | head -1 | sed 's/.*- \([0-9]*\):.*/\1/')
compose_category=$(grep 'category:' "$COMPOSE" | head -1 | sed 's/.*category: *"\(.*\)"/\1/')
compose_title=$(grep 'title:' "$COMPOSE" | head -1 | sed 's/.*title: *"\(.*\)"/\1/')
compose_volumes_doc=$(grep -A1 'volumes:' "$COMPOSE" | grep '/' | head -1 | sed 's/.*\(\/[^:]*\).*/\1/')
compose_upstream=$(grep 'upstream_url:' "$COMPOSE" | sed 's/.*upstream_url: *"\(.*\)"/\1/')
compose_freshports=$(grep 'freshports_url:' "$COMPOSE" | sed 's/.*freshports_url: *"\(.*\)"/\1/')

# Cross-check port
if [ -n "$label_port" ] && [ -n "$compose_port" ] && [ "$label_port" != "$compose_port" ]; then
  warn "port: Containerfile LABEL=$label_port vs compose.yaml=$compose_port"
fi
if [ -n "$expose_port" ] && [ -n "$label_port" ] && [ "$expose_port" != "$label_port" ]; then
  warn "port: EXPOSE=$expose_port vs LABEL=$label_port"
fi

# Cross-check category
if [ -n "$label_category" ] && [ -n "$compose_category" ] && [ "$label_category" != "$compose_category" ]; then
  warn "category: Containerfile LABEL=\"$label_category\" vs compose.yaml=\"$compose_category\""
fi

# Cross-check title
if [ -n "$label_title" ] && [ -n "$compose_title" ] && [ "$label_title" != "$compose_title" ]; then
  warn "title: Containerfile LABEL=\"$label_title\" vs compose.yaml=\"$compose_title\""
fi

# Check volumes documentation matches actual VOLUME
if [ -n "$label_volumes" ] && [ -n "$compose_volumes_doc" ]; then
  if ! echo "$label_volumes" | grep -qF "$compose_volumes_doc"; then
    warn "volumes: Containerfile LABEL=\"$label_volumes\" but compose docs reference \"$compose_volumes_doc\""
  fi
fi

# Check freshports URL looks real (not a copy-paste placeholder)
if [ -n "$compose_freshports" ]; then
  app_name=$(echo "$label_title" | tr '[:upper:]' '[:lower:]')
  if ! echo "$compose_freshports" | grep -qi "$app_name" 2>/dev/null; then
    info "freshports_url ($compose_freshports) doesn't reference the app name — verify it exists"
  fi
fi

# Check upstream_url points to daemonless, not upstream (common copy-paste error)
if [ -n "$compose_upstream" ]; then
  if ! echo "$compose_upstream" | grep -q 'daemonless/' 2>/dev/null; then
    info "upstream_url ($compose_upstream) should point to daemonless/<image>, not the upstream repo"
  fi
fi

# Summary
if [ "$ERRORS" -eq 0 ]; then
  echo "lint-compose: all checks passed"
  exit 0
else
  echo "lint-compose: $ERRORS mismatch(es) found" >&2
  exit 1
fi
