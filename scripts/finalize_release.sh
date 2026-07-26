#!/bin/bash

set -euo pipefail

: "${NOTARY_API_PRIVATE_KEY_BASE64:?NOTARY_API_PRIVATE_KEY_BASE64 secret is required}"
: "${NOTARY_API_KEY_ID:?NOTARY_API_KEY_ID secret is required}"
: "${NOTARY_API_ISSUER_ID:?NOTARY_API_ISSUER_ID secret is required}"
: "${PUBLICATION_MODE:?PUBLICATION_MODE is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

FINALIZER_DIRECTORY=$(
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)
RELEASE_SOURCE_ROOT=$(pwd)

case "$PUBLICATION_MODE" in
  routine)
    ;;
  forward-repair)
    : "${BAD_VERSION:?BAD_VERSION is required for Forward repair}"
    : "${VALIDATION_REFERENCE:?VALIDATION_REFERENCE is required for Forward repair}"
    : "${FORWARD_REPAIR_CONFIRMATION:?FORWARD_REPAIR_CONFIRMATION is required for Forward repair}"
    ;;
  *)
    echo "Unsupported publication mode: $PUBLICATION_MODE" >&2
    exit 2
    ;;
esac

NOTARY_KEY_PATH="$RUNNER_TEMP/foldwise-notary-key.p8"
export NOTARY_KEY_PATH
cleanup_notary_key() {
  finalizer_status=$?
  trap - EXIT
  rm -f "$NOTARY_KEY_PATH"
  exit "$finalizer_status"
}
trap cleanup_notary_key EXIT
umask 077
printf '%s' "$NOTARY_API_PRIVATE_KEY_BASE64" \
  | base64 --decode > "$NOTARY_KEY_PATH"

FINALIZE_ARGS=(
  "$FINALIZER_DIRECTORY/release_notarization.py"
  finalize
  --artifact-directory dist/notarization
  --record dist/notarization/submission.json
  --log dist/notarization/notarization-log.json
  --repository "$GITHUB_REPOSITORY"
  --release-source-root "$RELEASE_SOURCE_ROOT"
)
if [[ "$PUBLICATION_MODE" == "forward-repair" ]]; then
  FINALIZE_ARGS+=(
    --forward-repair-bad-version "$BAD_VERSION"
    --forward-repair-validation-reference "$VALIDATION_REFERENCE"
    --confirm-forward-repair "$FORWARD_REPAIR_CONFIRMATION"
  )
fi

python3 "${FINALIZE_ARGS[@]}"
