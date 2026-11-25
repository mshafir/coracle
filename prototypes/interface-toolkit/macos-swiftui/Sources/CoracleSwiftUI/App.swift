// PROTOTYPE, throwaway. Coracle issue #10: interface toolkit, macOS candidate B (SwiftUI hosting WKWebView).
// Hard-coded data, no persistence, no error handling. Never merged.
import SwiftUI
import WebKit

let rowH: CGFloat = 32, rowGap: CGFloat = 2

// MARK: - Data

@Observable final class Tab: Identifiable {
    let id = UUID()
    var title: String
    let home: URL
    let tint: Color
    @ObservationIgnored var webView: WKWebView?
    @ObservationIgnored var observers: [NSKeyValueObservation] = []
    init(_ title: String, _ url: String) {
        self.title = title
        home = URL(string: url)!
        let hue = Double(url.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
        tint = Color(hue: hue, saturation: 0.55, brightness: 0.9)
    }
}

struct Folder: Identifiable { let id = UUID(); let name: String; let tabs: [Tab] }

enum Item: Identifiable {
    case tab(Tab), folder(Folder)
    var id: UUID { switch self { case .tab(let t): return t.id; case .folder(let f): return f.id } }
}

@Observable final class Space: Identifiable {
    let id = UUID()
    let name: String
    let colors: [Color]
    var pinned: [Item]
    var unpinned: [Tab]
    var closedFolders: Set<UUID> = []
    @ObservationIgnored var selected: Tab?
    init(_ name: String, _ colors: [Color], pinned: [Item], unpinned: [Tab]) {
        self.name = name; self.colors = colors; self.pinned = pinned; self.unpinned = unpinned
    }
    var allTabs: [Tab] {
        pinned.flatMap { item -> [Tab] in
            switch item { case .tab(let t): return [t]; case .folder(let f): return f.tabs }
        } + unpinned
    }
}

func rgb(_ hex: Int) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}

func makeFavorites() -> [Tab] {
    [Tab("YouTube", "https://www.youtube.com/"), Tab("Wikipedia", "https://www.wikipedia.org/"),
     Tab("DuckDuckGo", "https://duckduckgo.com/"), Tab("Lobsters", "https://lobste.rs/")]
}

// The first space holds the ten measurement pages, in this order, in every candidate.
func makeSpaces() -> [Space] {
    [Space("Personal", [rgb(0x7B2FF7), rgb(0xF107A3)],
           pinned: [.tab(Tab("Coracle - Wikipedia", "https://en.wikipedia.org/wiki/Coracle")),
                    .tab(Tab("Hacker News", "https://news.ycombinator.com/")),
                    .tab(Tab("WebKit", "https://webkit.org/")),
                    .folder(Folder(name: "Reading", tabs: [
                        Tab("backdrop-filter - MDN", "https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter"),
                        Tab("GNOME", "https://www.gnome.org/"),
                        Tab("Swift.org", "https://www.swift.org/")]))],
           unpinned: [Tab("The Verge", "https://www.theverge.com/"),
                      Tab("BBC News", "https://www.bbc.com/news"),
                      Tab("WebKit on GitHub", "https://github.com/WebKit/WebKit"),
                      Tab("OpenStreetMap", "https://www.openstreetmap.org/")]),
     Space("Work", [rgb(0x0B486B), rgb(0x16A085)],
           pinned: [.tab(Tab("GTK", "https://www.gtk.org/")),
                    .folder(Folder(name: "Docs", tabs: [Tab("WebKitGTK", "https://webkitgtk.org/"),
                                                        Tab("Wayland", "https://wayland.freedesktop.org/")]))],
           unpinned: [Tab("Rust", "https://www.rust-lang.org/"), Tab("KDL", "https://kdl.dev/")]),
     Space("Play", [rgb(0xF2994A), rgb(0xD9376E)],
           pinned: [.tab(Tab("Internet Archive", "https://archive.org/")),
                    .folder(Folder(name: "Music", tabs: [Tab("Bandcamp", "https://bandcamp.com/")]))],
           unpinned: [Tab("xkcd", "https://xkcd.com/")])]
}

// MARK: - Model

