# OuterView — Architecture Blueprint

Architectural blueprint for **OuterView**: a Safari-faithful web browser built for dual-screen and foldable form factors (specifically the iPhone Duo), claiming the entire 466 × 678 pt outer display edge-to-edge with scroll-transient chrome and contextual command controls.

---

## 1. Soul & Design Theses

Stock Safari pins Duo web content to a narrow 382 pt strip beside a static side rail. OuterView claims the entire outer display edge-to-edge and replicates Safari's tactile feel while making chrome transient: controls disappear when reading starts.

1. **Chrome is Transient**: Chrome steps aside for content. The side rail hides on drag began or the first downward scroll movement. The address pill minifies after 24 pt of accumulated downward scroll. An upward scroll of 32 pt restores the address pill and rail.
2. **Quick-Access Menu Button**: When the rail collapses on downward scroll, a compact floating menu button drops down at the bottom right. Tapping it immediately pops the rail back out without requiring the user to scroll backwards.
3. **Wall-to-Wall Content**: WKWebView fills the window edge-to-edge; liquid glass chrome floats above it and adjusts content insets dynamically.
4. **Contextual Command Rail**: The 84 pt right system column is an adaptive command rail driven by `RailMode` (`.browsing`, `.startPage`, `.library`, `.bookmarkEditor`, `.tabOverview`). Contextual actions (Cancel, Save, Edit, Clear, Done) are surfaced directly in the rail rather than crammed into top navigation headers.
5. **Unified Start Page**: A single `StartPageView` serves empty tabs, menu-triggered home access, and the address bar editing backdrop. Large high-res site favicons, recent visits, and Safari import actions live in this single surface.
6. **Multi-Screen Migration**: The app migrates dynamically between the Duo's outer portrait display (466 × 678 pt) and inner landscape display (951 × 669 pt). Layout is always derived from window and safe-area geometry, never from static screen instances, orientation flags, or device idioms.
7. **Swift 6 Concurrency**: Built from day one with strict concurrency, `@MainActor` UI isolation, and immutable `Sendable` value types.

---

## 2. Technology Stack & Runtime Environment

