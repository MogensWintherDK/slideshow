# Slideshow — Rails + Action Cable

A simple local-network photo slideshow with a phone remote.

- **Big screen** → `http://YOUR-IP:3000/` — full-screen slideshow (multi-screen supported; each browser gets a 4-character ID)
- **Phone remote** → `http://YOUR-IP:3000/remote` — pick which screen to control, play/pause, reset, delay, mode
- **Admin** → `http://YOUR-IP:3000/admin` — inspect the database, see what each screen is showing live, nickname your screens, trigger reindex

For how it all works under the hood, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Requirements

- Ruby 3.0 or newer (any recent rbenv/asdf/Homebrew/mise install works)
- That's it — Bundler, Rails, SQLite and Puma are pulled in by `bin/start`

## Quick start

From this folder:

```
bin/start
```

The script installs gems on first run, applies database migrations, prints the IPs you can reach the app on, then boots the server bound to `0.0.0.0:3000`. Re-run it any time to start the server again — subsequent runs skip the install step.

Stop the server with `Ctrl+C`.

## Adding your photos

Drop JPEG files into `slides/` (at the project root — *not* inside `public/`). You have two options:

- **Single source** — put JPEGs directly in `slides/`. They land in an auto-created Photos source called `Default`.
- **Multiple sources** — create subfolders under `slides/` (e.g. `slides/holiday/`, `slides/family/`). Each subfolder becomes a named Photos source.

Photos within a source are ordered by EXIF `taken_at` so they play oldest → newest. The background indexer picks up new files within ~5 minutes; to force an immediate scan run `bundle exec rails runner Indexer.run`.

If you had photos in `public/slides/` from earlier versions, `bin/start` moves them to `slides/` for you on first run.

## Sources of other types

A **source** has a type. Three types are supported today:

- **Photos** — the indexer-managed folders under `slides/` described above.
- **Web** — a URL that the slideshow loads in a fullscreen iframe. Useful for dashboards, news feeds, or any web page.
- **Immich** — link a remote Immich album. The server fetches the asset list and serves the bytes via cached proxy, so it behaves just like a Photos source on the screens.

Add or remove sources from `/admin/sources`. To use Immich first go to **Settings** in the admin and paste your Immich API key (and adjust the base URL if it isn't the default `https://immich.mowin.dk`). Then on the Sources page pick the **Immich Photos** type — the album dropdown populates from your Immich server automatically. After saving, the indexer immediately pulls the album's asset list; afterwards the source behaves like a normal Photos source on the remote and the screens.

`IMMICH_API_KEY` and `IMMICH_BASE_URL` can also be set as environment variables (they're used as fallbacks if nothing is configured in the admin UI).

## Remote controls

| Control | Effect |
|---|---|
| Screen | Pick which big screen to control, or "All screens" |
| Album | Pick which album to play, or "All albums" |
| Play / Pause | Toggles automatic advancement |
| -100 / -10 / +10 / +100 | Jump forwards or backwards |
| Reset | Jumps to the first image of the current album and resumes playing |
| Play Mode | Switch between Linear and Random advance |
| + / − | Adjusts delay by 1 second per tap |
| 3s / 5s / 10s / 15s / 30s | Quick preset delay buttons |
| Birthday Mode | Show a timeline at the bottom of the slideshow with the person's age at each photo |

## Slideshow behaviour

- Default delay: **5 seconds**
- Transition: **crossfade** (0.8s)
- Loops continuously after the last image
- When paused: freezes on the current image

## Finding your IP

`bin/start` prints the likely candidates. If you'd rather look it up yourself:
- macOS: `ipconfig getifaddr en0` (Wi-Fi) or System Settings → Network
- Linux: `hostname -I`
