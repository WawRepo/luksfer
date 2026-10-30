#!/bin/zsh
# Builds the Swift package outside the repo (the repo sits in a synced folder).
# Usage: scripts/build.sh [swift build args...]   e.g. scripts/build.sh -c release
#        OKNO_SWIFT=test scripts/build.sh          runs `swift test` instead
set -eu
root="${0:A:h:h}"
scratch="${OKNO_SCRATCH:-$HOME/Library/Caches/okno-dev/build/${root:t}}"
mkdir -p "$scratch"
cd "$root"
exec "$root/scripts/heavy.sh" swift "${OKNO_SWIFT:-build}" --scratch-path "$scratch" -j 6 "$@"
