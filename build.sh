#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# MiKTeX without latexmk (latexmk needs Perl). Direct pdfLaTeX + biber passes for biblatex.
FLAGS="-synctex=1 -interaction=nonstopmode -halt-on-error -file-line-error -output-directory=build"
pdflatex $FLAGS main.tex
biber --input-directory=build --output-directory=build main
pdflatex $FLAGS main.tex
pdflatex $FLAGS main.tex
echo "Built build/main.pdf"
