# Sonos Now Playing for Niblet

A [Niblet](https://docs.heyniblet.com) app for the 64×32 display. It shows the
**song title**, **artist** and **album art** playing on your Sonos speakers.
When nothing is playing (paused, stopped or idle), the app returns no frames
and Niblet skips it in your rotation, so the display shows nothing for it.

```
┌──────────┬─────────────────────┐
│          │ Song title  (scroll)│
│  album   │ Artist              │
│  cover   │ Album (optional)    │
│  32×32   │                     │
└──────────┴─────────────────────┘
```

## How it works

Niblet renders apps in its cloud, which can't reach speakers on your home
network. So the app reads playback from your Sonos account through the
official [Sonos Control API](https://docs.sonos.com/docs/control):

1. It swaps your Sonos refresh token for an access token (cached for about 23 hours).
2. It lists your households and groups and picks the first group that is
   playing. If you set **Room**, it picks the group with that room in it.
3. It reads that group's `playbackMetadata` (track name, artist, album, image URL).
4. It downloads the album art and scales it to 32×32.

The app refreshes every 30 seconds (`refresh_interval_seconds`, the minimum
Niblet allows).

Album art comes from each music service's image CDN (Spotify, Apple Music,
Amazon, Tidal, YouTube Music, TuneIn, Deezer and others). Niblet only allows
hosts listed in `manifest.yaml`. Art from any other host shows a music-note
placeholder instead. To add a service, add its image host to both
`network_hosts` in `manifest.yaml` and `ART_HOSTS` in `main.star`.

## Setup

### 1. Create a Sonos integration (one time)

1. Sign in at <https://developer.sonos.com> with your Sonos account.
2. Create a **Control Integration** and add a **key**. Note its **client
   key** and **client secret**.
3. Add a **redirect URI** to the key. It must be HTTPS, but it doesn't need
   to serve a page. Any URL you control works, for example
   `https://example.com/sonos-callback`.

### 2. Get a refresh token (one time)

On your computer:

```sh
python3 tools/get_sonos_token.py
```

Enter the client key, secret and redirect URI. Sign in to Sonos in the
browser window that opens and allow access. Then paste the address your
browser lands on back into the script, and it prints your **refresh token**.

### 3. Build, install and configure with the Niblet CLI

```sh
curl -fsSL https://cdn.heyniblet.com/install.sh | sh   # install the CLI
niblet apps validate .
niblet serve .                    # local preview at http://localhost:8080
niblet auth login
niblet apps push .                # prints a revision ID
niblet devices                    # find your device ID
niblet apps install <REVISION_ID> --device <DEVICE_ID>
```

Then open **Manage** on the installed app in the Niblet dashboard and enter:

| Setting | Value |
| - | - |
| Sonos client key | from step 1 |
| Sonos client secret | from step 1 |
| Sonos refresh token | from step 2 |
| Room | optional, e.g. `Living Room` |
| Show album name | on/off |

These three credentials are declared as user-owned secret fields, so Niblet
stores them separately from ordinary settings. Never commit them to this repo.

To test locally with `niblet serve .`, pass them as preview URL parameters,
for example `?client_id=...&client_secret=...&refresh_token=...`.
Use that only on your own computer.

## Files

- `main.star`: the app (Starlark)
- `manifest.yaml`: Niblet project manifest (credentials and allowed network hosts)
- `tools/get_sonos_token.py`: one-time OAuth helper to get the refresh token