- **Language & Platform**: Swift 6 language mode, iOS 27.1 deployment target.
- **Project Generation**: Declarative `project.yml` managed via **XcodeGen**. The generated `.xcodeproj` is never manually modified or committed.
- **UI Architecture**: UIKit-first browser surface utilizing custom `UIViewController` containment for granular animation and gesture control. SwiftUI is integrated via `UIHostingController` for structured modal sheets (`BookmarkEditorView`, `SettingsView`).
- **Web Rendering**: WebKit (`WKWebView`) with customized navigation policies, process pooling, and certificate challenge handling (`SFSafariViewController` is excluded because its chrome is rigid and non-transient).
- **Persistence**: **SwiftData** backed by a shared `ModelContainer` managing `Bookmark`, `HistoryEntry`, `TabRecord`, `TabGroup`, and `RecentSearch`. An in-memory configuration is supported for unit test isolation.
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
│   ├── Chrome/           # Address bar, address editor, side rail, state machine, glass styling
│   ├── WebPage/          # WKWebView controller, tab pool, LRU eviction, process management
│   ├── StartPage/        # Unified start page, favorites grid, recently viewed list
│   ├── Bookmarks/        # Three-tab library container, bookmark browser, hierarchical editor
│   ├── Favorites/        # Large Safari-style favicon tiles & grid view
│   ├── History/          # Chronologically segmented history list & segmentation logic
│   └── TabOverview/      # Visual tab grid overview, swipe-to-close, search filtering
├── Services/
│   ├── Persistence/      # SwiftData database, bookmark store, history store, tab store, recent searches
│   ├── URLHandling/      # URL normalizer, search suggestions engine, Google Suggest, favicon service
│   └── Import/           # Netscape HTML bookmark parser & importer
└── Settings/             # Browser preferences, search engine selector, data clearance
```

### 4.1 Chrome & Contextual Rail
- **`SideRailView`**: Floating circular action buttons centered in the right 84 pt column. Context-driven via `RailMode`:
  - `.browsing`: Back button (dynamically enabled based on web view history), Bookmarks library trigger, New Tab, and Tab Overview.
  - `.startPage`: Prominent Blue Checkmark (`Done`) button.
  - `.library(tab)`: Done button at bottom; contextual actions at top (Add Folder and Edit for Bookmarks; Clear for History).
  - `.bookmarkEditor`: Cancel (`xmark`) at top; Save (`checkmark`) at bottom.
  - `.tabOverview`: Done at bottom, Add Tab at top.
  - *Quick Menu*: When collapsed, a compact circular button remains at `(402, 600)` to restore the rail on tap.
- **`AddressBarView`**: Liquid glass floating capsule displaying security status (lock icon), page domain/title, reload/stop action, and page menu anchor. Morphs between expanded (44 pt height) and minified (30 pt height).
- **`AddressEditorView`**: Full-bleed editing overlay docked above `keyboardLayoutGuide`. Features an integrated `UITextField` inside a glass capsule and a suggestions `UITableView` with `automaticDimension` row height to eliminate any text clipping.
- **`ChromeStateController`**: Pure, deterministic finite state machine driving chrome transitions from scroll offsets, drag events, and editing lifecycle changes.

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
- **`WebPageController`**: Wraps `WKWebView`, manages navigation delegates, script injection, progress observation, pull-to-refresh, certificate verification, and snapshot caching.
- **`TabPool`**: Manages the lifecycle of live tab controllers. Enforces a 30-tab live memory cap using an LRU eviction policy (evicting inactive WKWebViews to disk snapshots while preserving tab state and navigation history).
- **`TabOverviewViewController`**: Visual card grid (cols = `max(2, floor(width / 180))`) featuring snapshot previews, close buttons, private browsing segmentation, and real-time title search filtering.

### 4.4 Library, Bookmarks, Favorites & History
- **`BookmarksLibraryView`**: Full-screen container with custom `LibraryTabBar` providing full-width navigation across **Favorites**, **Bookmarks**, and **History**.
- **`BookmarksBrowserView`**: Hierarchical bookmark navigator supporting nested folders, section-bound drag-and-drop reordering, and context-menu operations.
- **`BookmarkEditorView` + `BookmarkEditorModel`**: Dedicated bookmark editing surface for modifying title, URL, and destination folder using `BookmarkLocationTree`. Directly integrated with side-rail Cancel/Save buttons.
- **`FavoritesGridView` + `FavoriteTileCell`**: Safari-faithful grid displaying large custom-rendered favicon tiles with rounded corners.
- **`HistoryListView` + `HistorySegmenter`**: Chronologically partitioned browsing history (Today Morning / Afternoon / Evening, Yesterday Morning / Afternoon / Evening, Previous 7 Days, Older) with swipe-to-delete and full clearance.

### 4.5 Data Persistence & Storage
- **`OuterViewDatabase`**: Central SwiftData `@ModelContainer` wrapper providing thread-safe main-actor model contexts and in-memory options for unit testing.
- **`BookmarkStore`**: Handles bookmark trees, folder management, deduplication, and favorites flags.
- **`HistoryStore`**: Records visits, enforces a 10,000-entry retention cap, and performs date-range lookups.
- **`TabStore`**: Persists active tabs and session state. Private tabs are strictly filtered out and never written to disk.
- **`RecentSearchStore`**: Tracks recent search queries with individual or complete clearance.

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
- **Action List**: Contextual list items including "Add to Favorites", "Add Bookmark", "Open Start Page", "Find on Page", and "Settings".

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
- **No Private APIs**: Safari functionality (bookmarks import, icon rendering, suggestions) is achieved strictly through public iOS SDKs.
- **Memory Safety & Process Isolation**: Inactive web views must be evicted via `TabPool` to prevent WebContent process bloat on memory-constrained devices.
