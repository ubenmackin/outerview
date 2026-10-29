# OuterView — Architecture Blueprint

Architectural blueprint for **OuterView**: a Safari-faithful web browser built for dual-screen and foldable form factors (specifically the iPhone Duo), claiming the entire 466 × 678 pt outer display edge-to-edge with scroll-transient chrome and contextual command controls.

---

## 1. Soul & Design Theses

Stock Safari pins Duo web content to a narrow 382 pt strip beside a static side rail. OuterView claims the entire outer display edge-to-edge and replicates Safari's tactile feel while making chrome transient: controls disappear when reading starts.

1. **Chrome is Transient**: Chrome steps aside for content. The side rail hides on drag began or the first downward scroll movement. The address pill minifies after 24 pt of accumulated downward scroll. An upward scroll of 32 pt restores the address pill and rail.
2. **Quick-Access Menu Button**: When the rail collapses on downward scroll, a compact floating menu button drops down at the bottom right. Tapping it immediately pops the rail back out without requiring the user to scroll backwards.
3. **Wall-to-Wall Content**: WKWebView fills the window edge-to-edge; liquid glass chrome floats above it and adjusts content insets dynamically.
4. **Contextual Command Rail**: The 84 pt right system column is an adaptive command rail driven by `RailMode` (`.browsing`, `.startPage`, `.library`, `.bookmarkEditor`). Contextual actions (Cancel, Save, Edit, Clear, Done) are surfaced directly in the rail rather than crammed into top navigation headers. Tab overview bypasses `RailMode` and composes its own rail via `TabOverviewViewController.applyRailItems(to:)`.
5. **Unified Start Page**: A single `StartPageView` serves empty tabs, menu-triggered home access, and the address bar editing backdrop. Large high-res site favicons, recent visits, and Safari import actions live in this single surface.
6. **Multi-Screen Migration**: The app migrates dynamically between the Duo's outer portrait display (466 × 678 pt) and inner landscape display (951 × 669 pt). Layout is always derived from window and safe-area geometry, never from static screen instances, orientation flags, or device idioms.
7. **Swift 6 Concurrency**: Built from day one with strict concurrency, `@MainActor` UI isolation, and immutable `Sendable` value types.
8. **Reuse over Reinvention (P1)**: New features extend the shipped architecture rather than adding parallel subsystems. Reader mode and Find in Page transform the SAME `WKWebView` document; the chrome FSM is untouched by P1 overlays.

---

## 2. Technology Stack & Runtime Environment

- **Language & Platform**: Swift 6 language mode, iOS 27.1 deployment target.
- **Project Generation**: Declarative `project.yml` managed via **XcodeGen**. The generated `.xcodeproj` is never manually modified or committed; run `xcodegen generate` whenever files are added or removed.
- **UI Architecture**: UIKit-first browser surface utilizing custom `UIViewController` containment for granular animation and gesture control. SwiftUI is integrated via `UIHostingController` for structured modal sheets (`BookmarkEditorView`, `SettingsView`, `DownloadsSheetView`).
- **Web Rendering**: WebKit (`WKWebView`) with customized navigation policies, process pooling, and certificate challenge handling (`SFSafariViewController` is excluded because its chrome is rigid and non-transient).
- **Persistence**: **SwiftData** backed by a shared `ModelContainer` managing `Bookmark`, `BookmarkFolder`, `HistoryEntry`, `TabRecord`, `TabGroup`, `TabSession`, `RecentSearch`, and `ReadingListItem`. An in-memory configuration is supported for unit test isolation. Tiny host-keyed preferences (per-site text zoom) use `UserDefaults` instead of a model.
- **Visual Design System**: Liquid Glass styling with blurred materials, capsule geometry, and subtle borders (`GlassEffect.swift`, `UIVisualEffectView`).
- **Data Import**: Safari-exported `Bookmarks.html` (Netscape bookmark format) imported via standard Document Picker without requiring private APIs or sandbox violations.

---

## 3. Display Geometry & Spatial Allocation

