// PROTOTYPE, throwaway. Scripted actions and measurements shared verbatim by both Mac prototypes.
// PROTO_ACTIONS="stress,scroll,snap=/tmp/x.png,quit" runs steps in order, starting PROTO_ACTIONS_DELAY
// seconds after launch (default 4). Generic steps live here; the rest go to the app's handler.
import AppKit
import WebKit

// MARK: - Self-render for the README screenshot
// This machine's agent session has no Screen Recording permission, so the app draws itself:
// the view tree via cacheDisplay plus WKWebView.takeSnapshot pasted into the web view's frame.
// It is NOT a screen capture: behind-window blur is not captured (flat grey stands in for the
// desktop) and the web view's rounded corners are re-drawn here, not proof of real clipping.
func selfRender(to path: String) {
    guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
          let root = win.contentView?.superview ?? win.contentView,
          let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor(white: 0.25, alpha: 1).setFill()
    root.bounds.fill()
    NSGraphicsContext.restoreGraphicsState()
    root.cacheDisplay(in: root.bounds, to: rep)
    func find(_ v: NSView) -> WKWebView? {
        if let w = v as? WKWebView { return w.isHiddenOrHasHiddenAncestor ? nil : w }
        for s in v.subviews { if let w = find(s) { return w } }
        return nil
    }
    let write = {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT_WRITTEN \(path)")
    }
    guard let web = find(root) else { write(); return }
    web.takeSnapshot(with: nil) { image, _ in
        if let image {
            let r = web.convert(web.bounds, to: root)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
            image.draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
        }
        write()
    }
}


// MARK: - Main-thread frame pacing
// Drives something once per display-link tick for three seconds and records the gaps between ticks.
// A gap well over the display's frame time means the main thread missed a frame doing layout or drawing.
// It does not see frames dropped by the window server, and it is not a substitute for looking.
final class PacingBench: NSObject {
    static var current: PacingBench?
    let name: String, step: (Double) -> Void
    var link: CADisplayLink?, start = 0.0, last = 0.0, gaps: [Double] = [], frame = 0.0
    init(_ name: String, view: NSView, step: @escaping (Double) -> Void) {
        self.name = name; self.step = step
        super.init()
        PacingBench.current = self
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }
    @objc func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        if start == 0 { start = now } else { gaps.append((now - last) * 1000) }
        last = now
        frame = (l.targetTimestamp - l.timestamp) * 1000
        let t = (now - start) / 3
        if t >= 1 {
            l.invalidate()
            let s = gaps.sorted()
            let late = gaps.filter { $0 > frame * 1.5 }.count
            print(String(format: "PACING %@ frames=%d display_frame_ms=%.1f median_ms=%.1f p95_ms=%.1f max_ms=%.1f late=%d",
                         name, s.count, frame, s[s.count / 2], s[s.count * 95 / 100], s.last ?? 0, late))
            return
        }
        step(t < 0.5 ? t * 2 : (1 - t) * 2)   // 0 -> 1 -> 0
    }
}

func benchScroll() {
    guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
    var best: NSScrollView?
    func walk(_ v: NSView) {
        if let s = v as? NSScrollView, !(v is WKWebView), !s.isHiddenOrHasHiddenAncestor,
           (s.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) { best = s }
        if !(v is WKWebView) { v.subviews.forEach(walk) }
    }
    walk(root)
    guard let scroll = best, let doc = scroll.documentView else { print("PACING scroll: no scroll view"); return }
    let range = max(0, doc.frame.height - scroll.contentView.bounds.height)
    print(String(format: "SCROLL_RANGE_PT=%.0f", range))
    _ = PacingBench("scroll", view: scroll) { f in
        scroll.contentView.scroll(to: NSPoint(x: 0, y: range * f))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

func benchResize() {
    guard let win = NSApp.windows.first(where: { $0.isVisible }), let view = win.contentView else { return }
    let base = win.frame
    _ = PacingBench("resize", view: view) { f in
        win.setFrame(NSRect(x: base.minX, y: base.minY, width: base.width - 400 * f, height: base.height - 250 * f), display: true)
    }
}

func runProtoActions(_ handler: @escaping (String) -> Void) {
    let env = ProcessInfo.processInfo.environment
    var at = Double(env["PROTO_ACTIONS_DELAY"] ?? "") ?? 4
    let timed: Set = ["collapse", "folder", "space0", "space1", "space2"]
    for a in (env["PROTO_ACTIONS"] ?? "").split(separator: ",").map(String.init) {
        DispatchQueue.main.asyncAfter(deadline: .now() + at) {
            print("ACTION \(a)")
            if a == "scroll" { benchScroll() }
            else if a == "resize" { benchResize() }
            else if a == "quit" { exit(0) }
            else if a.hasPrefix("snap=") { selfRender(to: String(a.dropFirst(5))) }
            else {
                handler(a)
                // Animated steps: watch main-thread pacing while the animation runs.
                if timed.contains(a), let v = NSApp.windows.first(where: { $0.isVisible })?.contentView {
                    _ = PacingBench(a, view: v) { _ in }
                }
            }
        }
        at += (a == "scroll" || a == "resize" || timed.contains(a)) ? 4 : 1.2
    }
}
