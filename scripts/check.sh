#!/usr/bin/env bash
# Quality gate: word count (follows \input) + chktex lint of authored content.
# Read-only — never edits or builds. Run before review passes.
# Template-owned files (declaration/titlepage/usepackages/main) are skipped:
# their warnings are template boilerplate you won't edit for prose.
set -uo pipefail
cd "$(dirname "$0")/.."  # scripts/ -> repo root (main.tex, chapters/ live here)

# Drop MiKTeX's "check for updates" nag from tool output.
nofilter() { grep -v 'checked for MiKTeX updates' || true; }

echo "=== word count (texcount, follows \\input) ==="
texcount -inc -sum -q -total main.tex 2>&1 | nofilter

echo
echo "=== chktex lint (authored chapters + appendices) ==="
lint_files=()
for f in chapters/*.tex appendices/*.tex; do
  case "$f" in
    chapters/declaration.tex) continue ;;   # UiA template form (vertical rules by design)
  esac
  [ -e "$f" ] && lint_files+=("$f")
done
found=0
for f in "${lint_files[@]}"; do
  out="$(chktex -q "$f" 2>&1 | nofilter)"
  if [ -n "$out" ]; then echo "$out"; found=1; fi
done
[ "$found" -eq 0 ] && echo "clean — no warnings in authored content"
