# TubeShelf

A Mac app for the YouTube videos you mean to find again.

Paste a link, get the real title and thumbnail, let Apple's on-device model suggest
categories, then browse your shelf by category and present any category as a
click-through slide deck. Categories can be pinned, renamed, merged and sorted by
size, and the search field can look at titles only. Everything is stored in one
JSON file on this Mac; no account, no server, no subscription.

## Requirements

| | |
|---|---|
| Run | macOS 14 or newer (built and verified on macOS 27) |
| AI tagging | macOS 26+ with Apple Intelligence enabled. Without it, a keyword classifier takes over and the app says so. |
| Build | Xcode 16+ / Swift 6 toolchain |

## Build and run

```bash
./scripts/build-app.sh          # release build → dist/TubeShelf.app
open dist/TubeShelf.app
```

Install it like any app:

```bash
cp -R dist/TubeShelf.app /Applications/
```

Verify the whole thing (tests, headless checks, bundle, signature):

```bash
./scripts/verify.sh
```

## Using it

1. **⌘N** (or **+** in the toolbar) opens *Save a video*. The clipboard is read
   automatically if it already holds a YouTube link.
2. The title, channel, duration and thumbnail arrive from YouTube — no API key.
   Categories are suggested on-device and applied; remove or add freely. The
   category field is a type-ahead: it lists your own categories that match what
   you type, then library matches, and always offers **Create “…”** plus a
   **Press ⏎** hint so a brand-new category is one keystroke away.
3. **Add to shelf**. Duplicates are detected by video ID, not by title.
4. The sidebar lists **All videos**, **Favorites**, **Unsorted**, then **Pinned**
   categories, then every other category with a count. The field above the list
   filters the categories themselves; the shelf field searches videos. **⌘F**
   jumps to it, and its scope menu switches between **Everything** (title,
   channel, note, category) and **Titles** only.
5. **⌘K** opens *Manage categories*: search, sort by most/fewest videos or name
   A–Z / Z–A, pin, rename, **merge two categories**, and delete. Merging moves
   every video into the target and keeps the pin; nothing is deleted.
6. **Pagination** — a category with hundreds of videos shows one page at a time
   with `1–48 of 312 · Page 1 of 7`, **⌥← / ⌥→** to move, and a page menu to jump.
   *Settings → Browsing* sets the page size (24, 48, 96 or 144; default 48).
   The deck still runs through every video in the category, not just the page.
7. **Present** (header button or **⌘↩**) opens the category as a slide deck.
   **← / →** move, **Esc** returns to the shelf, the filmstrip jumps, and
   the play button opens the video on YouTube (see the note on embeds below).
8. Hovering a category in the sidebar reveals a ▶ that presents it directly;
   right-click to pin, present, rename, **merge into another category**, or delete
   it. The ⋯ menu next to *Categories* sorts the sidebar and opens the manager.

Right-click a video for favorites, copying the link, editing categories and notes,
or removing it. Right-click a category to rename or delete it. Settings (**⌘,**)
shows the AI status, the library path, and a *Remove all videos* action.

## Categories

Thirty-one categories ship with the app, including Math and its subtopics
(Trigonometry, Calculus, Geometry, Linear Algebra, Statistics). A subtopic always
pulls its parent along, so a trig video is filed as *Math + Trigonometry*.
Recently (Programming, AI & Machine Learning,
Design, Science, Math, Business, Finance, Crypto & Web3, Productivity, Health &
Fitness, Cooking, Travel, History, News & Politics, Education, Music, Film &
Video, Gaming, DIY & Home, Photography, Cars, Sports, Writing, Psychology,
Language Learning, Talks & Podcasts). The list lives in one file
(`TagTaxonomy.swift`) and feeds the sidebar icons, the AI prompt and the keyword
fallback together, so they cannot drift apart.

Your own categories are part of the classifier too: once *Trigonometry* exists,
any video whose title mentions it gets that tag, and the on-device model is given
your category list alongside the built-ins. Plurals are understood
("distributions" matches "distribution").

Custom categories are allowed anywhere a category is entered. A video can carry
as many as you like; an empty list puts it in **Unsorted**.

Suggestions are deliberately conservative: a category needs a title or channel
hit to appear, ambiguous words ("model", "market", "band") can only support a
hit rather than create one, and every extra category must be at least 60% as
strong as the best one. One accurate tag beats four loose ones — you can always
add the rest while editing.

New categories are created where you need them: in *Edit details* or *Save a
video*, type the name and press **Return**. Names are never silently rewritten —
typing `Learning` creates *Learning* even though `learning` is an alias the
classifier uses for Education. The "Create “…”" row appears while
typing, and the category is immediately available on every video.

Categories are derived from videos, so one disappears when its last video loses
it. Pin the ones you use daily (**pin icon** in the manager, or right-click in the
sidebar); pins live in `library.json`, follow renames, transfer when merged, and
are dropped automatically when a category goes away. Sort order and search scope
are interface preferences, stored in `UserDefaults`, not in your library.

## Channels

