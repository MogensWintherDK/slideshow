# Slideshow — Rails + Action Cable

A simple local-network photo slideshow with a phone remote.

- **Big screen** → `http://YOUR-IP:3000/` — full-screen slideshow
- **Phone remote** → `http://YOUR-IP:3000/remote` — play/pause, reset, delay, mode
- **Admin** → `http://YOUR-IP:3000/admin` — inspect the database, trigger reindex

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

- **Single album** — put JPEGs directly in `slides/`. They land in an auto-created album called `Default`.
- **Multiple albums** — create subfolders under `slides/` (e.g. `slides/holiday/`, `slides/family/`). Each subfolder becomes a named album.

Files are sorted alphabetically by filename within an album, so prefix them (`001_holiday.jpg`, `002_holiday.jpg`) if you want a specific order. The background indexer picks up new files within ~5 minutes; to force an immediate scan run `bundle exec rails runner Indexer.run`.

If you had photos in `public/slides/` from earlier versions, `bin/start` moves them to `slides/` for you on first run.

## Remote controls

| Control | Effect |
|---|---|
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
