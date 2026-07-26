#!/bin/bash

set -euo pipefail

DESTINATION=${1:?Release tool destination is required}
SCRIPT_DIRECTORY=$(
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)

mkdir -p "$DESTINATION"
for tool in \
  finalize_release.sh \
  release_notarization.py \
  release_publication.py
do
  cp "$SCRIPT_DIRECTORY/$tool" "$DESTINATION/$tool"
done
chmod +x "$DESTINATION/finalize_release.sh"

printf '%s\n' "$DESTINATION/finalize_release.sh"
