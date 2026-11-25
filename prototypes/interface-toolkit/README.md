# Interface toolkit prototypes (issue #10)

**Throwaway.** Three rough builds of the same sidebar, made to help answer
[issue #10](https://github.com/mshafir/coracle/issues/10): which toolkit draws Coracle's
interface on macOS and on Linux, and can Linux reach the Arc-like feel. This branch is never
merged. Nothing here is product code, and nothing here decides the ticket.

| Folder | Candidate |
| --- | --- |
| `macos-appkit/` | macOS A: AppKit only (Swift), WKWebView |
| `macos-swiftui/` | macOS B: SwiftUI (Swift) hosting WKWebView |
| `linux-gtk4/` | Linux: GTK 4 + libadwaita + WebKitGTK 6.0, written in C |

The Linux prototype is in C only because that was the quickest way to a running window. The
core language is a separate, later ticket and is not being chosen here.

Each prototype is one window: a sidebar over a space-coloured gradient, a favorites row, pinned
tabs with one folder, a divider, a new-tab row and a flat list of unpinned tabs, three spaces,
an address field, and one live web view per tab in a rounded, inset card. Data is hard-coded and
identical in all three. Nothing is saved.

## Run them

macOS (needs Xcode's Swift toolchain, macOS 14 or newer):

```sh
cd prototypes/interface-toolkit/macos-appkit  && swift run -c release
cd prototypes/interface-toolkit/macos-swiftui && swift run -c release
```

Linux, on real hardware (this is the one that still needs a human, see below):

```sh
# Ubuntu 24.04 or newer / Debian 13
sudo apt install build-essential pkg-config libgtk-4-dev libadwaita-1-dev libwebkitgtk-6.0-dev
# Fedora
sudo dnf install gcc make pkgconf-pkg-config gtk4-devel libadwaita-devel webkitgtk6.0-devel

cd prototypes/interface-toolkit/linux-gtk4 && make run
```

Both package lists were checked by compiling in a container: Ubuntu 24.04 (GTK 4.14.5,
libadwaita 1.5.0, WebKitGTK 2.52.6) and Fedora 45 (GTK 4.24.1, libadwaita 1.10.0, WebKitGTK
2.54.2). The source needs GTK 4.12 or newer.

Headless smoke test from a Mac with Docker (build, start, screenshot, memory; no feel):

```sh
cd prototypes/interface-toolkit/linux-gtk4 && SHOT=linux-gtk4-headless.png ./docker-smoke.sh
```

### Keys

| Action | macOS | Linux |
| --- | --- | --- |
| Collapse or show the sidebar | Cmd+S | Ctrl+S |
| Switch space | Cmd+1, 2, 3 or the dots at the bottom | Ctrl+1, 2, 3 or the dots |
| Focus the address field | Cmd+L (AppKit only) | Ctrl+L |
| **Stress: add 200 unpinned tabs** (rows only) | Cmd+Shift+T | Ctrl+Shift+T |
| Toggle translucency | Cmd+Shift+O | Ctrl+Shift+O |

Drag the 8 px gap between sidebar and page to resize. Drag an unpinned row to reorder. Click the
folder row to expand or collapse it.

### Scripted steps

Every prototype reads two environment variables, used for the numbers below:

- `PROTO_LIVE_TABS=10` loads the first ten tabs of the first space at launch.
- `PROTO_ACTIONS="stress,scroll,heavy,resize,collapse,quit"` runs steps in order, starting 4 s
  after launch. Steps: `stress`, `scroll`, `resize`, `collapse`, `folder`, `space0`..`space2`,
  `heavy` (select The Verge), `newtab`, `quit`; `snap=/path.png` on macOS; `opaque` on Linux.
  `scroll`, `resize` and the animated steps print a `PACING` line (see below).

`./measure-macos.sh macos-appkit` (or `macos-swiftui`) reproduces all the Mac numbers.

## Comparison

Mac numbers: this machine, Apple M6, 32 GB, macOS 27.2.1, release builds, a 50 Hz display,
nobody at the keyboard. Linux numbers: an Ubuntu 24.04 arm64 container on the same machine, on
a headless X server with software rendering. **The Linux column is not comparable to the Mac
columns** and says nothing about a real desktop; it is there to show the prototype runs.

| | macOS A: AppKit | macOS B: SwiftUI | Linux: GTK 4 (container) |
| --- | --- | --- | --- |
| Builds and launches | yes, run here | yes, run here | yes, compiled and run headless here |
| Lines of code, prototype | 654 | 423 | 560 (C, of which about 45 are CSS) |
| Lines of code, measurement harness | 127 (shared file) | 127 (same file) | about 90, inside the 560 |
| Effort (agent wall-clock, see note) | about 10 min | about 4 min | about 6 min |
| Launch to first frame, 5 runs | 216 to 285 ms, median 230 | 164 to 244 ms, median 215 | 561 ms first, then 133 to 148 ms |
| Memory, 1 live tab: resident / footprint | 256 / 148 MB | 269 / 196 MB | 442 MB resident, 424 MB proportional |
| Memory, 10 live tabs: resident / footprint | 1831 / 1580 MB | 2057 / 1378 MB | 2317 MB resident, 2274 MB proportional |
| Of that, the app's own process (1 tab, 10 tabs) | footprint 30, 37 MB | footprint 32, 41 MB | resident 216, 263 MB |
| Building 200 rows | 64 to 72 ms (200 real views) | 5 to 20 ms (lazy, only visible rows built) | 2.5 ms (widgets only, layout comes after) |
| Main-thread pacing, scripted scroll of 200 rows | 5 runs, no late frame, max gap 20.0 ms | 2 runs: one clean, one with a single 156 ms gap | not meaningful in software rendering |
| Main-thread pacing, window resize while The Verge loads | 4 runs, no late frame, max 21.3 ms | 2 runs, 1 late frame each, max 30.7 ms | not meaningful |
| Main-thread pacing, collapse / folder / space switch | no late frame | one 40 ms gap in one space switch, otherwise none | not meaningful |
| Translucency | blur of the desktop behind the window, tinted by the gradient | same view, wrapped | none available: see-through chrome only, no blur |
| Rounded web view corners | layer corner radius on the container | same, done in AppKit not SwiftUI | CSS radius plus overflow clipping; seen working in the headless screenshot |
| Feel (smoothness, hitches, look of the blur) | **not observed** | **not observed** | **not observed, cannot be here** |

### How each number was measured

- **Lines of code**: `wc -l` on the source files, comments and blank lines included.
- **Effort**: wall-clock time I (an AI agent) spent writing and fixing each one, from command
  timestamps. It is not a human estimate. AppKit was written first, so it also paid for the
  design of the data, layout and harness that the other two reused; the order flatters them.
- **Launch to first frame**: each prototype prints the time from process start (kernel process
  start time; 10 ms resolution on Linux) to the first main-loop turn after the window was put
  on screen and its first layout and draw were committed (GTK: the first frame-clock
  `after-paint`). The page has not loaded at that point. Runs were back to back, so these are
  warm launches; I could not flush the disk cache, so there is no true cold number. The first
  run after a rebuild was 349 ms for AppKit and 561 ms for GTK, which is the nearest thing.
- **Memory**: taken 45 s after launch with `PROTO_LIVE_TABS` set to 1 and to 10, same ten pages
  in the same order (Wikipedia, Hacker News, webkit.org, MDN, gnome.org, swift.org, The Verge,
  BBC News, GitHub, OpenStreetMap). macOS: `mem-macos.py` sums the app and its WebKit helper
  processes; "resident" is `ps` rss, "footprint" is the `footprint` tool's figure, the one
  Activity Monitor shows. Linux: `Rss` and `Pss` from `/proc/<pid>/smaps_rollup` summed over the
  app and its WebKit processes. One sample each. Live pages vary by tens of megabytes from run
  to run (ads, video), so differences between the two Mac columns are noise, not toolkit cost.
  The row for the app's own process is the part the toolkit is responsible for.
- **Main-thread pacing**: a display-link (macOS) or frame-clock (GTK) callback does one step of
  work per display frame for three seconds and records the gaps between callbacks. A "late
  frame" is a gap over 1.5 display frames. On macOS both prototypes drive the same underlying
  `NSScrollView` and the same window resize. This catches the main thread missing a frame. It
  does not see what the window server actually presented, and it is not what a trackpad scroll
  feels like. Use it as a tripwire, not as a verdict.

### What fought me

**AppKit**
- Nothing refused to work. The cost is volume: every view, constraint and hover state is
  written by hand, which is most of the 230 extra lines over SwiftUI.
- The list is 200 real views in a stack view with no reuse. It built in about 70 ms and the
  scripted scroll stayed on pace, but a shipped list would want view reuse.
- With a mouse attached the scroll view shows a permanent scroller gutter, so rows end about
  15 pt short of the address field (visible in the screenshot). Cosmetic.
- Collapse, folder and space-switch animations run in Core Animation, so the web view is
  resized once, not once per frame.

**SwiftUI**
- The web view still has to be owned and laid out in AppKit. The prototype keeps one AppKit
  container holding every web view and SwiftUI only positions that container. The rounded
  corners are an AppKit layer property; I did not test whether SwiftUI's own `clipShape` clips
  a web view.
- The lazy list estimates its height: the reported scroll range for the same 200 rows was 6425,
  7311 and 7350 pt in three runs. That usually shows up as a scroll bar that jumps.
- One scripted scroll had a single 156 ms main-thread gap. The second run of the same step was
  clean. I could not repeat it further (see below), so treat it as one sighting, not a rate.
- Collapsing the sidebar animates the web view's frame from SwiftUI, on the main thread, every
  frame. Pacing stayed on time here with a light page.
- Reorder needed the drag measured in global coordinates, or the row's own movement fed back
  into the gesture.

**GTK 4**
- No blur behind the window. GTK draws see-through chrome and the compositor shows the desktop
  through it, unblurred. As far as I know there is no portable blur-behind for GTK apps on
  GNOME; I did not research this further and it is the main open question for "Arc-like".
- Most styling was nearly free: gradients, hover, selection and the gradient cross-fade between
  spaces are plain CSS; sidebar collapse, folder and space switch are stock `GtkRevealer` and
  `GtkStack` transitions.
- Reordering has no animation: a box does not animate its children to new positions. Arc-style
  rows sliding out of the way would be custom work.
- Without a header bar the window has no buttons or drag area, so the prototype adds its own at
  the top of the sidebar. They disappear when the sidebar is collapsed.
- Two layout traps cost a rebuild: expanding labels widened the whole sidebar to 760 px until
  expansion was stopped at the revealer, and negative margins are rejected.
- In the container the app's own process held over 200 MB, because with no GPU the page is
  composited in software inside it. Expect that figure to be very different on real hardware.

## What could not be verified

- **Feel, on all three.** I cannot see a screen or move a pointer. Every claim above about
  animation is "the code path ran and the main thread kept pace", never "it looked smooth".
- **Mac screenshots are not screen captures.** This session has no Screen Recording permission,
  so `screencapture` fails. The Mac prototypes draw themselves instead (`snap=`): the view tree
  plus a WebKit snapshot of the page. In those images the blur is absent (a flat grey stands in
  for the desktop) and the web view's rounded corners are redrawn by the snapshot code. They
  show layout and content only. They do not prove translucency or corner clipping on macOS.
- **Mouse interaction on macOS**: hover states, drag to resize, drag to reorder and typing in
  the address field were never exercised. Tab selection, folder, space switch, collapse, stress
  and scrolling were exercised through the scripted steps.
- **Mouse interaction on Linux**: same, and nothing was run on Wayland, on a GPU, or under a
  real compositor. Translucency on Linux was never seen at all: the headless X server has no
  compositor, so the screenshots show the gradient over black.
- **Cold launch**: only warm launches were measured.
- **Repeat pacing runs**: the Mac's display went to sleep and the screen locked part-way
  through, which stops the display link. AppKit has five scroll runs; SwiftUI has two.
- **Fedora**: compiled in a container, not run.

## What to look at when you run them

1. **Translucency on macOS** (Cmd+Shift+O toggles it): does the tinted blur read as Arc-like,
   and does either prototype stutter when the window moves over busy content?
2. **Web view corners on macOS**: are all four corners clean while a page scrolls and while
   video plays?
3. **Resize while The Verge loads**: drag the window edge and the sidebar edge. Compare AppKit
   and SwiftUI side by side; this is where SwiftUI showed the only late frames.
4. **Collapse the sidebar (Cmd+S) with a heavy page showing**: SwiftUI resizes the web view on
   every frame, AppKit does not. Look for the page reflowing or tearing.
5. **200 tabs (Cmd+Shift+T)**: flick-scroll with a trackpad, watch the scroll bar in SwiftUI,
   check hover highlights do not stick, then drag a row a long way.
6. **On Linux, everything**, in this order: does the window look right on your desktop with no
   header bar; is the see-through chrome acceptable without blur (Ctrl+Shift+O to compare);
   are collapse, folder and space switch smooth on Wayland; does the page keep up when you drag
   the sidebar edge; how bad is reordering without animation.
7. **On Linux, run the tripwire** on real hardware:
   `PROTO_ACTIONS="stress,scroll,heavy,resize,collapse,collapse,quit" ./coracle-gtk4`
   and compare the `PACING` lines with the Mac ones above.

## My read (an agent's opinion, not a decision)

- **macOS**: at this size the two are the same app. Launch, the app's own memory and pacing are
  within noise of each other. SwiftUI got there in about two thirds of the code. The only
  differences I measured lean AppKit's way and are small: late frames during resize, one
  unrepeated scroll hitch, and an unstable list height. The reported reason Dia left SwiftUI
  was performance at a scale this prototype does not reach, so this prototype neither confirms
  nor contradicts it. If I had to bet, AppKit is the lower-risk choice for the sidebar and web
  view, because the web view lives in AppKit either way.
- **Linux**: GTK 4 with libadwaita reached the same layout with less friction than I expected,
  and the web view embeds and clips cleanly. Two things stand between it and "Arc-like": no
  blur behind the window, and no free layout animation for reordering. Whether the rest feels
  fluid is exactly what I could not judge.
- **Memory** is decided by the pages, not the toolkit: ten live tabs cost 1.4 to 2.3 GB
  everywhere, and the interface's own share on macOS was under 45 MB.

## Files

- `mem-macos.py`, `measure-macos.sh`: Mac measurement.
- `linux-gtk4/Dockerfile`, `docker-smoke.sh`, `headless.sh`: container build and smoke test.
- `screenshots/macos-appkit.png`, `macos-appkit-stress.png`, `macos-swiftui.png`,
  `macos-swiftui-stress.png`: in-app self-renders (see the caveat above).
- `screenshots/linux-gtk4-headless.png`, `linux-gtk4-headless-stress.png`: real captures of the
  headless X display. The stress one was taken after the scripted steps, with The Verge loaded
  and translucency off.
