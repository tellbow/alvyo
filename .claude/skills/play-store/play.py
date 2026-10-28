# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]==2.10.1"]
# ///
"""A release of the Alvyo Android app on Google Play, through the Google Play
Developer API (https://developers.google.com/android-publisher).

  uv run play.py status                                  each track's releases
  uv run play.py upload  X.Y.Z AAB [--track T] [--draft] the bundle, on a track
  uv run play.py promote X.Y.Z --to T [--from T] [--draft]

Release notes per language are the «Was ist neu» lines (news_X_Y_Z in
web/messages/*.json). The service account's key file is PLAY_KEY_FILE
(default ~/.google-play/alvyo-publisher.json); it is read to sign the token
and never printed.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

PACKAGE = "ch.tellbow.alvyo"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
REPO = Path(__file__).resolve().parents[3]
# Google Play's limit for the release notes of one language.
NOTES_MAX = 500

_token: str | None = None


def token() -> str:
    global _token
    if _token:
        return _token
    path = Path(os.environ.get("PLAY_KEY_FILE", Path.home() / ".google-play/alvyo-publisher.json"))
    key = json.loads(path.read_text())
    now = int(time.time())
    assertion = jwt.encode(
        {
            "iss": key["client_email"],
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": key["token_uri"],
            "iat": now,
            "exp": now + 3600,
        },
        key["private_key"],
        algorithm="RS256",
        headers={"kid": key["private_key_id"]},
    )
    body = urllib.parse.urlencode(
        {"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}
    ).encode()
    with urllib.request.urlopen(urllib.request.Request(key["token_uri"], data=body), timeout=60) as r:
        _token = json.load(r)["access_token"]
    return _token


def call(method: str, url: str, body: dict | bytes | None = None, **query) -> dict:
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data, kind = (body, "application/octet-stream") if isinstance(body, bytes) else (
        json.dumps(body).encode() if body is not None else None,
        "application/json",
    )
    req = urllib.request.Request(
        url, method=method, data=data, headers={"Authorization": "Bearer " + token(), "Content-Type": kind}
    )
    try:
        # An upload of the bundle (about 80 MB) takes a while.
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        error = json.loads(e.read() or b"{}").get("error", {})
        sys.exit(f"{method} {url.split('?')[0].removeprefix(API)}: {e.code} {error.get('message')}")


def news(v: str) -> dict[str, str]:
    """The «Was ist neu» line of version v in each language."""
    key = "news_" + v.replace(".", "_")
    out = {}
    for f in sorted((REPO / "web/messages").glob("*.json")):
        text = json.loads(f.read_text()).get(key)
        if text:
            out[f.stem] = text
    if not out:
        sys.exit(f"no {key} in web/messages: the release skill writes it")
    return out


def notes(edit: str, v: str) -> list[dict]:
    """Release notes in each language of the store listing (de-DE → de, en-US and en-GB → en)."""
    texts = news(v)
    languages = [x["language"] for x in call("GET", f"{API}/edits/{edit}/listings").get("listings", [])]
    if not languages:
        sys.exit("the store listing has no language yet: set it up in Play Console")
    out, missing = [], []
    for lang in languages:
        text = texts.get(lang.split("-")[0])
        if text is None:
            missing.append(lang)
        elif len(text) > NOTES_MAX:
            sys.exit(f"{lang}: the line has {len(text)} characters, Google Play takes {NOTES_MAX}")
        else:
            out.append({"language": lang, "text": text})
    if missing:
        sys.exit("no text for " + ", ".join(missing))
    return out


def tracks(edit: str) -> list[dict]:
    return call("GET", f"{API}/edits/{edit}/tracks").get("tracks", [])


def put_release(edit: str, track: str, release: dict) -> None:
    call("PUT", f"{API}/edits/{edit}/tracks/{track}", {"track": track, "releases": [release]})
    codes = ", ".join(release["versionCodes"])
    print(f"{track}: {release['name']} ({codes}), {release['status']}")
    for n in release.get("releaseNotes", []):
        print(f"  {n['language']}: {n['text']}")


def commit(edit: str) -> None:
    call("POST", f"{API}/edits/{edit}:commit")
    print("committed: Google reviews it before it reaches the track's users")


def status(args):
    edit = call("POST", f"{API}/edits")["id"]
    try:
        for t in tracks(edit):
            for r in t.get("releases", []):
                codes = ", ".join(r.get("versionCodes", []))
                print(f"{t['track']}: {r.get('name')} ({codes}), {r['status']}")
    finally:
        call("DELETE", f"{API}/edits/{edit}")


def upload(args):
    aab = Path(args.aab)
    edit = call("POST", f"{API}/edits")["id"]
    release_notes = notes(edit, args.version)
    print(f"uploading {aab.name} ({aab.stat().st_size // 2**20} MB)", flush=True)
    bundle = call("POST", f"{UPLOAD}/edits/{edit}/bundles", aab.read_bytes(), uploadType="media")
    print(f"bundle {bundle['versionCode']} uploaded")
    put_release(
        edit,
        args.track,
        {
            "name": args.version,
            "versionCodes": [str(bundle["versionCode"])],
            "status": "draft" if args.draft else "completed",
            "releaseNotes": release_notes,
        },
    )
    commit(edit)


def promote(args):
    edit = call("POST", f"{API}/edits")["id"]
    found = [
        r
        for t in tracks(edit)
        if t["track"] == args.source
        for r in t.get("releases", [])
        if r.get("name") == args.version
    ]
    if not found:
        call("DELETE", f"{API}/edits/{edit}")
        sys.exit(f"no release {args.version} on {args.source}: run status")
    put_release(
        edit,
        args.to,
        {
            "name": args.version,
            "versionCodes": found[0]["versionCodes"],
            "status": "draft" if args.draft else "completed",
            "releaseNotes": notes(edit, args.version),
        },
    )
    commit(edit)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("status").set_defaults(fn=status)
    u = sub.add_parser("upload")
    u.add_argument("version", help="X.Y.Z, as tagged")
    u.add_argument("aab", help="the bundle build.sh wrote")
    u.add_argument("--track", default="internal", help="internal (default), alpha, beta or production")
    u.set_defaults(fn=upload)
    pr = sub.add_parser("promote")
    pr.add_argument("version", help="X.Y.Z, as tagged")
    pr.add_argument("--from", dest="source", default="internal", help="the track it is on (default internal)")
    pr.add_argument("--to", required=True, help="alpha, beta or production")
    pr.set_defaults(fn=promote)
    for s in (u, pr):
        # Until the app's first release is published, Google Play takes only drafts.
        s.add_argument("--draft", action="store_true", help="a draft, rolled out in Play Console")
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