| Display Target | Dimensions (pt) | Scale | Safe Area Insets | Key Physical Characteristics |
| :--- | :--- | :--- | :--- | :--- |
| **Outer Portrait** | 466 × 678 | @3x (radius 59) | top: 0, left: 0, right: 84, bottom: 34 | Right 84 pt column hosts system status & camera spot; bottom 34 pt home indicator |
| **Inner Landscape** | 951 × 669 | @3x | top: 0, left: 0, right: 84, bottom: 34 | Expanded widescreen canvas; right column reserved for controls |

### Safe Area Strategy
- **Right System Column (84 pt)**: Hosts the system status cluster (time, cellular, battery) and camera occlusion (an ~84 × 174 pt region containing the camera hardware). OuterView centers its 60 pt interactive command rail (`SideRailView`) within this 84 pt column, positioning buttons below the camera region.
- **Bottom Bar Spacing (34 pt)**: In browsing mode, the address capsule floats 4 pt above the bottom safe area (`38 pt` total offset from screen bottom). In address editing mode, the field docks cleanly above the active `keyboardLayoutGuide`.
- **Dynamic Transition Handling**: When migrating between displays, transition frames are handled through `viewWillTransition(to:with:)` and `layoutSubviews`. Size classes transition between compact-width/regular-height (outer) and regular/regular (inner).

---

## 4. Subsystem Architecture & Component Map

```
Sources/
├── App/                  # App lifecycle, scene phase forwarding, session restore
├── Browser/
│   ├── RootView/         # Central coordinator (BrowserRootViewController), scroll proxy, tab management
│   ├── Chrome/           # Address bar, address editor, side rail, state machine, glass styling, find-in-page overlay
│   ├── WebPage/          # WKWebView controller, tab pool, LRU eviction, element context menus
│   ├── Reader/           # Reader-mode DOM transform engine (same WKWebView document)
│   ├── StartPage/        # Unified start page, favorites grid, recently viewed list
│   ├── Bookmarks/        # Four-tab library container (Favorites/Bookmarks/History/Reading List), browser, editor
│   ├── Favorites/        # Large Safari-style favicon tiles & grid view
│   ├── History/          # Chronologically segmented history list & segmentation logic
│   └── TabOverview/      # Visual tab grid overview, groups sheet, card close/flick dismiss, search filtering
├── Services/
│   ├── Persistence/      # SwiftData database + stores (bookmark, history, tab, recent searches, reading list, site zoom)
│   ├── URLHandling/      # URL normalizer, search suggestions engine, Google Suggest, favicon service
│   ├── Downloads/        # WKDownloadDelegate pipeline writing to Documents/Downloads
│   └── Import/           # Netscape HTML bookmark parser & importer
└── Settings/             # Browser preferences, search engine, data clearance, downloads sheet, zoom reset
```

### 4.1 Chrome & Contextual Rail
- **`SideRailView`**: Floating circular action buttons centered in the right 84 pt column. Context-driven via `RailMode`:
  - `.browsing`: Back button (dynamically enabled based on web view history), Bookmarks library trigger, New Tab, and Tab Overview.
  - `.startPage`: Prominent Blue Checkmark (`Done`) button.
  - `.library(tab)`: Done button at bottom; contextual actions at top (Add Folder and Edit for Bookmarks; Clear for History; Reading List surfaces display, filter, and select actions through an ellipsis menu). Reading List selection mode repurposes the prominent blue check to mean "done selecting" (it exits selection mode and restores the normal Reading List rail) and keeps batch deletion as the trash action at the TOP of the rail; the blue check resumes its exit-the-Library role once selection mode ends.
  - `.bookmarkEditor`: Cancel (`xmark`) at top; Save (`checkmark`) at bottom.
  - Tab overview bypasses `RailMode`: `TabOverviewViewController.applyRailItems(to:)` puts Search and an ellipsis menu (Manage Tab Groups, New Group…, Close All Tabs behind a confirm sheet) on top, New Tab and Done at the bottom.
  - *Quick Menu*: When collapsed, a compact circular button remains at `(402, 600)` to restore the rail on tap.
