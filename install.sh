#!/bin/sh
# Install or refresh the daemonless porting toolkit into an image repo.
#
# Usage:
#   /path/to/porting-toolkit/install.sh           # first install
#   /path/to/porting-toolkit/install.sh --refresh  # update existing
#
# Run from the image repo root. Copies .claude/, templates/, and scripts/.
# The cookbook is copied (not symlinked) so it works offline. After a port,
# PR new cookbook entries back to the toolkit repo.

set -e

TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)"
REFRESH=false

case "$1" in
  --refresh) REFRESH=true ;;
esac

if [ "$TOOLKIT_DIR" = "$TARGET_DIR" ]; then
  echo "ERROR: run this from the image repo, not the toolkit repo" >&2
  exit 1
fi

# Sanity check: are we in a git repo?
if [ ! -d .git ]; then
  echo "WARNING: not a git repo — installing anyway" >&2
fi

echo "[toolkit] Source: $TOOLKIT_DIR"
echo "[toolkit] Target: $TARGET_DIR"

# Copy .claude/ (agents, hooks, reference, skills, settings)
if [ "$REFRESH" = true ] && [ -d .claude ]; then
  echo "[toolkit] Refreshing .claude/ (preserving local-only files)..."
  # Back up any local settings that aren't from the toolkit
  if [ -f .claude/settings.local.json ]; then
    cp .claude/settings.local.json /tmp/settings.local.json.bak
  fi
fi

# Core .claude/ directories — always overwrite from toolkit
for dir in agents hooks reference skills; do
  mkdir -p ".claude/$dir"
  cp -R "$TOOLKIT_DIR/.claude/$dir/" ".claude/$dir/"
  echo "[toolkit] Installed .claude/$dir/"
done

# settings.json — merge needed? For now, overwrite.
cp "$TOOLKIT_DIR/.claude/settings.json" ".claude/settings.json"
echo "[toolkit] Installed .claude/settings.json"

# Restore local settings
if [ -f /tmp/settings.local.json.bak ]; then
  mv /tmp/settings.local.json.bak .claude/settings.local.json
  echo "[toolkit] Restored .claude/settings.local.json"
fi

# Templates
mkdir -p templates
cp "$TOOLKIT_DIR/templates/"*.md templates/
echo "[toolkit] Installed templates/"

# Scripts
mkdir -p scripts
cp "$TOOLKIT_DIR/scripts/"*.sh scripts/
chmod +x scripts/*.sh
echo "[toolkit] Installed scripts/"

# Make hooks executable
chmod +x .claude/hooks/*.sh

# CLAUDE.md — only on first install, don't overwrite a filled-in one
if [ ! -f CLAUDE.md ]; then
  cp "$TOOLKIT_DIR/templates/CLAUDE.md" CLAUDE.md
  echo "[toolkit] Created CLAUDE.md from template (fill in the placeholders)"
elif [ "$REFRESH" != true ]; then
  echo "[toolkit] CLAUDE.md already exists — skipping (use --refresh to overwrite)"
fi

echo ""
echo "[toolkit] Done. Next steps:"
echo "  1. Fill in CLAUDE.md placeholders (<APP>, <upstream URL>)"
echo "  2. Run: claude"
echo "  3. Use: /port-package <upstream-repo> or /bump-upstream"
if [ "$REFRESH" != true ]; then
  echo "  4. After porting, PR new cookbook entries back to the toolkit repo"
fi
