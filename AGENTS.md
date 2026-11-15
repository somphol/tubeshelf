# AGENTS.md

Read `README.md` first; this file is the handoff for whoever changes the code next.

## What it is

TubeShelf is a native SwiftUI macOS app that stores YouTube links locally, tags
them with Apple's on-device Foundation Models (or a keyword fallback), and browses
each category as a slide deck. It is not a YouTube client: no login, no feed, no
playlists, no uploads.

## Commands

```bash
swift build                                  # debug build
swift test                                   # 62 unit tests
swift run tubeshelf-check                    # headless behavioural checks
swift run tubeshelf-check --probe            # model availability + live tagging
swift run tubeshelf-check --fetch <link>     # one real metadata fetch
swift run tubeshelf-check --pin <category>   # pin / unpin / merge from the CLI
swift run tubeshelf-check --merge A B
CONFIG=release ./scripts/build-app.sh        # dist/TubeShelf.app (ad-hoc signed)
./scripts/verify.sh                          # tests + checks + bundle + signature
open dist/TubeShelf.app
```

There is no Xcode project. `open Package.swift` works for editing and debugging;
the runnable app is the `TubeShelf` executable target bundled by
`scripts/build-app.sh`.

## Architecture

Three modules, one direction of dependency: `TubeShelfCheck → TubeShelfCore ← TubeShelf`.

- **TubeShelfCore is pure** (no AppKit, no SwiftUI). URL parsing, taxonomy, the
  tagger, the shelf model, the JSON store and the deck index live here, which is
  why they are all testable headlessly.
- **TagEngine** is the only place that talks to Foundation Models. It is guarded
  by `#if canImport(FoundationModels)` + `@available(macOS 26.0, *)` and always
  returns a `TagSuggestion`, falling back to `HeuristicTagger` on any error or
  unavailability.
- **AppModel** is the single `@MainActor @Observable` state object. Views take it
  as a `let` and use `@Bindable` locally for bindings; there is no global
  environment lookups or singleton state (the thumbnail cache is the one actor
  singleton).
- **DeckView** is an overlay in `RootView`, not a separate window, so it animates
  over the shelf and keeps one window. The window toolbar hides while it is open.
- Saving happens synchronously after every mutation (`AppModel.save()`); the
  library is small enough that this is cheaper than a debounce.

## Decisions and constraints

- **YouTube identity is the 11-character video ID.** Duplicates are detected by
  ID. Never key a library entry off the pasted URL.
- **No API key.** Metadata comes from `youtube.com/oembed`; description and
  duration are scraped best-effort from the watch page. Do not add a
  key-dependent path without a fallback.
- **The grid is paginated; the deck is not.** `PageWindow` (Core) owns the maths
  and clamps a stale page, so deletions can never strand the view. `pageIndex`
  resets on filter/query/scope changes, and page size is a UI preference. The
  deck receives `visibleVideos` (the whole filter) on purpose — presenting a
  category must not stop at page one. Its filmstrip only builds ±20 neighbours.
- **The sidebar shows five channels plus the active one.** `sidebarChannels`
  inserts the currently selected channel at the top if it is outside the top five,
  so the List selection can always highlight a real row. Do not cap this list to
  zero or hide the section when a filter is active.
- **Channels are free text, not IDs.** `video.channel` is whatever YouTube's
  oEmbed returned; `channelCounts` groups case-insensitively. That means a channel
  rename on YouTube looks like two channels here — acceptable until a real
  channel ID is stored.
- **`channelAffinity` is a fallback, never an override.** Three videos minimum,
  at least two in one category, at least 60% share; it only fills an empty
  suggestion and only with a taxonomy category.
- **An empty shelf must always offer a way out.** `ShelfView` checks
  `otherPopulatedProfiles` and surfaces *Switch to …* and *Restore from backup…*
  before the examples. Do not replace that with a plain "your shelf is empty"
  message: being parked on an empty profile looks exactly like data loss.
- **One folder per profile, no central index.** `Profiles/<uuid>/profile.json`
  plus that folder's `library.json` is the truth; the list is rebuilt by scanning.
  Deleting the index cannot hide a shelf. The active profile ID lives in
  `UserDefaults`, never in the data.
- **Adoption is copy-only.** The first profile copies the legacy root
  `library.json`; the original is never moved or deleted, so a failed migration
  still leaves the data where it was.
- **Deleting a profile goes to the Trash**, and the last profile is not removable.
  `AppModel.deleteProfile` hands over to a neighbour before trashing the active
  one; do not reorder those two steps.