- **`AddressBarView`**: Liquid glass floating capsule displaying security status (lock icon), page domain/title, reload/stop action, and page menu anchor. Morphs between expanded (44 pt height) and minified (30 pt height). While Find in Page is active, the find capsule (`FindInPageView`) occupies the pill's exact frame — the FSM is not involved; the overlay is independent like `errorContainer`.
- **`AddressEditorView`**: Full-bleed editing overlay docked above `keyboardLayoutGuide`. Features an integrated `UITextField` inside a glass capsule and a suggestions `UITableView` with `automaticDimension` row height to eliminate any text clipping.
- **`ChromeStateController`**: Pure, deterministic finite state machine driving chrome transitions from scroll offsets, drag events, and editing lifecycle changes. P1 introduces no new FSM inputs or states.

### 4.2 Address Editing & Suggestions Pipeline
- **`SuggestionEngine`**: High-performance multi-source candidate ranking pipeline:
  1. **Open Tabs**: Immediate matching against existing tabs (`SuggestionKind.openTab`), enabling one-tap switching.
  2. **Google Suggestions**: Live remote completions retrieved from the Google Suggest API (`GoogleSuggestService`), supporting both array-of-arrays and string formats.
  3. **Bookmarks & Favorites**: Host and title matches from `BookmarkStore`.
  4. **History & Recent Searches**: Recent search terms when the input is empty; chronological history visits when typing.
  5. **Web Search**: Fallback search query for the selected default search engine.
  6. **Find on Page**: In-page text search trigger when an active web page is loaded.
- **Execution Strategy**: Local candidate ranking (tabs, bookmarks, history) runs **synchronously on the main thread (< 1 ms latency)** for instantaneous keystroke response. Network queries to Google Suggest run in the background with a 120 ms debounce.
- **`FaviconService`**: Asynchronous favicon fetching and disk caching with monogram generation fallback for instant visual recognition.

