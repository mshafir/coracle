# WebKit profile isolation and tab lifecycle: macOS vs Linux

Research for [issue #1](https://github.com/mshafir/coracle/issues/1). Checked on 2026-11-25
against Apple's developer documentation, the webkitgtk.org API reference, the WebKit source
tree (`main`), and distro package databases. Every claim carries its source; anything marked
**(from memory)** was not confirmed against a source today and should be treated as a lead,
not a fact.

## Short answer

Both platforms can do what Coracle needs for profiles: several fully isolated, on-disk
profiles live at once in one app, each shared by any number of web views.

- **macOS**: `WKWebsiteDataStore(forIdentifier: UUID)`. Needs **macOS 14.0**.
- **Linux**: `WebKitNetworkSession` with its own data and cache directories, in the
  `webkitgtk-6.0` (GTK 4) API. Needs **WebKitGTK 2.40**.

On both, **the profile is fixed when the web view is created** and cannot be changed
afterwards. Moving a tab to another profile means building a new web view.

Neither platform has a public "discard this tab and bring it back later" call. The portable
recipe is the same on both: serialise the tab's session state (back/forward list, scroll
position, form state) to bytes, destroy the web view, and later build a fresh web view and
restore the bytes into it. Both platforms expose that serialisation publicly (macOS 12.0;
WebKitGTK 2.12). Neither lets the app choose which pages share an OS process.

## Side by side

| Capability | macOS (WKWebView) | Linux (WebKitGTK, `webkitgtk-6.0`) | Differs? |
|---|---|---|---|
| Isolated persistent profile | `WKWebsiteDataStore(forIdentifier:)`, keyed by a `UUID`. macOS 14.0 | `webkit_network_session_new(data_dir, cache_dir)`. 2.40 | Key is a UUID on macOS, a pair of directories on Linux |
| Where the data lives | WebKit chooses; no public API to pick the directory | The app chooses both directories | **Yes.** Coracle can lay out profile folders itself only on Linux |
| Several profiles live at once | Yes, one data store per configuration | Yes, one network session per view; all share one network process | No |
| Share a profile between views | Assign the same data store to each configuration | Pass the same `WebKitNetworkSession` to each view | No |
| Bind profile to a view | `WKWebViewConfiguration.websiteDataStore`, **creation time only** | `WebKitWebView:network-session`, **construct-only** | No |
| List existing profiles | `fetchAllDataStoreIdentifiers`. macOS 14.0 | None; the app tracks its own directories | Yes |
| Delete a profile | `remove(forIdentifier:)`; every web view using it must be released first. macOS 14.0 | No API; clear with `webkit_website_data_manager_clear()` and/or delete the directories yourself | Yes |
| Private (in-memory) profile | `WKWebsiteDataStore.nonPersistent()`. macOS 10.11 | `webkit_network_session_new_ephemeral()`. 2.40 | No |
| Cookies persisted to disk | Automatic with a persistent store | **Not by default.** Must call `webkit_cookie_manager_set_persistent_storage()` per session | **Yes.** Easy to miss on Linux |
| Serialise session state | `WKWebView.interactionState` (get). macOS 12.0 | `webkit_web_view_get_session_state()` + `webkit_web_view_session_state_serialize()` → `GBytes`. 2.12 | Formats are unrelated; not portable across platforms |
| Restore session state | Set `interactionState` on a new web view; it navigates itself | `webkit_web_view_session_state_new(bytes)` + `webkit_web_view_restore_session_state()`; the app must then trigger the load | Yes (see below) |
| Suspend a background page | `WKPreferences.inactiveSchedulingPolicy` (`suspend` is the default for a view not in a window). macOS 14.0 | No public API | **Yes** |
| Pause media in a tab | `setAllMediaPlaybackSuspended(_:)`. macOS 12.0 | Only mute: `webkit_web_view_set_is_muted()`. 2.30 | Yes |
| Kill a tab's content process, keep the view | Private only (`_killWebContentProcess`) | Public: `webkit_web_view_terminate_web_process()`. 2.34 | **Yes** |
| Told when a content process dies | `webViewWebContentProcessDidTerminate(_:)`. macOS 10.11 | `WebKitWebView::web-process-terminated`, with a reason. 2.20 | Linux gives a reason (crash, memory limit, API) |
| Choose which views share a process | No. `WKProcessPool` deprecated in macOS 12.0, "no longer has any effect" | Only `related-view` (construct-only), which also forces the same session. Process model itself is fixed | Neither gives real control |
| Per-process memory limits | No public API | `WebKitMemoryPressureSettings` on the `WebKitWebContext` (construct-only). 2.34 | Yes |

