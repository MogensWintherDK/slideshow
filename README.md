# Slideshow — Rails + Action Cable

A simple, local-network photo slideshow with a phone remote.

- **Big screen** → `http://YOUR-IP:3000/` — full-screen slideshow
- **Phone remote** → `http://YOUR-IP:3000/remote` — play/pause, reset, delay control

## Requirements

- Ruby 3.0 or newer (any version that ships with macOS Sonoma+ via `rbenv`/`asdf`/Homebrew works)
- That's it — Bundler, Rails, SQLite and Puma are pulled in by `bin/start`

## Quick start

From this folder:

```
bin/start
```

The script handles everything the first time: installs gems, creates the SQLite database, prints the IPs you can reach the app on, then boots the server bound to `0.0.0.0:3000`. Re-run it any time you want to start the server again — subsequent runs skip the install step.

Stop the server with `Ctrl+C`.

## Manual setup (if you'd rather)

```
bundle install
bundle exec rails db:create
bundle exec rails server -b 0.0.0.0
```

## Adding your photos

Drop JPEG files into `public/slides/`. They are sorted alphabetically by filename, so prefix them (e.g. `001_holiday.jpg`, `002_holiday.jpg`) if you want a specific order.

The display picks up all images at page load. After dropping new files in, just reload the slideshow page — the remote's **Reset** button restarts from image 1.

The folder ships with eight numbered test images so you can verify everything works before you copy in your real photos.

## Remote controls

| Control | Effect |
|---|---|
| Play / Pause | Toggles automatic advancement |
| Reset | Returns to image 1 and resumes playing |
| + / − | Adjusts delay by 1 second per tap |
| 3s / 5s / 10s / 15s / 30s | Quick preset delay buttons |

## Slideshow behaviour

- Default delay: **5 seconds**
- Transition: **crossfade** (0.8s)
- Loops continuously after the last image
- When paused: freezes on the current image

## Finding your IP

`bin/start` prints the likely candidates. If you'd rather look it up yourself:
- macOS: `ipconfig getifaddr en0` (Wi-Fi) or System Settings → Network
- Linux: `hostname -I`
# slideshow