The channel name on every video is a second facet, built without any API access.
The sidebar carries a **Channels** section with your five biggest channels and an
**All N** link; the toolbar's **Channels** button (**⇧⌘K**) opens the full list,
sorted by how many videos you saved, with a ▶ to present it and *usually
Programming* when that channel has a dominant category. Click a channel to filter the shelf; **More from <channel>**
in a video's context menu does the same from the grid.

The dominance rule is deliberately conservative: at least three videos from the
channel, at least two in the same category, and at least 60% share. When a video's
title says nothing useful, that category is used as the suggestion — never over a
real match.

## Playback

In-app playback is deliberately not offered: YouTube's embedded player refuses to
initialise inside the app's web view (error 152/153, reproducible both with and
without a referer wrapper). The play button opens the video in your browser, where
it always works.

## Adding a video you already saved

Paste a duplicate link and the sheet says so, but stays editable: the existing
categories and note arrive prefilled, **Update video** saves changes in place, and
**Show it on the shelf** jumps to it. Nothing is duplicated.

## Shuffle and watch state

**Shuffle** (the shuffle button, or **⌘R**) reorders the current view — videos or
the playlist catalog — randomly — and every click gives a fresh order, which is the point: it resurfaces
videos you filed and forgot. The order stays put while you scroll, the deck follows
the same order, and *Newest* returns to chronological. The catalog keeps its own shuffle order,
so shuffling courses never disturbs the video grid.

**Watch state** tracks `Unwatched → Watching → Watched`. The sidebar has an
**Unwatched** filter, the deck marks a video watched in one click, and finished
videos get a small badge on the card. Videos saved before this feature count as
unwatched, which is the honest default.

## Playlists

Two independent actions, both in the toolbar's playlist menu and the File menu:

- **Add Videos from Playlist…** (**⇧⌘N**) — review every video, edit its categories,
  add the ones you tick to the shelf. The list header has a tri-state checkbox plus
  **Select all / Deselect all**, and shows `15 of 15 selected`. It never touches the
  catalog.
- **Add Playlist to Catalog…** (**⇧⌘⌥N**) — keep a public or unlisted playlist as a
  *course*: title, channel and ordered chapters. Adds no videos. The clipboard is
  read automatically when it holds a playlist link, categories are suggested from
  the course title and its first chapters and are editable before saving, and a
  course that is already in the catalog is detected up front — with an *Open*
  shortcut and a note on whether updating adds chapters.

The catalog is a first-class row under **Library** — *Playlist Catalog* — and the
main pane shows playlists as thumbnail cards with chapter counts and progress
(**⌘⇧L** jumps there).

**Courses take categories too.** *Edit categories* on a course card or in its
detail view uses the same picker as videos, including creating a new category.
When a category contains both, its view mixes video cards and course cards in one
grid, newest first, and the header says `2 videos · 1 course`. Presenting now walks both: video slides and one poster per course.

A category that exists **only on courses** appears in the sidebar like any other
(e.g. `C++ · 2`), and its counts include both videos and courses. Pins survive as
long as either kind still carries the category. Each entry keeps its chapter order offline, shows `3 / 16` progress, and
opens a detail view where you can tick chapters, add a single chapter with its
**+** button (the category editor appears first), use **Add missing to Shelf**
(the bulk review sheet for that playlist), **Present** the chapters you already
have in order, or remove the course without touching any video.

Progress belongs to the playlist, not the shelf: ticking a chapter marks the
shelf's copy watched when it exists, but a course can be tracked without filing
every video. Backups carry the catalog alongside the library; older backups still
restore.

Limits: public and unlisted only (private playlists, Watch later and Liked cannot
be read), roughly 100 chapters per fetch, and refresh is manual for now.

## Profiles

A profile is a whole separate shelf. Your own videos never mix with a friend's
list, and importing someone else's export cannot overwrite your data.

- The sidebar shows the current profile under the app name — click it to switch.
- **Add from Backup…** imports a `.json` export as a *new* profile and switches to it.
- **New Empty Profile…** starts a clean shelf for a different topic or person.
- **Manage Profiles…** renames, switches, or moves a profile to the Trash.
- Every profile is its own folder, so deleting one cannot damage another, and the
  last profile cannot be deleted.

On the first launch after upgrading, the existing `library.json` is copied into a
profile called **My Shelf**. The original file is left untouched as a backup.

If the profile you are looking at is empty, the shelf says so and offers three
ways forward: **Switch to <your other profile>**, **Add a YouTube link** (starting
this shelf from scratch), or **Restore from backup…**. Importing a
file that contains no videos asks for confirmation first, instead of silently
parking you on an empty shelf.

## Backup and restore

Backups carry the playlist catalog alongside the library, and importing a backup
as a profile brings its courses too. Restoring copies the outgoing library *and*
catalog aside first.

**Google Drive:** *Back up to Drive* (**⌥⇧⌘S**, or the button in Settings) writes
straight into `My Drive/TubeShelf Backups` as long as Google Drive for Desktop is
installed and signed in. No OAuth, no upload API, no account linking — Drive syncs
the file like any other. With several accounts you pick once and the choice is
remembered. If Drive is not installed the button stays disabled and Settings links
to the download.

