#!/usr/bin/env bash
# Continuous build: rebuilds build/main.pdf whenever a .tex or .bib file changes.
# Pure-bash polling (1s), no extra tools. Shows only a one-line status:
#   BUILD OK / BUILD FAILED (full pdflatex output goes to build/build.log).
# Stop with Ctrl-C. Auto-opens SumatraPDF on the first successful build.
set -uo pipefail
cd "$(dirname "$0")/.."  # scripts/ -> repo root
mkdir -p build

# Single-instance guard: only one watcher may run. Extra watchers all firing
# ./build.sh at once was what corrupted build/main.aux and caused BUILD FAILED
# on every terminal open. A stale PID (dead process) is reclaimed automatically.
PIDFILE="build/.watch.pid"
if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    printf '  \e[33mwatch.sh already running (pid %s)\e[0m\n' "$old"
    exit 0
  fi
fi
echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"; printf "\e[?25h\n"' EXIT

snapshot() {
  find . -path ./build -prune -o \( -name '*.tex' -o -name '*.bib' \) -printf '%T@ %p\n' 2>/dev/null | sort
}

SUMATRA="/c/Users/philip/AppData/Local/SumatraPDF/SumatraPDF.exe"
opened=0

printf '\e[?25l'                       # hide cursor — this pane is a status display
status() { printf '\r\e[2K%s' "$1"; }  # overwrite the single status line in place
# Plain one-word status mirrored to a file so the WezTerm tab title can show it
# ("build  OK 12:34:56") from any tab. Format: "STATE HH:MM:SS".
STATUSFILE="build/.build-status"
tstatus() { printf '%s\n' "$1" >"$STATUSFILE"; }

tstatus "watching"
status "  watching for changes..."
last=""
while true; do
  cur="$(snapshot)"
  if [ "$cur" != "$last" ]; then
    tstatus "building $(date +%H:%M:%S)"
    status "  building $(date +%H:%M:%S) ..."
    if scripts/build.sh >build/build.log 2>&1; then
      tstatus "OK $(date +%H:%M:%S)"
      status "  $(printf '\e[1;32mBUILD OK\e[0m')     $(date +%H:%M:%S)"
      if [ "$opened" -eq 0 ] && [ -x "$SUMATRA" ] && [ -f build/main.pdf ]; then
        "$SUMATRA" -reuse-instance "$(cygpath -w "$PWD/build/main.pdf")" &
        opened=1
      fi
    else
      tstatus "FAILED $(date +%H:%M:%S)"
      status "  $(printf '\e[1;31mBUILD FAILED\e[0m') $(date +%H:%M:%S)  (see build/build.log)"
    fi
    last="$cur"
  fi
  sleep 1
done
