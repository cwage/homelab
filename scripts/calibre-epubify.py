#!/usr/bin/env python3
"""
Add an EPUB format to every Calibre book that lacks a browser-readable one.

Calibre-Web's in-browser reader handles epub, pdf, txt, cbz, fb2, and djvu --
but not mobi, azw3, lit, lrf, or doc. Books in those formats are download-only
in the web UI. This walks the library, converts the best available source to
EPUB, and attaches it to the existing book record with `calibredb add_format`
(the original format is left untouched -- nothing is replaced or deleted).

DRY RUN BY DEFAULT. Pass --apply to actually modify the library.

    scripts/calibre-epubify.py                     # show what would happen
    scripts/calibre-epubify.py --apply             # do it
    scripts/calibre-epubify.py --apply --jobs 8    # ...faster
    scripts/calibre-epubify.py --apply --with-doc  # also handle legacy .doc via LibreOffice

Close the Calibre desktop GUI first: it holds a lock on metadata.db and
calibredb will refuse to write while it is running.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

DEFAULT_LIBRARY = "/mnt/nas/Books"

# Formats Calibre-Web can render in the browser. A book with any of these
# needs nothing from us.
READABLE = {"epub", "pdf", "txt", "cbz", "cbr", "fb2", "djvu", "kepub"}

# Conversion source preference, best fidelity first. azw3 and mobi are the
# same lineage as epub and convert cleanly; the office formats are last
# resorts.
SOURCE_PREFERENCE = [
    "azw3", "mobi", "azw", "azw4", "prc", "kfx",
    "lit", "lrf", "fb2", "htmlz", "html", "rtf", "docx", "doc",
]

# Legacy binary .doc (Word 97-2003) is not a Calibre input format -- it needs
# a LibreOffice pass to .docx first. Opt-in via --with-doc.
NEEDS_LIBREOFFICE = {"doc"}


def log(msg):
    print(msg, flush=True)


def calibre_gui_running():
    """calibredb cannot write while the desktop GUI holds the library lock."""
    try:
        out = subprocess.run(
            ["pgrep", "-af", "calibre"], capture_output=True, text=True
        ).stdout
    except FileNotFoundError:
        return False
    for line in out.splitlines():
        # Match the GUI and the content server, not calibredb/ebook-convert
        # or this script itself.
        if "calibre-server" in line or "/calibre-gui" in line:
            return True
        parts = line.split(None, 1)
        cmd0 = parts[1].split()[0] if len(parts) == 2 else ""
        if cmd0 == "calibre" or cmd0.endswith("/calibre"):
            return True
    return False


def fetch_books(library):
    """Ask calibredb for every book and its formats, as JSON."""
    proc = subprocess.run(
        [
            "calibredb", "list",
            "--library-path", library,
            "--fields", "id,title,authors,formats",
            "--for-machine",
        ],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"calibredb list failed:\n{proc.stderr.strip()}")
    return json.loads(proc.stdout)


def classify(books, with_doc):
    """Split the library into: already fine, convertible, and stuck."""
    todo, stuck = [], []
    for b in books:
        paths = b.get("formats", []) or []
        by_ext = {}
        for p in paths:
            by_ext.setdefault(os.path.splitext(p)[1].lower().lstrip("."), p)

        if by_ext.keys() & READABLE:
            continue

        source = None
        for ext in SOURCE_PREFERENCE:
            if ext in by_ext:
                if ext in NEEDS_LIBREOFFICE and not with_doc:
                    continue
                source = (ext, by_ext[ext])
                break

        entry = {
            "id": b["id"],
            "title": b.get("title", "(untitled)"),
            "authors": b.get("authors", ""),
            "formats": sorted(by_ext),
        }
        if source:
            entry["src_ext"], entry["src_path"] = source
            todo.append(entry)
        else:
            entry["reason"] = (
                "no ebook file at all (metadata-only record)"
                if not by_ext else
                f"no convertible source among {sorted(by_ext)}"
            )
            stuck.append(entry)
    return todo, stuck


def doc_to_docx(src, workdir):
    """LibreOffice pre-pass for legacy binary .doc.

    Serialized by the caller: concurrent soffice invocations sharing a user
    profile step on each other, and -env:UserInstallation per worker is more
    fragile than just doing these one at a time (there are only a handful).
    """
    proc = subprocess.run(
        [
            "soffice", "--headless", "--norestore",
            "--convert-to", "docx", "--outdir", workdir, src,
        ],
        capture_output=True, text=True, timeout=300,
    )
    out = os.path.join(workdir, os.path.splitext(os.path.basename(src))[0] + ".docx")
    if proc.returncode != 0 or not os.path.exists(out):
        raise RuntimeError(f"libreoffice failed: {proc.stderr.strip()[:200]}")
    return out


def convert(book, timeout):
    """Convert one book to EPUB in a temp dir. Returns (book, epub_path, error)."""
    workdir = tempfile.mkdtemp(prefix="epubify-")
    try:
        src = book["src_path"]
        if book["src_ext"] in NEEDS_LIBREOFFICE:
            src = doc_to_docx(src, workdir)

        out = os.path.join(workdir, f"{book['id']}.epub")
        proc = subprocess.run(
            ["ebook-convert", src, out],
            capture_output=True, text=True, timeout=timeout,
        )
        if proc.returncode != 0 or not os.path.exists(out):
            tail = (proc.stderr or proc.stdout or "").strip().splitlines()
            hint = next(
                (l for l in reversed(tail) if l.strip() and "Traceback" not in l),
                "unknown error",
            )
            if "DeDRM" in (proc.stdout + proc.stderr) or "DRM" in hint:
                hint = "DRM-protected: " + hint
            raise RuntimeError(hint[:200])
        return book, out, None
    except subprocess.TimeoutExpired:
        shutil.rmtree(workdir, ignore_errors=True)
        return book, None, f"timed out after {timeout}s"
    except Exception as exc:  # noqa: BLE001 -- surface any failure per-book
        shutil.rmtree(workdir, ignore_errors=True)
        return book, None, str(exc)


def add_format(library, book_id, epub_path):
    proc = subprocess.run(
        ["calibredb", "add_format", "--library-path", library,
         str(book_id), epub_path],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip()[:200])


# Backups and reports go here, NOT next to the script -- this script lives in
# a git repo and metadata.db copies have no business in it.
STATE_DIR = os.path.expanduser("~/.cache/calibre-epubify")


def backup_metadata(library):
    src = os.path.join(library, "metadata.db")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    os.makedirs(STATE_DIR, exist_ok=True)
    dest = os.path.join(STATE_DIR, f"metadata.db.{stamp}")
    shutil.copy2(src, dest)
    return dest


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--library", default=DEFAULT_LIBRARY)
    ap.add_argument("--apply", action="store_true",
                    help="actually modify the library (default: dry run)")
    ap.add_argument("--jobs", type=int, default=4,
                    help="parallel conversions (default 4)")
    ap.add_argument("--limit", type=int,
                    help="only process the first N books -- good for a trial run")
    ap.add_argument("--with-doc", action="store_true",
                    help="also convert legacy .doc via a LibreOffice pre-pass")
    ap.add_argument("--timeout", type=int, default=600,
                    help="per-book conversion timeout in seconds (default 600)")
    ap.add_argument("--report",
                    default=os.path.join(STATE_DIR, "report.tsv"),
                    help=f"per-book results (default {STATE_DIR}/report.tsv)")
    args = ap.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)

    if not os.path.exists(os.path.join(args.library, "metadata.db")):
        sys.exit(f"no metadata.db under {args.library} -- not a Calibre library")

    books = fetch_books(args.library)
    todo, stuck = classify(books, args.with_doc)

    log(f"library:        {args.library}")
    log(f"books total:    {len(books)}")
    log(f"need an EPUB:   {len(todo) + len(stuck)}")
    log(f"  convertible:  {len(todo)}")
    log(f"  not fixable:  {len(stuck)}")

    counts = {}
    for b in todo:
        counts[b["src_ext"]] = counts.get(b["src_ext"], 0) + 1
    if counts:
        log("  sources:      " + ", ".join(
            f"{k}={v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))

    if args.limit:
        todo = todo[: args.limit]
        log(f"\n--limit {args.limit}: only processing {len(todo)} of them")

    if not args.apply:
        log("\nDRY RUN -- nothing will be modified. First 15 that would convert:")
        for b in todo[:15]:
            log(f"  [{b['id']:>5}] {b['src_ext']:>5} -> epub   {b['title'][:60]}")
        if stuck:
            log(f"\nNot fixable ({len(stuck)}), first 10:")
            for b in stuck[:10]:
                log(f"  [{b['id']:>5}] {b['title'][:50]:<52} {b['reason']}")
        log("\nRe-run with --apply to convert. Close the Calibre GUI first.")
        return

    if calibre_gui_running():
        sys.exit("Calibre GUI (or content server) appears to be running.\n"
                 "It locks metadata.db -- close it and re-run.")

    backup = backup_metadata(args.library)
    log(f"\nmetadata.db backed up to {backup}")
    log(f"converting {len(todo)} books with {args.jobs} workers...\n")

    # .doc goes through LibreOffice, which does not like being run
    # concurrently -- do those serially after the parallel batch.
    parallel = [b for b in todo if b["src_ext"] not in NEEDS_LIBREOFFICE]
    serial = [b for b in todo if b["src_ext"] in NEEDS_LIBREOFFICE]

    ok = failed = 0
    started = time.time()
    with open(args.report, "w") as report:
        report.write("id\tstatus\tsrc\ttitle\tdetail\n")

        def record(book, epub, err):
            nonlocal ok, failed
            if err:
                failed += 1
                status, detail = "FAIL", err
            else:
                try:
                    add_format(args.library, book["id"], epub)
                    ok += 1
                    status, detail = "OK", ""
                except Exception as exc:  # noqa: BLE001
                    failed += 1
                    status, detail = "FAIL", f"add_format: {exc}"
                finally:
                    shutil.rmtree(os.path.dirname(epub), ignore_errors=True)
            report.write(f"{book['id']}\t{status}\t{book['src_ext']}\t"
                         f"{book['title'][:60]}\t{detail}\n")
            report.flush()
            done = ok + failed
            log(f"[{done:>4}/{len(todo)}] {status:<4} [{book['id']:>5}] "
                f"{book['title'][:55]}" + (f"  -- {detail}" if detail else ""))

        # add_format is a sqlite writer, so results are consumed one at a
        # time on this thread while conversions run in parallel.
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for book, epub, err in pool.map(
                lambda b: convert(b, args.timeout), parallel
            ):
                record(book, epub, err)

        for book in serial:
            record(*convert(book, args.timeout))

    mins = (time.time() - started) / 60
    log(f"\ndone in {mins:.1f} min: {ok} converted, {failed} failed")
    log(f"per-book results: {args.report}")
    if failed:
        log("Failures are usually DRM or a corrupt source file. The originals "
            "were not touched.")


if __name__ == "__main__":
    main()