- **`AppModel.store` is mutable now.** Anything that caches a `LibraryStore` across
  a profile switch will write into the wrong shelf. Always go through
  `model.store` / `model.save()`.
- **Playlist import reads `ytInitialData`, never an API key.** Support both the
  legacy `playlistVideoRenderer` and the current `lockupViewModel` markup; YouTube
  changes this. Private playlists return zero items by design — never add cookie
  auth to work around it. One page ships ~100 items, so a continuation token means
  "partial", not "complete".
- **Playlist categories are reviewed, never guessed at add time.** Rows pre-fill
  from `HeuristicTagger` on the title only (a playlist page has no descriptions);
  the per-row editor can fetch metadata and re-run `TagEngine`, and import writes
  exactly `tagsByVideo`. Do not reintroduce suggestions inside the import loop —
  that is what makes bulk adds unpredictable.
- **Large imports are sequential.** Each item gets a category suggestion; with the
  on-device model enabled, 100 items can take a while. The sheet stays disabled
  while it runs. Do not parallelise model calls without rate thinking.
- **Shuffle is seeded, never `shuffled()` in a view.** `SeededShuffle` with a
  stored seed keeps the order stable across renders and pages; clicking stores a
  new seed. The deck must keep receiving `visibleVideos` so its order matches the
  grid. Do not sort by a random value at render time.
- **`WatchStatus` defaults to `.unwatched` on decode.** `Unwatched` means "not
  done", so `watching` stays in the queue. Badges appear only for non-default
  states; the sidebar count is the queue size.
- **Time is stored as an instant, never as a zoned wall clock.** `Video.addedAt`
  is a UTC instant truncated to whole seconds; `addedTimestamp()` renders it in
  the current zone for display. Do not add a per-video timezone field — backups
  must stay portable, and import must never rewrite the moment.
- **Categories can have parents.** `VideoCategory.parent` makes Trigonometry imply
  Math, and `TagTaxonomy.withParents` is applied to both model and keyword
  answers. Add a parent whenever a subtopic is introduced.
- **The person's categories are classifier input.** `HeuristicTagger` accepts
  `knownCategories` and matches their names; `TagEngine` passes the same list into
  the model prompt and accepts those names from the model. Do not filter
  suggestions down to the built-in taxonomy again.
- **Matching is stemmed and token-based.** "distributions" matches "distribution",
  "probabilities" matches "probability"; words under five characters are never
  stemmed so "news" cannot match "new". Tests pin both directions.
- **Aliases never rewrite storage.** `TagNormalizer.canonical` only cleans and
  capitalises; `taxonomyMatch` is the alias-aware lookup used solely for model
  output. Rewriting "Learning" to "Education" at entry made it impossible to
  create a category whose name happened to be an alias — do not merge the two
  functions again.
- **Backups are a versioned envelope, restores are replace-only.** The backup
  carries `format` and `version`; a newer version is refused with a clear reason.
  Raw `library.json` is accepted only when a top-level `videos` array exists,
  because `Library` decodes unknown JSON into an *empty* shelf and that would let
  a stray file wipe data. Every restore writes a `library-before-restore-*` copy
  first; never remove that step.
- **Drive support is a folder write, not an API.** `CloudDriveLocator` scans
  `~/Library/CloudStorage/GoogleDrive-*/My Drive`; the button writes
  `TubeShelf Backups/<timestamped>.json` there. No OAuth, no tokens, no network
  code. Never invent a Drive path outside CloudStorage, and never fall back to a
  silent local folder when the drive is missing.
- **Backups exclude thumbnails on purpose.** They rebuild from YouTube, and
  including them would turn a 40 KB file into hundreds of megabytes.
- **Duplicates are editable.** Opening a saved link prefills its tags and note and
  updates the existing record in place. Never re-add it, and never start the
  editor from an empty tag list in that state — that would wipe categories.
- **Categories are derived, never empty.** A category exists only while a video
  carries it, so there is no "create empty category" path. Pins are pruned on load
  and on every save; do not let an orphaned pin reach disk.
- **`Library` owns pins; `UserDefaults` owns view preferences.** `pinnedTags`
  lives in `library.json` because it is user data worth backing up. Sort order and
  search scope are interface state in `UserDefaults` (`Preferences`), never in the
  library file.
- **Merging is a rename that also absorbs.** `mergeTags(_:into:)` moves every
  video, dedupes, removes the source and transfers the pin in one operation. The
  manager confirms before running it; the sidebar deliberately has no one-click
  merge.
