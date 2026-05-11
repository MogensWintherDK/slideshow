# Architecture

This document describes how the slideshow is wired together. The README
covers how to *use* it; this one covers how it *works*.

## High-level shape

```
┌────────────────┐     POST /remote/command       ┌────────────────┐
│ Phone (remote) │ ──────────────────────────────▶│  Rails server  │
└────────────────┘                                │  (Puma, dev)   │
        ▲                                         │                │
        │   WebSocket /cable                      │   ActionCable  │
        │   (channel: SlideshowChannel)           │   stream:      │
        ▼                                         │   "slideshow"  │
┌────────────────┐  WS broadcasts                 │                │
│ Big screen     │ ◀──────────────────────────────│                │
│ (Chromium)     │                                │  SQLite +      │
│                │  GET /slideshow/playlist       │  filesystem    │
│                │ ──────────────────────────────▶│  cache         │
└────────────────┘  GET /slides/<album>/<file>    └────────────────┘
```

There are exactly two HTTP clients in normal operation: the phone (the
remote, `/remote`) and the big screen (`/`). They never talk to each
other directly — every state change is broadcast through ActionCable so
both pages can update in lockstep.

## Components

### Rails app

* **`SlideshowController`** — renders the big-screen shell (`#display`)
  and serves the paginated JSON playlist (`#playlist`).
* **`RemoteController`** — renders the phone remote (`#index`) and
  receives control POSTs (`#command`). Each command broadcasts a
  payload over ActionCable and (for stateful commands) writes to
  `SettingsStore`.
* **`SlideshowChannel`** — single ActionCable channel; the server
  broadcasts onto the `"slideshow"` stream and both pages subscribe to
  it. The client speaks the protocol via a small vanilla-WebSocket
  helper at `public/javascript/cable.js`; we don't use the official
  `@rails/actioncable` package or importmap, so no asset pipeline is
  involved.

### Indexer (`app/services/indexer.rb`)

Walks `public/slides/` and syncs the `albums` and `images` tables to
match what's on disk:

* Each **subdirectory** of `public/slides/` becomes a row in `albums`
  with `album_type = "local"` and the directory name as the album name.
* JPEGs **directly** in `public/slides/` are kept in a single album
  named `Default` (`path = ""`).
* New files are inserted; EXIF (`DateTimeOriginal` + GPS) is read once
  on insert and never re-parsed for existing rows.
* Files that disappear from disk are deleted from `images`.
  Subdirectories that disappear are deleted from `albums` (cascading
  to their images).
* Runs once at boot (started lazily on first request) and re-runs
  every 5 minutes in a single background thread that properly checks
  out an ActiveRecord connection.

### Geocoder (`app/services/geocoder.rb`)

Reverse-geocodes EXIF GPS coordinates via OpenStreetMap Nominatim:

* The indexer computes a 3-decimal-rounded lat/lon key
  (`Geocoder.key_for`) and stores it on the image. It then calls
  `Geocoder.resolve_async(lat, lon)`.