@Observable final class Model {
    let spaces = makeSpaces()
    let favorites = makeFavorites()
    var spaceIndex = 0
    var pushFrom: Edge = .trailing
    var selected: Tab?
    var width: CGFloat = 260
    var collapsed = false
    var translucent = true
    var address = ""
    /// AppKit view that owns every live web view; SwiftUI only positions it.
    @ObservationIgnored let webHost: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        v.layer?.backgroundColor = NSColor.white.cgColor
        return v
    }()
    var space: Space { spaces[spaceIndex] }

    func ensureWebView(_ t: Tab) {
        guard t.webView == nil else { return }
        let w = WKWebView(frame: webHost.bounds, configuration: WKWebViewConfiguration())
        w.autoresizingMask = [.width, .height]
        w.isHidden = true
        webHost.addSubview(w)
        t.webView = w
        t.observers = [
            w.observe(\.title) { [weak t] w, _ in
                if let title = w.title, !title.isEmpty { t?.title = title }
            },
            w.observe(\.url) { [weak self, weak t] w, _ in
                if let self, let t, self.selected === t { self.address = w.url?.absoluteString ?? "" }
            }]
        w.load(URLRequest(url: t.home))
    }

    func select(_ t: Tab) {
        selected?.webView?.isHidden = true
        ensureWebView(t)
        selected = t
        if !favorites.contains(where: { $0 === t }) { space.selected = t }
        t.webView?.isHidden = false
        address = t.webView?.url?.absoluteString ?? t.home.absoluteString
    }

    func go() {
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") {
            text = text.contains(".") && !text.contains(" ") ? "https://" + text
                : "https://duckduckgo.com/?q=" + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        if let u = URL(string: text) { selected?.webView?.load(URLRequest(url: u)) }
    }

    func showSpace(_ i: Int) {
        guard i != spaceIndex else { return }
        pushFrom = i > spaceIndex ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.32)) { spaceIndex = i }
        if let t = space.selected ?? space.allTabs.first { select(t) }
    }

    func toggleSidebar() { withAnimation(.easeInOut(duration: 0.28)) { collapsed.toggle() } }

    func toggleFolder(_ f: Folder) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if space.closedFolders.contains(f.id) { space.closedFolders.remove(f.id) } else { space.closedFolders.insert(f.id) }
        }
    }

    func newTab() {
        let t = Tab("DuckDuckGo", "https://duckduckgo.com/")
        withAnimation(.easeInOut(duration: 0.2)) { space.unpinned.insert(t, at: 0) }
        select(t)
    }

    func stress() {
        let t0 = CFAbsoluteTimeGetCurrent()
        space.unpinned += (1...200).map { Tab("Stress tab \($0)", "https://example.com/?tab=\($0)") }
        // The list is lazy, so this is the cost of the model change plus the next layout pass, not of 200 rows.
        DispatchQueue.main.async { print(String(format: "STRESS_BUILD_MS=%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000)) }
    }

    func handle(_ a: String) {
        switch a {
        case "stress": stress()
        case "collapse": toggleSidebar()
        case "folder": if case .folder(let f)? = space.pinned.first(where: { if case .folder = $0 { return true } else { return false } }) { toggleFolder(f) }
        case "newtab": newTab()
        case "space0", "space1", "space2": showSpace(Int(a.suffix(1))!)
        case "heavy": select(spaces[0].unpinned[0])
        default: break
        }
    }
}

// MARK: - Views

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct WebHost: NSViewRepresentable {
    let host: NSView
    func makeNSView(context: Context) -> NSView { host }
    func updateNSView(_ v: NSView, context: Context) {}
}

struct Badge: View {
    let text: String, tint: Color, side: CGFloat
    var body: some View {
        Text(text).font(.system(size: side * 0.62, weight: .bold)).foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct Row: View {
    let title: String, glyph: String, tint: Color
    var indent: CGFloat = 0
    var selected = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Badge(text: glyph, tint: tint, side: 18)
            Text(title).font(.system(size: 13)).lineLimit(1).foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 0)
        }
        .padding(.leading, 8 + indent).padding(.trailing, 8)
        .frame(height: rowH)
        .background(.white.opacity(selected ? 0.26 : hover ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct TabRow: View {
    @Environment(Model.self) var model
    let tab: Tab
    var indent: CGFloat = 0
    var body: some View {
        Row(title: tab.title, glyph: String(tab.title.prefix(1)), tint: tab.tint, indent: indent, selected: model.selected === tab)
            .onTapGesture { model.select(tab) }
    }
}

struct Tile: View {
    @Environment(Model.self) var model
    let tab: Tab
    @State private var hover = false
    var body: some View {
        Badge(text: String(tab.title.prefix(1)), tint: tab.tint, side: 24)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(.white.opacity(model.selected === tab ? 0.26 : hover ? 0.14 : 0.10), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { model.select(tab) }
            .help(tab.title)
    }
}

struct SpaceList: View {
    @Environment(Model.self) var model
    let space: Space
    @State private var dragging: UUID?
    @State private var moved = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: rowGap) {
                ForEach(space.pinned) { item in
                    switch item {
                    case .tab(let t): TabRow(tab: t)
                    case .folder(let f): folder(f)
                    }
                }
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1).padding(.vertical, 6)
                Row(title: "New Tab", glyph: "+", tint: .white.opacity(0.15)).onTapGesture { model.newTab() }
                ForEach(space.unpinned) { t in
                    TabRow(tab: t)
                        .opacity(dragging == t.id ? 0.6 : 1)
                        .gesture(reorder(t))
                }
            }
            .padding(.trailing, 8).padding(.bottom, 8)
        }
    }

    @ViewBuilder func folder(_ f: Folder) -> some View {
        let open = !space.closedFolders.contains(f.id)
        Row(title: f.name, glyph: open ? "▾" : "▸", tint: .clear).onTapGesture { model.toggleFolder(f) }
        VStack(spacing: rowGap) {
            ForEach(f.tabs) { TabRow(tab: $0, indent: 16) }
        }
        .frame(height: open ? CGFloat(f.tabs.count) * (rowH + rowGap) - rowGap : 0, alignment: .top)
        .clipped()
        .opacity(open ? 1 : 0)
    }

    /// Live reorder: the dragged row jumps to the slot under the pointer, neighbours animate.
    func reorder(_ t: Tab) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                dragging = t.id
                let want = Int((v.translation.height / (rowH + rowGap)).rounded())
                guard want != moved, let from = space.unpinned.firstIndex(where: { $0 === t }) else { return }
                let to = max(0, min(space.unpinned.count - 1, from + want - moved))
                moved += to - from
                guard to != from else { return }
                withAnimation(.easeInOut(duration: 0.16)) { space.unpinned.insert(space.unpinned.remove(at: from), at: to) }
            }
            .onEnded { _ in dragging = nil; moved = 0 }
    }
}