### 4.3 Web Surface & Tab Management
- **`WebPageController`**: Wraps `WKWebView`, manages navigation delegates, script injection, progress observation, pull-to-refresh, certificate verification, and snapshot caching. P1 adds: `WKUIDelegate` element context menus (links/images via `ElementContextMenu`), the download policy (downloadable navigation actions and responses return `.download` so WebKit drives the transfer with the original request; `DownloadsManager` completes each `WKDownload` via `didBecome` + `decideDestinationUsing`), find-in-page JS engine (`findText`/`findStep`/`clearFind`), reader-mode DOM transforms (`toggleReader`/`setReaderTheme`/`setReaderFontSize`, guarded by a document generation so stale extractions never touch a new document), and per-site `pageZoom` application (`SiteZoomStore`).
- **`TabPool`**: Manages the lifecycle of live tab controllers. Enforces a 30-tab live memory cap using an LRU eviction policy (evicting inactive WKWebViews to disk snapshots while preserving tab state and navigation history).
- **`TabOverviewViewController`**: Visual card grid (cols = `max(2, floor(width / 180))`) featuring snapshot previews, close buttons, real-time title search filtering, and **tab groups** (card context menu Move to Group; zero-member groups hidden). Bottom chrome is ONE Safari-style glass pill owned by **`TabGroupPickerBar`** (`Sources/Browser/TabOverview/TabGroupPickerBar.swift`) titled "<other mode> · <N> Tabs" via the shared `compactSegments`/`compactTitle`/`compactAttributedTitle` builder: tap opens the **`TabGroupsSheetController`** sheet, long-press shows an action sheet, and a horizontal drag past threshold crossfades to an item strip that tracks the nearest pill with a sliding indicator while live-filtering the grid, collapsing on release. Mode/group application lives in **`TabOverviewViewController+Picker.swift`** (`updatePickerBar`, single-refresh `applySelectionBatched`, `showPickerMenu`, sheet presentation). The bottom chrome itself holds no segmented control or separate groups capsule; Standard/Private switching happens inside the sheet via its own pill.
- **`TabGroupsSheetController`**: Standalone UIKit sheet (Sources/Browser/TabOverview/) listing All (Standard), Private, existing groups with counts and active checkmarks, and both create rows ("New Empty Tab Group", "New Tab Group with N Tabs" — the latter hidden at zero standard tabs). Under the header sits a `pillControl: UISegmentedControl` mirroring `LibraryTabBar`: segments are derived from the rows via `Segment(row:)` (All/Private/groups; create rows map to `nil` and have no pill equivalent), so the All/Private/group mapping lives in exactly one place. Tapping a pill segment or a table row selects that mode/group and dismisses the sheet; long-press (context menu) on a group row offers Rename/Delete, which keep the sheet open. A trailing blue checkmark button dismisses the sheet. It knows nothing of `TabOverviewViewController`'s internals: it consumes a `TabGroupsSheetState` snapshot via `stateProvider` and emits `Action`s. The sheet re-reads state on `viewWillAppear` and after actions that keep it open.
- **Group delegate protocol**: `TabOverviewViewControllerDelegate.tabOverview(_:didCreateGroup:withTabIDs:)` is the single own-side batch creation method; the owner (`BrowserRootViewController+Overview.swift`) creates the group and assigns every listed standard tab (empty array = empty group). Private tabs are never assigned.
- **`TabCardCell`**: Card with preview + favicon/title/host strip, a visible 28 pt close button at the preview's top-left, and a begin-always / claim-on-speed flick-to-dismiss along the dominant axis (horizontal or vertical): the pan begins alongside the grid's scroll gesture and latches only once velocity passes `shouldBeginCardFlick`/`shouldClaimFlick`, freezing grid scrolling only after the claim; slow drags never latch so the grid scrolls instead; thresholds are pure statics unit-tested in `TabCardFlickTests`).
- **`ElementContextMenu`**: Pure UIMenu builder — the canonical item owner. Links: Open in New Tab, Add to Reading List, Copy Link, Share. Images: Open in New Tab, Save to Photos, Copy Image, Share. Photos saving declares `NSPhotoLibraryAddUsageDescription`.

### 4.4 Library, Bookmarks, Favorites, History & Reading List
- **`BookmarksLibraryView`**: Full-screen container with custom `LibraryTabBar` providing full-width navigation across **Favorites**, **Bookmarks**, **History**, and **Reading List** (`LibraryTab.readingList`, systemImage `eyeglasses`).
- **Library search tuck contract**: In all three searchable lists the search bar is **hidden by default** and revealed only by pulling down from the top. `LibrarySearchTuckController` (Sources/Browser/Bookmarks/LibrarySearchHeaderView.swift) is the SOLE tuck decider: every host list re-asserts the hidden state via `reassert` immediately after every `tableReload` (`reassert` detaches the header via `requiresCollapse` on short lists that cannot tuck, otherwise re-attaches the header and tucks via `enforceTuck`); first-layout tuck stays in `layoutTuckIfNeeded`; re-exposure on reload is a bug. The spacing between the revealed search bar and list content is owned by the header view's internal padding (`defaultHeight` 64 with ~14 pt bottom padding), never by per-list constants.
- **`BookmarksBrowserView`**: Hierarchical bookmark navigator supporting nested folders, section-bound drag-and-drop reordering, and context-menu operations.
- **`BookmarkEditorView` + `BookmarkEditorModel`**: Dedicated bookmark editing surface for modifying title, URL, and destination folder using `BookmarkLocationTree`. Directly integrated with side-rail Cancel/Save buttons.
- **`FavoritesGridView` + `FavoriteTileCell`**: Safari-faithful grid displaying large custom-rendered favicon tiles with rounded corners.
- **`HistoryListView` + `HistorySegmenter`**: Chronologically partitioned browsing history (Today Morning / Afternoon / Evening, Yesterday Morning / Afternoon / Evening, Previous 7 Days, Older) with swipe-to-delete and full clearance.
- **`ReadingListView`**: Saved-pages list mirroring the History list pattern (insetGrouped rows, favicon, semibold unread titles, swipe-to-delete, display/filter/select via the rail ellipsis menu with batch deletion in selection mode). P1 loads saved pages as ordinary URLs; no offline snapshot cache.

