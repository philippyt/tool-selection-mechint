#!/usr/bin/env bash
# Zotero bridge: list the papers in the Zotero collection (default "ikt590")
set -uo pipefail
python - "$@" <<'PY'
import sqlite3, shutil, tempfile, os, sys

DATA = r"C:\Users\philip\Zotero"
SRC = os.path.join(DATA, "zotero.sqlite")
STORAGE = os.path.join(DATA, "storage")
paths_only = "--paths" in sys.argv[1:]
COLLECTION = os.environ.get("ZOTERO_COLLECTION", "ikt590")

tmp = os.path.join(tempfile.gettempdir(), "zotero_papers_copy.sqlite")
shutil.copy2(SRC, tmp)
db = sqlite3.connect(tmp); c = db.cursor()

row = c.execute("SELECT collectionID FROM collections WHERE lower(collectionName)=lower(?)",
                (COLLECTION,)).fetchone()
if not row:
    sys.stderr.write(f"No Zotero collection named '{COLLECTION}'. "
                     f"Create it in Zotero and save papers into it.\n")
    sys.exit(1)
cid = row[0]

def title(i):
    r = c.execute("SELECT idv.value FROM itemData d "
                  "JOIN fields f ON f.fieldID=d.fieldID "
                  "JOIN itemDataValues idv ON idv.valueID=d.valueID "
                  "WHERE d.itemID=? AND f.fieldName='title'", (i,)).fetchone()
    return r[0] if r else "(untitled)"

items = [r[0] for r in c.execute(
    "SELECT itemID FROM collectionItems WHERE collectionID=?", (cid,)).fetchall()]
n = 0
for it in items:
    atts = c.execute(
        "SELECT ai.key, ia.path FROM itemAttachments ia JOIN items ai ON ai.itemID=ia.itemID "
        "WHERE ia.contentType='application/pdf' AND (ia.parentItemID=? OR ia.itemID=?)",
        (it, it)).fetchall()
    for key, path in atts:
        fn = path.split("storage:", 1)[-1] if path else ""
        full = os.path.join(STORAGE, key, fn)
        if not os.path.exists(full):
            continue
        n += 1
        if paths_only:
            print(full)
        else:
            print(f"- {title(it)}\n    {full}")
if not paths_only:
    sys.stderr.write(f"\n{n} readable PDF(s) in '{COLLECTION}'.\n")
PY