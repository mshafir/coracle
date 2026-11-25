// PROTOTYPE, throwaway. Coracle issue #10: interface toolkit, macOS candidate A (AppKit only).
// Hard-coded data, no persistence, no error handling. Never merged.
import AppKit
import WebKit

let rowH: CGFloat = 32, rowGap: CGFloat = 2

// MARK: - Data

final class Tab {
    var title: String
    let home: URL
    let tint: NSColor
    var webView: WKWebView?
    var observers: [NSKeyValueObservation] = []
    weak var row: RowView?
    init(_ title: String, _ url: String) {
        self.title = title
        home = URL(string: url)!
        let hue = CGFloat(url.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
        tint = NSColor(hue: hue, saturation: 0.55, brightness: 0.9, alpha: 1)
    }
}

enum Item { case tab(Tab), folder(String, [Tab]) }

final class Space {
    let name: String
    let colors: [NSColor]
    var pinned: [Item]
    var unpinned: [Tab]
    var selected: Tab?
    init(_ name: String, _ colors: [NSColor], pinned: [Item], unpinned: [Tab]) {
        self.name = name; self.colors = colors; self.pinned = pinned; self.unpinned = unpinned
    }
    var allTabs: [Tab] {
        pinned.flatMap { item -> [Tab] in
            switch item { case .tab(let t): return [t]; case .folder(_, let ts): return ts }
        } + unpinned
    }
}

func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
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
                    .folder("Reading", [Tab("backdrop-filter - MDN", "https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter"),
                                        Tab("GNOME", "https://www.gnome.org/"),
                                        Tab("Swift.org", "https://www.swift.org/")])],
           unpinned: [Tab("The Verge", "https://www.theverge.com/"),
                      Tab("BBC News", "https://www.bbc.com/news"),
                      Tab("WebKit on GitHub", "https://github.com/WebKit/WebKit"),
                      Tab("OpenStreetMap", "https://www.openstreetmap.org/")]),
     Space("Work", [rgb(0x0B486B), rgb(0x16A085)],
           pinned: [.tab(Tab("GTK", "https://www.gtk.org/")),
                    .folder("Docs", [Tab("WebKitGTK", "https://webkitgtk.org/"),
                                     Tab("Wayland", "https://wayland.freedesktop.org/")])],
           unpinned: [Tab("Rust", "https://www.rust-lang.org/"), Tab("KDL", "https://kdl.dev/")]),
     Space("Play", [rgb(0xF2994A), rgb(0xD9376E)],
           pinned: [.tab(Tab("Internet Archive", "https://archive.org/")),
                    .folder("Music", [Tab("Bandcamp", "https://bandcamp.com/")])],
           unpinned: [Tab("xkcd", "https://xkcd.com/")])]
}

// MARK: - Small views

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class GradientView: NSView {
    override func makeBackingLayer() -> CALayer {
        let g = CAGradientLayer()
        g.startPoint = CGPoint(x: 0, y: 1); g.endPoint = CGPoint(x: 1, y: 0)
        return g
    }
    func set(_ colors: [NSColor], animated: Bool) {
        let g = layer as! CAGradientLayer
        let new = colors.map(\.cgColor)
        if animated {
            let a = CABasicAnimation(keyPath: "colors")
            a.fromValue = g.presentation()?.colors ?? g.colors
            a.toValue = new; a.duration = 0.45
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(a, forKey: "colors")
        }
        g.colors = new
    }
}

final class Handle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with e: NSEvent) {}
    override func mouseDragged(with e: NSEvent) { onDrag?(e.locationInWindow.x) }
}

/// One sidebar entry: a tab row, a folder header, the new-tab row or a favorite tile.
final class RowView: NSView {
    let label = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onDrag: ((RowView, NSEvent) -> Void)?
    var selected = false { didSet { refresh() } }
    private var hovered = false { didSet { refresh() } }
    private var dragged = false

