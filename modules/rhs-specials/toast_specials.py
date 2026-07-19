#!/usr/bin/env python3
"""Watch Redheaded Stranger's Toast menu for specials coming in stock, notify via ntfy.

Toast's online ordering page carries a "Specials" menu group whose items are
toggled in/out of stock as the kitchen runs them — the POS ground truth for
what's on today, including specials that never make it to Instagram. The page
sits behind a Cloudflare JS challenge, so the fetch goes through a FlareSolverr
instance (any solver with the same POST API works); parsing reads the
window.__APOLLO_STATE__ JSON embedded in the returned HTML.

Each run compares current stock against the previous run's state file and
publishes one ntfy message listing items that just became available
(out-of-stock -> in-stock, or new items that appear already in stock). The
first run only records a baseline and never notifies. All observed changes,
including items going off, are appended to a human-readable log.

Scheduling-agnostic: run from cron/systemd/by hand; state diffing makes
repeated runs idempotent. Config via flags or NTFY_TOPIC / NTFY_SERVER /
SOLVER_URL / STATE_FILE / LOG_FILE environment variables.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

PAGE_URL = ("https://www.toasttab.com/local/order/"
            "redheaded-stranger-305-arrington-st/"
            "r-51a2234d-400c-4c54-9ba6-62c6aa4c6d51")
RESTAURANT_TZ = ZoneInfo("America/Chicago")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--solver-url", default=os.environ.get("SOLVER_URL", "http://localhost:8191/v1"),
                   help="FlareSolverr endpoint (default: %(default)s)")
    p.add_argument("--page-url", default=PAGE_URL,
                   help="Toast online-ordering page to scrape (default: Redheaded Stranger)")
    p.add_argument("--group", default="Specials",
                   help="menu group to watch (default: %(default)s)")
    p.add_argument("--topic", default=os.environ.get("NTFY_TOPIC", "rhs-specials"),
                   help="ntfy topic to publish to (default: %(default)s)")
    p.add_argument("--server", default=os.environ.get("NTFY_SERVER", "https://ntfy.sh"),
                   help="ntfy server base URL (default: %(default)s)")
    p.add_argument("--state-file", type=Path,
                   default=Path(os.environ.get("STATE_FILE", "toast_state.json")),
                   help="JSON file recording last-seen stock state (default: %(default)s)")
    p.add_argument("--log-file", type=Path,
                   default=Path(os.environ.get("LOG_FILE", "toast_log.md")),
                   help="human-readable markdown log of stock changes (default: %(default)s)")
    p.add_argument("--dry-run", action="store_true",
                   help="print what would be sent instead of publishing; state is not written")
    return p.parse_args()


class FetchError(Exception):
    pass


def fetch_page(solver_url, page_url):
    payload = json.dumps({
        "cmd": "request.get",
        "url": page_url,
        "maxTimeout": 60000,
    }).encode("utf-8")
    req = urllib.request.Request(
        solver_url, data=payload, headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            result = json.load(resp)
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as e:
        raise FetchError(f"solver request failed: {e}") from e
    if result.get("status") != "ok":
        raise FetchError(f"solver returned {result.get('status')}: {result.get('message')}")
    solution = result.get("solution") or {}
    if solution.get("status") != 200:
        raise FetchError(f"page fetch returned HTTP {solution.get('status')}")
    html = solution.get("response") or ""
    if not html:
        raise FetchError("solver returned empty page")
    return html


# The menu lives in window.__OO_STATE__ (online-ordering cache);
# __APOLLO_STATE__ is a near-empty sibling kept as a fallback in case Toast
# renames things.
STATE_MARKERS = ["window.__OO_STATE__", "window.__APOLLO_STATE__"]


def extract_embedded_state(html, marker):
    idx = html.find(marker)
    if idx == -1:
        raise FetchError(f"no {marker} in page (format changed?)")
    start = html.index("{", idx)
    # Balanced-brace scan that respects JSON strings/escapes.
    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(html)):
        c = html[i]
        if in_string:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return json.loads(html[start:i + 1])
    raise FetchError(f"unterminated {marker} JSON")


def find_menu_items(html, group_name):
    last_err = None
    for marker in STATE_MARKERS:
        try:
            items = find_group_items(extract_embedded_state(html, marker),
                                     group_name)
        except (FetchError, json.JSONDecodeError) as e:
            last_err = e
            continue
        if items:
            return items
    if last_err:
        raise FetchError(str(last_err))
    return {}


def find_group_items(state, group_name):
    """Walk the apollo cache for MenuGroup objects named group_name and
    return {guid: item} for their fully-materialized MenuItem children."""
    items = {}

    def walk(node):
        if isinstance(node, dict):
            if (node.get("__typename") == "MenuGroup"
                    and node.get("name") == group_name):
                for item in node.get("items") or []:
                    if (isinstance(item, dict)
                            and item.get("__typename") == "MenuItem"
                            and item.get("guid")):
                        items[item["guid"]] = {
                            "name": (item.get("name") or "").strip(),
                            "description": (item.get("description") or "").strip(),
                            "price": (item.get("prices") or [None])[0],
                            "inStock": not item.get("outOfStock", True),
                        }
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(state)
    return items


def load_state(state_file):
    if state_file.exists():
        return json.loads(state_file.read_text())
    return None


def save_state(state_file, items):
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps(items, indent=2) + "\n")


def fmt_item(item):
    price = f" (${item['price']:g})" if item["price"] is not None else ""
    return f"{item['name']}{price}"


def append_log(log_file, lines):
    now = datetime.now(RESTAURANT_TZ)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    if not log_file.exists():
        log_file.write_text("# Redheaded Stranger Toast specials\n\n")
    with log_file.open("a") as f:
        f.write(f"## {now:%Y-%m-%d (%a) %H:%M %Z}\n\n")
        for line in lines:
            f.write(f"- {line}\n")
        f.write("\n")


def publish(server, topic, page_url, available, dry_run):
    body_lines = []
    for item in available:
        line = fmt_item(item)
        if item["description"]:
            line += f" — {item['description']}"
        body_lines.append(line)
    body = "\n".join(body_lines)
    if dry_run:
        print(f"[dry-run] would publish to {server}/{topic}:")
        print(f"  {body}")
        return
    req = urllib.request.Request(
        f"{server}/{topic}",
        data=body.encode("utf-8"),
        headers={
            "Title": "Redheaded Stranger: on special today",
            "Click": page_url,
            "Tags": "taco",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
    print(f"published {len(available)} item(s) to {server}/{topic}")


def main():
    args = parse_args()
    try:
        html = fetch_page(args.solver_url, args.page_url)
        current = find_menu_items(html, args.group)
    except (FetchError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    if not current:
        # A menu rework could rename the group; that should page us, not
        # silently disable the watcher.
        print(f"error: no '{args.group}' items found (group renamed?)", file=sys.stderr)
        return 1

    previous = load_state(args.state_file)
    if previous is None:
        in_stock = [i for i in current.values() if i["inStock"]]
        print(f"first run: baseline of {len(current)} item(s), "
              f"{len(in_stock)} in stock — not notifying")
        if not args.dry_run:
            save_state(args.state_file, current)
            append_log(args.log_file, [
                f"baseline: {fmt_item(i)} — "
                f"{'in stock' if i['inStock'] else 'out of stock'}"
                for i in current.values()
            ])
        return 0

    became_available = []
    changes = []
    for guid, item in current.items():
        was = previous.get(guid)
        if was is None:
            changes.append(f"new item: {fmt_item(item)} — "
                           f"{'in stock' if item['inStock'] else 'out of stock'}")
            if item["inStock"]:
                became_available.append(item)
        elif item["inStock"] and not was.get("inStock"):
            changes.append(f"now available: {fmt_item(item)}")
            became_available.append(item)
        elif not item["inStock"] and was.get("inStock"):
            changes.append(f"now 86'd: {fmt_item(item)}")
    for guid, was in previous.items():
        if guid not in current:
            changes.append(f"removed from menu: {was.get('name', guid)}")

    if became_available:
        try:
            publish(args.server, args.topic, args.page_url, became_available,
                    args.dry_run)
        except (urllib.error.URLError, OSError) as e:
            # State is not saved, so the next run re-detects the transition
            # and retries the notification.
            print(f"error: failed to publish to ntfy: {e}", file=sys.stderr)
            return 1

    if not args.dry_run:
        if changes:
            append_log(args.log_file, changes)
        save_state(args.state_file, current)

    if changes:
        for c in changes:
            print(c)
    else:
        print(f"no changes ({len(current)} item(s) tracked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