## (a) Profiles

### macOS

- `WKWebsiteDataStore.init(forIdentifier:)` "returns the persistent data store with the unique
  identifier you provide", creating it if it does not exist; Apple's text says "use this method
  to get a data store for a profile". Introduced in **macOS 14.0** / iOS 17.0.
  [Apple: init(forIdentifier:)](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:))
- The class overview spells out the three kinds of store: `default()` (persistent, shared),
  `nonPersistent()` (private browsing), and `init(forIdentifier:)` ("to implement profile
  browsing"). It also says to assign the store to the configuration "before you create your web
  view". [Apple: WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
- The identifier is an `NSUUID`; the header says it "throws exception if identifier is 0".
  [WKWebsiteDataStore.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h)
- `remove(forIdentifier:completionHandler:)` deletes a store. "Release any WKWebView instances
  using the data store before you call this method." macOS 14.0.
  [Apple: remove(forIdentifier:)](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove(foridentifier:completionhandler:))
- `fetchAllDataStoreIdentifiers(_:)` lists identified stores; the default and non-persistent
  stores have no identifier. macOS 14.0.
  [Apple: fetchAllDataStoreIdentifiers](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/fetchalldatastoreidentifiers(_:))
- WebKit's own release notes describe this as the API added alongside Safari 17 profiles
  ("creating persistent website data stores").
  [WebKit blog: Safari 17.0](https://webkit.org/blog/14445/webkit-features-in-safari-17-0/)
- **Creation-time only.** "The web view incorporates your configuration settings only at
  creation time; you cannot change those settings dynamically later", and
  `WKWebView.configuration` returns a copy.
  [Apple: WKWebViewConfiguration](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration),
  [Apple: configuration](https://developer.apple.com/documentation/webkit/wkwebview/configuration)
- **No public control over the on-disk location.** The public API takes only a UUID. Choosing
  directories exists only as private API (`_WKWebsiteDataStoreConfiguration`,
  `_initWithConfiguration:`).
  [WKWebsiteDataStorePrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStorePrivate.h)
  The actual path WebKit uses under the app's Library folder was not checked. Consequence:
  a profile's site data cannot live in a folder Coracle chooses on macOS, so the "profile link"
  in a space file has to be a UUID (or a name Coracle maps to a UUID), not a path.
- Before macOS 14 there is one persistent store per app plus any number of in-memory ones, so
  there is no public way to have several persistent profiles. That makes **macOS 14.0 the hard
  floor** for the profiles feature.

### Linux

- In `webkitgtk-6.0`, "different network sessions can be created and used in the same network
  process"; "the `WebKitNetworkSession` to be used must be passed to the `WebKitWebView` as a
  construct parameter. You can pass the same `WebKitNetworkSession` object to several web views
  to use the same session." It is no longer possible to create a `WebKitWebsiteDataManager`
  directly; the session creates it.
  [Migrating to webkitgtk-6.0](https://webkitgtk.org/reference/webkitgtk/stable/migrating-to-webkitgtk-6.0.html)
- `webkit_network_session_new(data_directory, cache_directory)` creates a persistent session
  with those base directories. Since **2.40**. "A web view created without a network session
  uses the one of its related view, if any, or the default one."
  [webkit_network_session_new](https://webkitgtk.org/reference/webkitgtk/stable/ctor.NetworkSession.new.html)
- `WebKitWebView:network-session` is **construct-only**. Since 2.40.
  [property network-session](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.network-session.html)
- The session owns the cookie manager, the website data manager, ITP, TLS policy, downloads and
  HTTP-auth credential storage ("enabled ... by default for non-ephemeral sessions").
  [WebKitNetworkSession](https://webkitgtk.org/reference/webkitgtk/stable/class.NetworkSession.html),
  [set_persistent_credential_storage_enabled](https://webkitgtk.org/reference/webkitgtk/stable/method.NetworkSession.set_persistent_credential_storage_enabled.html)
- **Cookies are not written to disk unless asked.** "By default, cookie_manager doesn't store
  the cookies persistently, so you need to call this method to keep cookies saved across
  sessions." Each profile's session needs its own cookie file (SQLite or text).
  [webkit_cookie_manager_set_persistent_storage](https://webkitgtk.org/reference/webkitgtk/stable/method.CookieManager.set_persistent_storage.html)
  The source agrees: a persistent cookie jar is only created when a storage path was set.
  [NetworkSessionSoup.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/soup/NetworkSessionSoup.cpp)
- There is no "list sessions" or "delete session" call in the class reference. Coracle owns the
  directories, so it enumerates and deletes them itself;
  `webkit_website_data_manager_clear()` empties a live one.
  [WebKitWebsiteDataManager](https://webkitgtk.org/reference/webkitgtk/stable/class.WebsiteDataManager.html)
- Whether a second process (or second `WebKitNetworkSession` object) pointed at the same
  directories is safe was **not verified**. Assume one session object per profile directory.

#### The older GTK 3 API (`webkit2gtk-4.1`) is a poor fit

In 4.1 the data manager is bound to the `WebKitWebContext`
(`webkit_web_context_new_with_website_data_manager()`, construct-only, since 2.10), not to the
view, so each profile needs its own web context.
[new_with_website_data_manager](https://webkitgtk.org/reference/webkit2gtk/stable/ctor.WebContext.new_with_website_data_manager.html),
[WebContext:website-data-manager](https://webkitgtk.org/reference/webkit2gtk/stable/property.WebContext.website-data-manager.html)
It works **(from memory: one network process per context in that API)**, but the 6.0 design is
the one that matches "several spaces share a profile".

## (b) Tab lifecycle

### Serialising and restoring a tab

**macOS.** `WKWebView.interactionState` holds "the interaction state (back-forward list,
currently loaded page, scroll position, form data...) ... which can be retrieved and set on
another WKWebView to restore state". **macOS 12.0.**
[Apple: interactionState](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate),
[WKWebView.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.h)

- The declared type is an opaque `id`. In the current source the getter returns encoded
  session-state `NSData`, and the setter ignores anything that is not `NSData`, then restores
  and navigates.
  [WKWebView.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm)
  So writing it to disk works today, but **the `NSData` shape is an implementation detail, not
  a documented contract**. Coracle should type-check it and fall back to "reload the URL" if it
  ever stops being data or fails to decode.

**Linux.** `webkit_web_view_get_session_state()` returns a `WebKitWebViewSessionState`;
`webkit_web_view_session_state_serialize()` turns it into `GBytes`;
`webkit_web_view_session_state_new(bytes)` parses it back (returning `NULL` if invalid);
`webkit_web_view_restore_session_state()` applies it. All since **2.12**, present in both 4.1
and 6.0.
[WebKitWebViewSessionState](https://webkitgtk.org/reference/webkitgtk/stable/struct.WebViewSessionState.html),
[get_session_state](https://webkitgtk.org/reference/webkitgtk/stable/method.WebView.get_session_state.html),
[restore_session_state](https://webkitgtk.org/reference/webkitgtk/stable/method.WebView.restore_session_state.html)

- The serialised form is a versioned GVariant (currently version 3) carrying, per history item:
  URL, original URL, referrer, title, document (form) state, `history.pushState` data, scroll
  position, page scale, POST body, and child frames.
  [WebKitWebViewSessionState.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitWebViewSessionState.cpp)
- Restoring does **not** navigate: the GTK code calls `restoreFromSessionState(state, false)`,
  where macOS passes `true`.
  [WebKitWebView.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitWebView.cpp)
  The app has to go to the current back/forward item itself after restoring **(from memory:
  this is what GNOME Web does; not checked today)**.

**Shared limits.** The two formats are unrelated, so a saved tab cannot move between a Mac and
a Linux machine with its history; only the URL and title are portable. That matters for the
glossary: session state belongs with unpinned, machine-local tabs, not in the sync folder. Both
restore by reloading pages from the network or cache; neither snapshots the live JavaScript
heap, so in-page state that is not in form fields is lost on discard.

### Suspending a page that stays alive

- **macOS 14.0+**: `WKPreferences.inactiveSchedulingPolicy` controls "how a web view that's not
  in a window handles tasks": `suspend` (default), `throttle`, or `none`. "A suspended web view
  will pause JavaScript execution and page layout." Views playing media, capturing media or
  loading are exempt.
  [Apple: inactiveSchedulingPolicy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property),
  [WKPreferences.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKPreferences.h)
  This saves CPU, not memory: the process and its heap stay.
  It is the trigger "not in a window" that matters, so the abstraction should detach
  background tabs' views from the window rather than merely hide them.
- **macOS 12.0+**: `setAllMediaPlaybackSuspended(_:)` pauses all media so that "neither the user
  nor the webpage can resume playback" until it is undone.
  [Apple: setAllMediaPlaybackSuspended](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended(_:completionhandler:))
- Explicit `_suspendPage:` / `_resumePage:` exist only as private API (macOS 12.0).
  [WKWebViewPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h)
- **Linux**: the `WebKitWebView` reference has no suspend or scheduling-policy API. What
  WebKitGTK does on its own to a view that is unmapped or hidden (timer throttling and so on)
  was **not verified**.

### Discarding a tab to free memory

- **macOS**: no public discard. The only public route is to save `interactionState`, release
  the `WKWebView`, and recreate it later. Killing the content process while keeping the view is
  private API (`_killWebContentProcess`, `_killWebContentProcessAndResetState`).
  [WKWebViewPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h)
  Coracle is not App Store-bound by necessity, so private API is technically usable, but it is
  unversioned and can change without notice.
- **Linux**: `webkit_web_view_terminate_web_process()` (since **2.34**) is public and emits
  `web-process-terminated` with reason `TERMINATED_BY_API`.
  [terminate_web_process](https://webkitgtk.org/reference/webkitgtk/stable/method.WebView.terminate_web_process.html),
  [WebProcessTerminationReason](https://webkitgtk.org/reference/webkitgtk/stable/enum.WebProcessTerminationReason.html)
  Because processes can be shared (see below), this may take other views down with it
  **(inferred from the process-sharing docs; not tested)**. Destroying the view is the safer,
  portable form.
- Both platforms report an unexpected process death, which a browser must handle anyway and
  which gives a natural "this tab was unloaded, click to reload" state:
  [webViewWebContentProcessDidTerminate](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:)) (macOS 10.11),
  [web-process-terminated](https://webkitgtk.org/reference/webkitgtk/stable/signal.WebView.web-process-terminated.html) (2.20).
- Linux only: `WebKitMemoryPressureSettings` sets a per-web-process memory limit and
  thresholds; it is a construct-only property of the `WebKitWebContext`, since 2.34. A process
  over the limit is killed with reason `EXCEEDED_MEMORY_LIMIT`.
  [WebKitMemoryPressureSettings](https://webkitgtk.org/reference/webkitgtk/stable/struct.MemoryPressureSettings.html),
  [WebContext:memory-pressure-settings](https://webkitgtk.org/reference/webkitgtk/stable/property.WebContext.memory-pressure-settings.html)

### Process sharing

- **macOS**: `WKProcessPool` and `WKWebViewConfiguration.processPool` are deprecated as of
  macOS 12.0: "Creating and using multiple instances of WKProcessPool no longer has any
  effect."
  [WKProcessPool.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKProcessPool.h),
  [Apple: processPool](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/processpool)
  Apple's older text says WebKit gives each web view its own process "until it reaches an
  implementation-defined process limit", after which views share.
  [Apple: WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool)
  The private `_relatedWebView` knob is deprecated too (macOS 15.2).
  [WKWebViewConfigurationPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfigurationPrivate.h)
- **Linux**: the process model has been fixed at multiple secondary processes since 2.26;
  `webkit_web_context_set_process_model()` "does nothing" and is gone from 6.0.
  [set_process_model (4.1)](https://webkitgtk.org/reference/webkit2gtk/stable/method.WebContext.set_process_model.html)
  In 6.0, swapping process on cross-site navigation is mandatory: "be prepared for the web
  view's web process to be replaced when navigating between different security origins".
  [Migrating to webkitgtk-6.0](https://webkitgtk.org/reference/webkitgtk/stable/migrating-to-webkitgtk-6.0.html)
  The one lever is `WebKitWebView:related-view` (construct-only, since 2.4), which makes a new
  view "share the same web process and network session" as another.
  [property related-view](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.related-view.html)
  When it is set, `web-context`, `network-session` and `is-ephemeral` passed alongside are
  ignored with a warning.
  [WebKitWebView.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitWebView.cpp)
- Conclusion for both: treat the process layout as WebKit's business. A web view's content
  process can change under it during navigation, so nothing in Coracle should key off a
  process ID, and "memory per tab" can only be an estimate.

## Fixed at web view creation

These cannot be changed on a live web view. The abstraction's "create web view" call has to
take all of them up front.

| | macOS | Linux (6.0) |
|---|---|---|
| Profile | `configuration.websiteDataStore` | `network-session` |
| Private/ephemeral | by choosing a non-persistent store | `network-session` (ephemeral) or `is-ephemeral` |
| Process relationship | n/a publicly | `related-view` |
| Engine context | n/a | `web-context` (and through it, memory-pressure settings, which are construct-only on the context) |
| Other | the whole `WKWebViewConfiguration` (user content controller, URL scheme handlers, etc.) is copied at creation | `is-controlled-by-automation`, `web-extension-mode`, `default-content-security-policy`, `user-content-manager` are construct-only |

Sources: [Apple: WKWebViewConfiguration](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration);
construct-only flags in
[WebKitWebView.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitWebView.cpp).
On macOS, `WKPreferences.inactiveSchedulingPolicy` is a plain read-write property on the
preferences object; whether changing it on a live view takes effect immediately was not
verified.

Also fixed for the life of the profile, not the view: on macOS a store can only be removed
once every web view using it is released; on Linux the data and cache directories are
construct-only on the data manager
([base-data-directory](https://webkitgtk.org/reference/webkitgtk/stable/property.WebsiteDataManager.base-data-directory.html)).

## Minimum versions

| Need | macOS | WebKitGTK |
|---|---|---|
| Several persistent profiles | **14.0** | **2.40** with `webkitgtk-6.0` (GTK 4) |
| Session save/restore | 12.0 | 2.12 |
| Background suspension | 14.0 | not available |
| Kill content process via public API | not available | 2.34 |
| Media pause / mute | 12.0 (pause) | 2.30 (mute only) |

Recommended floor: **macOS 14.0** and **WebKitGTK 2.40 via `webkitgtk-6.0`**. Everything else
listed is older than those two.

### What distros ship (checked 2026-11-25)

| Distro | `webkitgtk-6.0` | `webkit2gtk-4.1` | `4.0` (libsoup 2) |
|---|---|---|---|
| Debian 12 bookworm (oldstable) | 2.50.6 | 2.50.6 | 2.50.6 |
| Debian 13 trixie (stable) | 2.52.6 | 2.52.6 | gone |
| Debian testing / sid | 2.52.6 / 2.54.3 | same | gone |
| Ubuntu 22.04 jammy | 2.50.4 (updates only; not in the original release) | 2.50.4 | 2.50.4 |
| Ubuntu 24.04 noble | 2.52.6 | 2.52.6 | gone |
| Ubuntu 25.10 questing | 2.52.3 | 2.52.3 | gone |
| Ubuntu 26.04 resolute | 2.52.6 | 2.52.6 | gone |
| Fedora 43 | 2.54.2 | 2.54.2 | gone |
| Fedora 44 | 2.54.3 (updates-testing) | 2.54.3 | gone |
| Arch | 2.54.3 | 2.54.3 | gone |

Sources: [Debian source versions](https://sources.debian.org/src/webkit2gtk/) and the
[Debian madison API](https://api.ftp-master.debian.org/madison?package=libwebkitgtk-6.0-4&f=json);
Launchpad published binaries for `libwebkitgtk-6.0-4`, `libwebkit2gtk-4.1-0`,
`libwebkit2gtk-4.0-37` ([Ubuntu package page](https://launchpad.net/ubuntu/+source/webkit2gtk));
[Fedora mdapi](https://mdapi.fedoraproject.org/f43/pkg/webkitgtk6.0);
[Arch webkitgtk-6.0](https://archlinux.org/packages/extra/x86_64/webkitgtk-6.0/).
Latest upstream stable is 2.54.3 ([releases](https://webkitgtk.org/releases/)).
openSUSE, RHEL and derivatives were not checked.

Reading: every current release of Debian, Ubuntu, Fedora and Arch ships **both** API versions
from the same source package at the same version, and they keep the engine current through
security updates (even Ubuntu 22.04 and Debian 12 are on 2.50.x). So the distro does not force
4.1 on us. Choosing `webkitgtk-6.0` costs nothing in reach on these distros and means GTK 4.
Upstream calls 6.0 the API that "obsoletes" 4.0 and 4.1.
[Migrating to webkitgtk-6.0](https://webkitgtk.org/reference/webkitgtk/stable/migrating-to-webkitgtk-6.0.html)

## Where the two platforms differ (what the abstraction must absorb)

1. **Profile identity.** UUID on macOS, directory pair on Linux. A neutral profile ID that maps
   to a UUID on one side and a directory name on the other covers both.
2. **Profile storage location.** App-chosen on Linux, WebKit-chosen on macOS.
3. **Cookie persistence.** Automatic on macOS, opt-in per session on Linux.
4. **Profile listing and deletion.** Built in on macOS, do-it-yourself on Linux.
5. **Restore semantics.** macOS restores and navigates; Linux restores the list and waits.
6. **Background suspension.** Built in on macOS 14; nothing public on Linux.
7. **Discard.** Linux can kill the content process publicly; macOS must destroy the view. The
   common denominator, "save state, destroy the view, recreate later", works on both.
8. **Session-state format.** Opaque and different on each; not portable, and not promised
   stable across engine versions on either side (Linux carries an explicit version number and
   returns `NULL` for data it cannot parse).

## Not verified

- The on-disk path of identified data stores on macOS, and whether they are included in or
  excluded from backups.
- That `interactionState` will remain `NSData`. It is so in today's source; the public type is
  `id`.
- How much memory is actually reclaimed by each discard route, on either platform. Needs
  measurement in a prototype.
- WebKitGTK's automatic throttling of hidden or unmapped views.
- Whether `webkit_web_view_terminate_web_process()` affects other views sharing the process.
- Behaviour of two `WebKitNetworkSession` objects on the same directories.
- Whether the restored-then-not-navigated behaviour on Linux needs an explicit
  `go_to_back_forward_list_item` (from memory, yes).
- That service workers, IndexedDB, local storage and HTTP cache are all partitioned per store
  or session. The docs describe the store/session as owning "website data" in general; the
  Safari 17 notes list cookies, caches, service workers and Web Push as per-profile. Not tested
  per data type on Linux.
- openSUSE, RHEL-family and Flatpak runtime versions.