- **Search scope is explicit.** `SearchScope.titles` matches only `video.title`;
  `.everything` matches the existing corpus (title, channel, note, categories).
  Never widen `.titles` — that is the precision mode the person asked for.
- **`TagTaxonomy` is the source of truth** for category names, SF Symbols, the
  AI prompt list and the fallback keywords. Adding a category means adding one
  `VideoCategory` entry; the sidebar, prompt and classifier follow automatically.
- **The keyword classifier must stay quiet rather than guess.** A category needs
  a title/channel anchor (`score >= 4`), ambiguous words live in `weakKeywords`
  and can never carry a category alone, and every extra tag must score at least
  60% of the top tag. Tests pin this — do not lower the bar to "fill" the shelf.
- **Never mix model and keyword answers.** If Foundation Models returns one
  accurate category, keep exactly that; topping it up with heuristic guesses was
  removed on purpose because it made suggestions less relevant.
- **Persisted JSON is tolerant**: new fields use `decodeIfPresent`, dates are
  truncated to whole seconds for exact round-trips, and a corrupt file is moved
  aside, never overwritten.
- **The deployment target is macOS 14** so the app runs without Apple
  Intelligence; every macOS 26-only symbol is availability-guarded.
- **Thumbnails are cached on disk** under Application Support; deleting that
  folder is always safe.
- **`#if DEBUG` snapshot support** (`Snapshotter.swift`) captures the app's own
  window for visual checks because screen recording permission is not available
  in this environment. It is excluded from release builds; keep it that way.
  Variables: `TUBESHELF_SNAPSHOT=<path>`, `_MODE=shelf|deck|add|manager|edit`,
  `_WIDTH`, `_HEIGHT`, `_APPEARANCE=light|dark`, and
  `TUBESHELF_PICKER_PREFILL=<text>` to pre-fill the category field.

## Known issues

- The Foundation Models call is compiled but **not runtime-verified**: this
  machine has no downloaded model asset (`modelNotReady`), so only the keyword
  fallback has actually executed. Verify on a Mac with Apple Intelligence enabled
  using `swift run tubeshelf-check --probe` and expect `Apple Intelligence` as the
  source.
- Google Drive for Desktop needs an admin install and an interactive sign-in, so
  the Drive button is disabled until `My Drive` appears. That is intentional; the
  Settings row links to the download.
- Profiles are per-machine; there is no merge between two profiles.
- `activeProfileID` lives in `UserDefaults` and is written even when the debug
  snapshot override (`TUBESHELF_LIBRARY_DIR`) points at a throwaway root. After
  such a run, reset it or the real app opens on a demo profile. Moving a
  shelf between them means export + import-as-profile.
- Channel merging is not offered: channel names come from YouTube, so renaming
  one would only fragment it further. Category merge (sidebar and manager) covers
  the case that matters.
- Search lives in the shelf header, not the window toolbar; the deck hides the
  toolbar and therefore has no search field.
- The category manager cannot create a category with zero videos by design.
- At the 940 pt minimum width, very long category names truncate in the sidebar
  (full name on hover). Shortening the row font is not the fix; the name is data.
- Keyword suggestions are precision-first: a video whose only signal is in the
  description lands in Unsorted rather than getting a loose tag.
- Inline playback needs network access and a video that allows embedding.
- Scraping depends on YouTube's private page markup; only description and
  duration are at risk, never the title or channel.

## Deferred ideas

`IDEAS.md` holds features that were planned but not scheduled. The watch-history
importer is specced there, including the Takeout failure mode ("Service failed to
retrieve this item") and why scraping/embedded login is not an option. Read it
before re-researching any of those questions.

## Continuity

- Repository: <https://github.com/somphol/tubeshelf> — **private**, no Pages, no
  public releases. Do not publish the app bundle or anyone's library data here.
- Read-only web viewer lives in the **public** repo
  <https://github.com/somphol/tubeshelf-web-ro>. It must only ever hold code and a
  public demo; the backup format contract is in `PLAN.md` /
  `format.schema.json` there. Update both when the envelope changes.
- Deployed copy for local use: `dist/TubeShelf.app` (created by
  `scripts/build-app.sh`, ignored by git).
- Local library and thumbnails: `~/Library/Application Support/TubeShelf/` —
  this is user data and must never be committed or attached to an issue.
- A clone is enough to build: `swift build`, `swift test`, then
  `./scripts/build-app.sh`. The icon is drawn at build time, so no binary assets
  are required.
