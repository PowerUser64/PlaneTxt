# Changelog

## [2.2.0] - 2026-10-23

### Added
- Settings: the name given to each day's file, from a template such as `YYYY-MM-DD-Agenda`. The days that already have a file keep it ([#1](https://github.com/brvier/PlaneTxt/issues/1))
- Events show their Markdown rendered - bold, italic, code, lists - and a link in an event or its description opens in the browser ([#2](https://github.com/brvier/PlaneTxt/issues/2))

## [2.1.0] - 2026-10-11

### Added
- Search across all days and notes, ignoring accents
- Week review: todos done, still open and carried over, and the week's events
- Each morning, an offer to carry over the todos left open on previous days, grouped by day, moved or copied
- Swipe between days, a Today button, an empty day with "Start the day", and the selected tab kept
- Tick or untick a todo with one tap in the day view
- Notes: collapsible folders, sharing, and archiving to `archives/` with undo
- Save a shared text as a new note
- Reminders: adjustable delay or off, and tapping a reminder opens its day. On Linux, event reminders while the app is open
- Widget text size setting
- Edits made outside the app are detected before saving, with a choice to keep either version or both
- Conflict copies left by Syncthing, Nextcloud or Dropbox are reported
- The first launch offers to pick a synced folder, and an unreachable storage folder is reported until it is selected again

### Changed
- Event reminders no longer ask for exact alarm access, and the notification permission is asked once
- Logs no longer contain the user's text (event titles, todos, shared content): counts, dates and ids only
- Android backup is disabled: files live in your folder, or in the app's private storage by choice
- Debug tools are hidden behind a long press on the version, and widget settings only show on Android
- Store icon, screenshots and feature graphic now show the PlaneTxt name

### Removed
- Unused `USE_FULL_SCREEN_INTENT` permission
- Unused files from `assets/` (about 800 KB) are no longer bundled in the APK

### Fixed
- Creating a note no longer overwrites an existing one, and accented letters are kept in note and folder names
- The last keystrokes are saved when closing the editor or leaving the app
- An unreadable file is no longer treated as missing and overwritten with the template
- Todos and events are recognized in files with CRLF line endings, and `[X]` counts as done
- Writes to a SAF folder are atomic, and interrupted writes are recovered
- Carry-over writes the target day before removing the todos from the source days
- ICS import: descriptions stay under their event, no duplicates on re-import, TZID time zones, folded lines, VALARM ignored, and the import is saved after the dialog closes
- A shared text that is not a calendar opens quick add instead of "Invalid ICS", and the imported day opens
- Editor: Bold button, new todo unchecked after Enter, a list ends on an empty bullet, markers at line start, readable hints
- Event descriptions are no longer repeated in notes
- The widget reads the default storage where the app writes it (`app_flutter/Org`)
- Quick add places an event after the last event's description, and dates outside 2000-2100 are ignored
- Tapping a reminder shows its day even with an editor open
- Ticking a todo shows at once, and writes to the same day are queued

## [2.0.1] - 2026-09-17

### Fixed
- `pubspec.lock` matches the pinned Flutter 3.44.6 again, so builds with `--enforce-lockfile` (F-Droid) succeed. CI and releases now enforce the lockfile.

### Added
- Release workflow builds the Play Store app bundle (AAB) as a workflow artifact.

## [2.0.0] - 2026-09-17

### Changed
- Renamed from Planova to PlaneTxt, as the Planova name was already used by a similar product. The application id is now `fr.rvier.planetxt` on Android, iOS and Linux, so existing Android installs do not upgrade in place: install PlaneTxt, then point it at the same storage folder. On Linux, preferences are copied from `~/.local/share/fr.rvier.planova/` on first launch.

## [1.4.4] - 2026-09-13

### Changed
- Split APKs now carry a per-ABI versionCode (base code x 10 + 1 for armeabi-v7a, + 2 for arm64-v8a, + 3 for x86_64), as required by F-Droid. The AAB keeps the base code.

## [1.4.3] - 2026-09-12

### Fixed
- App label is now "Planova" instead of "planova"
- The APK no longer embeds the Play Store dependency metadata signing block, which F-Droid rejects

## [1.4.2] - 2026-09-11

### Added
- Fastlane metadata, description and phone screenshots for the F-Droid and IzzyOnDroid listings
- GitHub Actions release workflow: builds signed per-ABI APKs on every version tag and attaches them to the GitHub release
- Screenshot generation script with demo data (`tool/screenshots/`)

### Changed
- README rewritten with screenshots, feature list, build instructions, updated roadmap and a link to the Omarchy shell plugin
- MIT license added, Android build artifacts untracked

### Fixed
- Android build: pin androidx.work to 2.9.1 so home_widget compiles again (JVM target mismatch with newer WorkManager releases)

## [1.4.1] - 2026-07-15

### Fixed
- Refill now saves reliably by using the view's context instead of the dialog's, which unmounts before the async saves complete

## [1.4.0] - 2026-07-13

### Added
- Progress banner while the app builds its cache on first launch or after changing the storage folder

### Changed
- Custom storage folder on Android now uses the system folder picker (Storage Access Framework): syncing with Syncthing, Dropbox, etc. works without any special permission
- Files on SAF folders are read in bulk (one directory query per batch): full startup goes from about a minute to under 3 seconds on a 300-file folder
- Notification review reuses in-memory content instead of re-reading every daily file
- INFO logs are enabled in release builds to allow on-device diagnostics
- Repository caches moved to app-private storage, so they are no longer synced along with your notes
- File monitoring falls back to periodic polling on SAF folders (native events are used elsewhere)

### Removed
- "All files access" (MANAGE_EXTERNAL_STORAGE) and legacy storage permissions, per Play Store policy

## [1.3.2] - 2026-07-13

### Fixed
- **Data loss on Android restart**: the startup disk cache is now flushed after every save (debounced) and when the app goes to background, so edits to past days survive a process kill; the editor and day selection re-read files from disk before use, so a stale cache can no longer overwrite newer file content
- Atomic file writes (temp file + rename) — a crash mid-write can no longer truncate a markdown file
- Repository cache revalidates file mtime, so edits made by external tools are picked up instead of being silently overwritten on the next save
- File monitor notifies the UI of external changes and deletions (including past dates), not only the notification scheduler
- "Saved" confirmation is now only shown after the write actually succeeded; save/autosave failures show an error and keep the content marked as unsaved
- ICS import: UTC timestamps (`...Z`) are now correctly converted to local time
- ICS import: merging events into a day no longer drops the day's existing events

### Changed
- Release builds are signed with a dedicated upload key via key.properties (Play Store)
- Refill dialog now offers undone todos from all previous days (was limited to the last 30), sorted from most recent to oldest
- Calendar cells and daily sections use the provider's memoised parse cache instead of re-parsing markdown on every rebuild
- Event notifications and home-widget updates are debounced after saves instead of running on every 500ms autosave
- Saving a note updates the list in memory instead of re-scanning the whole notes directory

### Added
- Unit tests for markdown parser, ICS parser, daily content helpers and storage service
- GitHub Actions CI (analyze + tests)

### Removed
- Dead code: unused FileProvider, EventProvider and embedded DailyEditor

## [1.3.1] - 2026-07-04

### Changed
- Add builtInKotlin and newDsl Gradle flags (Flutter migrator)

## [1.3.0] - 2026-07-04

### Added
- Today-priority startup load with per-file parse caching
- Adaptive launcher icons (Android)
- Native file-system watching for daily files (inotify), with polling fallback

### Changed
- Faster startup: notification init and permission request deferred after first paint
- Theme and settings load synchronously (no more loading spinner)
- Disk cache JSON encoding/decoding moved off the UI isolate
- File scanning uses async I/O instead of blocking sync calls
- Event notifications are only scheduled for today and future dates
- Refactor daily content helpers
- Upgrade Flutter plugins (file_picker 12, flutter_local_notifications 21, flutter_timezone 5, device_info_plus 13, home_widget 0.9, timezone 0.11, package_info_plus 10)

## [1.2.0] - 2026-04-27

### Added
- Android widget with auto-refresh via boot receiver
- ICS intent sharing
- Event notifications
- Themes, styles and application icon
- Auto-indent in text editor and quick-add modal
- Sort notes by modification date (most recent first)
- Linux platform support

### Changed
- Extract preferences screen into dedicated sections (debug, header patterns, storage)
- Introduce base repository shared by daily and note repositories
- Improve daily loading and ensure file is loaded before use
- Refactor text editor, file provider and preferences screen
- Improve notifications

### Fixed
- Remove duplicate bullet on android widget tasks
- Widget refresh and android alarm updates
- Todo handling in editor
- Custom storage path loading timing issue

### Removed
- PlanovaSAAS backend + frontend prototype
