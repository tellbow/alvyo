# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]==2.10.1"]
# ///
"""A release of the Alvyo iOS app on the App Store, through the App Store
Connect API (https://developer.apple.com/documentation/appstoreconnectapi).

  uv run asc.py status  X.Y.Z               what App Store Connect has
  uv run asc.py prepare X.Y.Z [--build N]   the version, «Neuerungen», the build
  uv run asc.py submit  X.Y.Z               to App Review

«Neuerungen» per language are the «Was ist neu» lines (news_X_Y_Z in
web/messages/*.json). The key id and issuer id come from ASC_KEY_ID and
ASC_ISSUER_ID; the key file is read to sign the token and never printed.
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

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "ch.tellbow.alvyo"
REPO = Path(__file__).resolve().parents[3]
# A new version can be edited only in these states; later ones are Apple's.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


def token() -> str:
    key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    key = (Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8").read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id},
    )


def call(method: str, path: str, body: dict | None = None, **query) -> dict:
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r) if r.status != 204 else {}
    except urllib.error.HTTPError as e:
        errors = json.loads(e.read() or b"{}").get("errors", [])
        detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errors)
        sys.exit(f"{method} {path}: {e.code} {detail}")


def app_id() -> str:
    apps = call("GET", "/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"no app {BUNDLE_ID} in App Store Connect")
    return apps[0]["id"]


def version(app: str, v: str) -> dict | None:
    found = call(
        "GET", f"/apps/{app}/appStoreVersions", **{"filter[versionString]": v, "filter[platform]": "IOS"}
    )["data"]
    return found[0] if found else None


def builds(app: str, v: str, number: str | None) -> list[dict]:
    query = {"filter[app]": app, "filter[preReleaseVersion.version]": v, "sort": "-uploadedDate", "limit": "20"}
    if number:
        query["filter[version]"] = number
    return call("GET", "/builds", **query)["data"]


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


def localizations(version_id: str) -> list[dict]:
    return call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]


def status(args):
    app = app_id()
    for b in builds(app, args.version, None):
        a = b["attributes"]
        print(f"build {a['version']}: {a['processingState']}, uploaded {a['uploadedDate']}")
    ver = version(app, args.version)
    if not ver:
        print(f"no App Store version {args.version} yet")
        return
    print(f"version {args.version}: {ver['attributes']['appStoreState']}")
    build = call("GET", f"/appStoreVersions/{ver['id']}/build")["data"]
    print("build chosen: " + (build["attributes"]["version"] if build else "none"))
    for loc in localizations(ver["id"]):
        print(f"{loc['attributes']['locale']}: {loc['attributes'].get('whatsNew')}")


def prepare(args):
    texts = news(args.version)
    app = app_id()

    # The build, once Apple has processed it (5 to 30 minutes after the upload).
    end = time.time() + 45 * 60
    while True:
        found = builds(app, args.version, args.build)
        state = found[0]["attributes"]["processingState"] if found else "not uploaded"
        if state == "VALID":
            build = found[0]
            break
        if state in ("FAILED", "INVALID") or time.time() > end:
            sys.exit(f"build {args.build or 'of ' + args.version}: {state}")
        print(f"build {args.build or 'of ' + args.version}: {state}, waiting", flush=True)
        time.sleep(60)

    ver = version(app, args.version)
    if ver is None:
        ver = call(
            "POST",
            "/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": args.version, "releaseType": "AFTER_APPROVAL"},
                    "relationships": {"app": {"data": {"type": "apps", "id": app}}},
                }
            },
        )["data"]
        print(f"version {args.version} created")
    elif ver["attributes"]["appStoreState"] not in EDITABLE:
        sys.exit(f"version {args.version} is {ver['attributes']['appStoreState']}: no longer editable")

    # The localizations are copied from the last version; each gets its
    # language's line (de-DE → de, en-US and en-GB → en).
    missing = []
    for loc in localizations(ver["id"]):
        locale = loc["attributes"]["locale"]
        text = texts.get(locale.split("-")[0])
        if text is None:
            missing.append(locale)
            continue
        call(
            "PATCH",
            f"/appStoreVersionLocalizations/{loc['id']}",
            {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}},
        )
        print(f"{locale}: {text}")
    if missing:
        sys.exit("no text for " + ", ".join(missing))

    call(
        "PATCH",
        f"/appStoreVersions/{ver['id']}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    print(f"build {build['attributes']['version']} chosen for {args.version}")


def submit(args):
    app = app_id()
    ver = version(app, args.version)
    if ver is None:
        sys.exit(f"no App Store version {args.version}: run prepare first")
    if not call("GET", f"/appStoreVersions/{ver['id']}/build")["data"]:
        sys.exit(f"version {args.version} has no build: run prepare first")
    sub = call(
        "POST",
        "/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        },
    )["data"]
    call(
        "POST",
        "/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}},
                },
            }
        },
    )
    call(
        "PATCH",
        f"/reviewSubmissions/{sub['id']}",
        {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}},
    )
    print(f"version {args.version} submitted for review")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    for name, fn in (("status", status), ("prepare", prepare), ("submit", submit)):
        s = sub.add_parser(name)
        s.add_argument("version", help="X.Y.Z, as tagged")
        if name == "prepare":
            s.add_argument("--build", help="the build number (default: the newest of that version)")
        s.set_defaults(fn=fn)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
