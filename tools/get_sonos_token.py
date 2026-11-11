#!/usr/bin/env python3
"""One-time helper: get a Sonos refresh token for the Niblet app.

Run it on your own computer:

    python3 tools/get_sonos_token.py

It asks for your Sonos integration's client key, client secret and redirect
URI, opens the Sonos sign-in page, then exchanges the code Sonos sends back
for a refresh token. Paste the three values into the app's settings in
Niblet. Nothing is saved to disk.
"""

import base64
import getpass
import json
import secrets
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

AUTHORIZE_URL = "https://api.sonos.com/login/v3/oauth"
TOKEN_URL = "https://api.sonos.com/login/v3/oauth/access"


def main():
    client_id = input("Sonos client key: ").strip()
    client_secret = getpass.getpass("Sonos client secret (hidden): ").strip()
    redirect_uri = input("Redirect URI registered on the integration: ").strip()

    state = secrets.token_urlsafe(16)
    url = AUTHORIZE_URL + "?" + urllib.parse.urlencode({
        "client_id": client_id,
        "response_type": "code",
        "state": state,
        "scope": "playback-control-all",
        "redirect_uri": redirect_uri,
    })

    print("\nSign in to Sonos and allow access:\n\n  " + url + "\n")
    webbrowser.open(url)
    print("After you allow access, your browser goes to your redirect URI.")
    print("The page may not load. That's fine: copy the full address from the address bar.\n")
    redirected = input("Paste the full redirected URL (or just the code): ").strip()

    if redirected.startswith("http"):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(redirected).query)
        if query.get("state", [""])[0] != state:
            raise SystemExit("State mismatch: start again.")
        code = query.get("code", [""])[0]
    else:
        code = redirected
    if not code:
        raise SystemExit("No authorization code found.")

    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    request = urllib.request.Request(
        TOKEN_URL,
        data=urllib.parse.urlencode({
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
        }).encode(),
        headers={
            "Authorization": "Basic " + basic,
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"Token exchange failed: HTTP {error.code} {error.read().decode()}")

    print("\nSuccess. Enter these in the app's settings in Niblet:\n")
    print("  Sonos refresh token: " + data["refresh_token"])
    print("\n(Use the same client key and client secret you entered above.)")


if __name__ == "__main__":
    main()
