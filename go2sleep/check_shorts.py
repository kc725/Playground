#!/usr/bin/env python3
"""
check_shorts.py
Reads Firefox's live session store to detect open YouTube Shorts tabs.

Exit codes:
  0 → Shorts tab found       (stdout: "found")
  1 → Not found              (stdout: "not_found")
  2 → lz4 module missing     (stdout: "lz4_missing")
  3 → Firefox not installed  (stdout: "no_firefox")
"""

import json
import os
import glob
import sys


def decompress_mozlz4(path):
    """Decompress a Firefox mozlz4 session file."""
    try:
        import lz4.block
    except ImportError:
        print("lz4_missing", flush=True)
        sys.exit(2)

    try:
        with open(path, "rb") as f:
            magic = f.read(8)
            if magic != b"mozLz40\0":
                return None
            compressed = f.read()
        return lz4.block.decompress(compressed, uncompressed_size=256 * 1024 * 1024)
    except Exception:
        return None


def find_session_files():
    """Locate all Firefox session store files across profiles."""
    profile_dir = os.path.expanduser(
        "~/Library/Application Support/Firefox/Profiles"
    )
    if not os.path.exists(profile_dir):
        print("no_firefox", flush=True)
        sys.exit(3)

    # recovery.jsonlz4 is written while Firefox is running (most up-to-date)
    # sessionstore.jsonlz4 is written when Firefox is closed
    patterns = [
        os.path.join(profile_dir, "*/sessionstore-backups/recovery.jsonlz4"),
        os.path.join(profile_dir, "*/sessionstore.jsonlz4"),
    ]
    files = []
    for p in patterns:
        files.extend(glob.glob(p))
    return files


def check_for_shorts():
    session_files = find_session_files()
    if not session_files:
        print("not_found", flush=True)
        sys.exit(1)

    for path in session_files:
        data = decompress_mozlz4(path)
        if data is None:
            continue

        try:
            session = json.loads(data)
        except json.JSONDecodeError:
            continue

        for window in session.get("windows", []):
            for tab in window.get("tabs", []):
                entries = tab.get("entries", [])
                if not entries:
                    continue
                # The last entry is the current page
                url = entries[-1].get("url", "")
                if "youtube.com/shorts" in url:
                    print("found", flush=True)
                    sys.exit(0)

    print("not_found", flush=True)
    sys.exit(1)


if __name__ == "__main__":
    check_for_shorts()
