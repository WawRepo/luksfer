#!/bin/zsh
# Runs one heavy job (Swift build, test run, benchmark) at a time on this machine. Builds started
# from several terminals at once wait for each other instead of competing for memory.
# Usage: scripts/heavy.sh <command> [args...]
set -u
lock_root="$HOME/Library/Caches/luksfer-dev"
lock="$lock_root/heavy.lock"
mkdir -p "$lock_root"
waited=0
while ! mkdir "$lock" 2>/dev/null; do
  pid=$(cat "$lock/pid" 2>/dev/null)
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "heavy.sh: removing a stale lock left by pid $pid" >&2
    rm -rf "$lock"
    continue
  fi
  if (( waited % 30 == 0 )); then
    echo "heavy.sh: waiting for another heavy job (pid ${pid:-?}): $(cat "$lock/cmd" 2>/dev/null)" >&2
  fi
  sleep 2
  waited=$((waited + 2))
done
echo $$ > "$lock/pid"
echo "$*" > "$lock/cmd"
trap 'rm -rf "$lock"' EXIT INT TERM
"$@"
exit $?
