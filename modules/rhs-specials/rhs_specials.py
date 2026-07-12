#!/usr/bin/env python3
"""Push Redheaded Stranger's Instagram posts (daily specials etc.) to a ntfy topic.

Fetches the public profile feed via Instagram's anonymous web_profile_info
endpoint (no login required) and publishes each new recent post to ntfy.
By default nothing is filtered out; --match/--ignore restrict by caption.

Scheduling-agnostic: run it from cron, systemd timers, GitHub Actions, or by
hand. Dedup state is a plain text file of already-notified post shortcodes,
so repeated runs are safe and you can poll as often as you like.

Configuration via flags, or the corresponding NTFY_TOPIC / NTFY_SERVER /
IG_USERNAME / STATE_FILE environment variables.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

PROFILE_API = "https://i.instagram.com/api/v1/users/web_profile_info/?username={user}"
IG_APP_ID = "936619743392459"  # public web-app id; required or the API 403s
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
RESTAURANT_TZ = ZoneInfo("America/Chicago")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--user", default=os.environ.get("IG_USERNAME", "redheadedstrngr"),
                   help="Instagram username to watch (default: %(default)s)")
    p.add_argument("--topic", default=os.environ.get("NTFY_TOPIC", "rhs-specials"),
                   help="ntfy topic to publish to (default: %(default)s)")
    p.add_argument("--server", default=os.environ.get("NTFY_SERVER", "https://ntfy.sh"),
                   help="ntfy server base URL (default: %(default)s)")
    p.add_argument("--match", action="append", default=None, metavar="TEXT",
                   help="only notify when the caption contains TEXT (case-insensitive); "
                        "repeatable, any match wins; default: notify on every post. "
                        "Env: MATCH_KEYWORDS (comma-separated)")
    p.add_argument("--ignore", action="append", default=None, metavar="TEXT",
                   help="skip posts whose caption contains TEXT (case-insensitive); "
                        "repeatable. Env: IGNORE_KEYWORDS (comma-separated)")
    p.add_argument("--days", type=int, default=1,
                   help="how many calendar days back (restaurant-local time) to consider; "
                        "1 = today only (default: %(default)s)")
    p.add_argument("--state-file", type=Path,
                   default=Path(os.environ.get("STATE_FILE", "seen_posts.txt")),
                   help="file recording already-notified post shortcodes "
                        "(default: %(default)s)")
    p.add_argument("--log-file", type=Path,
                   default=Path(os.environ.get("LOG_FILE", "specials_log.md")),
                   help="human-readable markdown log of published specials "
                        "(default: %(default)s)")
    p.add_argument("--dry-run", action="store_true",
                   help="print what would be sent instead of publishing to ntfy")
    args = p.parse_args()
    if args.match is None:
        args.match = _env_list("MATCH_KEYWORDS")
    if args.ignore is None:
        args.ignore = _env_list("IGNORE_KEYWORDS")
    return args


def _env_list(name):
    raw = os.environ.get(name, "")
    return [s.strip() for s in raw.split(",") if s.strip()]


def caption_wanted(caption, match, ignore):
    text = caption.lower()
    if match and not any(m.lower() in text for m in match):
        return False
    if any(i.lower() in text for i in ignore):
        return False
    return True


class FetchError(Exception):
    pass


def fetch_posts(user):
    # Instagram 429s Python's TLS fingerprint but accepts curl's, so shell out.
    # One request per invocation — do not add retries here; if you need
    # resilience, space out whole runs instead.
    result = subprocess.run(
        ["curl", "-sS", "--fail-with-body", "--max-time", "30",
         "-A", USER_AGENT, "-H", f"X-IG-App-ID: {IG_APP_ID}",
         PROFILE_API.format(user=user)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise FetchError(result.stderr.strip() or f"curl exit {result.returncode}")
    data = json.loads(result.stdout)
    edges = data["data"]["user"]["edge_owner_to_timeline_media"]["edges"]
    posts = []
    for edge in edges:
        node = edge["node"]
        captions = node["edge_media_to_caption"]["edges"]
        posts.append({
            "shortcode": node["shortcode"],
            "taken_at": datetime.fromtimestamp(node["taken_at_timestamp"], tz=RESTAURANT_TZ),
            "caption": captions[0]["node"]["text"] if captions else "",
            "image_url": node.get("display_url", ""),
        })
    return posts


def load_seen(state_file):
    if state_file.exists():
        return set(state_file.read_text().split())
    return set()


def save_seen(state_file, seen):
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text("\n".join(sorted(seen)) + "\n")


def append_log(log_file, post):
    post_url = f"https://www.instagram.com/p/{post['shortcode']}/"
    entry = (
        f"## {post['taken_at']:%Y-%m-%d (%a) %H:%M %Z}\n\n"
        f"{post['caption'].strip()}\n\n"
        f"[instagram post]({post_url})\n\n---\n\n"
    )
    log_file.parent.mkdir(parents=True, exist_ok=True)
    if not log_file.exists():
        log_file.write_text("# Redheaded Stranger specials\n\n---\n\n")
    with log_file.open("a") as f:
        f.write(entry)


def publish(server, topic, post, dry_run):
    post_url = f"https://www.instagram.com/p/{post['shortcode']}/"
    if dry_run:
        print(f"[dry-run] would publish to {server}/{topic}:")
        print(f"  posted:  {post['taken_at']:%Y-%m-%d %H:%M %Z}")
        print(f"  link:    {post_url}")
        print(f"  caption: {post['caption']}")
        return
    headers = {
        "Title": "Redheaded Stranger",
        "Click": post_url,
        "Tags": "taco",
    }
    if post["image_url"]:
        headers["Attach"] = post["image_url"]
    req = urllib.request.Request(
        f"{server}/{topic}",
        data=post["caption"].encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
    print(f"published {post['shortcode']} to {server}/{topic}")


def main():
    args = parse_args()
    try:
        posts = fetch_posts(args.user)
    except (FetchError, KeyError, TypeError, json.JSONDecodeError) as e:
        print(f"error: failed to fetch Instagram feed for @{args.user}: {e}", file=sys.stderr)
        return 1

    cutoff = datetime.now(RESTAURANT_TZ).date() - timedelta(days=args.days - 1)
    seen = load_seen(args.state_file)
    matched = 0
    for post in posts:
        if post["taken_at"].date() < cutoff:
            continue
        if not caption_wanted(post["caption"], args.match, args.ignore):
            continue
        if post["shortcode"] in seen:
            continue
        publish(args.server, args.topic, post, args.dry_run)
        matched += 1
        if not args.dry_run:
            append_log(args.log_file, post)
            seen.add(post["shortcode"])
            save_seen(args.state_file, seen)

    if matched == 0:
        print(f"no new matching posts since {cutoff:%Y-%m-%d} (checked {len(posts)} posts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
