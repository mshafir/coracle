# Native extension and content-filtering mechanisms in WKWebView and WebKitGTK

Research for [issue #4](https://github.com/mshafir/coracle/issues/4). Researched 2026-11-25.

Sources are primary: Apple developer documentation, the webkitgtk.org API reference (stable = library 2.54.3, unstable = 2.53.92 on the day of reading), the WebKit source tree on `main`, and GNOME Web's own README. Anything marked **(memory)** or **(inference)** is not backed by a source read today.

## Short answer

| Mechanism | macOS (WKWebView) | Linux (WebKitGTK) |
|---|---|---|
| Content filtering | `WKContentRuleList`, macOS 10.13+. Stable. | `WebKitUserContentFilterStore` + `WebKitUserContentFilter`, WebKitGTK 2.24+. Stable. **Same JSON rule format.** |
| Browser extensions (WebExtensions) | `WKWebExtension` / `WKWebExtensionContext` / `WKWebExtensionController`, **macOS 15.4+**. Public, complete enough to build on; MV2 and MV3. | **Not usable today.** A manifest-parsing class shipped in 2.52; the runtime is under active upstream development, off by default at build time, and almost every JavaScript API is still Cocoa-only in the source. |
| In-process native hook | none public | Web process extensions (`WebKitWebProcessExtension`): a shared library loaded into each web process. Stable, but it is a native-code hook, not a WebExtension. |

The thing to get right at web-view creation time is the same on both platforms: **every creation-time object that an extension or filter system hangs off must already be a named, per-profile object owned by our abstraction, and a tab must be able to replace its underlying web view.** Details in [What must be right at creation time](#what-must-be-right-at-creation-time).

## macOS: WKWebView

### Content filtering: WKContentRuleList

- `WKContentRuleList` and `WKContentRuleListStore` are available from macOS 10.13 / iOS 11. [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)
- You write rules as JSON, compile them with `WKContentRuleListStore.compileContentRuleList(forIdentifier:encodedContentRuleList:completionHandler:)` into "an efficient byte format", and the store keeps the compiled result on disk and reloads it at creation. The syntax is the same as Safari content blocker extensions. (same pages)
- A store "doesn't automatically apply any of its rules to a particular web view. To apply a rule to a web view, add it to the `WKUserContentController` object of the web view's configuration object." [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)
- `WKUserContentController` has `add(_:)`, `remove(_:)` and `removeAllContentRuleLists()` for rule lists. [WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)
- Rule format: a JSON array of `{trigger, action}`. Triggers: `url-filter` (restricted regex), `url-filter-is-case-sensitive`, `resource-type`, `load-type` (first/third party), `if-domain` / `unless-domain`. Actions: `block`, `block-cookies`, `css-display-none` (with `selector`), `ignore-previous-rules`. Rules are compiled ahead of time to bytecode and evaluated inside the engine; no app or extension code runs per request and the app never sees the URLs. [WebKit blog: Content Blockers first look](https://webkit.org/blog/3476/content-blockers-first-look/). Later additions such as `make-https`, `if-top-url` / `unless-top-url` exist **(memory; the Apple page that lists them did not render for me today)**.
- Hard limit: the parser rejects a list with more than 150,000 rules (`maxRuleCount = 150000` in [`ContentExtensionParser.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionParser.cpp)). Several lists can be added to one content controller, so a large blocklist is split across lists **(inference from the API shape; the practical ceiling on number of lists was not checked)**.

Consequence: this is declarative blocking only. It cannot do what uBlock Origin does with scriptlets and dynamic filtering, and a filter-list (EasyList-style) to JSON converter is our job, not the platform's.

### Browser extensions: WKWebExtension

Availability: macOS 15.4, iOS/iPadOS 18.4, Mac Catalyst 18.4, visionOS 2.4. None of the pages carry a beta marker. [WKWebExtension](https://developer.apple.com/documentation/webkit/wkwebextension), [WKWebExtensionContext](https://developer.apple.com/documentation/webkit/wkwebextensioncontext), [WKWebExtensionController](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)

The three objects:

- **`WKWebExtension`**: the parsed package. Created from a directory or ZIP containing `manifest.json` (`init(resourceBaseURL:)`) or from an app-extension bundle. [init(resourceBaseURL:)](https://developer.apple.com/documentation/webkit/wkwebextension/init(resourcebaseurl:))
- **`WKWebExtensionContext`**: the runtime for one extension: permissions, background content, popups, base URL (`webkit-extension://` scheme by default), unique identifier. [WKWebExtensionContext](https://developer.apple.com/documentation/webkit/wkwebextensioncontext), [baseURL](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/baseurl)
- **`WKWebExtensionController`**: manages a set of loaded contexts. "You can have one or more extension controller instances, allowing different parts of the app to use different sets of extensions. You can associate a controller with `WKWebView` using the `webExtensionController` property on `WKWebViewConfiguration`." [WKWebExtensionController](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)

What the host browser must supply. This is the bulk of the work, and it is all ours:

- **Tab and window model.** The app implements the `WKWebExtensionTab` and `WKWebExtensionWindow` protocols (URL, title, pinned, muted, index in window, parent tab, reader mode, zoom, snapshot, activate/close/duplicate, window frame/state/type, private flag) and must *notify* the controller of every change: `didOpenTab`, `didCloseTab`, `didActivateTab`, `didMoveTab`, `didReplaceTab`, `didChangeTabProperties`, `didOpenWindow`, `didCloseWindow`, `didFocusWindow`, `didSelectTabs`. [WKWebExtensionTab](https://developer.apple.com/documentation/webkit/wkwebextensiontab), [WKWebExtensionWindow](https://developer.apple.com/documentation/webkit/wkwebextensionwindow)
- **Delegate UI.** `WKWebExtensionControllerDelegate` asks the app to open tabs/windows, open the options page, present the action popup, prompt for permissions and host access, and handle native messaging. [WKWebExtensionControllerDelegate](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate)
- **Permission state.** Granted/denied permissions and match patterns live on the context and "should be saved and restored as needed by the app" (stated for private-data access; the same set/get API covers all permissions). [hasAccessToPrivateData](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/hasaccesstoprivatedata)
- **Installation, updating, a store.** Nothing in the API fetches, verifies or updates extensions. It loads a folder or ZIP. Chrome Web Store / AMO `.crx` / `.xpi` handling is not provided **(inference from the API surface)**.

Manifest versions: both MV2 and MV3. The shared parser branches on `supportsManifestVersion(3)` throughout, handling `browser_action` / `page_action` for MV2 and `action` for MV3, persistent background pages for MV2 and non-persistent/service-worker backgrounds for MV3. [`WebExtension.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/WebExtension.cpp)

JavaScript API namespaces. Apple's docs do not list them for the WKWebView API; the source of truth is the namespace IDL in WebKit `main`, [`WebExtensionAPINamespace.idl`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPINamespace.idl):

- Always built on Cocoa: `action`, `alarms`, `browserAction`, `pageAction`, `commands`, `contextMenus`, `menus`, `cookies`, `declarativeNetRequest`, `dom`, `extension`, `extensionTypes`, `i18n`, `permissions`, `runtime`, `scripting`, `storage`, `tabs`, `windows`, `webNavigation`, `webRequest`.
- Behind a build conditional (whether Apple's shipping macOS build enables each was **not verified**): `bookmarks`, `devtools`, `notifications`, `offscreen`, `sidebarAction`, `sidePanel`.
- Not present at all: `downloads`, `history`, `identity`, `proxy`, `sessions`, `topSites`, `privacy`, `management`, and others.
- The declared permission constants match: `activeTab`, `alarms`, `clipboardWrite`, `contextMenus`, `cookies`, `declarativeNetRequest` (+`Feedback`, +`WithHostAccess`), `menus`, `nativeMessaging`, `scripting`, `storage`, `tabs`, `unlimitedStorage`, `webNavigation`, `webRequest`. [WKWebExtension.Permission](https://developer.apple.com/documentation/webkit/wkwebextension/permission)
- `webRequest` is observational; request blocking is done through `declarativeNetRequest` **(memory, consistent with Safari's long-standing behaviour; not re-verified today)**. This is why full uBlock Origin does not run on WebKit.
- The host can remove APIs it does not implement: `WKWebExtensionContext.unsupportedAPIs` makes named `browser.*` members `undefined` so extensions can feature-detect. [unsupportedAPIs](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/unsupportedapis)

Stability: public API, same engine code Safari uses, one OS generation old. `main` is a moving target (IDL above is newer than macOS 15.4), so the exact namespace set on a given macOS version needs a runtime check. Known rough edges are reported on Apple's forums, for example inspecting extension service workers ([thread 781070](https://developer.apple.com/forums/thread/781070)); I did not survey them.

## Linux: WebKitGTK

### Content filtering: WebKitUserContentFilterStore

- `WebKitUserContentFilterStore` (since 2.24) "Handles storage of user content filters on disk": it imports JSON rule sets and saves them in an implementation-defined compiled format under a `storage_path` you choose, for efficient loading later. Methods: `save`, `save_from_file`, `load`, `remove`, `fetch_identifiers` (all async). The docs point at WebKit's content-blocker documentation for the JSON format, so it is the **same rule format as `WKContentRuleList`**. [UserContentFilterStore](https://webkitgtk.org/reference/webkitgtk/stable/class.UserContentFilterStore.html)
- A loaded `WebKitUserContentFilter` is applied with `webkit_user_content_manager_add_filter()` (since 2.24). "The same `WebKitUserContentFilter` can be reused with multiple `WebKitUserContentManager` instances." [UserContentManager.add_filter](https://webkitgtk.org/reference/webkitgtk/stable/method.UserContentManager.add_filter.html)
- The GTK build has the underlying engine feature on by default (`ENABLE_CONTENT_EXTENSIONS ... ON` in [`OptionsGTK.cmake`](https://github.com/WebKit/WebKit/blob/main/Source/cmake/OptionsGTK.cmake)).
- This is what GNOME Web's built-in ad blocker uses **(memory)**.

So one JSON rule set, compiled separately on each platform, serves both. The compiled form is not portable and must not go in the sync folder; the JSON source (or the filter-list source it was generated from) can.

### Browser extensions: WebKit's WebExtensions in the GTK port

Naming trap first. Before API 6.0, "WebKitWebExtension" meant the native web-process plugin (now `WebKitWebProcessExtension`, see below). Since 2.52 the name `WebKitWebExtension` means an actual browser WebExtension. Old bug reports and blog posts using the name are about the other thing.

What exists in a release (stable docs, library 2.54.3):

- `WebKitWebExtension` (since 2.52): created from a folder with `manifest.json`; exposes parsed metadata only: names, version, manifest version, icons, requested/optional permissions and match patterns, has-background-content, has-injected-content, has-content-modification-rules, and so on. **There is no method to load, run or attach it to a web view.** [WebExtension](https://webkitgtk.org/reference/webkitgtk/stable/class.WebExtension.html)
- `WebKitWebExtensionMatchPattern` (since 2.48), plus error domains. [API index](https://webkitgtk.org/reference/webkitgtk/stable/index.html)
- The 2.52 release notes describe this only as "An initial API to support Web Extensions". [WebKitGTK 2.52 highlights](https://webkitgtk.org/2026/03/18/webkitgtk-2.52-highlights.html)
- The unstable docs (2.53.92) list nothing further: no context, no controller. [unstable index](https://webkitgtk.org/reference/webkitgtk/unstable/index.html)

What exists only on `main` (unreleased):

- `WebKitWebExtensionContext` with base URI, options page URI, new-tab override URI, injected-content queries and `load_background_content`. Its commits are dated August to October 2026 ("Create WebKitWebExtensionContext Options Page API", "Support Background Web View in WebKitWebExtensionContext"). [`WebKitWebExtensionContext.h.in`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitWebExtensionContext.h.in), [commit history](https://github.com/WebKit/WebKit/commits/main/Source/WebKit/UIProcess/API/glib/WebKitWebExtensionContext.cpp)
- No public `WebKitWebExtensionController`, no tab/window interfaces, and nothing yet that ties a context to a `WebKitWebView`. [glib API directory](https://github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/API/glib)
- The GLib backend files still contain many `notImplemented()` stubs (17 in `WebExtensionContextGLib.cpp`, 9 in `WebExtensionControllerGLib.cpp` as of today). [glib backend](https://github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/Extensions/glib)
- In the namespace IDL, every JavaScript API except `alarms`, `extensionTypes` and the internal `test` is marked `Platform=COCOA`. On GTK today an extension would get essentially no `browser.*` API: no `runtime`, `tabs`, `storage`, `scripting`. Upstream is porting the implementations from Objective-C to C++ one by one ("Port WebExtensionAPIStorage to C++", 2026-10-23; "Port WebExtensionAPIEvent to C++", 2026-11-05). [`WebExtensionAPINamespace.idl`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPINamespace.idl), [commit history](https://github.com/WebKit/WebKit/commits/main/Source/WebKit/UIProcess/Extensions/glib)
- Build flag: `ENABLE_WK_WEB_EXTENSIONS` defaults to `${ENABLE_EXPERIMENTAL_FEATURES}`, which is off for release builds, and is forced `OFF` for the GTK3 (4.1) API. So it is GTK4 / `webkitgtk-6.0` only, and a distribution package will normally not have it compiled in. [`OptionsGTK.cmake`](https://github.com/WebKit/WebKit/blob/main/Source/cmake/OptionsGTK.cmake). Whether a given distro's 2.52+/2.54 package exports the `WebKitWebExtension` symbols was **not verified**.

Conclusion: the GTK port is following the same design as Apple's API (extension, context, controller), which is good news for a shared abstraction, but there is no shippable extension runtime on Linux today and no published date for one.

### GNOME Web's own implementation

GNOME Web (Epiphany) has a separate, browser-level WebExtension implementation, written inside Epiphany rather than in WebKit. Its README calls it "an experimental implementation" that "should be assumed insecure, incomplete, and full of issues for now". It loads `.xpi` or extracted extensions, supports initial content scripts and background pages/scripts, and implements parts of `alarms`, `browserAction`, `cookies`, `downloads`, `extension`, `i18n`, `runtime`, `menus`/`contextMenus`, `notifications`, `pageAction` and more. [Epiphany `src/webextension/README.md`](https://gitlab.gnome.org/GNOME/epiphany/-/blob/main/src/webextension/README.md). It is off by default behind a hidden setting, and a GNOME Discourse reply describes it as not actively developed ([thread](https://discourse.gnome.org/t/is-there-a-small-list-of-webextensions/24696); forum post, not an official statement).

It is evidence of what a browser can build on the pieces below, at significant cost. It is GPL application code, not a library we can call.

### The pieces a browser can use today

- **`web-extension-mode`** on `WebKitWebView` (since 2.38, **construct-only**): `NONE`, `MANIFESTV2`, `MANIFESTV3`. "This configures `web_view` to treat the content as a WebExtension... In practice this limits the Content-Security-Policies that are allowed to be set." Meant for the views that host extension pages (background, popup), not ordinary tabs. [property](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.web-extension-mode.html), [enum](https://webkitgtk.org/reference/webkitgtk/stable/enum.WebExtensionMode.html)
- **`default-content-security-policy`** on `WebKitWebView` (since 2.38, **construct-only**). [property](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.default-content-security-policy.html)
- **`WebKitUserContentManager`**: user scripts, user style sheets, script message handlers and script worlds, which is how content scripts are injected without engine support. [index](https://webkitgtk.org/reference/webkitgtk/stable/index.html)
- **Web process extensions** (`webkitgtk-web-process-extension-6.0`): a shared library loaded into each web process, with access to pages, frames, the DOM, script worlds, request/response objects and user messages to and from the UI process. The directory and user data are set on the `WebKitWebContext`, in the `initialize-web-process-extensions` signal, which "is emitted when a new web process is about to be launched". [reference](https://webkitgtk.org/reference/webkitgtk-web-process-extension/stable/index.html), [signal](https://webkitgtk.org/reference/webkitgtk/stable/signal.WebContext.initialize-web-process-extensions.html). This is a stable native hook (since 2.4), has no WKWebView equivalent, and is not something end users install.

## What must be right at creation time

Both platforms freeze the important references when the view is constructed.

- macOS: "The web view incorporates your configuration settings only at creation time; you cannot change those settings dynamically later." [WKWebViewConfiguration](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration)
- WebKitGTK: `user-content-manager`, `network-session`, `web-context`, `web-extension-mode` and `default-content-security-policy` are all construct-only properties. [user-content-manager](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.user-content-manager.html), [network-session](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.network-session.html), [web-context](https://webkitgtk.org/reference/webkitgtk/stable/property.WebView.web-context.html)

The *contents* of those objects stay mutable: rule lists, filters and user scripts can be added to or removed from a content controller/manager after views exist. Only the object identity is fixed.

So the abstraction needs these, from the first line of code:

1. **A per-profile "web view environment" object that owns the creation-time handles**, and every web view is created from one. It must hold, at least:
   - the user content controller (`WKUserContentController` / `WebKitUserContentManager`). Content filtering needs this in v1 anyway. Never let a view be created with an implicit default one.
   - the data store (`WKWebsiteDataStore` / `WebKitNetworkSession`).
   - on Linux, the `WebKitWebContext` (needed later for web process extensions).
   - an opaque, initially empty **extension-controller slot**: on macOS 15.4+ this becomes `WKWebViewConfiguration.webExtensionController`.
2. **`webExtensionController` cannot be added to an existing WKWebView.** A tab's web view "must have its `webExtensionController` property set to match the controller of the given context; otherwise `nil` will be used... If `nil`, some critical features will not be available for this tab, such as content injection or modification." [WKWebExtensionTab.webView(for:)](https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview(for:)). Either set a controller (with no extensions loaded) on every view from day one when the OS supports it, or accept that enabling extensions later means recreating views. Whether an empty controller has a measurable cost was **not verified**.
3. **A tab must not be its web view.** Apple requires that extension pages load in a view built from the context's own configuration, and "The app must also swap web views in tabs when navigating to and from web extension URLs"; navigations in the wrong kind of view are cancelled. [WKWebExtensionContext.webViewConfiguration](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration). The GTK equivalent is that `web-extension-mode` is construct-only. Design the tab as a stable identity that owns a replaceable web view, with navigation able to trigger the swap. This is the single most expensive thing to retrofit.
4. **Private/ephemeral views need their own content controller and a non-persistent data store.** "web views associated with private data must use a different `WKUserContentController`... private web views must be configured to use a non-persistent `WKWebsiteDataStore`." [isPrivate(for:)](https://developer.apple.com/documentation/webkit/wkwebextensionwindow/isprivate(for:)). Do not share one content controller across everything.
5. **Scope the extension-controller slot per profile, not globally (inference).** A controller configuration has one `defaultWebsiteDataStore` for cookie access and an `identifier` for its own persistent storage, and Apple says "When using multiple extension controllers, each controller should use a unique configuration to avoid conflicts." [Configuration](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/configuration-swift.class), [default()](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/configuration-swift.class/default()). Coracle profiles each have their own data store, so one controller per profile is the natural fit. Extension storage is then machine-local state held by WebKit, outside the sync folder.
6. **Stable tab and window identities plus a complete event stream.** The extension API is driven by the host reporting opens, closes, activations, moves, replacements and property changes. If the core model emits these events and exposes pinned, muted, index, parent, URL, title and loading state per tab, adapting to `WKWebExtensionTab` later is a thin layer. Coracle has one extra decision to make then: how spaces and folders map onto the extension model's flat "windows containing ordered tabs".

## What can wait

- Everything about loading, installing, updating and showing UI for extensions (action buttons, popups, permission prompts, options pages, native messaging).
- The `WKWebExtensionTab` / `WKWebExtensionWindow` adapters themselves.
- Any Linux extension runtime. Revisit when a WebKitGTK release documents a way to attach a `WebKitWebExtensionContext` to a web view and the core namespaces lose `Platform=COCOA`.
- Web process extensions on Linux, as long as the `WebKitWebContext` is owned by the environment object so the signal can be connected later.
- For content filtering in v1: the filter-list to JSON converter, list updates, and per-site allow-listing are product work on top of a mechanism that is already identical on both platforms.

## Minimum versions

| Capability | Minimum |
|---|---|
| Content rule lists on macOS | macOS 10.13 |
| WebExtensions in WKWebView | macOS 15.4 |
| Content filters on Linux | WebKitGTK 2.24 |
| `web-extension-mode`, `default-content-security-policy` | WebKitGTK 2.38 |
| `WebKitNetworkSession`, API 6.0 (GTK4) | WebKitGTK 2.40 |
| `WebKitWebExtension` (manifest parsing only) | WebKitGTK 2.52, GTK4 API only, build flag off by default |
| Working WebExtension runtime on Linux | none released |

If Coracle's macOS floor is below 15.4, the extension slot must be optional at runtime.

## Not verified

- Which conditional namespaces (`bookmarks`, `notifications`, `offscreen`, `sidePanel`/`sidebarAction`, `devtools`) Apple's shipping macOS builds enable, and what changed between macOS 15.4 and the current release. The IDL read is `main`, which is ahead of any shipped OS.
- That `webRequest` on WebKit is non-blocking (memory).
- The newer content-blocker trigger/action keys beyond the original set (memory; Apple's "Creating a content blocker" page did not render).
- Whether distro WebKitGTK packages compile in `ENABLE_WK_WEB_EXTENSIONS`, and any upstream timeline or tracking bug for the GTK/WPE WebExtensions work. I found no roadmap.
- The cost of attaching an empty `WKWebExtensionController` to every web view.
- Real-world extension compatibility of `WKWebExtension` in a third-party browser (which popular extensions actually work). Nothing here was run.
- Current development status of Epiphany's implementation beyond its README and one forum post.
