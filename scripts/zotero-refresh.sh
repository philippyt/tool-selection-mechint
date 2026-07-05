#!/usr/bin/env bash
# A single-line pane showing "REFRESH ZOTERO.BIB".
# Click the pane (it highlights via inactive_pane_hsb) and tap any key to regenerate
# zotero.bib from the Zotero 'ikt590' collection (runs ./zoterobib.sh); watch.sh then
# rebuilds. The cursor is hidden so it reads as a button. q closes it.
set -uo pipefail
cd "$(dirname "$0")/.."  # scripts/ -> repo root (build/ status files live here)
mkdir -p build

printf '\e[?25l'
trap 'printf "\e[?25h\n"' EXIT

# Plain status mirrored to a file so the WezTerm "zotero" tab title can show it.
STATUSFILE="build/.zotero-status"
tstatus() { printf '%s\n' "$1" >"$STATUSFILE"; }

label() { printf '\r\e[2K  \e[1;36mREFRESH ZOTERO.BIB\e[0m'; }

tstatus "ready"
label
while true; do
  IFS= read -rsn1 key || break
  case "$key" in
    q|Q) break ;;
    *)
      tstatus "refreshing"
      printf '\r\e[2K  \e[33mrefreshing...\e[0m'
      if scripts/zoterobib.sh >build/zotero-refresh.log 2>&1; then
        tstatus "updated $(date +%H:%M:%S)"
        printf '\r\e[2K  \e[1;32mzotero.bib updated\e[0m %s' "$(date +%H:%M:%S)"
      else
        tstatus "FAILED $(date +%H:%M:%S)"
        printf '\r\e[2K  \e[1;31mrefresh FAILED\e[0m (build/zotero-refresh.log)'
      fi
      sleep 1.3
      label
      ;;
  esac
done