struct Sidebar: View {
    @Environment(Model.self) var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search or enter address", text: $model.address)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(.white)
                .onSubmit { model.go() }
                .padding(.horizontal, 8).frame(height: 32)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 38)
            HStack(spacing: 6) { ForEach(model.favorites) { Tile(tab: $0) } }.padding(.top, 8)
            Text(model.space.name.uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 8).padding(.top, 12).padding(.bottom, 6)
            ZStack {
                SpaceList(space: model.space)
                    .id(model.space.id)
                    .transition(.push(from: model.pushFrom))
            }
            .clipped()
            .padding(.trailing, -8)
            HStack(spacing: 10) {
                ForEach(Array(model.spaces.enumerated()), id: \.offset) { i, s in
                    Circle().fill(s.colors[1]).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: i == model.spaceIndex ? 2 : 0))
                        .onTapGesture { model.showSpace(i) }
                        .help(s.name)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .padding(.leading, 8)
    }
}

struct RootView: View {
    @Environment(Model.self) var model
    var body: some View {
        ZStack {
            VisualEffect()
            LinearGradient(colors: model.space.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(model.translucent ? 0.62 : 1)
                .animation(.easeInOut(duration: 0.45), value: model.spaceIndex)
            HStack(spacing: 0) {
                // The sidebar keeps its width and is pinned to the trailing edge of a shrinking frame, so collapsing slides it out.
                Sidebar()
                    .frame(width: model.width)
                    .frame(width: model.collapsed ? 0 : model.width, alignment: .trailing)
                    .clipped()
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { v in
                        if !model.collapsed { model.width = max(180, min(480, v.location.x)) }
                    })
                WebHost(host: model.webHost).padding([.top, .bottom, .trailing], 8)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 600, minHeight: 400)
        .preferredColorScheme(.dark)
        .onAppear {
            model.select(model.spaces[0].allTabs[0])
            if let n = Int(ProcessInfo.processInfo.environment["PROTO_LIVE_TABS"] ?? "") {
                for t in model.spaces[0].allTabs.prefix(n) { model.ensureWebView(t) }
            }
            DispatchQueue.main.async { print(String(format: "FIRST_FRAME_MS=%.1f", msSinceProcessStart())) }
            runProtoActions { model.handle($0) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct CoraclePrototype: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = Model()
    init() { setvbuf(stdout, nil, _IOLBF, 0) }
    var body: some Scene {
        Window("Coracle SwiftUI prototype", id: "main") {
            RootView().environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandMenu("Go") {
                Button("Toggle Sidebar") { model.toggleSidebar() }.keyboardShortcut("s")
                ForEach(Array(model.spaces.enumerated()), id: \.offset) { i, s in
                    Button("Space: \(s.name)") { model.showSpace(i) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
            CommandMenu("Debug") {
                Button("Fill Unpinned List With 200 Tabs") { model.stress() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Toggle Translucency") { withAnimation { model.translucent.toggle() } }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

func msSinceProcessStart() -> Double {
    var kp = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &kp, &size, nil, 0)
    let start = kp.kp_proc.p_starttime
    var now = timeval()
    gettimeofday(&now, nil)
    return Double(now.tv_sec - start.tv_sec) * 1000 + Double(now.tv_usec - start.tv_usec) / 1000
}
