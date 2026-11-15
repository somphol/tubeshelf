# IDEAS

Deferred features, specced well enough to build later without redoing the research.
Nothing here is scheduled. Each entry states what is cheap, what is fragile, and why
it was parked.

---

## Playlist import

**Status:** parser written and unit tested; **no UI shipped**; live validation
blocked. Parked 2026-11-14.

- `PlaylistService` + `PlaylistParser` read the first batch of a playlist from
  `ytInitialData` (no API key), dedupe by video ID, and parse durations.
- `YouTubeURL.playlistID(from:)` handles playlist, watch and share links.
- **Blocker:** the playlist used for testing
  (`PLsut0F29QsHjQmcTxUIjlfrPxa2ZbVetP`) is not public — YouTube answers "The
  playlist does not exist." Private playlists, Watch Later and Liked videos are
  invisible to a scraper; only public/unlisted ones can work.
- Next steps: find a genuinely public playlist to validate the parser, then build
  the review sheet (checkbox per item, "on shelf" status, batch add with
  suggestions). Until then the feature must not be exposed in the UI.
- Search results no longer embed `playlistRenderer`, so do not rely on that to
  discover test playlists.

---

## Watch history → "what haven't I filed yet?"

**Status:** idea, not scheduled. Parked 2026-11-14.
**Effort if built:** ~6–8 hours (parser + sheet + states), plus an optional ~1–2 h
for the bookmarklet path.

### The constraint that shapes everything

YouTube exposes **no API for watch history** — not through Data API v3, not through
any other endpoint. Google also blocks OAuth sign-in inside embedded web views
("This browser or app may not be secure"), so the Mac app cannot log in and read
`youtube.com/feed/history` on its own.

Two workable routes, both credential-free:

1. **Google Takeout** (recommended, robust). The user exports "YouTube and YouTube
   Music" and gets `Takeout/YouTube and YouTube Music/history/watch-history.json`.
2. **Bookmarklet** (fresh but fragile). The user opens `youtube.com/feed/history` in
   a browser while signed in, runs a bookmarklet that reads the page's
   `ytInitialData`, and downloads a small JSON the app imports. Only captures what
   has been scrolled into view, and breaks whenever YouTube changes markup.

Rejected: scraping with stored Google cookies (credential risk), embedded login
webview (blocked by Google).

### Observed failure mode (design for it)

A Nov 2026 export from this machine contained **only**
`Takeout/archive_browser.html`, with this text next to `watch-history`:

> Service failed to retrieve this item

So a Takeout zip can be "valid" and still contain no history. The importer must
detect this and say *"Google failed to include watch history in this export — run it
again"* rather than a generic parse error. Retrying usually fixes it; keeping the
export small (YouTube only) reduces failures.

### Input handling

- Accept the **`.zip` directly**: look inside for `*watch-history*.json`
  (case-insensitive, anywhere in the archive). Do not make people unzip.
- Also accept a bare `watch-history.json`.
- Cap at ~50 MB JSON / 100k entries. Takeout can be enormous.
- Parse with the existing `YouTubeURL.videoID(from:)` so every link shape works.

Takeout record shape:

```json
{ "title": "Watched Never Gonna Give You Up",
  "titleUrl": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "subtitles": [{ "name": "Rick Astley" }],
  "time": "2026-11-14T10:12:03Z",
  "products": ["YouTube"] }
```

Normalise to `{ videoID, title, channel, watchedAt, watchCount }`:

- Skip entries without a valid 11-character video ID (removed videos, ads,
  deleted channels) and report how many were skipped.
- Collapse repeated watches of the same ID into one row, keeping the latest
  timestamp and a `×N` count.
- `title` may be "Watched a video that has been removed" — skip when it has no ID.

### UI

A **Watch history** sheet (⇧⌘Y), not a new navigation mode:

- Filters: **Last 3 days** (default), 7, 30, All; text search; channel filter.
- Rows: thumbnail, title, channel, "watched 2 hours ago", and a state:
  - **On shelf** → its category chips, *Edit*, *Open*.
  - **Not on shelf** → **Add**.
- **Add** files it with the normal on-device suggestion, no sheet, toast confirms.
  *Add with details…* opens the existing editor for the exceptions.
- Footer: "87 watched · 12 already on the shelf · 4 unavailable".

Aged-file behaviour: if the newest entry is older than the selected window, fall
back to the newest N days *in the file* and label it ("3 days ending 9 Nov"), rather
than showing an empty list that looks broken.

### Data and privacy

- History is **global**, not per profile; the "on shelf" check uses the active
  profile.
- Cached at `Application Support/TubeShelf/History/history.json` — never inside a
  profile, never in backups, never in the public web viewer's repo.
- *Settings → Remove history data* with an explicit line that it stays on this Mac.

### Acceptance

- A Takeout zip with history imports; a zip without it reports the exact failure.
- 100k-entry file loads without freezing; the sheet paginates.
- Repeated watches collapse; removed videos are skipped with a count.
- Nothing about the history appears in an exported shelf backup.

### Open questions for later

- Default window: 3 days as requested, or "since last visit"?
- Should Add also bump the video's `addedAt` to now? (Probably not — keep the
  original save order.)
- Is a per-channel "add all unseen" action worth it, or does that violate the
  one-at-a-time intent?