### 4.5 Reader Mode & Per-Site Zoom
- **`ReaderMode`** (pure engine): extraction script (idempotent, `window.__outerviewReader` namespace; ≥ 60-char paragraph heuristic; not readerable when text < 200 chars), `replaceBodyScript` applying light/sepia/dark themes and 14–28 pt font (default 20) inline on the live document, restore via `webView.reload()`. Preferences persist in `UserDefaults` keys `readerTheme` / `readerFontSize`. Reader state clears on every navigation/reload.
- **`SiteZoomStore`**: `UserDefaults` dictionary (key `siteZoom`) mapping host → zoom, clamped 0.5–3.0 in 0.1 steps (entry removed at 1.0). Applied to `WKWebView.pageZoom` on every navigation commit; zoom controls (In/Out/Reset) live in the page menu; Settings offers "Reset All Text Zooms".

### 4.6 Data Persistence & Storage
- **`OuterViewDatabase`**: Central SwiftData `@ModelContainer` wrapper providing thread-safe main-actor model contexts and in-memory options for unit testing.
- **`BookmarkStore`**: Handles bookmark trees, folder management, deduplication, and favorites flags.
- **`HistoryStore`**: Records visits, enforces a 10,000-entry retention cap, and performs date-range lookups.
- **`TabStore`**: Persists active tabs and session state; P1 adds tab-group CRUD (create/rename with 32-char clamp, delete orphans members to ungrouped, assign). Private tabs are strictly filtered out and never written to disk.
- **`RecentSearchStore`**: Tracks recent search queries with individual or complete clearance.
- **`ReadingListStore`**: URL-deduped (earliest wins, empty-title refresh), 2000-entry cap with prune-oldest, read-state flags, ordering, and clearance.
- **`DownloadsManager`**: `@MainActor` WKDownloadDelegate pipeline writing to `Documents/Downloads` (Files-app visible); sanitized suggested names with `name (2).ext` collision handling; row state (inProgress/finished/failed) with cancel/delete; folder export to the Files app.

---

## 5. Key Contracts & Interaction Flows

### 5.1 Chrome Scroll State Machine
```
[User Down-Scroll] ──> Accumulate Delta ≥ 0 pt  ──> Rail Collapses; Quick Menu Appears
                   ──> Accumulate Delta ≥ 24 pt ──> Address Pill Minifies (30 pt)

[User Up-Scroll]   ──> Accumulate Delta ≥ 32 pt ──> Rail Expands; Address Pill Restores (44 pt)

[Quick Menu Tap]   ──> Immediate Override       ──> Rail Expands Instantly
```

### 5.2 Address Editing & Start Page Coordination
1. **Initiation**: Tapping the address bar or selecting "Open Start Page" invokes `beginEditing()`:
   - On tabs with an active web page, `BrowserRootViewController` displays the unified `StartPageView` underneath the address editor.
   - `editorView` unhides and keyboard focuses on `textField` docked above `keyboardLayoutGuide`.
   - The side rail transitions to `RailMode.startPage` presenting the prominent Blue Checkmark (`Done`).
2. **Typing**: Keystrokes switch `AddressEditorView` into typing mode:
   - Synchronous local suggestions render instantly over an opaque `.systemBackground` backdrop.
   - Debounced remote Google suggestions merge seamlessly upon arrival.
3. **Exit**: Tapping the Blue Checkmark in the side rail invokes `dismissStartPageOrEditing()`, cleanly dismissing the keyboard, hiding the editor, and smoothly restoring the underlying web page.

