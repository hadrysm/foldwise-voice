#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    cat <<'EOF'
Usage: ./scripts/coverage.sh [target-ref]

Runs the XCTest suite exactly once with SwiftPM/LLVM coverage, then applies
the repository coverage policy. Set COVERAGE_BASE_REF (or pass target-ref) to
choose the target branch or commit used for changed-line coverage.

When no target is provided, the command uses origin/main, main, or HEAD in
that order. Uncommitted production changes are included in the comparison.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    usage
    exit 0
fi
if (( $# > 1 )); then
    usage >&2
    exit 2
fi

cd "$ROOT"

BASE_REF=${1:-${COVERAGE_BASE_REF:-}}
if [[ -z "$BASE_REF" ]]; then
    if git show-ref --verify --quiet refs/remotes/origin/main; then
        BASE_REF=origin/main
    elif git show-ref --verify --quiet refs/heads/main; then
        BASE_REF=main
    else
        BASE_REF=HEAD
    fi
fi

if ! MERGE_BASE=$(git merge-base "$BASE_REF" HEAD); then
    echo "Coverage policy error: cannot find a merge base for '$BASE_REF' and HEAD" >&2
    exit 2
fi

DIFF=$(mktemp "${TMPDIR:-/tmp}/foldwise-coverage.XXXXXX")
BASELINE_POLICY=$(mktemp "${TMPDIR:-/tmp}/foldwise-coverage-policy.XXXXXX")
trap 'rm -f "$DIFF" "$BASELINE_POLICY"' EXIT
git diff --unified=0 --no-ext-diff "$MERGE_BASE" -- Sources/FoldWiseVoiceKit > "$DIFF"

BASELINE_ARGUMENTS=()
if git cat-file -e "$BASE_REF:coverage-policy.json" 2>/dev/null; then
    git show "$BASE_REF:coverage-policy.json" > "$BASELINE_POLICY"
    BASELINE_ARGUMENTS=(--baseline-policy "$BASELINE_POLICY")
fi

BIN_PATH=$(swift build --show-bin-path)
swift test --enable-code-coverage

REPORT="$BIN_PATH/codecov/FoldWiseVoice.json"
if [[ ! -f "$REPORT" ]]; then
    echo "Coverage policy error: SwiftPM did not produce $REPORT" >&2
    exit 2
fi

python3 scripts/check_coverage.py \
    --report "$REPORT" \
    --policy coverage-policy.json \
    --diff "$DIFF" \
    --root "$ROOT" \
    "${BASELINE_ARGUMENTS[@]}"
