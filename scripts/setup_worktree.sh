#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    cat <<'EOF'
Usage: ./scripts/setup_worktree.sh

Prepares a fresh checkout or worktree for work on FoldWise Voice:

  1. Points git at the tracked hooks in .githooks (per-worktree config, so
     every new worktree needs this again).
  2. Pre-resolves the Swift package dependencies so the first build is fast.
  3. Installs the Sandcastle runner's dependencies.

Steps 2 and 3 are skipped when swift or pnpm is missing — a machine without
them still gets a usable checkout; only the Sandcastle runner needs pnpm.

Idempotent: safe to re-run on an already-configured worktree.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    usage
    exit 0
fi
if (( $# > 0 )); then
    usage >&2
    exit 2
fi

cd "$ROOT"

echo "==> Configuring git hooks path"
git config core.hooksPath .githooks

if command -v swift >/dev/null 2>&1; then
    echo "==> Resolving Swift package dependencies"
    swift package resolve
else
    echo "==> Skipping Swift package resolve (swift not on PATH)"
fi

if command -v pnpm >/dev/null 2>&1; then
    echo "==> Installing Sandcastle runner dependencies"
    pnpm -C .sandcastle install
else
    echo "==> Skipping Sandcastle install (pnpm not on PATH)"
fi

echo "==> Worktree ready"
