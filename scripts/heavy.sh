#!/bin/zsh
# Runs one heavy job (Swift build, test run, benchmark) at a time on this machine. Builds started
# from several terminals at once wait for each other instead of competing for memory.
# Usage: scripts/heavy.sh <command> [args...]
#
# The lock is a folder. Other projects on the same Mac can share it, so their heavy jobs wait too.
# LUKSFER_HEAVY_LOCK puts it somewhere else (for a test). Default: ~/Library/Caches/luksfer-dev/heavy.lock.
set -u
# Already inside a heavy job (a script run through heavy.sh calls build.sh): just run it.
if [[ "${LUKSFER_HEAVY_HELD:-}" == 1 ]]; then "$@"; exit $?; fi
lock="${LUKSFER_HEAVY_LOCK:-$HOME/Library/Caches/luksfer-dev/heavy.lock}"
mkdir -p "${lock:h}"
# Only one waiter at a time clears a stale lock: a kernel lock, gone when its holder ends. Its path
# comes from the lock path, so every project that shares the lock also shares this guard (other
# projects' scripts use the same "<lock>.clear").
zmodload zsh/system
guard="${lock}.clear"
touch "$guard"

# Removes the lock folder: only its pid and cmd files, then the empty folder (never rm -rf: the
# path comes from a variable).
remove_lock() {
  local name
  for name in "$lock"/*(DN:t); do [[ "$name" == (pid|cmd) ]] || return 1; done
  rm -f "$lock/pid" "$lock/cmd"
  rmdir "$lock" 2>/dev/null
}

waited=0
while ! mkdir "$lock" 2>/dev/null; do
  pid=$(cat "$lock/pid" 2>/dev/null)
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    if zsystem flock -t 10 -f fd "$guard" 2>/dev/null; then
      # Still the dead holder's lock? A job that took the lock in the meantime keeps it.
      if [[ "$(cat "$lock/pid" 2>/dev/null)" == "$pid" ]]; then
        if remove_lock; then
          echo "heavy.sh: removed a stale lock left by pid $pid" >&2
        else
          echo "heavy.sh: $lock has other files, so it is not a lock folder; check it and remove it by hand" >&2
          exit 1
        fi
      fi
      exec {fd}>&-
    fi
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
# At the end, remove the lock only while it is still ours.
trap '[[ "$(cat "$lock/pid" 2>/dev/null)" == $$ ]] && remove_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
LUKSFER_HEAVY_HELD=1 "$@"
exit $?
