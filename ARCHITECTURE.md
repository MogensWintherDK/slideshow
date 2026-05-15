# Architecture

This document describes how the slideshow is wired together. The README
covers how to *use* it; this one covers how it *works*.

## High-level shape

```
┌────────────────┐     POST /remote/command            ┌────────────────┐
│ Phone (remote) │ ───────────────────────────────────▶│  Rails server  │
└────────────────┘                                     │  (Puma, dev)   │
        ▲                                              │                │
        │   WebSocket /cable                           │   ActionCable  │
        │   (channel: SlideshowChannel)                │   stream:      │
        ▼                                              │   "slideshow"  │
┌────────────────┐  WS broadcasts                      │                │
│ Big screen     │ ◀───────────────────────────────────│                │
│ (Chromium)     │                                     │  SQLite +      │
│                │  GET /slideshow/playlist            │  filesystem    │
│                │ ───────────────────────────────────▶│  cache         │
│                │  GET /slideshow/timeline            │                │
│                │ ───────────────────────────────────▶│                │
│                │  GET /slideshow/sources/:a/images/:i │                │
│                │ ───────────────────────────────────▶│  ┌──────────┐  │
└────────────────┘   (ETag + 1y Cache-Control)         │  │ slides/  │  │
                                                       │  └──────────┘  │
                                                       └────────────────┘
```

The `slides/` folder lives at the project root, *outside* `public/`,
so photos are never reachable except through the cached image
endpoint.

There are exactly two HTTP clients in normal operation: the phone (the
remote, `/remote`) and the big screen (`/`). They never talk to each
other directly — every state change is broadcast through ActionCable so
both pages can update in lockstep.

## Components

### Rails app

* **`SlideshowController`** — renders the big-screen shell (`#display`)
  and serves the paginated JSON playlist (`#playlist`), per-position
  date list (`#timeline`), image bytes with long-lived cache headers
  (`#image`), and the per-screen state report endpoint (`#update_state`).
* **`RemoteController`** — renders the phone remote (`#index`) and
  receives control POSTs (`#command`). Each command broadcasts a
  payload over ActionCable; commands target either a specific screen
  (via `target_screen_id`) or all screens. Per-screen settings are
  written to the `screens` table.
* **`AdminController`** — dashboard at `/admin` plus a manual reindex
  button. Shows database counts, source list with image counts,
  paginated images, the location cache, indexer status, a Screens page
  (nicknames are editable; each row has a "Delete screen" action that
  also tidies up an emptied group), and a Groups page that lists the
  per-group playback configuration (each row has a "Delete" action
  that cascades to remove all member screens after an explicit confirm).
  The Settings page is kept around as a legacy view since the table
  itself is no longer written to.
* **`ScreenIdentity` concern** — finds or creates a `Screen` from a
  signed `screen_token` cookie on the first hit to `/`. The cookie
  persists for 5 years, so a given browser keeps the same 4-character
  screen code (and all its per-screen settings) until the cookie is
  cleared.
* **`SlideshowChannel`** — single ActionCable channel; the server
  broadcasts onto the `"slideshow"` stream and both pages subscribe to
  it. The client speaks the protocol via a small vanilla-WebSocket
  helper at `public/javascript/cable.js`; we don't use the official
  `@rails/actioncable` package or importmap, so no asset pipeline is
  involved.

### Indexer (`app/services/indexer.rb`)

Walks `slides/` (at the project root) and syncs the `sources` and
`images` tables to match what's on disk:

* Each **subdirectory** of `slides/` becomes a row in `sources` with
  `source_type = "photos"` and the directory name as the source name.
* JPEGs **directly** in `slides/` are kept in a single source named
  `Default` (`path = ""`).
* New files are inserted; EXIF (`DateTimeOriginal` + GPS) is read once
  on insert. We also re-read EXIF if the file's mtime is newer than
  the image record's `updated_at` — that bumps the `?v=` cache buster
  so the browser refetches the changed image.
