# Running 1Password in a WKWebView browser

Research for [issue #22](https://github.com/mshafir/coracle/issues/22). Researched 2026-11-26. Builds on [native-extension-mechanisms.md](native-extension-mechanisms.md) (issue #4, on its own branch), which is not repeated here.

Every claim below carries one of these labels:

- **(documented)**: stated by a primary source read today, linked.
- **(observed)**: read today from a file on Michael's Mac or from the published extension package. Nothing was launched, signed in to or changed, and no 1Password data was read.
- **(precedent)**: read today in another browser's open source code. It shows what that browser had to do; it is not a vendor statement.
- **(forum)**: a forum post, quoted as such. Low trust unless the author is staff.
- **(inference)**: my reasoning from the above. Not a fact.
- **(memory)**: not backed by a source read today.

Nothing in this document was run. See [Only a hands-on test can settle](#only-a-hands-on-test-can-settle).

Versions examined: 1Password for Mac 8.12.46, 1Password browser extension 8.12.46.29 (Chrome Web Store and Firefox AMO packages, build date 2026-11-17), macOS 27.2.1, WebKit `main` on the day of reading.

## Short answer

1Password in v1 is feasible, and there is one realistic route: **load 1Password's Chrome Web Store extension through `WKWebExtension`, bridge its native messaging to the 1Password desktop app, and have Michael add Coracle under 1Password > Settings > Browser > Add Browser.** 1Password documents the "Add Browser" step for unsupported browsers, Kagi documents the same step for Orion, and DuckDuckGo's WKWebView browser merged this exact combination in October 2026 (behind a feature flag).

The cost is high. It is not "turn on the extension API":

- A real extension host: tab and window adapters, toolbar button and popup, extension pages in tabs, permission storage, install and update of a `.crx`.
- A native messaging bridge that runs 1Password's helper binary and speaks Chrome's stdio protocol.
- A compatibility layer for Chrome-only APIs that WebKit lacks. DuckDuckGo's is about 1,800 lines of injected JavaScript plus a manifest rewriter, and it was written for two extensions.
- macOS 15.4 as the floor for the feature, and a Developer ID signature on the app.

No route avoids the extension. Universal Autofill and macOS Password AutoFill are not established to work for web content in an unknown WKWebView browser, and neither saves logins or offers an inline menu. Passkeys come through the extension too, so Apple's passkey entitlement is not needed for 1Password.

## 1. Can the extension load through WKWebExtension?

### The manifest

The Chrome Web Store package (extension ID `aeblfdkhhhdcdjpifhhbdiojplfjncoa`) **(observed)**:

| Key | Value |
|---|---|
| `manifest_version` | 3 |
| `minimum_chrome_version` | 140 |
| `background` | `service_worker: background/background.js`, `type: module` |
| `action` | `default_popup: popup/index.html` |
| `permissions` | `alarms`, `contextMenus`, `downloads`, `idle`, `management`, `nativeMessaging`, `notifications`, `privacy`, `scripting`, `storage`, `tabs`, `webNavigation`, `webRequest`, `webRequestAuthProvider`, `declarativeNetRequestWithHostAccess` |
| `host_permissions` | `<all_urls>` |
| `content_scripts` | `<all_urls>`, all frames, `document_start`; two WebAuthn scripts on `https://*/*`, one of them in `"world": "MAIN"`; scripts for 1Password's own sites |
| `web_accessible_resources` | inline menu, notification, modal and sign-on pages (`inline/menu/menu.html` and others), matched on `<all_urls>` |
| `commands` | `_execute_action` (Cmd+Shift+X), `lock` (Cmd+Shift+L) |
| `declarative_net_request` | one static rule set: `modifyHeaders` on DNS-over-HTTPS requests |
| `storage.managed_schema` | `schema.json` |
| `content_security_policy.extension_pages` | `default-src 'none'`, `script-src 'self' 'wasm-unsafe-eval'`, a long `connect-src` list |

The Firefox AMO package is the same version but Manifest V2: `background.page`, `browser_action`, `webRequestBlocking`, `clipboardWrite`, gecko ID `{d634138d-c276-4fc8-924b-40a0ea21d284}`, minimum Firefox 140 **(observed)**.

The Safari version is a separate Mac App Store app, "1Password for Safari" ([App Store link on 1Password's download page](https://1password.com/downloads/browser-extension/)). It is not installed on this Mac, so its manifest was not read.

### Namespaces used, against WebKit

Namespaces were counted by searching the package's minified JavaScript for `chrome.x.y` and `browser.x.y` **(observed)**. Minified code can hide uses behind aliases, so treat the list as a lower bound. WebKit support is read from the interface files in WebKit `main` ([namespace IDL](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPINamespace.idl), per-API IDL files in the same directory, [permission names](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/Extensions/WebExtensionPermission.cpp)) **(documented, source)**. `main` is ahead of any shipped macOS.

| Namespace or permission | Used for (members seen) | In WebKit `main` |
|---|---|---|
| `runtime` | messaging, `getURL`, `connectNative`, `sendNativeMessage`, `onInstalled`, `setUninstallURL`, `reload` | Yes. Missing: `requestUpdateCheck`, `onSuspend`. |
| `tabs` | `create`, `query`, `update`, `remove`, `sendMessage`, `reload`, `captureVisibleTab`, `onUpdated`, `onRemoved`, `onActivated`, `onCreated` | Yes, all of these. |
| `windows` | `getCurrent`, `getAll`, `get`, `create`, `onFocusChanged`, `onCreated` | Yes. |
| `action` / `browserAction` | `setIcon`, `setPopup`, `openPopup`, `onClicked`, `getUserSettings` | Yes, except `getUserSettings`. |
| `scripting` | `executeScript`, `insertCSS` | Yes. |
| `storage` | `local`, `session`, `managed` | `local`, `session`, `sync`. No `managed`. |
| `alarms` | `create`, `get`, `clear`, `onAlarm` | Yes. |
| `webNavigation` | `getFrame`, `getAllFrames`, `onBeforeNavigate`, `onCommitted`, `onDOMContentLoaded`, `onCreatedNavigationTarget` | Yes, except `onCreatedNavigationTarget`. |
| `webRequest` | `onHeadersReceived`, `onBeforeRedirect`, `onAuthRequired` | All three names exist. Whether `onAuthRequired` can supply credentials is disputed, see below. |
| `contextMenus` | `create`, `update`, `removeAll`, `onClicked` | Yes. |
| `commands` | `getAll`, `onCommand`, `update` | Yes, except `update`. |
| `permissions` | `contains`, `addHostAccessRequest`, `removeHostAccessRequest` | `contains` yes. The host-access-request pair is absent. |
| `dom` | `openOrClosedShadowRoot` | Yes. |
| `declarativeNetRequest` | static rule set with `modifyHeaders` | Namespace and permission exist. Whether `modifyHeaders` on request headers works was not checked. |
| `notifications` | `create`, `update`, `clear`, `getAll`, click and close events | Behind a build conditional (`WK_WEB_EXTENSIONS_NOTIFICATIONS`). Not verified for shipping macOS. |
| `devtools` | `panels` | Behind a build conditional. Not needed for filling **(inference)**. |
| `nativeMessaging` permission | | Yes. |
| `privacy` | `services` (turning off the browser's own password saving) | **Absent.** |
| `idle` | `queryState`, `setDetectionInterval`, `onStateChanged` (auto-lock) | **Absent.** |
| `management` | `getSelf`, `getAll`, `setEnabled` | **Absent.** |
| `downloads` | `download`, `onChanged` | **Absent.** |
| `webRequestAuthProvider` permission | HTTP auth dialogs | Not a WebKit permission name. |
| content script `"world": "MAIN"` | WebAuthn interception | The `world` manifest key is parsed ([`WebExtension.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/WebExtension.cpp)). |

So the core of filling (content scripts, messaging, tabs, storage, scripting, popup, native messaging) is covered, and four whole namespaces plus several members are missing.

Does a missing namespace break it? **(precedent)** DuckDuckGo found that it does for a Chrome Manifest V3 package, and built three things to get 1Password and Bitwarden running on `WKWebExtension`:

- **A background rewrite.** "In WebKit, if that script throws while starting, for example because it calls a Chrome API WebKit doesn't have, the whole background is discarded and the extension doesn't work." They copy the extension, rewrite its manifest to load the same script from a generated background page, and load the copy. [`WebExtensionBackgroundPagePatcher.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/WebExtensions/Sources/WebExtensions/Loading/WebExtensionBackgroundPagePatcher.swift)
- **API stubs.** A script injected into extension pages that defines placeholders for missing `chrome.*` names, and real implementations of `chrome.idle`, `chrome.downloads.download`, `chrome.privacy` and `chrome.offscreen`, plus Chrome's enum constants and `storage.managed`. The file is 1,779 lines. [`WebExtensionAPIStubScript.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/WebExtensions/Sources/WebExtensions/Loading/WebExtensionAPIStubScript.swift)
- **A WebAssembly policy patch.** WebKit before macOS 26 ignores `'wasm-unsafe-eval'` in a Manifest V3 `extension_pages` policy, so they rewrite the policy. [`WebExtensionWasmPolicyPatch.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/WebExtensions/Sources/WebExtensions/Loading/WebExtensionWasmPolicyPatch.swift), citing [WebKit bug 290153](https://bugs.webkit.org/show_bug.cgi?id=290153) ("wasm-unsafe-eval not working for Safari Web Extension", resolved). 1Password's policy uses exactly that directive **(observed)**.

Known gap: HTTP authentication dialogs. A WKWebExtension browser, Zigzag, lists 1Password as unable to fill them because the native auth challenge is not bridged to `webRequest.onAuthRequired` ([issue](https://github.com/ZigaoWang/zigzag/issues/13)) **(precedent)**. DuckDuckGo's stub comment says the opposite, that "WebKit implements `webRequest.onAuthRequired` under `webRequest`". The sources conflict; the IDL confirms only that the event name exists.

The Firefox package already uses a background page, which would avoid the service-worker problem **(inference)**. Nobody was found doing this, its native host manifest is keyed by gecko ID rather than Chrome origin, and it may depend on Firefox-only behaviour. Untested.

**Confidence:** high that it can be made to load and work (a shipping WKWebView browser's merged code does it). High that it does not work unmodified.

### Native messaging

How WebKit routes it **(documented)**:

- `runtime.sendNativeMessage` calls the app's delegate method `webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:)`. "This method should be implemented by the app to handle one-off messages to applications. If not implemented, the default behavior is to pass the message to the app extension handler within the extension's bundle, if the extension was loaded from an app extension bundle; otherwise, no action is performed." [Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:sendmessage:toapplicationwithidentifier:for:replyhandler:))
- `runtime.connectNative` calls `webExtensionController(_:connectUsing:for:completionHandler:)` with a `WKWebExtension.MessagePort`. The app must keep the port: "Releasing the port will disconnect it." [Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:connectusing:for:completionhandler:))
- The host name the extension passed arrives as `applicationIdentifier`. "It's up to the app to decide how to interpret this identifier." [Apple](https://developer.apple.com/documentation/webkit/wkwebextension/messageport/applicationidentifier)
- The source matches: the delegate is called when implemented, and the fallback creates an `NSExtension` from the extension's own bundle. [`WebExtensionContextAPIRuntimeCocoa.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/Cocoa/API/WebExtensionContextAPIRuntimeCocoa.mm)

So WebKit routes native messages **to the host app**, not to a named native host. There is no built-in equivalent of Chrome's host manifests. The browser can forward them, and must write the forwarding itself.

What the browser forwards to **(observed)**: 1Password installs a Chrome-format host manifest named `com.1password.1password` into each browser's `NativeMessagingHosts` directory that it knows (Arc, Chrome channels, Edge channels, Vivaldi, Firefox on this Mac). It points at

`/Applications/1Password.app/Contents/Library/LoginItems/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport`

with `"type": "stdio"` and an `allowed_origins` list of six `chrome-extension://` origins that includes the Web Store ID above. The extension's code contains the host names `com.1password.1password` and `com.1password.1password7` **(observed)**.

What the forwarding involves **(precedent)**, from DuckDuckGo's implementation ([`NativeMessagingHandler.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/macOS/DuckDuckGo/WebExtensions/NativeMessaging/NativeMessagingHandler.swift), [`NativeMessagingHostSession.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/macOS/DuckDuckGo/WebExtensions/NativeMessaging/NativeMessagingHostSession.swift), [`NativeMessagingHostManifest.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/macOS/DuckDuckGo/WebExtensions/NativeMessaging/NativeMessagingHostManifest.swift), [`WebExtensionManager+NativeMessaging.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/WebExtensions/Sources/WebExtensions/Manager/WebExtensionManager+NativeMessaging.swift)):

- Find the host manifest by name. They look in their own directory first, then in other Chromium browsers' directories, "because a companion app writes one file per browser it knows and may not write one for us".
- Launch the manifest's `path` as a child process and pass the caller origin as its first argument. They pass the extension's **Chrome** origin (`chrome-extension://<id>/`), not WebKit's `webkit-extension://` one, and refuse the connection if the manifest's `allowed_origins` does not list it. They take the ID from the verified Web Store package.
- Carry Chrome's length-prefixed JSON over stdin and stdout.
- Accept the port immediately and queue early messages: "WebKit drops every message the extension posts before `completionHandler` is called."
- Keep the background page alive while a native port is open, because WebKit "unloads the page about 30 seconds after the last extension event" and the session lives only in that page.

**Confidence:** high on the routing (Apple's docs and WebKit source agree). Medium-high that forwarding to 1Password works from a third-party WKWebView app: the DuckDuckGo pull request's own test steps go through authorising the app in 1Password and completing sign-in, but I did not run it.

## 2. How the extension talks to the app, and what 1Password requires

**(documented)** [About the security of 1Password in your browser](https://support.1password.com/1password-browser-security/):

- "Native messaging ports allow 1Password to verify the connection between the app and extension. Before accepting a connection, the 1Password app verifies the extension ID and native messaging hosts file."
- "Code signature validation makes sure the browser is properly signed on macOS and Windows."

**(documented)** [Connect additional browsers to the 1Password app](https://support.1password.com/additional-browsers/) (published 2026-08-17):

- "By default, the 1Password browser extension will connect to the 1Password app in many common web browsers, including Chrome, Firefox, Edge, Brave, and Arc. If you want to connect the 1Password app to an unsupported browser, you can specify additional browsers on Mac, Windows, and Linux."
- On Mac: Settings > Browser > Add Browser, then "Choose a browser that's code signed by Apple in the Applications folder."
- "You must be able to install the 1Password browser extension from either the Chrome Web Store or Firefox extensions site."
- What connecting gives: unlocking the extension from the app "including unlocking with biometrics and system authentication", and having the app's accounts "automatically added to the 1Password browser extension".
- The warning: the added browser "will receive full access to the information saved in 1Password when the 1Password app is unlocked".

So there are two tiers, and no application or partnership process is documented:

1. **A built-in allow-list**, which Coracle is not on. The helper binary contains a fixed list of bundle identifiers (Chrome, Firefox, Edge, Brave, Vivaldi, Arc, Dia, Comet and their channels) beside code-requirement strings and Apple team IDs **(observed, from strings in `1Password-BrowserSupport`)**. Getting onto it would take 1Password's cooperation; no public process for that was found.
2. **A per-user "Add Browser" setting**, which is the route for Coracle. The helper has strings such as `validateBrowserProcess(pid:customBrowserIter:…)`, "browser was unsigned, rejecting it" and "requirements string from user settings was corrupt, skipping it" **(observed)**. My reading **(inference)**: the helper checks the code signature of the process that launched it against the built-in list and then against requirement strings saved by Add Browser. If so, the process that spawns the helper must be Coracle's signed main app, the app must be signed with an Apple-issued certificate (ad-hoc signing fails), and it must sit in `/Applications`. DuckDuckGo's test steps authorise a debug build at `/Applications/DEBUG/DuckDuckGo.app` **(precedent)**, so a subfolder is accepted there.

"Code signed by Apple" is 1Password's wording. Whether an Apple Development certificate is enough or Developer ID is required is not stated.

The extension has a failure path for this: its code contains a `BrowserVerificationFailed` notification type **(observed)**.

### Standalone, without the desktop app

The extension holds its own account sign-in. 1Password's security page says it "stores your Secret Key in local storage" ([source](https://support.1password.com/1password-browser-security/)), and its troubleshooting page treats the app connection as an optional setting, "Integrate this extension with the 1Password desktop app" ([source](https://support.1password.com/connect-1password-browser-app/)) **(documented)**. What is lost without the app, taken from the list of what connecting gives: unlock by Touch ID or system authentication, shared lock state with the app, and automatic account setup **(inference from the documented list)**. Filling, saving and passkeys are extension features and should remain **(inference)**.

This is the fallback if native messaging proves hard: it needs no bridge and no Add Browser step, at the price of typing the account password to unlock.

## 3. How other browsers got there

- **Orion (WebKit, own extension implementation).** Kagi: "1Password is now compatible with Orion thanks to the joint effort between 1Password and Orion teams." It needs the 1Password app 8.10.16 or later "since it allows browser whitelisting", and the user adds Orion at Settings > Browser > Add Browser and presses Authorize. [Kagi docs](https://help.kagi.com/orion/browser-extensions/1password.html) **(documented by Kagi)**. So Orion uses tier 2, the same route open to Coracle. Orion is not in the helper's built-in list **(observed)**.
  - History **(forum)**, from the [1Password community thread](https://www.1password.community/discussions/1password/support-for-orion-browser/75299): before 2023 the app refused Orion; a staff member said the company did not want the app to connect to arbitrary browsers; the Trusted Browsers setting arrived in a July 2023 nightly; staff later called Orion not an officially supported or tested browser; a staff reply in February 2024 said passkeys worked in Orion with the extension. These came from a search summary of the thread, not a full read.
- **DuckDuckGo for Mac (WKWebView, `WKWebExtension`).** [Pull request #7540](https://github.com/duckduckgo/apple-browsers/pull/7540), merged 2026-10-22, "Adds support for setting up and using the 1Password browser extension". Install from the Chrome Web Store, authorise the app in 1Password's Browser settings, sign in. It sits behind a `webExtensionOnePassword` feature flag; whether it has reached users was not checked **(precedent)**. This is the closest match to Coracle and the best evidence that the route works.
- **Arc, Dia, Vivaldi, Brave, Comet** are Chromium, run the Chrome extension natively, and are in the helper's built-in list **(observed)**. **Zen** is Firefox-based; it is not in the helper's list, but the extension package itself carries a small table naming Zen and OpenAI Codex with their team IDs **(observed)**. What that table does was not determined.
- **Other WKWebExtension adopters.** Several small open-source projects use the API (search results only, not read). Zigzag reports 1Password working apart from HTTP auth dialogs ([issue](https://github.com/ZigaoWang/zigzag/issues/13)).

Known broken or weaker, collected: HTTP auth dialogs (Zigzag); anything that needs `privacy`, `idle`, `management` or `downloads` unless the browser supplies it; WebAssembly before macOS 26 unless the policy is patched; background unloading that drops the native session unless the browser keeps the page alive.

## 4. Install source

**The Safari extension already on a Mac.** `WKWebExtension.init(appExtensionBundle:)` exists: "The app extension bundle must contain a `manifest.json` file in its resources directory." [Apple](https://developer.apple.com/documentation/webkit/wkwebextension/init(appextensionbundle:)) **(documented)**. And when the app does not implement the native messaging delegate, WebKit passes messages to "the app extension handler within the extension's bundle" **(documented, above)**. So the API has a path for loading an extension out of an app bundle, native handler included.

Whether that works for *another vendor's* app is not documented anywhere I found. Open points **(inference)**: the handler is 1Password's sandboxed code and may check who is hosting it; its app-group and keychain access are tied to 1Password's team; the Safari build of the JavaScript expects Safari; and "1Password for Safari" is a separate App Store install that Michael does not have. I would not plan on this route. It is testable in an afternoon if wanted.

**The Chrome or Firefox package.** This is what 1Password's own instructions for unsupported browsers assume ("install the 1Password browser extension from either the Chrome Web Store or Firefox extensions site") **(documented)**. `WKWebExtension.init(resourceBaseURL:)` takes a directory or a ZIP ([Apple](https://developer.apple.com/documentation/webkit/wkwebextension/init(resourcebaseurl:))) **(documented)**; a `.crx` is a ZIP with a signed header in front, so the browser strips and should verify the header **(inference; DuckDuckGo's installer has an `invalidSignature` error case, [source](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/WebExtensions/Sources/WebExtensions/ChromeWebStore/ChromeWebStoreCatalog.swift))**. The download endpoint DuckDuckGo uses is `clients2.google.com/service/update2/crx` **(precedent)**; the same endpoint returned the package for this research.

**Store terms.** The Chrome Web Store Terms of Service define products as "created for use in connection with Google Chrome", and say: "You agree not to access (or attempt to access) the Web Store by any means other than through the interface that is provided by Google... You specifically agree not to access (or attempt to access) the Web Store through any automated means". [User terms](https://ssl.gstatic.com/chrome/webstore/intl/en/gallery_tos.html), same clause in the [developer agreement](https://developer.chrome.com/docs/webstore/terms) **(documented)**. Read literally, a non-Chrome browser fetching `.crx` files is outside those terms. Orion, DuckDuckGo and others do it anyway; I found no statement from Google permitting or pursuing it. This is a legal judgement for Michael, not something research settles. Lower-risk variants **(inference)**: let the user download the file themselves and open it in Coracle, or load an unpacked folder. AMO's terms were not read.

The extension itself is 1Password's proprietary software; no licence text for redistributing it was looked for. Coracle should fetch it on the user's machine and never bundle it **(inference)**.

## 5. Routes without an extension

**Universal Autofill (Cmd+\\).** 1Password: it fills "in all your apps and websites", needs the Accessibility permission, and uses "the macOS accessibility APIs to view all running applications on your Mac so it can identify fields that can be filled". [Use Universal Autofill](https://support.1password.com/mac-universal-autofill/), [privacy settings](https://support.1password.com/mac-universal-autofill-settings/) **(documented)**. It fills user names and passwords only; the page mentions nothing about saving, generating, passkeys or cards.

Whether it matches the right login for a *website* inside an unknown browser is not documented. Evidence that it will not, without 1Password's help:

- 1Password's core library holds a fixed table of browser bundle IDs with team IDs (Safari, Chrome, Brave, Edge, Arc, Dia, Opera, Vivaldi, Comet, Orion as `com.kagi.kagimacOS`, DuckDuckGo, Firefox and a few more), next to the strings "A browser target was provided when the app is not a browser" and "No collected unparsed url" **(observed)**. My reading **(inference)**: only listed apps are treated as browsers whose page URL is read; any other app is matched as an app.
- A staff reply said Orion's bundle ID is on Universal Autofill's allow list and that an Orion build with a different bundle ID would not work, and another that Add Browser "doesn't yet extend to the autofill capabilities that originate from the desktop app (Quick Access/Command-\\)" **(forum, staff, 2023, via search summary)**.
- For an unknown app the documented behaviour is a prompt to "link your 1Password item to an app" **(documented)**, which would tie one login to Coracle as a whole **(inference)**.

So expect Universal Autofill to be unusable for websites in Coracle until 1Password adds Coracle's bundle ID. Quick Access (Shift+Cmd+Space) and copy-paste always work and are the floor.

**macOS Password AutoFill with a credential provider.** 1Password ships a credential provider extension that declares passwords, passkeys and one-time codes **(observed in its `Info.plist`)**, and documents it for "apps and websites in Safari" ([source](https://support.1password.com/macos-autofill/)). `ASCredentialProviderViewController` is available from macOS 11 ([Apple](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller)) **(documented)**.

For web content in a third-party app's WKWebView, the only Apple statement found is a forum answer from an Apple Frameworks Engineer (June 2026): "to get autofill working in web views, you need to set up an associated domain for your app", which lets AutoFill "surface existing credentials for a domain" ([thread](https://developer.apple.com/forums/thread/830314)) **(forum, Apple staff)**. Apple's Password AutoFill page says the same of apps in general: it "recommends credentials only for your app's associated domain" ([source](https://developer.apple.com/documentation/security/password-autofill)) **(documented, written about iOS)**. A browser cannot be associated with every website, so this is not a general route **(inference)**. No Apple source gives a macOS version at which WKWebView web content gets AutoFill; one user post claims "macOS 26 now autofills in web views" ([thread](https://developer.apple.com/forums/thread/130570)) **(forum, unverified)**.

**Confidence:** medium that neither route works for arbitrary sites in Coracle. Both are cheap to test.

## 6. Passkeys

**With the 1Password extension, no Apple entitlement is involved (inference from observed and documented facts).** The extension injects WebAuthn scripts into every HTTPS page, one in the page's main world **(observed)**, and 1Password documents saving and using passkeys through the browser extension ([source](https://support.1password.com/getting-started-browser/)). It answers `navigator.credentials` itself. A staff reply reported this working in Orion **(forum)**. So passkeys for Michael come with route 1.

**System passkeys (iCloud Keychain, security keys, and other providers through macOS)** need:

- `com.apple.developer.web-browser.public-key-credential`, macOS 13.3+: "An entitlement that lets your app make registration and assertion requests for passkeys and security keys for any relying party identifier." [Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential) **(documented)**
- How it is requested: "you must hold the Account Holder role for an organization's Apple Developer account and complete the request form... Apple reviews each application using predefined criteria." The criteria: the app declares the HTTP and HTTPS schemes in `Info.plist`; on launch it offers a URL field, search or bookmarks; it navigates directly to the destination and renders the expected content. (same page) **(documented)**. An Apple DTS engineer confirmed it "uses a dedicated request form, not the general entitlement request flow" ([thread](https://developer.apple.com/forums/thread/829169)) **(forum, Apple staff)**.
- The wording says *organization* account. A developer on an individual membership asked whether that is eligible and got no answer; their request was still pending a month on ([thread](https://developer.apple.com/forums/thread/852550)) **(forum)**.
- `com.apple.developer.web-browser` is documented for iOS and iPadOS only, as the default-browser entitlement ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser)) **(documented)**. On macOS it is not what unlocks passkeys.
- Third-party providers: `ASAuthorizationWebBrowserPublicKeyCredentialManager.platformCredentials(forRelyingParty:)` returns credentials "stored on the keychain, or managed by third-party credential managers" ([Apple](https://developer.apple.com/documentation/authenticationservices/asauthorizationwebbrowserpublickeycredentialmanager/platformcredentials(forrelyingparty:))) **(documented)**. So with the entitlement, 1Password's provider should be offered by the system too.
- Does WKWebView's own WebAuthn start working once the entitlement is present, with no extra code? Only a developer's report says so: without it, webauthn.io failed with `ASAuthorizationError` 1004; after Apple approved it, "the first tests look good" ([thread](https://developer.apple.com/forums/thread/774904)) **(forum)**. I could not find the entitlement check in WebKit's open source (the code search returned nothing), so this is unconfirmed.

For v1 this entitlement is not needed for 1Password. It matters for users who rely on iCloud Keychain passkeys, and the request should go in early because approval is slow and may need an organization account.

## 7. The minimum Coracle must build for 1Password

Needed, in rough build order:

1. **Extension controller on every web view**, one per profile, from creation time (already recommended by issue #4).
2. **Tab and window adapters** (`WKWebExtensionTab`, `WKWebExtensionWindow`) with the full event stream. The extension uses `tabs.query/create/update/remove/sendMessage`, tab and window events, and `windows.getCurrent/getAll/create` **(observed)**, so this cannot be a stub. `windows.create` and `tabs.create` matter: sign-in opens a 1Password web page in a tab.
3. **Extension pages in tabs**, with the web-view swap Apple requires. The welcome, settings and sign-in flows are extension pages **(observed: `app/app.html`; DuckDuckGo's test steps open "the extension's welcome page")**.
4. **Toolbar button and popup.** `presentActionPopup` in an `NSPopover`, plus icon updates (the extension changes its icon for locked and unlocked). The popup is where the account password is entered, so it is required even with the desktop app **(documented: "Only enter your 1Password account password in the 1Password pop-up")**.
5. **Content scripts and the inline menu.** WebKit does the injection. The inline menu is an iframe of a web-accessible extension page inside the site **(documented by 1Password, observed in the manifest)**, so nothing to build, but it must be tested in Coracle's view setup. DuckDuckGo needed a fix for calling `action.openPopup` from such an embedded page **(precedent)**.
6. **Permission handling.** For a single-user v1, granting the requested permissions and `<all_urls>` at install and persisting that is enough **(inference)**; the three `promptForPermission…` delegate methods can auto-grant for an extension the user explicitly installed. A real prompt UI can wait.
7. **Native messaging bridge** to `1Password-BrowserSupport`, as in section 1. Skippable only by accepting standalone mode.
8. **Chrome compatibility layer**: background rewrite, stubs for `privacy`, `idle`, `management`, `downloads`, `storage.managed` and the missing members, Wasm policy patch below macOS 26. Scope is unknown until tried; DuckDuckGo's is large but covers more than 1Password.
9. **Install and update.** Smallest version: the user points Coracle at a `.crx` or folder; Coracle unpacks, patches a copy and loads it. Updating can be manual at first ("reinstall"), but the extension and desktop app are released in step (both 8.12.46 today) and may refuse to pair across versions **(inference)**, so automatic update should follow soon.
10. **Keyboard commands** (`commands`): Cmd+Shift+X opens the popup, Cmd+Shift+L locks. Small.
11. **Developer ID signing** and installation in `/Applications`, for Add Browser.

Can wait: context menus, notifications, DevTools panel, options-page UI beyond opening a tab, HTTP auth dialog filling, extension management UI beyond one on/off, any store browsing.

### Minimum macOS version

`WKWebExtension` requires macOS 15.4 **(documented)**. Two ways to hold that:

- **Keep the 14.0 floor and make extensions conditional at runtime.** DuckDuckGo deploys to macOS 12.3 and gates extensions by availability **(precedent)**. Cost: every extension type is behind `if #available`, the controller slot is optional, and 1Password does not exist on 14.x.
- **Raise the floor to 15.4.** Cost: Coracle will not run on macOS 14 or on 15.0 to 15.3. Any Mac on 15.0 can update to 15.4 **(inference: point releases share hardware support)**; Macs that stopped at macOS 14 are excluded. Benefit: no availability branching, and one code path for the feature the owner depends on.

Michael's Mac runs macOS 27.2 **(observed)**. Since the browser is not viable for him without 1Password, and 1Password needs 15.4, raising the floor costs him nothing and removes a class of conditional code. A floor of macOS 26 would additionally remove the Wasm policy patch **(precedent, DuckDuckGo's comment)**; whether that is worth excluding macOS 15 is a product call.

## Only a hands-on test can settle

1. Whether 1Password's Add Browser accepts a Coracle build, and with which signature (Developer ID or Apple Development; ad-hoc is expected to fail).
2. Whether `1Password-BrowserSupport`, launched by Coracle with the Chrome origin as its argument, completes the handshake, and which process's signature it checks.
3. Whether 1Password writes a host manifest for an added browser, or Coracle must read the one in another browser's directory (absent if no Chromium browser is installed).
4. How much of DuckDuckGo's compatibility layer 1Password actually needs: does the unmodified package start at all on the target macOS; which missing APIs it trips on.
5. Which code path the extension takes under a WebKit user agent. It contains Safari-specific native messaging code (`sendNativeMessage("")` to a Safari app extension) and user-agent checks **(observed)**; a WKWebView's default user agent may push it down the Safari path. Coracle may need to present a Chrome-like user agent to extension pages.
6. Inline menu, save prompts, passkey creation and sign-in, and two-factor code filling, each on real sites.
7. Whether `notifications` and `declarativeNetRequest` header modification work on shipping macOS.
8. Whether the Firefox package is an easier fit than the Chrome one.
9. Whether Universal Autofill fills the right login for a site in Coracle, and whether macOS AutoFill offers anything in a Coracle web view (macOS 26 and 27).
10. Whether WKWebView's built-in WebAuthn works with only the passkey entitlement, and whether Apple grants that entitlement to an individual account.
11. Whether loading "1Password for Safari" from its app bundle works at all.

A two-day spike covers 1 to 6: a bare AppKit app with one window, one tab, a `WKWebExtensionController`, a toolbar button, and DuckDuckGo's Apache-2.0 sources as a reference.

## Not verified

- The Safari extension's manifest and bundle (not installed here).
- The 1Password community thread on Orion was read through search summaries, not in full; the staff quotations are indirect.
- Orion's changelog and its current list of 1Password problems.
- Whether DuckDuckGo's 1Password support is enabled for users or still flagged off.
- AMO's terms, and any Google statement on third-party browsers using the Web Store.
- Which conditional WebKit namespaces ship in macOS 15.4, 26 and 27.
- The meaning of the Zen and Codex table inside the extension.
- All readings of binary strings are of names and messages only; the logic they belong to was inferred, not disassembled.