    init(title: String, tint: NSColor?, glyph: String? = nil, tile: Bool = false, indent: CGFloat = 0) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = tile ? 10 : 8
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: tile ? 44 : rowH).isActive = true

        badge.stringValue = glyph ?? String(title.prefix(1))
        badge.alignment = .center
        badge.font = .systemFont(ofSize: tile ? 15 : 11, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.backgroundColor = tint?.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        let side: CGFloat = tile ? 24 : 18
        NSLayoutConstraint.activate([badge.widthAnchor.constraint(equalToConstant: side),
                                     badge.heightAnchor.constraint(equalToConstant: side),
                                     badge.centerYAnchor.constraint(equalTo: centerYAnchor)])
        if tile {
            badge.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
            toolTip = title
        } else {
            label.stringValue = title
            label.font = .systemFont(ofSize: 13)
            label.textColor = NSColor(white: 1, alpha: 0.92)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(label)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8 + indent),
                label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        let base: CGFloat = layer?.cornerRadius == 10 ? 0.10 : 0
        layer?.backgroundColor = NSColor(white: 1, alpha: selected ? 0.26 : hovered ? 0.14 : base).cgColor
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent) { hovered = false }
    override func mouseDown(with e: NSEvent) { dragged = false }
    override func mouseDragged(with e: NSEvent) {
        guard let onDrag else { return }
        dragged = true
        alphaValue = 0.6
        onDrag(self, e)
    }
    override func mouseUp(with e: NSEvent) {
        alphaValue = 1
        if !dragged { onClick?() }
    }
}

// MARK: - One space's list (pinned, folder, divider, new tab, unpinned)

final class SpaceList: NSScrollView {
    let space: Space
    unowned let browser: Browser
    let outer = NSStackView()
    let unpinnedStack = NSStackView()
    var folderHeaders: [RowView] = []
    var newTab: RowView?

