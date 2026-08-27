#!/usr/bin/env python3
"""Watch Redheaded Stranger's Toast menu for specials coming in stock, notify via ntfy.

Toast's online ordering page carries a "Specials" menu group whose items are
toggled in/out of stock as the kitchen runs them — the POS ground truth for
what's on today, including specials that never make it to Instagram. The page
sits behind a Cloudflare JS challenge, so the fetch goes through a FlareSolverr
instance (any solver with the same POST API works); parsing reads the
window.__OO_STATE__ JSON embedded in the returned HTML (with
window.__APOLLO_STATE__ as a fallback).

Each run compares current stock against the previous run's state file and
publishes one ntfy message listing items that just became available
(out-of-stock -> in-stock, or new items that appear already in stock). The
first run only records a baseline and never notifies. All observed changes,
including items going off, are appended to a human-readable log.

Optionally also delivers each alert as an SMS: with an XMPP account whose JID
is registered with JMP (see docs/xmpp.md in the homelab repo), sending an XMPP
message to a +1...@cheogram.com JID comes out the other end as a real text
from the JMP number. Needs the slixmpp package, an XMPP credentials file
(lines "jid: user@domain" and "password: ..."; the server is found via the
domain's SRV records), and a recipient. ntfy stays the primary channel — an
SMS failure is reported but does not re-trigger the ntfy alert on the next
run.

Scheduling-agnostic: run from cron/systemd/by hand; state diffing makes
repeated runs idempotent. Config via flags or NTFY_TOPIC / NTFY_SERVER /
SOLVER_URL / STATE_FILE / LOG_FILE / XMPP_CREDS / SMS_TO / SMS_TO_FILE
environment variables.
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
    p.add_argument("--solver-url", default=os.environ.get("SOLVER_URL", "http://127.0.0.1:8191/v1"),
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
    p.add_argument("--xmpp-creds", type=Path,
                   default=os.environ.get("XMPP_CREDS"),
                   help='XMPP credentials file ("jid: ..." / "password: ..." '
                        "lines); with a recipient, enables SMS delivery via "
                        "the JMP gateway")
    p.add_argument("--sms-to", default=os.environ.get("SMS_TO"),
                   help="SMS recipient: a +1... number (auto-suffixed "
                        "@cheogram.com) or a full JID")
    p.add_argument("--sms-to-file", type=Path,
                   default=os.environ.get("SMS_TO_FILE"),
                   help="file holding the SMS recipient (overrides --sms-to); "
                        "lets the number live in a secrets file, not the unit")
    p.add_argument("--sms-test", metavar="MESSAGE",
                   help="send MESSAGE as an SMS using the configured "
                        "credentials/recipient and exit (no menu fetch)")
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
    start = html.find("{", idx)
    if start == -1:
        raise FetchError(f"no JSON object after {marker} (format changed?)")
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


NTFY_TITLE = "Redheaded Stranger: on special today"


def format_body(available):
    body_lines = []
    for item in available:
        line = fmt_item(item)
        if item["description"]:
            line += f" — {item['description']}"
        body_lines.append(line)
    return "\n".join(body_lines)


def sms_recipient(args):
    """Resolve the SMS recipient, or None if SMS delivery isn't configured.

    A bare phone number becomes a JID on the JMP/Cheogram gateway, which
    relays the XMPP message as a real text.
    """
    if not args.xmpp_creds:
        return None
    to = args.sms_to
    if args.sms_to_file:
        to = args.sms_to_file.read_text().strip()
    if not to:
        return None
    if "@" not in to:
        to += "@cheogram.com"
    return to


def parse_xmpp_creds(path):
    creds = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        creds[key.strip()] = value.strip()
    missing = [k for k in ("jid", "password") if not creds.get(k)]
    if missing:
        raise ValueError(f"{path}: missing {', '.join(missing)}")
    return creds


def send_sms(creds_file, to, message, dry_run):
    if dry_run:
        print(f"[dry-run] would SMS {to} via XMPP:")
        print(f"  {message}")
        return
    creds = parse_xmpp_creds(creds_file)
    # Imported lazily so ntfy-only setups don't need slixmpp installed.
    import slixmpp

    class Sender(slixmpp.ClientXMPP):
        def __init__(self):
            super().__init__(creds["jid"], creds["password"])
            self.sent = False
            self.error = None
            self.add_event_handler("session_start", self._session_start)
            self.add_event_handler("failed_auth", self._failed)
            self.add_event_handler("connection_failed", self._failed)

        async def _session_start(self, _event):
            self.send_message(mto=to, mbody=message, mtype="chat")
            self.sent = True
            # wait= flushes the send queue before closing the stream
            self.disconnect(wait=5.0)

        def _failed(self, event):
            self.error = str(event)
            self.abort()

    xmpp = Sender()
    # Server/port come from the JID domain's SRV records, same as any client.
    xmpp.connect()
    # Backstop: a wedged connection would otherwise stall process() forever.
    xmpp.loop.call_later(120, xmpp.abort)
    xmpp.process(forever=False)
    if not xmpp.sent:
        raise RuntimeError(f"XMPP send failed: {xmpp.error or 'no session'}")
    print(f"sent SMS to {to}")


def publish(server, topic, page_url, available, dry_run):
    body = format_body(available)
    if dry_run:
        print(f"[dry-run] would publish to {server}/{topic}:")
        print(f"  {body}")
        return
    req = urllib.request.Request(
        f"{server}/{topic}",
        data=body.encode("utf-8"),
        headers={
            "Title": NTFY_TITLE,
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

    if args.sms_test is not None:
        to = sms_recipient(args)
        if not to:
            print("error: --sms-test needs --xmpp-creds and a recipient",
                  file=sys.stderr)
            return 2
        try:
            send_sms(args.xmpp_creds, to, args.sms_test, args.dry_run)
        except Exception as e:
            print(f"error: failed to send SMS: {e}", file=sys.stderr)
            return 1
        return 0

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

    sms_failed = False
    if became_available:
        try:
            publish(args.server, args.topic, args.page_url, became_available,
                    args.dry_run)
        except (urllib.error.URLError, OSError) as e:
            # State is not saved, so the next run re-detects the transition
            # and retries the notification.
            print(f"error: failed to publish to ntfy: {e}", file=sys.stderr)
            return 1
        to = sms_recipient(args)
        if to:
            try:
                # SMS has no title field; lead with the ntfy title so the
                # text stands alone.
                send_sms(args.xmpp_creds, to,
                         f"{NTFY_TITLE}\n{format_body(became_available)}",
                         args.dry_run)
            except Exception as e:
                # Deliberately broad: SMS is the best-effort secondary
                # channel, and ntfy already went out, so state must still be
                # saved (a retry would duplicate the ntfy alert). Surface
                # the failure through the exit code instead.
                print(f"error: failed to send SMS: {e}", file=sys.stderr)
                sms_failed = True

    if not args.dry_run:
        if changes:
            append_log(args.log_file, changes)
        save_state(args.state_file, current)

    if changes:
        for c in changes:
            print(c)
    else:
        print(f"no changes ({len(current)} item(s) tracked)")
    return 1 if sms_failed else 0


if __name__ == "__main__":
    sys.exit(main())
