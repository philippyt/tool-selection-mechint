#!/usr/bin/env python
"""Generate zotero.bib from the Zotero "ikt590" collection (read-only).

Reads a COPY of zotero.sqlite (never locks Zotero) and writes a biblatex file
with stable, deterministic cite keys. Run on demand via ./zoterobib.sh
(build.sh no longer calls it, to avoid a watch/build rewrite loop).
Override the collection with the ZOTERO_COLLECTION env var. Keys are real
(derived from Zotero metadata) so they are safe to \\cite — not invented.
"""
import sqlite3, shutil, tempfile, os, re, sys, unicodedata

DATA = r"C:\Users\philip\Zotero"
# This script lives in scripts/; zotero.bib belongs at the repo root (main.tex
# \addbibresource{zotero.bib}), so write one level up.
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "zotero.bib"))
COLLECTION = os.environ.get("ZOTERO_COLLECTION", "ikt590")

TYPE_MAP = {
    "journalArticle": "article", "conferencePaper": "inproceedings",
    "book": "book", "bookSection": "incollection", "report": "report",
    "thesis": "thesis", "preprint": "article", "webpage": "online",
    "manuscript": "unpublished", "presentation": "misc", "document": "misc",
}
STOP = {"a", "an", "the", "on", "of", "in", "for", "and", "to", "is", "are"}

def esc(s):
    s = str(s).replace("\\", r"\textbackslash{}")
    for a, b in [("&", r"\&"), ("%", r"\%"), ("$", r"\$"), ("#", r"\#"),
                 ("_", r"\_"), ("{", r"\{"), ("}", r"\}"),
                 ("~", r"\textasciitilde{}"), ("^", r"\textasciicircum{}")]:
        s = s.replace(a, b)
    return s

