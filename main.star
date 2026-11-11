"""
Sonos Now Playing for Niblet.

Shows the song title, artist and album art for whatever is playing on a Sonos
speaker, using the Sonos Control API (cloud). When nothing is playing the app
returns no frames, so it is skipped in the display rotation.
"""

load("cache.star", "cache")
load("encoding/base64.star", "base64")
load("hash.star", "hash")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

TOKEN_URL = "https://api.sonos.com/login/v3/oauth/access"
CONTROL_API = "https://api.ws.sonos.com/control/api/v1"

PLAYING_STATES = ["PLAYBACK_STATE_PLAYING", "PLAYBACK_STATE_BUFFERING"]

# Album art is only fetched from hosts declared in manifest.yaml. Hosted
# rendering blocks every other host, so anything else gets a placeholder.
ART_HOSTS = [
    "i.scdn.co",
    "mosaic.scdn.co",
    "image-cdn-ak.spotifycdn.com",
    "image-cdn-fa.spotifycdn.com",
    "is1-ssl.mzstatic.com",
    "is2-ssl.mzstatic.com",
    "is3-ssl.mzstatic.com",
    "is4-ssl.mzstatic.com",
    "is5-ssl.mzstatic.com",
    "m.media-amazon.com",
    "images-na.ssl-images-amazon.com",
    "resources.tidal.com",
    "lh3.googleusercontent.com",
    "yt3.ggpht.com",
    "i.ytimg.com",
    "cdn-profiles.tunein.com",
    "cdn-radiotime-logos.tunein.com",
    "e-cdns-images.dzcdn.net",
    "cdn-images.dzcdn.net",
    "i1.sndcdn.com",
    "f4.bcbits.com",
    "static.qobuz.com",
    "content-images.p-cdn.com",
    "i.iheart.com",
]

ART_SIZE = 32
TEXT_WIDTH = 64 - ART_SIZE - 2

def main(config):
    client_id = (config.get("client_id") or "").strip()
    client_secret = (config.get("client_secret") or "").strip()
    refresh_token = (config.get("refresh_token") or "").strip()

    if not client_id or not client_secret or not refresh_token:
        return message_frame("Sonos", "Add Sonos keys in settings")

    token = get_access_token(client_id, client_secret, refresh_token)
    if token == None:
        return message_frame("Sonos", "Sign-in failed")

    headers = {"Authorization": "Bearer " + token}
    room = (config.get("room") or "").strip().lower()

    group = find_group(headers, room)
    if group == None:
        # Nothing playing: show nothing.
        return []

    track = get_track(headers, group["id"])
    if track == None or not track["title"]:
        return []

    return now_playing_frame(track, config.bool("show_album", True))

# ---------------------------------------------------------------------------
# Sonos API
# ---------------------------------------------------------------------------

