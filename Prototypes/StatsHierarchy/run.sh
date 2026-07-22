#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
prototype_bin="$repo_root/.context/bin/StatsHierarchyPrototype"

mkdir -p "$(dirname "$prototype_bin")"
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/FoldWiseVoiceKit/DesignSystem/Theme.swift" \
  "$repo_root/Prototypes/StatsHierarchy/StatsHierarchyPrototype.swift" \
  -o "$prototype_bin"

exec "$prototype_bin" "$@"
