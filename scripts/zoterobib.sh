#!/usr/bin/env bash
# Regenerate zotero.bib (repo root) from the Zotero "ikt590" collection.
# On-demand only (build.sh does NOT call this, to avoid a watch/build loop).
set -uo pipefail
cd "$(dirname "$0")"  # scripts/ — zotero2bib.py is a sibling; it writes ../zotero.bib
python zotero2bib.py
