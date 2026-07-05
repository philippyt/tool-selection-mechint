#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."  # scripts/ -> repo root (main.tex, build/, bibs live here)
mkdir -p build

# Atomic build lock: `mkdir` is atomic, so only one build runs at a time even if
# several watchers (or a manual ./build.sh) fire at once. Concurrent pdflatex
# passes writing build/main.aux simultaneously interleave and corrupt it
# ("Missing \begin{document}"); serialising the builds prevents that for good.
LOCK="build/.build.lock"
for _ in $(seq 1 120); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
    break
  fi
  sleep 1
done
if [ ! -d "$LOCK" ]; then
  echo "build.sh: could not acquire $LOCK (another build stuck?)" >&2
  exit 1
fi

# NOTE: zotero.bib is NOT refreshed here — run ./zoterobib.sh on demand instead.
# (Regenerating it every build churned its mtime and made watch.sh loop forever.)
# MiKTeX without latexmk (latexmk needs Perl). Direct pdfLaTeX + biber passes for biblatex.
FLAGS="-synctex=1 -interaction=nonstopmode -halt-on-error -file-line-error -output-directory=build"
pdflatex $FLAGS main.tex
biber --input-directory=build --output-directory=build main
pdflatex $FLAGS main.tex
pdflatex $FLAGS main.tex
echo "Built build/main.pdf"