* Files that disappear from disk are deleted from `images`.
  Subdirectories that disappear are deleted from `sources` (cascading
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
| `selected_source_id` | int / null | Which source to play (null = all merged) |

Defaults live in `SettingsStore::DEFAULTS`.

A legacy `db/settings.json` file (from before the DB-backed store
existed) is imported once on first read if the `settings` table is
empty.

## Database schema

```
sources
  id integer PK
  name string
  source_type string  -- "photos" | "web" | "immich"
  url string          -- iframe URL for web sources
  external_id string  -- Immich album UUID for immich sources
  path string        -- "" for Default, or subfolder name for others
  created_at, updated_at
  UNIQUE INDEX (source_type, path)

images
  id integer PK
  source_id FK → sources.id  ON DELETE CASCADE
  filename string             -- Immich asset UUID for immich-typed rows
  external_id string          -- Immich asset UUID (also)
  taken_at datetime        -- EXIF DateTimeOriginal, mtime fallback
  latitude float, longitude float
  location_key string      -- "lat,lon" rounded to 3 decimals
  position integer         -- 0-based intra-source sort order
  created_at, updated_at
  UNIQUE INDEX (source_id, filename)
  INDEX (source_id, position)
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

screens
  id integer PK
  code string UNIQUE         -- 4-char Chromecast-style "AB3F"
  cookie_token string UNIQUE
  nickname string            -- editable in /admin/screens
  last_seen_at datetime      -- bumped on every request from this screen
  current_image_id integer   -- reported by client after each advance
  current_position integer
  primed boolean             -- false until first remote command (splash gate)
  screen_group_id FK → screen_groups.id   -- every screen has exactly one group
  created_at, updated_at

screen_groups
  id integer PK
  name string                -- optional group label
  selected_source_id integer  -- nil = all sources
  play_mode string           -- "linear" or "random"
  delay_seconds integer
  playing boolean
  birthday_mode boolean      -- show the per-group timeline overlay?
  birthday string            -- ISO date anchoring the timeline
  created_at, updated_at
```

## Playlist endpoint

```
GET /slideshow/playlist?from=N&count=M[&source_id=K]
```

```json
{
  "from":  0,
  "count": 10,
  "total": 541,
  "images": [
    {
      "url":          "/slideshow/sources/3/images/47?v=1746710400",
      "taken_at":     "2018-07-04T14:22:11+02:00",
      "location_key": "55.676,12.568",
      "location":     { "country": "Denmark", "area": "Copenhagen" },
      "source":        { "id": 3, "name": "holiday", "type": "local" }
    }
  ]
}
```

`location` is `null` if the key hasn't been resolved yet — the client
listens for `location_resolved` broadcasts and patches the cached entry
in place.

## Image endpoint

```
GET /slideshow/sources/:source_id/images/:image_id?v=<updated_at_unix>
```

Streams the JPEG bytes. Both ids in the path are validated — a stale
URL pointing at the wrong source returns 404.

Cache headers:
* `ETag: "<image_id>-<file_mtime_unix>"` (strong)
* `Last-Modified: <file_mtime>`
* `Cache-Control: public, max-age=31536000` (1 year)

A conditional `GET` with `If-None-Match` returns `304 Not Modified`
with no body. If the file is replaced on disk, the indexer touches the
record on its next scan, which bumps `updated_at`; the URL's `?v=`
parameter changes; the browser cache key changes; the new file is
fetched. This is why photos live outside `public/` — we want the
request to always go through Rails so these headers are applied.

## Timeline endpoint

```
GET /slideshow/timeline[?source_id=K]
```

```json
{ "total": 541, "dates": ["2018-07-04T14:22:11+02:00", null, ...] }
```

`dates[i]` is the ISO `taken_at` for the image at playlist position `i`,
or `null` if EXIF reading failed for that file. The display page
fetches this once on boot so it can render every timeline marker
up-front, without waiting for `playlist` pagination to complete.

Ordering across the global playlist: by `source.name ASC`, then by
`image.position ASC`. If `selected_source_id` is set (or `source_id` is
passed as a query parameter), only that source's images are returned.

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

## Screens and groups (Sonos-style)

Every browser that opens `/` is registered as a `Screen` record on
first visit. A signed `screen_token` cookie maps that browser to its
record forever (5-year TTL). The screen is shown its 4-character code
as a big Chromecast-style splash at boot.

A new screen starts with `primed = false` and stays on the splash
until a remote sends it a command — exactly like a Chromecast waiting
to be cast to. Once a remote first talks to a screen (`broadcast_playback`
or `/screen/state`) the column is flipped to `true` and persisted, so
subsequent reloads auto-resume rather than dropping back to the splash.
Existing screens were backfilled to `primed = true` during the
migration so they keep their previous auto-start behaviour.

After every slide advance, the display POSTs the new
`(image_id, position)` to `/screen/state`. The admin page polls
`/admin/screens.json` every 3 seconds to render a live thumbnail grid
of what each screen is currently showing.

Every screen belongs to exactly one `ScreenGroup`. A "standalone"
screen is just the only member of its group. **Playback state lives on
the group**, not on the screen — `selected_source_id`, `play_mode`,
`delay_seconds`, and `playing` are columns on `screen_groups`. So:

* Putting two screens in one group makes them share an source, play
  mode, delay, and play/pause state.
* Splitting a screen out moves it into a fresh group (with the default
  settings).
* If a group has no members it's deleted automatically.

Group management — adding / removing screens, renaming — lives on the
phone remote. The remote's first view is a list of groups; tapping
into a group opens the controls for *that* group, with a Members card
where you can `+` other screens in or `×` members out.

## ActionCable protocol

All messages flow through the single `"slideshow"` stream. The phone
sends commands as HTTP POSTs to `/remote/command`; the controller
broadcasts the corresponding message to all subscribers. **Every
broadcast includes a `target_screen_ids` array** (the screen ids the
command should apply to). The server resolves the targeted group to its
member screens before broadcasting. A display applies the message only
if `target_screen_ids` is `null` (broadcast to all) or contains its own
screen id.

| Action | Payload | Effect |
|---|---|---|
| `play` | — | Resume auto-advance |
| `pause` | — | Stop auto-advance |
| `reset` | — | Jump to the first image of the source containing the current slide |
| `skip` | `{delta: int}` | Move playlist index by ±N |
| `set_delay` | `{delay: int seconds}` | Change auto-advance interval |
| `set_play_mode` | `{mode: "linear"\|"random"}` | Change advance policy |
| `set_birthday_mode` | `{enabled: bool}` | Show/hide timeline |
| `set_birthday` | `{birthday: "YYYY-MM-DD" \| null}` | Set timeline anchor |
| `set_source` | `{source_id: int \| null}` | Change playlist scope; slideshow reloads |
| `sources_changed` | `{sources: [{id, name, type}, ...]}` | Pushed by Indexer when sources are added or removed; the remote rebuilds its source selector in place |
| `screens_changed` | `{screens: [...]}` | Pushed when a new screen registers or a nickname changes; the remote rebuilds its screen picker |
| `wake` | `{target_screen_ids: [...]}` | Pushed after a screen is added to a group; tells the target displays to leave the splash and start playing |
| `scroll` | `{delta: ±1, target_screen_ids: [...]}` | Web sources only — translate the iframe by 80% of viewport up or down |
| `reload_page` | `{target_screen_ids: [...]}` | Web sources only — reload the iframe and reset scroll |
| `location_resolved` | `{key, location}` | Pushed by Geocoder when a coord resolves |

## File layout (just the parts that matter)

```
app/
  channels/slideshow_channel.rb       # streams from "slideshow"
  controllers/
    application_controller.rb
    slideshow_controller.rb           # display + playlist + timeline + image
    remote_controller.rb              # remote UI + command POSTs
    admin_controller.rb               # /admin read-only inspection
  models/
    source.rb image.rb
    setting.rb location.rb
    settings_store.rb                 # key/value façade
  services/
    indexer.rb                        # disk → DB sync
    geocoder.rb                       # reverse geocoding worker
  views/
    slideshow/display.html.erb
    remote/index.html.erb
    admin/*.html.erb                  # dashboard, sources, images, locations, settings
    layouts/application.html.erb      # just <%= yield %>
    layouts/admin.html.erb            # shared admin shell (dark theme)
public/
  javascript/cable.js                 # tiny vanilla WS Action Cable client
slides/                               # photos (subfolders = sources); NOT under public/
db/
  migrate/                            # schema
  development.sqlite3                 # sources, images, locations, settings
config/
  routes.rb
  cable.yml                           # async adapter, no Redis needed
  initializers/start_indexer.rb       # kicks off the background indexer
```

## Adding a new source type (future Immich support)

The `sources.source_type` column was added with this in mind. To add a
new type:

1. Decide on a type string (e.g. `"immich"`) and add it to
   `Source::TYPES` (currently `%w[photos web]`).
2. Add the source-specific URL logic to `Image#url`'s `case`
   statement.
3. Write a sync method that creates sources of that type. The
   indexer's local sync is a good template — split it into a
   per-type module if it grows.

`source.path` is only meaningful for photos sources; remote
types can ignore it or repurpose it (e.g. as an Immich source UUID).

## Things deliberately kept simple

* No authentication — internal LAN use only.
* No multi-screen / multi-remote coordination — every subscriber
  receives every broadcast and applies it to its own local state.
* SQLite, in-process. No Redis: ActionCable uses the `async` adapter
  in both development and production.
* No asset pipeline (no Sprockets / Propshaft / importmap-rails).
  We ship two HTML templates and one tiny JS file.