Every video keeps the exact moment it was saved — an instant, not a wall time —
and the deck shows it as `14 Nov 2026, 19:32 PST`. Because it is stored as an
instant, a backup restored in another timezone still reads correctly, and the
original value is never rewritten by an import.

*Settings → Library → **Back up…*** (or **⇧⌘S**) writes one JSON file:
videos, categories, notes and pins. Put it in a Google Drive, Dropbox or iCloud
folder and it is a portable snapshot — not a live sync.

*Restore…* reads that file back, shows how many videos are in it, and replaces the
**current profile** only after you confirm. To keep both shelves instead, use
*Profiles → Add from Backup…*, which creates a new profile and leaves yours alone. Before anything changes, the outgoing library is
copied to `library-before-restore-<timestamp>.json` next to your library file, so a
wrong choice is always recoverable.

The file is a versioned envelope (`format: tubeshelf.backup`, `version: 1`), and a
plain `library.json` is also accepted for people who back up by hand — but only if
it really is a library (a top-level `videos` array), never arbitrary JSON.

```bash
swift run tubeshelf-check --backup ~/Desktop/shelf.json
swift run tubeshelf-check --restore ~/Desktop/shelf.json
```

## Where your data lives

```
~/Library/Application Support/TubeShelf/
├── Profiles/
│   └── <uuid>/
│       ├── profile.json  # name, created date, import source
│       └── library.json  # that profile's videos, tags and pins
├── Thumbnails/           # shared artwork cache, safe to delete
└── library.json          # pre-profile file, kept as a backup after migration
```

Back up by copying that folder. The app writes atomically; a corrupt file is moved
aside as `library-corrupt-<timestamp>.json` instead of being overwritten.

## Verification

```bash
swift test                          # 74 unit tests: links, tagging, shelf, deck, disk, profiles
swift run tubeshelf-check           # headless checks against the same logic
swift run tubeshelf-check --probe   # model status + live suggestions
swift run tubeshelf-check --fetch <link>   # metadata + suggestion for one video
swift run tubeshelf-check --seed-demo      # add the seven example videos
swift run tubeshelf-check --reset          # empty the library
swift run tubeshelf-check --pin <category>       # pin from the terminal
swift run tubeshelf-check --unpin <category>
swift run tubeshelf-check --merge <from> <into>  # collapse two categories
swift run tubeshelf-check --help                 # every flag
```

## Architecture

| File | Role |
|---|---|
| `Sources/TubeShelfCore/YouTubeURL.swift` | Every link shape → 11-character video ID |
| `.../VideoMetadataService.swift` | oEmbed for title/channel, best-effort page scrape for description and duration |
| `.../TagTaxonomy.swift` | Categories, keywords, aliases, normalisation |
| `.../TagEngine.swift` | Foundation Models call + keyword fallback + availability reporting |
| `.../Library.swift` | Pure shelf model: filters, scoped search, pins, merge, sorted tag counts |
| `.../LibraryStore.swift` | Atomic JSON persistence |
| `.../DeckModel.swift` | Slide index, clamping, progress |
| `Sources/TubeShelf/AppModel.swift` | Observable app state and mutations |
| `.../RootView.swift` | Split view, sidebar, toolbar, sheets |
| `.../ShelfView.swift` | Grid of cards + the title/everything search field |
| `.../CategoryPickerField.swift` | Type-ahead category field: yours, library, or create |
| `.../CategoryManagerView.swift` | Browse, sort, pin, rename, merge and delete categories |
| `.../ChannelBrowserView.swift` | Channels sorted by size, with a deck per channel |
| `Sources/TubeShelfCore/PageWindow.swift` | Pure pagination maths and clamping |
| `Sources/TubeShelfCore/ProfileStore.swift` | One folder per shelf, migration, safe delete |
| `.../ProfileManagerView.swift` | Switch, rename, import and trash profiles |
| `.../DeckView.swift` | Full-window slide deck |
| `.../AddVideoSheet.swift` | Paste → preview → classify → save |
| `scripts/build-app.sh` | Builds and ad-hoc signs the `.app` |
| `scripts/make-icon.swift` | Draws the icon from code at build time |
| `scripts/verify.sh` | The full gate |

## Known limitations

- The Foundation Models path is compiled against the macOS 26 SDK but could not
  be exercised on this machine: the Apple Intelligence model asset is not
  downloaded, so `SystemLanguageModel` reports `modelNotReady` and the app uses
  the keyword classifier. Turn Apple Intelligence on in System Settings and the
  model path activates with no rebuild.
- No OAuth, so the app cannot read your subscriptions or playlists; it only sees
  links you paste.
- Inline playback uses the privacy-preserving `youtube-nocookie` embed. Videos
  that forbid embedding fall back to *Open on YouTube*.
- Description and duration come from scraping the watch page; if YouTube changes
  that markup, tags fall back to title + channel only.
- Single-user, single-machine. No sync.