### 5.3 Page Menu Structure
The page menu accessed from the address capsule adheres strictly to Safari's structure:
- **Top Inline Palette Row** (`[.displayInline, .displayAsPalette]`): Horizontal row with Back, Forward, Reload, and Share icon actions.
- **Action List**: Contextual list items including "Add to Favorites", "Add to/Remove from Reading List", "Show/Hide Reader" (only when readerable), "Find on Page", "Text Zoom" submenu (Zoom In / Zoom Out / Reset), "Downloads", "Open Start Page", and "Settings".

### 5.4 Find in Page Flow
1. Page menu "Find on Page" → `beginFind()`: the find capsule swaps into the expanded pill's frame (full content width); pill suppressed while active.
2. Typing runs `window.__outerviewFind(query)` → live highlights + "n/m" counter; prev/next cycle via `findStep(±1)`.
3. Done → `endFind()`: `clearFind()` + pill restored in the FSM's current state (rail commands keep animating during find).

### 5.5 Tab Overview Chrome Flow
1. **Rail**: Search + ellipsis menu (Manage Tab Groups, New Group…, Close All Tabs with confirm sheet) on top; New Tab and Done at the bottom.
2. **Tabs pill**: One bottom glass capsule (`TabGroupPickerBar`); tap opens `TabGroupsSheetController` (medium detent, grabber); long-press shows an action sheet (Manage Tab Groups, New Group…, Cancel — the destructive Close All Tabs stays rail-only behind its own confirm sheet). A tap-and-drag scrub past threshold crossfades to the item strip, tracks the nearest pill with a sliding indicator, live-filters the grid on each tick through the single-refresh `applySelectionBatched` path, and commits on release (cancel reverts to the committed selection).
3. **Sheet pill + rows**: A `pillControl: UISegmentedControl` under the header mirrors `LibraryTabBar` (segments derived via `Segment(row:)`); tapping a pill segment or a table row selects All/Private/a group and dismisses; create rows prompt for a name and forward the batch `didCreateGroup:withTabIDs:` delegate call; long-press (context menu) on a group row offers Rename/Delete, which keep the sheet open (owner-refresh re-reads `stateProvider`).

---

## 6. Engineering Standards & Test Automation Contracts

### Test & Target Matrix
- **Target Device**: All automated builds (`xcodebuild build`) and unit tests (`xcodebuild test`) **strictly target the iPhone 17 Pro simulator**:
  ```bash
  xcodebuild test -scheme OuterView -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/OuterViewDD -only-testing:OuterViewTests
  ```
- **Test Scope**: Only the unit test bundle (`OuterViewTests`) is executed in automated workflows. UI tests (`OuterViewUITests`) are excluded unless explicitly requested.
- **Project Maintenance**: Whenever files are added, removed, or project configuration changes, `xcodegen generate` must be run to synchronize `OuterView.xcodeproj` from `project.yml`.

### Architectural Invariants
- **No Hardcoded Screen Dimensions**: All view layouts must use dynamic safe-area insets, layout guides, and trait collections. Never query `UIScreen.main` or branch on device models.
- **No Private APIs**: Safari functionality (bookmarks import, icon rendering, suggestions, find, reader, downloads) is achieved strictly through public iOS SDKs.
- **Memory Safety & Process Isolation**: Inactive web views must be evicted via `TabPool` to prevent WebContent process bloat on memory-constrained devices.
- **Single-Owner Menus**: The page menu structure is edited only where the integration task specifies; feature tasks expose capability APIs and never fork the menu builder.
- **Single-Owner Tuck + Chrome Composition**: Library-list tuck decisions live only in `LibrarySearchTuckController`; library select-mode rail composition lives only in `BrowserRootViewController.updateLibraryRailItems(for:)`; tab-card dismissal lives only in `TabCardCell`; bottom overview chrome lives only in the TabOverview trio — `TabGroupPickerBar` (pill/strip/indicator/scrub gestures), `TabOverviewViewController+Picker.swift` (selection/menu/sheet application), and `TabOverviewViewController` (hosts and constrains `pickerBar`). Call sites delegate; they never re-implement.