* A single background worker thread drains a queue at 1.1 s per
  request (Nominatim's stated rate limit), sends a `User-Agent`
  header, and upserts into `locations`.
* When a key resolves it broadcasts an
  `{ action: "location_resolved", key, location }` payload on the
  ActionCable stream. The big screen patches matching cached metadata
  in place — no reload required.

### Settings (`app/models/settings_store.rb`)

Tiny key/value façade around the `settings` table. Values are
JSON-encoded text so booleans, strings, and `nil` round-trip
correctly. Current keys:

| Key | Type | Meaning |
|---|---|---|
| `birthday_mode` | bool | Show the timeline on the slideshow |
| `birthday` | ISO date / null | Anchor date for the timeline |
| `play_mode` | `"linear"` / `"random"` | Auto-advance policy |
| `selected_album_id` | int / null | Which album to play (null = all merged) |

Defaults live in `SettingsStore::DEFAULTS`.

A legacy `db/settings.json` file (from before the DB-backed store
existed) is imported once on first read if the `settings` table is
empty.

## Database schema

```
albums
  id integer PK
  name string
  album_type string  -- "local" (extensible: "immich", …)
  path string        -- "" for Default, or subfolder name for others
  created_at, updated_at
  UNIQUE INDEX (album_type, path)

images
  id integer PK
  album_id FK → albums.id  ON DELETE CASCADE
  filename string
  taken_at datetime        -- EXIF DateTimeOriginal, mtime fallback
  latitude float, longitude float
  location_key string      -- "lat,lon" rounded to 3 decimals
  position integer         -- 0-based intra-album sort order
  created_at, updated_at
  UNIQUE INDEX (album_id, filename)
  INDEX (album_id, position)
  INDEX (location_key)

locations
  key string PK            -- "lat,lon" (3 decimals)
  country string
  area string              -- city / town / village / …
  resolved_at datetime

settings
  key string PK
  value text               -- JSON-encoded
  created_at, updated_at
```

## Playlist endpoint

```
GET /slideshow/playlist?from=N&count=M[&album_id=K]
```

```json
{
  "from":  0,
  "count": 10,
  "total": 541,
  "images": [
    {
      "url":          "/slides/holiday/IMG_001.jpg",
      "taken_at":     "2018-07-04T14:22:11+02:00",
      "location_key": "55.676,12.568",
      "location":     { "country": "Denmark", "area": "Copenhagen" },
      "album":        { "id": 3, "name": "holiday", "type": "local" }
    }
  ]
}
```

`location` is `null` if the key hasn't been resolved yet — the client
listens for `location_resolved` broadcasts and patches the cached entry
in place.

## Timeline endpoint

```
GET /slideshow/timeline[?album_id=K]
```

```json
{ "total": 541, "dates": ["2018-07-04T14:22:11+02:00", null, ...] }
```

`dates[i]` is the ISO `taken_at` for the image at playlist position `i`,
or `null` if EXIF reading failed for that file. The display page
fetches this once on boot so it can render every timeline marker
up-front, without waiting for `playlist` pagination to complete.

Ordering across the global playlist: by `album.name ASC`, then by
`image.position ASC`. If `selected_album_id` is set (or `album_id` is
passed as a query parameter), only that album's images are returned.

## Big-screen client

The display page is a **thin shell**: it renders just two `<img>`
slots in the DOM and bootstraps a small ES module. There is no per-photo
HTML element. This keeps Chromium's image-decode and DOM-element load
bounded so the Raspberry Pi 4K kiosk can run for hours.

State machine on the client:

```
fetch metadata page → ensure index N is loaded
                    ↓
                cross-fade slot[0] ↔ slot[1]
                    ↓
                kick off prefetch for N+1, N+2 via Image()
                    ↓
                wait for timer tick → next index
```

Bounded caches keep memory steady on a 4 GB Pi:

* `playlist` is a sparse array of metadata (~150 B per entry).
* `prefetchCache` is capped at 6 `Image()` instances; when the cap is
  reached the oldest entry has `img.src = ""` set to hint at GC, then
  is removed from the Map.
* The DOM only ever contains two `<img>` elements (the two slots) plus
  the timeline markers (one `<div>` per photo, but they're 4–28 px
  dots, not images).

## ActionCable protocol

All messages flow through the single `"slideshow"` stream. The phone
sends commands as HTTP POSTs to `/remote/command`; the controller
broadcasts the corresponding message to all subscribers (including
itself, but it ignores the echo).

| Action | Payload | Effect |
|---|---|---|
| `play` | — | Resume auto-advance |
| `pause` | — | Stop auto-advance |
| `reset` | — | Go to playlist index 0 |
| `skip` | `{delta: int}` | Move playlist index by ±N |
| `set_delay` | `{delay: int seconds}` | Change auto-advance interval |
| `set_play_mode` | `{mode: "linear"\|"random"}` | Change advance policy |
| `set_birthday_mode` | `{enabled: bool}` | Show/hide timeline |
| `set_birthday` | `{birthday: "YYYY-MM-DD" \| null}` | Set timeline anchor |
| `set_album` | `{album_id: int \| null}` | Change playlist scope; slideshow reloads |
| `location_resolved` | `{key, location}` | Pushed by Geocoder when a coord resolves |

## File layout (just the parts that matter)

```
app/
  channels/slideshow_channel.rb       # streams from "slideshow"
  controllers/
    application_controller.rb
    slideshow_controller.rb           # display + playlist
    remote_controller.rb              # remote UI + command POSTs
  models/
    album.rb image.rb
    setting.rb location.rb
    settings_store.rb                 # key/value façade
  services/
    indexer.rb                        # disk → DB sync
    geocoder.rb                       # reverse geocoding worker
  views/
    slideshow/display.html.erb
    remote/index.html.erb
    layouts/application.html.erb      # just <%= yield %>
public/
  javascript/cable.js                 # tiny vanilla WS Action Cable client
  slides/                             # photos (subfolders = albums)
db/
  migrate/                            # schema
  development.sqlite3                 # albums, images, locations, settings
config/
  routes.rb
  cable.yml                           # async adapter, no Redis needed
  initializers/start_indexer.rb       # kicks off the background indexer
```

## Adding a new album type (future Immich support)

The `albums.album_type` column was added with this in mind. To add a
new type:

1. Decide on a type string (e.g. `"immich"`) and add it to
   `Album#validates :album_type, inclusion: { in: %w[local immich] }`.
2. Add the source-specific URL logic to `Image#url`'s `case`
   statement.
3. Write a sync method that creates albums of that type. The
   indexer's local sync is a good template — split it into a
   per-type module if it grows.

`album.path` is currently only meaningful for local albums; remote
types can ignore it or repurpose it (e.g. as an Immich album UUID).

## Things deliberately kept simple

* No authentication — internal LAN use only.
* No multi-screen / multi-remote coordination — every subscriber
  receives every broadcast and applies it to its own local state.
* SQLite, in-process. No Redis: ActionCable uses the `async` adapter
  in both development and production.
* No asset pipeline (no Sprockets / Propshaft / importmap-rails).
  We ship two HTML templates and one tiny JS file.
