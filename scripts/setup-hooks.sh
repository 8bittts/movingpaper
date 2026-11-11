#!/usr/bin/env bash
#
# setup-hooks.sh — Point Git at the tracked hooks so this clone and every
# worktree run .githooks/commit-msg. Run once per clone.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

[ -x .githooks/commit-msg ] || { echo "[hooks] FAIL — .githooks/commit-msg is missing or not executable." >&2; exit 1; }
git config core.hooksPath .githooks
echo "[hooks] PASS — core.hooksPath is .githooks."