def get_access_token(client_id, client_secret, refresh_token):
    """Exchanges the long-lived refresh token for an access token (cached)."""
    cache_key = "sonos_token_" + hash.sha256(client_id + ":" + refresh_token)[:24]
    cached = cache.get(cache_key)
    if cached:
        return cached

    basic = base64.encode(client_id + ":" + client_secret)
    response = http.post(
        TOKEN_URL,
        headers = {
            "Authorization": "Basic " + basic,
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        },
        form_body = {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
    )
    if response.status_code != 200:
        print("Sonos token refresh failed: HTTP %d" % response.status_code)
        return None

    data = response.json()
    token = data.get("access_token")
    if not token:
        return None

    # Sonos access tokens last 24 hours; refresh a little early.
    expires_in = int(data.get("expires_in") or 3600)
    cache.set(cache_key, token, ttl_seconds = max(60, expires_in - 600))
    return token

def api_get(headers, path, ttl_seconds):
    response = http.get(CONTROL_API + path, headers = headers, ttl_seconds = ttl_seconds)
    if response.status_code != 200:
        print("Sonos API %s failed: HTTP %d" % (path.split("/")[-1], response.status_code))
        return None
    return response.json()

def find_group(headers, room):
    """Returns the playing group to show, or None when nothing is playing."""
    households = api_get(headers, "/households", 3600)
    if households == None:
        return None

    for household in households.get("households", []):
        data = api_get(headers, "/households/%s/groups" % household["id"], 20)
        if data == None:
            continue

        player_names = {}
        for player in data.get("players", []):
            player_names[player.get("id")] = (player.get("name") or "").lower()

        for group in data.get("groups", []):
            if group.get("playbackState") not in PLAYING_STATES:
                continue
            if not room:
                return group
            names = [(group.get("name") or "").lower()]
            for player_id in group.get("playerIds", []):
                names.append(player_names.get(player_id, ""))
            for name in names:
                if name and (name == room or room in name):
                    return group

    return None

def get_track(headers, group_id):
    data = api_get(headers, "/groups/%s/playbackMetadata" % group_id, 20)
    if data == None:
        return None

    item = data.get("currentItem") or {}
    track = item.get("track") or {}
    container = data.get("container") or {}
    stream = data.get("streamInfo")

    artist = (track.get("artist") or {}).get("name") or ""
    album = (track.get("album") or {}).get("name") or ""
    title = track.get("name") or ""

    # Radio stations often have no track name; fall back to station info.
    if not title:
        title = container.get("name") or ""
        if not artist and type(stream) == "string":
            artist = stream

    return {
        "title": title,
        "artist": artist,
        "album": album,
        "image_url": track.get("imageUrl") or container.get("imageUrl") or "",
    }

def fetch_art(url):
    if not url.startswith("https://"):
        return None
    host = url[len("https://"):].split("/")[0].split("@")[-1].split(":")[0].lower()
    if host not in ART_HOSTS:
        return None
    response = http.get(url, ttl_seconds = 3600)
    if response.status_code != 200:
        return None
    return response.body()

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def scroll_text(content, font, color):
    return render.Marquee(
        width = TEXT_WIDTH,
        child = render.Text(content = content, font = font, color = color),
    )

def now_playing_frame(track, show_album):
    art = fetch_art(track["image_url"])
    if art != None:
        cover = render.Image(src = art, width = ART_SIZE, height = ART_SIZE)
    else:
        cover = placeholder_art()

    lines = [scroll_text(track["title"], "tb-8", "#ffffff")]
    if track["artist"]:
        lines.append(scroll_text(track["artist"], "tom-thumb", "#b3b3b3"))
    if show_album and track["album"]:
        lines.append(scroll_text(track["album"], "tom-thumb", "#6e6e6e"))

    return render.Root(
        delay = 80,
        max_age = 90,
        child = render.Row(
            children = [
                cover,
                render.Padding(
                    pad = (2, 0, 0, 0),
                    child = render.Box(
                        width = TEXT_WIDTH,
                        height = 32,
                        child = render.Column(
                            main_align = "space_evenly",
                            cross_align = "start",
                            expanded = True,
                            children = lines,
                        ),
                    ),
                ),
            ],
        ),
    )

def placeholder_art():
    """A simple music-note tile used when album art is unavailable."""
    return render.Box(
        width = ART_SIZE,
        height = ART_SIZE,
        color = "#1f1f1f",
        child = render.Stack(
            children = [
                render.Box(width = 20, height = 22),
                render.Padding(pad = (12, 2, 0, 0), child = render.Box(width = 2, height = 15, color = "#9a9a9a")),
                render.Padding(pad = (12, 2, 0, 0), child = render.Box(width = 7, height = 2, color = "#9a9a9a")),
                render.Padding(pad = (7, 15, 0, 0), child = render.Circle(diameter = 7, color = "#9a9a9a")),
            ],
        ),
    )

def message_frame(title, detail):
    return render.Root(
        child = render.Box(
            color = "#000000",
            child = render.Column(
                main_align = "center",
                cross_align = "center",
                expanded = True,
                children = [
                    render.Text(content = title, font = "tb-8", color = "#ffffff"),
                    render.WrappedText(
                        content = detail,
                        font = "tom-thumb",
                        color = "#b3b3b3",
                        width = 60,
                        align = "center",
                    ),
                ],
            ),
        ),
    )

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "client_id",
                name = "Sonos client key",
                desc = "Key from your integration at developer.sonos.com.",
                icon = "key",
                secret = True,
            ),
            schema.Text(
                id = "client_secret",
                name = "Sonos client secret",
                desc = "Secret from your integration at developer.sonos.com.",
                icon = "key",
                secret = True,
            ),
            schema.Text(
                id = "refresh_token",
                name = "Sonos refresh token",
                desc = "Created once with tools/get_sonos_token.py.",
                icon = "key",
                secret = True,
            ),
            schema.Text(
                id = "room",
                name = "Room",
                desc = "Optional speaker or room name. Leave empty to show any playing speaker.",
                icon = "speaker",
                default = "",
            ),
            schema.Toggle(
                id = "show_album",
                name = "Show album name",
                desc = "Show the album name under the artist.",
                icon = "compactDisc",
                default = True,
            ),
        ],
    )