def ascii_alnum(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", s.lower())

def year_of(date):
    m = re.search(r"\d{4}", date or "")
    return m.group(0) if m else ""

def creator_name(mode, first, last):
    if mode == 1 or not first:
        return "{%s}" % esc(last or "")
    return "%s, %s" % (esc(last), esc(first))

def main():
    src = os.path.join(DATA, "zotero.sqlite")
    tmp = os.path.join(tempfile.gettempdir(), "zotero2bib_copy.sqlite")
    shutil.copy2(src, tmp)
    db = sqlite3.connect(tmp); c = db.cursor()

    row = c.execute("SELECT collectionID FROM collections WHERE lower(collectionName)=lower(?)",
                    (COLLECTION,)).fetchone()
    if not row:
        sys.stderr.write(f"zotero2bib: no collection '{COLLECTION}'; leaving zotero.bib untouched.\n")
        return 1
    cid = row[0]
    item_ids = [r[0] for r in c.execute(
        "SELECT itemID FROM collectionItems WHERE collectionID=?", (cid,)).fetchall()]

    records = []
    for it in item_ids:
        tr = c.execute("SELECT it.typeName FROM items i JOIN itemTypes it "
                       "ON it.itemTypeID=i.itemTypeID WHERE i.itemID=?", (it,)).fetchone()
        itype = tr[0] if tr else "document"
        if itype in ("attachment", "note"):
            continue
        fields = {fn: v for fn, v in c.execute(
            "SELECT f.fieldName, idv.value FROM itemData d JOIN fields f ON f.fieldID=d.fieldID "
            "JOIN itemDataValues idv ON idv.valueID=d.valueID WHERE d.itemID=?", (it,))}
        creators = c.execute(
            "SELECT cr.fieldMode, cr.firstName, cr.lastName, ct.creatorType "
            "FROM itemCreators ic JOIN creators cr ON cr.creatorID=ic.creatorID "
            "JOIN creatorTypes ct ON ct.creatorTypeID=ic.creatorTypeID "
            "WHERE ic.itemID=? ORDER BY ic.orderIndex", (it,)).fetchall()
        records.append((itype, fields, creators))

    # Deterministic order so generated keys are stable across runs.
    def sort_key(rec):
        _, f, cr = rec
        first_last = cr[0][2] if cr else ""
        return (year_of(f.get("date", "")), ascii_alnum(first_last), f.get("title", ""))
    records.sort(key=sort_key)

    used, entries = {}, []
    for itype, f, creators in records:
        authors = [creator_name(m, fi, la) for (m, fi, la, ct) in creators if ct == "author"]
        editors = [creator_name(m, fi, la) for (m, fi, la, ct) in creators if ct == "editor"]
        title = f.get("title", "")
        # arXiv detection + new-scheme eprint id (YYMM.number). Used to correct the year
        # (Zotero often stores a later revision date) and to drop a redundant arXiv DOI.
        is_arxiv = f.get("repository") == "arXiv" or f.get("archiveID", "").startswith("arXiv:")
        am = re.search(r"\d{4}\.\d{4,5}", f.get("archiveID", "") + " " + f.get("url", ""))
        arxiv_id = am.group(0) if (is_arxiv and am) else ""
        year = year_of(f.get("date", ""))
        if arxiv_id:
            year = "20" + arxiv_id[:2]  # 1706.03762 -> 2017 (arXiv IDs encode YYMM)

        first_last = creators[0][2] if creators else ""
        stem = ascii_alnum(first_last) or ascii_alnum(title.split()[0] if title else "ref")
        tword = next((ascii_alnum(w) for w in title.split() if ascii_alnum(w) and w.lower() not in STOP), "")
        base = f"{stem}{year}{tword}" or "ref"
        key = base
        if key in used:
            used[base] += 1
            key = base + chr(ord("a") + used[base])
        else:
            used[base] = 0

        # E holds the inner content of each field; every value is brace-wrapped on output.
        E = {}
        if authors: E["author"] = " and ".join(authors)
        if editors: E["editor"] = " and ".join(editors)
        if title:   E["title"] = "{" + esc(title) + "}"   # inner braces protect capitalisation
        if year:    E["year"] = year
        container = f.get("proceedingsTitle") or f.get("bookTitle") or f.get("publicationTitle")
        if container:
            key_field = "journaltitle" if itype == "journalArticle" else "booktitle"
            E[key_field] = "{" + esc(container) + "}"
        for zf, bf in [("volume", "volume"), ("issue", "number"), ("pages", "pages"),
                       ("publisher", "publisher"), ("series", "series"), ("edition", "edition"),
                       ("DOI", "doi"), ("url", "url"), ("ISBN", "isbn"), ("place", "location"),
                       ("institution", "institution"), ("university", "institution"),
                       ("number", "number"), ("language", "langid")]:
            if f.get(zf) and bf not in E:
                # URLs/DOIs must not be LaTeX-escaped, only braced.
                E[bf] = f[zf] if bf in ("doi", "url") else esc(f[zf])
        if arxiv_id:
            E["eprinttype"] = "arXiv"
            E["eprint"] = arxiv_id
            # Drop the arXiv DOI (10.48550/arXiv.*) — the eprint already identifies the
            # paper, and IEEE output shouldn't show both "arXiv:..." and a duplicate DOI.
            if E.get("doi", "").lower().startswith("10.48550/arxiv"):
                del E["doi"]

        lines = [f"@{TYPE_MAP.get(itype, 'misc')}{{{key},"]
        for k in ("author", "editor", "title", "journaltitle", "booktitle", "year",
                  "volume", "number", "pages", "publisher", "series", "edition",
                  "institution", "location", "doi", "eprint", "eprinttype", "isbn", "url", "langid"):
            if k in E:
                lines.append(f"  {k} = {{{E[k]}}},")
        lines.append("}")
        entries.append("\n".join(lines))

    header = ("% AUTO-GENERATED from Zotero collection '" + COLLECTION
              + "' by zotero2bib.py - DO NOT EDIT.\n"
              "% Regenerate on demand with ./zoterobib.sh\n\n")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(header)
        fh.write("\n\n".join(entries) + ("\n" if entries else ""))
    sys.stderr.write(f"zotero2bib: wrote {len(entries)} entr{'y' if len(entries)==1 else 'ies'} to zotero.bib\n")
    for e in entries:
        sys.stderr.write("  " + e.splitlines()[0].rstrip(",") + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