    init(space: Space, browser: Browser) {
        self.space = space; self.browser = browser
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        scrollerStyle = .overlay
        automaticallyAdjustsContentInsets = false
        translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        documentView = doc
        for s in [outer, unpinnedStack] {
            s.orientation = .vertical; s.spacing = rowGap; s.alignment = .leading
            s.translatesAutoresizingMaskIntoConstraints = false
        }
        doc.addSubview(outer)
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            outer.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8),
            outer.topAnchor.constraint(equalTo: doc.topAnchor),
            doc.bottomAnchor.constraint(equalTo: outer.bottomAnchor, constant: 8)])

        for item in space.pinned {
            switch item {
            case .tab(let t): add(row(for: t), to: outer)
            case .folder(let name, let tabs): addFolder(name, tabs)
            }
        }
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        add(divider, to: outer)
        outer.setCustomSpacing(8, after: outer.arrangedSubviews[outer.arrangedSubviews.count - 2])
        outer.setCustomSpacing(8, after: divider)

        let newTab = RowView(title: "New Tab", tint: NSColor(white: 1, alpha: 0.15), glyph: "+")
        newTab.onClick = { [unowned self] in
            let t = Tab("DuckDuckGo", "https://duckduckgo.com/")
            self.space.unpinned.insert(t, at: 0)
            self.unpinnedStack.insertArrangedSubview(self.reorderable(t), at: 0)
            t.row!.widthAnchor.constraint(equalTo: self.unpinnedStack.widthAnchor).isActive = true
            self.browser.select(t)
        }
        self.newTab = newTab
        add(newTab, to: outer)
        add(unpinnedStack, to: outer)
        for t in space.unpinned { add(reorderable(t), to: unpinnedStack) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func add(_ v: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func row(for t: Tab, indent: CGFloat = 0) -> RowView {
        let r = RowView(title: t.title, tint: t.tint, indent: indent)
        r.onClick = { [unowned self] in self.browser.select(t) }
        t.row = r
        return r
    }

    func reorderable(_ t: Tab) -> RowView {
        let r = row(for: t)
        r.onDrag = { [unowned self] row, e in self.drag(row, e) }
        return r
    }

    func addFolder(_ name: String, _ tabs: [Tab]) {
        let header = RowView(title: name, tint: nil, glyph: "▾")
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.clipsToBounds = true
        let inner = NSStackView()
        inner.orientation = .vertical; inner.spacing = rowGap; inner.alignment = .leading
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        let full = CGFloat(tabs.count) * (rowH + rowGap) - rowGap
        let height = box.heightAnchor.constraint(equalToConstant: full)
        NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                                     inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                                     inner.topAnchor.constraint(equalTo: box.topAnchor), height])
        for t in tabs { add(row(for: t, indent: 16), to: inner) }
        var open = true
        header.onClick = { [unowned self] in
            open.toggle()
            header.badge.stringValue = open ? "▾" : "▸"
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                height.constant = open ? full : 0
                box.alphaValue = open ? 1 : 0
                self.documentView?.layoutSubtreeIfNeeded()
            }
        }
        folderHeaders.append(header)
        add(header, to: outer)
        add(box, to: outer)
    }

    /// Live reorder: the dragged row jumps to the slot under the pointer, neighbours animate.
    func drag(_ row: RowView, _ e: NSEvent) {
        let p = unpinnedStack.convert(e.locationInWindow, from: nil)
        let fromTop = unpinnedStack.isFlipped ? p.y : unpinnedStack.bounds.height - p.y
        let rows = unpinnedStack.arrangedSubviews
        guard let from = rows.firstIndex(of: row) else { return }
        let to = max(0, min(rows.count - 1, Int(fromTop / (rowH + rowGap))))
        guard to != from else { return }
        space.unpinned.insert(space.unpinned.remove(at: from), at: to)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.allowsImplicitAnimation = true
            unpinnedStack.removeArrangedSubview(row)
            unpinnedStack.insertArrangedSubview(row, at: to)
            unpinnedStack.layoutSubtreeIfNeeded()
        }
    }

    func stress() {
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 1...200 {
            let t = Tab("Stress tab \(i)", "https://example.com/?tab=\(i)")
            space.unpinned.append(t)
            add(reorderable(t), to: unpinnedStack)
        }
        layoutSubtreeIfNeeded()
        print(String(format: "STRESS_BUILD_MS=%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))
    }
}

// MARK: - Window and behaviour

final class Browser: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let spaces = makeSpaces()
    let favorites = makeFavorites()
    var spaceIndex = 0
    var selected: Tab?
    var lists: [Int: SpaceList] = [:]
    var dots: [NSButton] = []
    var favTiles: [RowView] = []
    var translucent = true
    var collapsed = false
    var width: CGFloat = 260

    let gradient = GradientView()
    let sidebarClip = NSView(), sidebar = NSView(), listHost = NSView(), card = NSView()
    let handle = Handle()
    let address = NSTextField()
    let spaceName = NSTextField(labelWithString: "")
    var clipW: NSLayoutConstraint!, contentW: NSLayoutConstraint!

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        buildLayout()
        showSpace(0, animated: false)
        select(spaces[0].allTabs[0])
        if let n = Int(ProcessInfo.processInfo.environment["PROTO_LIVE_TABS"] ?? "") {
            for t in spaces[0].allTabs.prefix(n) { ensureWebView(t) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        CATransaction.flush()
        DispatchQueue.main.async { print(String(format: "FIRST_FRAME_MS=%.1f", msSinceProcessStart())) }
        runProtoActions { [unowned self] a in
            switch a {
            case "stress": self.stress()
            case "collapse": self.toggleSidebar()
            case "folder": self.lists[self.spaceIndex]?.folderHeaders.first?.onClick?()
            case "newtab": self.lists[self.spaceIndex]?.newTab?.onClick?()
            case "space0", "space1", "space2": self.showSpace(Int(a.suffix(1))!, animated: true)
            case "heavy": self.select(self.spaces[0].unpinned[0])
            default: break
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func buildLayout() {
        let root = NSView()
        window.contentView = root
        // Chrome background for the whole window: blur of what is behind the window, tinted by the space gradient.
        let blur = NSVisualEffectView()
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        gradient.wantsLayer = true
        gradient.alphaValue = 0.62
        for v in [blur, gradient] as [NSView] {
            v.frame = root.bounds; v.autoresizingMask = [.width, .height]; root.addSubview(v)
        }
        for v in [sidebarClip, handle, card] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v)
        }
        sidebarClip.clipsToBounds = true
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        clipW = sidebarClip.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([
            sidebarClip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarClip.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarClip.bottomAnchor.constraint(equalTo: root.bottomAnchor), clipW,
            handle.leadingAnchor.constraint(equalTo: sidebarClip.trailingAnchor),
            handle.widthAnchor.constraint(equalToConstant: 8),
            handle.topAnchor.constraint(equalTo: root.topAnchor),
            handle.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: handle.trailingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)])
        handle.onDrag = { [unowned self] x in
            guard !self.collapsed else { return }
            self.width = max(180, min(480, x))
            self.clipW.constant = self.width
            self.contentW.constant = self.width
        }

        // Sidebar content keeps its own width and is pinned to the clip's trailing edge, so collapsing slides it out.
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarClip.addSubview(sidebar)
        contentW = sidebar.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([sidebar.trailingAnchor.constraint(equalTo: sidebarClip.trailingAnchor),
                                     sidebar.topAnchor.constraint(equalTo: sidebarClip.topAnchor),
                                     sidebar.bottomAnchor.constraint(equalTo: sidebarClip.bottomAnchor), contentW])

        address.isBordered = false
        address.drawsBackground = false
        address.focusRingType = .none
        address.font = .systemFont(ofSize: 13)
        address.textColor = .white
        address.placeholderString = "Search or enter address"
        address.lineBreakMode = .byTruncatingTail
        address.cell?.usesSingleLineMode = true
        address.target = self
        address.action = #selector(go)
        let addressBox = NSView()
        addressBox.wantsLayer = true
        addressBox.layer?.cornerRadius = 8
        addressBox.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        address.translatesAutoresizingMaskIntoConstraints = false
        addressBox.addSubview(address)

        let favRow = NSStackView()
        favRow.distribution = .fillEqually
        favRow.spacing = 6
        for f in favorites {
            let tile = RowView(title: f.title, tint: f.tint, tile: true)
            tile.onClick = { [unowned self] in self.select(f) }
            f.row = tile
            favRow.addArrangedSubview(tile)
        }

        let switcher = NSStackView()
        switcher.spacing = 10
        for (i, s) in spaces.enumerated() {
            let b = NSButton(title: "", target: self, action: #selector(pickSpace(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 8
            b.layer?.backgroundColor = s.colors[1].cgColor
            b.layer?.borderColor = NSColor.white.cgColor
            b.toolTip = s.name
            b.widthAnchor.constraint(equalToConstant: 16).isActive = true
            b.heightAnchor.constraint(equalToConstant: 16).isActive = true
            dots.append(b)
            switcher.addArrangedSubview(b)
        }
        spaceName.font = .systemFont(ofSize: 11, weight: .semibold)
        spaceName.textColor = NSColor(white: 1, alpha: 0.7)
        listHost.wantsLayer = true
        listHost.layer?.masksToBounds = true

        for v in [addressBox, favRow, spaceName, listHost, switcher] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(v)
        }
        NSLayoutConstraint.activate([
            addressBox.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 38),
            addressBox.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressBox.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            addressBox.heightAnchor.constraint(equalToConstant: 32),
            address.leadingAnchor.constraint(equalTo: addressBox.leadingAnchor, constant: 8),
            address.trailingAnchor.constraint(equalTo: addressBox.trailingAnchor, constant: -8),
            address.centerYAnchor.constraint(equalTo: addressBox.centerYAnchor),
            favRow.topAnchor.constraint(equalTo: addressBox.bottomAnchor, constant: 8),
            favRow.leadingAnchor.constraint(equalTo: addressBox.leadingAnchor),
            favRow.trailingAnchor.constraint(equalTo: addressBox.trailingAnchor),
            spaceName.topAnchor.constraint(equalTo: favRow.bottomAnchor, constant: 12),
            spaceName.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            listHost.topAnchor.constraint(equalTo: spaceName.bottomAnchor, constant: 6),
            listHost.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            listHost.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            listHost.bottomAnchor.constraint(equalTo: switcher.topAnchor, constant: -8),
            switcher.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            switcher.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)])
    }

    // MARK: Spaces

    func list(_ i: Int) -> SpaceList {
        if let l = lists[i] { return l }
        let l = SpaceList(space: spaces[i], browser: self)
        l.isHidden = true
        listHost.addSubview(l)
        NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: listHost.leadingAnchor),
                                     l.trailingAnchor.constraint(equalTo: listHost.trailingAnchor),
                                     l.topAnchor.constraint(equalTo: listHost.topAnchor),
                                     l.bottomAnchor.constraint(equalTo: listHost.bottomAnchor)])
        lists[i] = l
        return l
    }

    func showSpace(_ i: Int, animated: Bool) {
        let old = spaceIndex
        let new = list(i)
        if animated && i != old {
            let push = CATransition()
            push.type = .push
            push.subtype = i > old ? .fromRight : .fromLeft
            push.duration = 0.32
            push.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            listHost.layer?.add(push, forKey: "space")
        }
        lists[old]?.isHidden = true
        new.isHidden = false
        spaceIndex = i
        gradient.set(spaces[i].colors, animated: animated)
        spaceName.stringValue = spaces[i].name.uppercased()
        for (n, d) in dots.enumerated() { d.layer?.borderWidth = n == i ? 2 : 0 }
        if animated, let t = spaces[i].selected ?? spaces[i].allTabs.first { select(t) }
    }

    @objc func pickSpace(_ sender: NSControl) { showSpace(sender.tag, animated: true) }

    // MARK: Tabs

    func ensureWebView(_ t: Tab) {
        guard t.webView == nil else { return }
        let w = WKWebView(frame: card.bounds, configuration: WKWebViewConfiguration())
        w.autoresizingMask = [.width, .height]
        w.isHidden = true
        card.addSubview(w)
        t.webView = w
        t.observers = [
            w.observe(\.title) { [weak t] w, _ in
                guard let t, let title = w.title, !title.isEmpty else { return }
                t.title = title
                t.row?.label.stringValue = title
            },
            w.observe(\.url) { [weak self, weak t] w, _ in
                if let self, let t, self.selected === t { self.address.stringValue = w.url?.absoluteString ?? "" }
            }]
        w.load(URLRequest(url: t.home))
    }

    func select(_ t: Tab) {
        selected?.row?.selected = false
        selected?.webView?.isHidden = true
        ensureWebView(t)
        selected = t
        if !favorites.contains(where: { $0 === t }) { spaces[spaceIndex].selected = t }
        t.row?.selected = true
        t.webView?.isHidden = false
        address.stringValue = t.webView?.url?.absoluteString ?? t.home.absoluteString
    }

    @objc func go() {
        var text = address.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") {
            text = text.contains(".") && !text.contains(" ") ? "https://" + text
                : "https://duckduckgo.com/?q=" + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        if let u = URL(string: text) { selected?.webView?.load(URLRequest(url: u)) }
        window.makeFirstResponder(selected?.webView)
    }

    // MARK: Commands

    @objc func toggleSidebar() {
        collapsed.toggle()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            clipW.constant = collapsed ? 0 : width
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
    @objc func focusAddress() { window.makeFirstResponder(address) }
    @objc func stress() { lists[spaceIndex]?.stress() }
    @objc func toggleTranslucency() {
        translucent.toggle()
        gradient.animator().alphaValue = translucent ? 0.62 : 1
    }

    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(), menu = NSMenu(title: title)
            build(menu); item.submenu = menu; main.addItem(item)
        }
        func item(_ m: NSMenu, _ title: String, _ sel: Selector, _ key: String, shift: Bool = false,
                  target: AnyObject? = nil, tag: Int = 0) {
            let i = m.addItem(withTitle: title, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            i.target = target; i.tag = tag
        }
        add("Coracle") { item($0, "Quit Coracle Prototype", #selector(NSApplication.terminate(_:)), "q") }
        add("Edit") {
            item($0, "Undo", Selector(("undo:")), "z"); item($0, "Redo", Selector(("redo:")), "z", shift: true)
            item($0, "Cut", #selector(NSText.cut(_:)), "x"); item($0, "Copy", #selector(NSText.copy(_:)), "c")
            item($0, "Paste", #selector(NSText.paste(_:)), "v"); item($0, "Select All", #selector(NSText.selectAll(_:)), "a")
        }
        add("View") {
            item($0, "Toggle Sidebar", #selector(toggleSidebar), "s", target: self)
            item($0, "Focus Address", #selector(focusAddress), "l", target: self)
            for (i, s) in spaces.enumerated() {
                item($0, "Space: \(s.name)", #selector(pickSpace(_:)), "\(i + 1)", target: self, tag: i)
            }
        }
        add("Debug") {
            item($0, "Fill Unpinned List With 200 Tabs", #selector(stress), "t", shift: true, target: self)
            item($0, "Toggle Translucency", #selector(toggleTranslucency), "o", shift: true, target: self)
        }
        NSApp.mainMenu = main
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

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
let browser = Browser()
app.delegate = browser
app.setActivationPolicy(.regular)
app.run()
