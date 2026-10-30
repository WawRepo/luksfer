#!/bin/zsh
# Builds the Swift package outside the repo (the repo sits in a synced folder).
# Usage: scripts/build.sh [swift build args...]   e.g. scripts/build.sh -c release
#        LUKSFER_SWIFT=test scripts/build.sh          runs `swift test` instead
set -eu
root="${0:A:h:h}"
scratch="${LUKSFER_SCRATCH:-$HOME/Library/Caches/luksfer-dev/build/${root:t}}"
mkdir -p "$scratch"
cd "$root"
exec "$root/scripts/heavy.sh" swift "${LUKSFER_SWIFT:-build}" --scratch-path "$scratch" -j 6 "$@"
