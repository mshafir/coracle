# How Arc and Dia built their interface

Research for [issue #3](https://github.com/mshafir/coracle/issues/3). Researched 2026-11-25.

This note supplies facts for a later toolkit decision. It does not make that decision.

## Short answer

- The Browser Company (TBC) first built Arc's interface in web technology (React inside a forked Electron), found it "stuttery", and rewrote it in native Swift, using a mix of SwiftUI and AppKit over Chromium.
- For Dia they went further: they dropped SwiftUI and the TCA state library and now use AppKit only on Mac, because SwiftUI "consistently regressed performance".
- They never shared interface code across platforms. Arc on Windows used Swift with Microsoft's native WinUI 3 toolkit; only non-interface code was shared.
- I did not find one long TBC article arguing the case for native. Their reasoning is spread over a podcast, a letter and one social post. The long article the owner remembers may be OpenAI's piece on ChatGPT Atlas, which makes that argument at length.
- On Linux, WebKitGTK's web view is a GTK 4 widget, so GTK 4 (usually with libadwaita) is the toolkit the engine plugs into directly. Qt has no current WebKit route.
- No shipping Linux browser was found that combines a native toolkit interface, WebKit and an Arc-style sidebar. Kagi's attempt (Orion for Linux) was stopped in October 2026.

## How sources were read

Most pages were read through a fetch tool that summarises and returns short quotes. Two were downloaded and read directly: Josh Miller's post of 2025-05-27 and the Syntax podcast transcript. Quotes from those two are exact. Other quotes are short phrases returned by the tool and should be checked against the page before being relied on word for word.

## Arc on macOS

Source: Hursh Agrawal (TBC co-founder), Syntax podcast episode 514, 2022-09-23, [transcript](https://syntax.fm/show/514/supper-club-arc-browser-with-hursh-agrawal/transcript), about 10:47 to 13:40.

- **Why not work inside Chromium's own interface code.** Chromium is a very large C++ codebase. He cites a clean build of "about 4 and a half hours" and incremental builds of three to four minutes: "you, like, change a margin, and then you wait 3 minutes to see how it updated the UI." He also says many "craft focused engineers" do not know C++.
- **First attempt was web technology.** "the 1st year, we actually took electron, and we Forked Electron and built it into a browser and then built all of the UI with JavaScript." The first prototype shipped about eight months in, with the interface in React.
- **Why they left it.** "quickly realized it just wasn't, performing enough. JavaScript is single threaded, and that single thread keeps getting blocked, especially when you're loading web pages, and the UI is kinda stuttery. Brave and Firefox have pulled it off, but it felt like this constant uphill battle for us."
- **What replaced it.** "Built a similar Electron out of Swift." Asked whether the interface elements are now Swift: "They're all Swift. A lot of them are SwiftUI. Others use AppKit. And so, it's all native Swift." Web contents and extensions hook into Chromium underneath.

Later, TBC named this layer: "Arc isn't just a Chromium fork. It runs on custom infrastructure we call ADK — the Arc Development Kit", and "ADK is also the foundation of Dia." Source: [Letter to Arc members 2025](https://browsercompany.substack.com/p/letter-to-arc-members-2025), 2025-05-26.

Arc also used an early, customised branch of The Composable Architecture (TCA), a state library that works by comparing old and new state. Source: the letter above names TCA; the detail about the early branch comes from a TCA author's post as summarised by [Fatbobman's Swift Weekly 086](https://fatbobman.com/en/weekly/issue-086/) (secondary).

## Arc on Windows

- TBC built Arc for Windows in Swift, not by rewriting in C++ or wrapping a web interface. They published a blog series, [Speaking in Swift](https://speakinginswift.substack.com/archive), about the work.
- The interface used Microsoft's own toolkit: "WinUI 3 is the native UI framework of choice on Windows" and it "is what we are using to build Arc on Windows." Source: [Swift, meet WinRT](https://speakinginswift.substack.com/p/swift-meet-winrt), 2023-10-30. They open-sourced the binding generator, [swift-winrt](https://github.com/thebrowsercompany/swift-winrt), which was still receiving commits in November 2026.
- [Interoperability: Swift's Super Power](https://speakinginswift.substack.com/p/interoperability-swifts-super-power), 2023-09-20, by Saleem Abdulrasool, covers calling C, C++ and COM from Swift. It calls Swift "a great alternative to C and C++ with its improved memory safety and ergonomics". It does not compare native with web interfaces.
- The interface was not shared across platforms. Hursh Agrawal clarified in 2023 that they were building a declarative toolkit for WinUI in Swift, not a cross-platform one, so each platform has its own interface layer and shares the rest. Source: [iOS Dev Weekly 609](https://iosdevweekly.com/issues/609) reporting his [post](https://twitter.com/hursh/status/1653427830330368001) (secondary; the post itself was not read).
- The posts in this series are about language tooling. None of them argues why native beats web for smoothness.

## Dia

Source for the three points below: Josh Miller (TBC chief executive), [post of 2025-05-27](https://x.com/joshm/status/1927466374781079799), read in full.

1. "We use a modified version of MVVM that retains many ideas from unidirectional data flow architectures, but avoids state diffing for performance reasons."
2. "This new architecture is optimized for cross-platform code sharing, making it easier to port Dia to Windows."
3. "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance. Don't @ us, just what we learned!"

He adds: "Dia feels super snappy thanks to their hard work and bold call."

The letter of 2025-05-26 says the same more briefly: "Arc was bloated", "we started fresh from an architecture perspective and prioritized performance from the start", "sunsetting our use of TCA and SwiftUI to make Dia lightweight, snappy, and responsive." It also says some of Arc's shortcomings "were too large to tackle retroactively".

Other facts:

- Dia for Windows 1.0 shipped on 2026-10-06, per the [Dia release log](https://www.diabrowser.com/changelog). Dia later gained sidebar tabs and Arc-style pinned tabs (same source).
- Arc is being shut down on 2026-12-22, per the notice on [arc.net](https://arc.net/).
- Dia's design lead wrote about its design in [The strategy behind Dia's design](https://browsercompany.substack.com/p/the-strategy-behind-dias-design), 2025-06-17. It covers familiarity and where animation is spent ("We fluidly animate the most commonly used UI"). It says nothing about implementation.

## What TBC said made it smooth

Taken together, their published statements give these causes:

- **The interface does not share a thread with page loading.** This was the stated reason for leaving the web-technology interface.
- **Fast interface iteration.** Keeping interface work out of the Chromium build let designers and engineers adjust details in seconds, not minutes.
- **The older, lower-level native toolkit.** On Mac, AppKit beat SwiftUI for them. "Native" alone was not enough; Arc was fully native and they still called it bloated.
- **No state diffing.** They name avoiding it as a performance choice in Dia.
- **Performance treated as a starting requirement.** They say it could not be added to Arc afterwards.

They published no measurements. All of these are statements of experience, not benchmarks.

## The "extensive article"

I could not find a single long TBC article on the native decision. The closest TBC sources are the ones above. Two related TBC videos exist but were not watched or transcribed: Hursh Agrawal's 2023 announcement of Swift on Windows (linked from iOS Dev Weekly 609) and [How we're building the Arc Windows app with Swift](https://www.youtube.com/watch?v=Xa_fNuaSE_I).

A long article that does make this argument is OpenAI's [How we built OWL, the new architecture behind our ChatGPT Atlas browser](https://openai.com/index/building-chatgpt-atlas), 2025-10-30. It is not from TBC. Its points:

- The interface is a full native rebuild in "SwiftUI, AppKit and Metal", chosen for animation and visual effects over "simply reskinning the open source Chromium UX".
- Chromium runs in a separate process from the app. The app shows its window without waiting for Chromium, and "If its main thread hangs, Atlas doesn't."
- Most engineers never build Chromium, so app builds take minutes.

Whether this is the article the owner means is a guess.

## What this implies for Coracle

Facts that bear on the later decision:

- **The owner's belief has support, with a caveat.** TBC did abandon a web-technology interface for smoothness. But their later lesson was that the choice of native toolkit matters too: the newer declarative one (SwiftUI) was the problem on Mac.
- **TBC's model is one interface per platform over a shared core.** That is the same shape as "AppKit on macOS, something else on Linux". Their Swift interface code would not have carried to Linux even in principle, since it targeted AppKit, SwiftUI and WinUI.
- **A shipping app already uses this shape on macOS and Linux.** Ghostty (a terminal, not a browser) has a shared core library, a macOS interface "written in Swift" using "AppKit and SwiftUI", and a Linux interface using "the GTK4 C API". Its docs say "GTK4 is the closest thing to a standard GUI toolkit that exists" on Linux. Source: [About Ghostty](https://ghostty.org/docs/about).
- **Coracle's engine changes part of the picture.** TBC's stutter came from running the interface in the same JavaScript thread as browser work inside Electron. Coracle uses the system WebKit, which TBC did not, so their experience is evidence about interface toolkits, not about WebKit embedding.

## Native options on Linux

- **GTK 4 with libadwaita.** WebKitGTK's current API (6.0) targets GTK 4, and its `WebKitWebView` is a `GtkWidget`. Sources: [WebKitGTK reference](https://webkitgtk.org/reference/webkitgtk/stable/index.html), [WebView class](https://webkitgtk.org/reference/webkitgtk/stable/class.WebView.html). libadwaita ships ready-made split views, a sidebar, a tab bar and a tab overview. Source: [libadwaita widget gallery](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/widget-gallery.html).
- **Qt.** Qt's web component is Chromium: "The Qt WebEngine core is based on the Chromium Project" ([Qt WebEngine overview](https://doc.qt.io/qt-6/qtwebengine-overview.html)). Qt WebView uses the system web view on macOS, but "On Linux, Qt WebView depends on the Qt WebEngine module" ([Qt WebView](https://doc.qt.io/qt-6/qtwebview-index.html)). So Qt gives no supported way to host WebKitGTK. From memory, not checked: the old QtWebKit module was removed from Qt years ago.
- **Swift on Linux with GTK bindings.** [Adwaita for Swift](https://codeberg.org/aparoksha/adwaita-swift) is a SwiftUI-like layer over libadwaita; its last commit was 2026-10-03 and its page says some widgets may be missing. [swift-cross-ui](https://github.com/stackotter/swift-cross-ui) is a cross-platform SwiftUI-like framework, active in November 2026. I found no browser shipped on either. Both are declarative, diffing-style layers, the kind TBC moved away from on Mac; whether that matters on GTK is not established.
- **Another language calling GTK 4 directly.** Ghostty does this from Zig. GNOME Web does it from C.

## Linux browsers and how they feel

- **GNOME Web (Epiphany).** GTK 4, libadwaita and WebKitGTK, per its [build file](https://github.com/GNOME/epiphany/blob/main/meson.build) (GTK 4.21+, libadwaita 1.8+, WebKitGTK 2.53.90+). Version 51.1 was released 2026-09-24 ([GNOME apps page](https://apps.gnome.org/Epiphany/)). It proves the stack ships. It is a conventional top-tab browser; I did not check whether it has any sidebar tab mode.
- **Orion for Linux (Kagi).** A native GTK 4 and libadwaita interface on WebKitGTK, reaching beta 0.4.3 in September 2026 ([OMG! Ubuntu](https://www.omgubuntu.co.uk/2026/09/orion-browser-linux-043-update), secondary). Kagi ended development on 2026-10-02 and said it would release the source: "Rather than spread a small team across three platforms, we're putting our energy where we can do our best work." Source: [Kagi blog](https://blog.kagi.com/update-orion-linux-windows). The stated reason is team size, not the toolkit or engine. The source release was promised within 30 days; I did not confirm whether it has happened.
- **Zen Browser.** The Arc-like browser most used on Linux. It is a Firefox fork, so its interface is Firefox's own web-technology front end (the [repository](https://github.com/zen-browser/desktop) is mostly C++, JavaScript and CSS), not GTK widgets. It is active (commits on 2026-11-25). Hursh Agrawal's 2022 remark that "Brave and Firefox have pulled it off" is about this kind of interface.
- **Comparable feel.** I found no primary source that measures or compares the smoothness of any Linux browser with Arc. This remains a matter of judgement that a prototype would have to settle.

## Could not verify

- The two TBC videos were not transcribed, so any reasoning given only there is missing.
- A figure that Arc for Windows shared about 80% of its code with the Mac version appears only in press coverage (Windows Central). No TBC source was found.
- What interface toolkit Dia for Windows uses. Josh Miller's post says the architecture was built for sharing code with Windows but does not name the toolkit.
- A third-party teardown of Dia's Mac app bundle (everettjf, January 2026) now returns "page not found" and was not used.
- TBC's quotes from the letter and the Speaking in Swift posts came through a summarising tool; see "How sources were read".
- Whether Kagi has published the Orion for Linux source.
- Whether GNOME Web offers vertical tabs.
