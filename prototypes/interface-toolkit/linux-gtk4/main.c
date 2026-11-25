// PROTOTYPE, throwaway. Coracle issue #10: interface toolkit, Linux candidate
// (GTK 4 + libadwaita + WebKitGTK 6.0). Written in C only because it was the fastest route to a
// running window; the core language is a separate, later decision. Hard-coded data, no persistence.
#include <adwaita.h>
#include <webkit/webkit.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define ROW_PITCH 34.0

typedef struct { const char *title, *url; } Site;

typedef struct {
  const char *url;
  GtkWidget *row, *label;
  WebKitWebView *web;
  gboolean favorite, moved;
} Tab;

typedef struct {
  const char *name;
  const Site *pinned;   int n_pinned;
  const char *folder;
  const Site *in_folder; int n_folder;
  const Site *unpinned; int n_unpinned;
} SpaceDef;

typedef struct {
  GtkWidget *page, *unpinned_box, *folder_revealer, *folder_badge;
  GPtrArray *tabs;      // pinned, then folder, then unpinned, in creation order
  Tab *selected;
} Space;

static const Site favorites[] = {
  {"YouTube", "https://www.youtube.com/"}, {"Wikipedia", "https://www.wikipedia.org/"},
  {"DuckDuckGo", "https://duckduckgo.com/"}, {"Lobsters", "https://lobste.rs/"}};

// The first space holds the ten measurement pages, in this order, in every candidate.
static const Site p0[] = {{"Coracle - Wikipedia", "https://en.wikipedia.org/wiki/Coracle"},
                          {"Hacker News", "https://news.ycombinator.com/"},
                          {"WebKit", "https://webkit.org/"}};
static const Site f0[] = {{"backdrop-filter - MDN", "https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter"},
                          {"GNOME", "https://www.gnome.org/"},
                          {"Swift.org", "https://www.swift.org/"}};
static const Site u0[] = {{"The Verge", "https://www.theverge.com/"},
                          {"BBC News", "https://www.bbc.com/news"},
                          {"WebKit on GitHub", "https://github.com/WebKit/WebKit"},
                          {"OpenStreetMap", "https://www.openstreetmap.org/"}};
static const Site p1[] = {{"GTK", "https://www.gtk.org/"}};
static const Site f1[] = {{"WebKitGTK", "https://webkitgtk.org/"}, {"Wayland", "https://wayland.freedesktop.org/"}};
static const Site u1[] = {{"Rust", "https://www.rust-lang.org/"}, {"KDL", "https://kdl.dev/"}};
static const Site p2[] = {{"Internet Archive", "https://archive.org/"}};
static const Site f2[] = {{"Bandcamp", "https://bandcamp.com/"}};
static const Site u2[] = {{"xkcd", "https://xkcd.com/"}};

#define N_SPACES 3
static const SpaceDef defs[N_SPACES] = {
  {"Personal", p0, 3, "Reading", f0, 3, u0, 4},
  {"Work", p1, 1, "Docs", f1, 2, u1, 2},
  {"Play", p2, 1, "Music", f2, 1, u2, 1}};

static const char *CSS =
  "window.coracle { background: none; }"
  ".chrome { transition: background-image 450ms ease-in-out; color: white; }"
  ".chrome.space-0 { background-image: linear-gradient(135deg, #7B2FF7, #F107A3); }"
  ".chrome.space-1 { background-image: linear-gradient(135deg, #0B486B, #16A085); }"
  ".chrome.space-2 { background-image: linear-gradient(135deg, #F2994A, #D9376E); }"
  // GTK has no blur-behind; the nearest thing is plain see-through chrome drawn by the compositor.
  ".chrome.translucent.space-0 { background-image: linear-gradient(135deg, alpha(#7B2FF7, 0.78), alpha(#F107A3, 0.78)); }"
  ".chrome.translucent.space-1 { background-image: linear-gradient(135deg, alpha(#0B486B, 0.78), alpha(#16A085, 0.78)); }"
  ".chrome.translucent.space-2 { background-image: linear-gradient(135deg, alpha(#F2994A, 0.78), alpha(#D9376E, 0.78)); }"
  ".row { border-radius: 8px; min-height: 32px; padding: 0 8px; color: rgba(255,255,255,0.92);"
  "       font-size: 13px; transition: background-color 120ms; }"
  ".row:hover { background-color: rgba(255,255,255,0.14); }"
  ".row.selected { background-color: rgba(255,255,255,0.26); }"
  ".row.dragging { opacity: 0.6; }"
  ".badge { border-radius: 5px; min-width: 18px; min-height: 18px; font-weight: bold; font-size: 11px; color: white; }"
  ".tile { border-radius: 10px; min-height: 44px; background-color: rgba(255,255,255,0.10); transition: background-color 120ms; }"
  ".tile:hover { background-color: rgba(255,255,255,0.14); }"
  ".tile.selected { background-color: rgba(255,255,255,0.26); }"
  ".tile .badge { min-width: 24px; min-height: 24px; font-size: 15px; }"
  ".tint-0 { background-color: #e5677a; } .tint-1 { background-color: #e59a52; } .tint-2 { background-color: #c9b23c; }"
  ".tint-3 { background-color: #67c26b; } .tint-4 { background-color: #4fb8c4; } .tint-5 { background-color: #5b8de5; }"
  ".tint-6 { background-color: #9a6be5; } .tint-7 { background-color: #d667c8; } .tint-none { background: none; }"
  ".tint-plus { background-color: rgba(255,255,255,0.15); }"
  "entry.address { border-radius: 8px; background-color: rgba(255,255,255,0.14); color: white; min-height: 32px;"
  "                border: none; box-shadow: none; outline: none; font-size: 13px; }"
  ".spacename { font-size: 11px; font-weight: 600; color: rgba(255,255,255,0.7); }"
  ".divider { min-height: 1px; background-color: rgba(255,255,255,0.18); margin: 6px 0; }"
  ".webcard { border-radius: 10px; background-color: white; }"
  "button.dot { border-radius: 8px; min-width: 16px; min-height: 16px; padding: 0; border: none; box-shadow: none; }"
  "button.dot.current { box-shadow: 0 0 0 2px white; }"
  "button.dot-0 { background: #F107A3; } button.dot-1 { background: #16A085; } button.dot-2 { background: #D9376E; }";

static GtkWidget *window, *chrome, *revealer, *sidebar, *address, *space_stack, *space_label, *web_stack;
static GtkWidget *dots[N_SPACES];
static Space spaces[N_SPACES];
static Tab *selected;
static int cur_space, sidebar_width = 260;

// ---------------------------------------------------------------- tabs

static void on_title(WebKitWebView *web, GParamSpec *p, Tab *t) {
  const char *title = webkit_web_view_get_title(web);
  if (t->label && title && *title) gtk_label_set_text(GTK_LABEL(t->label), title);
}

static void on_uri(WebKitWebView *web, GParamSpec *p, Tab *t) {
  const char *uri = webkit_web_view_get_uri(web);
  if (t == selected && uri) gtk_editable_set_text(GTK_EDITABLE(address), uri);
}

static void ensure_web(Tab *t) {
  if (t->web) return;
  t->web = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_stack_add_child(GTK_STACK(web_stack), GTK_WIDGET(t->web));
  g_signal_connect(t->web, "notify::title", G_CALLBACK(on_title), t);
  g_signal_connect(t->web, "notify::uri", G_CALLBACK(on_uri), t);
  webkit_web_view_load_uri(t->web, t->url);
}

static void select_tab(Tab *t) {
  if (selected) gtk_widget_remove_css_class(selected->row, "selected");
  ensure_web(t);
  selected = t;
  if (!t->favorite) spaces[cur_space].selected = t;
  gtk_widget_add_css_class(t->row, "selected");
  gtk_stack_set_visible_child(GTK_STACK(web_stack), GTK_WIDGET(t->web));
  const char *uri = webkit_web_view_get_uri(t->web);
  gtk_editable_set_text(GTK_EDITABLE(address), uri ? uri : t->url);
}

static void on_address(GtkEntry *e, gpointer d) {
  const char *text = gtk_editable_get_text(GTK_EDITABLE(e));
  g_autofree char *uri = NULL;
  if (strstr(text, "://")) uri = g_strdup(text);
  else if (strchr(text, '.') && !strchr(text, ' ')) uri = g_strconcat("https://", text, NULL);
  else {
    g_autofree char *q = g_uri_escape_string(text, NULL, TRUE);
    uri = g_strconcat("https://duckduckgo.com/?q=", q, NULL);
  }
  if (selected) {
    webkit_web_view_load_uri(selected->web, uri);
    gtk_widget_grab_focus(GTK_WIDGET(selected->web));
  }
}

// ---------------------------------------------------------------- rows

static int tint_of(const char *s) {
  unsigned h = 0;
  for (; *s; s++) h = h * 31 + (unsigned char)*s;
  return h % 8;
}

static GtkWidget *make_row(const char *glyph, const char *title, const char *tint, int indent,
                           GtkWidget **label_out, GtkWidget **badge_out) {
  GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_widget_add_css_class(row, "row");
  GtkWidget *badge = gtk_label_new(glyph);
  gtk_widget_add_css_class(badge, "badge");
  gtk_widget_add_css_class(badge, tint);
  gtk_widget_set_valign(badge, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_start(badge, indent);
  GtkWidget *label = gtk_label_new(title);
  gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
  gtk_label_set_xalign(GTK_LABEL(label), 0);
  gtk_widget_set_hexpand(label, TRUE);
  gtk_box_append(GTK_BOX(row), badge);
  gtk_box_append(GTK_BOX(row), label);
  if (label_out) *label_out = label;
  if (badge_out) *badge_out = badge;
  return row;
}

// One drag gesture per tab row: a drag that never moved is a click; in the unpinned box it reorders.
static void on_row_drag_update(GtkGestureDrag *g, double dx, double dy, Tab *t) {
  GtkWidget *box = gtk_widget_get_parent(t->row);
  if (box != spaces[cur_space].unpinned_box) return;
  // Offsets are in the row's own coordinates, so they rebase by themselves once the row has moved.
  if (dy > ROW_PITCH * 0.6) {
    GtkWidget *next = gtk_widget_get_next_sibling(t->row);
    if (next) gtk_box_reorder_child_after(GTK_BOX(box), t->row, next);
  } else if (dy < -ROW_PITCH * 0.6) {
    GtkWidget *prev = gtk_widget_get_prev_sibling(t->row);
    if (prev) gtk_box_reorder_child_after(GTK_BOX(box), prev, t->row);
  } else return;
  t->moved = TRUE;
  gtk_widget_add_css_class(t->row, "dragging");
}

static void on_row_drag_end(GtkGestureDrag *g, double dx, double dy, Tab *t) {
  gtk_widget_remove_css_class(t->row, "dragging");
  if (!t->moved && ABS(dx) < 4 && ABS(dy) < 4) select_tab(t);
  t->moved = FALSE;
}

static Tab *make_tab(const Site *s, int indent, Space *space) {
  Tab *t = g_new0(Tab, 1);
  t->url = s->url;
  char glyph[8] = {0};
  g_utf8_strncpy(glyph, s->title, 1);
  g_autofree char *tint = g_strdup_printf("tint-%d", tint_of(s->url));
  if (space) {
    t->row = make_row(glyph, s->title, tint, indent, &t->label, NULL);
    g_ptr_array_add(space->tabs, t);
  } else {  // favorite tile
    t->favorite = TRUE;
    t->row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(t->row, "tile");
    gtk_widget_set_tooltip_text(t->row, s->title);
    GtkWidget *badge = gtk_label_new(glyph);
    gtk_widget_add_css_class(badge, "badge");
    gtk_widget_add_css_class(badge, tint);
    gtk_widget_set_halign(badge, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(badge, GTK_ALIGN_CENTER);
    gtk_widget_set_hexpand(badge, TRUE);
    gtk_box_append(GTK_BOX(t->row), badge);
  }
  GtkGesture *drag = gtk_gesture_drag_new();
  g_signal_connect(drag, "drag-update", G_CALLBACK(on_row_drag_update), t);
  g_signal_connect(drag, "drag-end", G_CALLBACK(on_row_drag_end), t);
  gtk_widget_add_controller(t->row, GTK_EVENT_CONTROLLER(drag));
  return t;
}

static void on_click(GtkWidget *w, GCallback cb, gpointer data) {
  GtkGesture *click = gtk_gesture_click_new();
  g_signal_connect_swapped(click, "released", cb, data);
  gtk_widget_add_controller(w, GTK_EVENT_CONTROLLER(click));
}

static void toggle_folder(Space *s) {
  gboolean open = !gtk_revealer_get_reveal_child(GTK_REVEALER(s->folder_revealer));
  gtk_revealer_set_reveal_child(GTK_REVEALER(s->folder_revealer), open);
  gtk_label_set_text(GTK_LABEL(s->folder_badge), open ? "▾" : "▸");
}

static void new_tab(Space *s) {
  static const Site ddg = {"DuckDuckGo", "https://duckduckgo.com/"};
  Tab *t = make_tab(&ddg, 0, s);
  gtk_box_prepend(GTK_BOX(s->unpinned_box), t->row);
  select_tab(t);
}

static void build_space(int i) {
  const SpaceDef *d = &defs[i];
  Space *s = &spaces[i];
  s->tabs = g_ptr_array_new();
  GtkWidget *list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_set_margin_bottom(list, 8);
  for (int n = 0; n < d->n_pinned; n++) gtk_box_append(GTK_BOX(list), make_tab(&d->pinned[n], 0, s)->row);

  GtkWidget *header = make_row("▾", d->folder, "tint-none", 0, NULL, &s->folder_badge);
  on_click(header, G_CALLBACK(toggle_folder), s);
  gtk_box_append(GTK_BOX(list), header);
  GtkWidget *children = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  for (int n = 0; n < d->n_folder; n++) gtk_box_append(GTK_BOX(children), make_tab(&d->in_folder[n], 16, s)->row);
  s->folder_revealer = gtk_revealer_new();
  gtk_revealer_set_transition_type(GTK_REVEALER(s->folder_revealer), GTK_REVEALER_TRANSITION_TYPE_SLIDE_DOWN);
  gtk_revealer_set_transition_duration(GTK_REVEALER(s->folder_revealer), 220);
  gtk_revealer_set_child(GTK_REVEALER(s->folder_revealer), children);
  gtk_revealer_set_reveal_child(GTK_REVEALER(s->folder_revealer), TRUE);
  gtk_box_append(GTK_BOX(list), s->folder_revealer);

  GtkWidget *divider = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(divider, "divider");
  gtk_box_append(GTK_BOX(list), divider);
  GtkWidget *add = make_row("+", "New Tab", "tint-plus", 0, NULL, NULL);
  on_click(add, G_CALLBACK(new_tab), s);
  gtk_box_append(GTK_BOX(list), add);

  s->unpinned_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  for (int n = 0; n < d->n_unpinned; n++) gtk_box_append(GTK_BOX(s->unpinned_box), make_tab(&d->unpinned[n], 0, s)->row);
  gtk_box_append(GTK_BOX(list), s->unpinned_box);

  s->page = gtk_scrolled_window_new();
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(s->page), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(s->page), list);
  gtk_stack_add_child(GTK_STACK(space_stack), s->page);
}

static void show_space(int i) {
  g_autofree char *old_class = g_strdup_printf("space-%d", cur_space);
  g_autofree char *new_class = g_strdup_printf("space-%d", i);
  gtk_widget_remove_css_class(chrome, old_class);
  gtk_widget_add_css_class(chrome, new_class);
  gtk_widget_remove_css_class(dots[cur_space], "current");
  gtk_widget_add_css_class(dots[i], "current");
  cur_space = i;
  g_autofree char *upper = g_utf8_strup(defs[i].name, -1);
  gtk_label_set_text(GTK_LABEL(space_label), upper);
  gtk_stack_set_visible_child(GTK_STACK(space_stack), spaces[i].page);   // slides left or right by child order
  Space *s = &spaces[i];
  select_tab(s->selected ? s->selected : g_ptr_array_index(s->tabs, 0));
}

static void on_dot(GtkButton *b, gpointer i) { show_space(GPOINTER_TO_INT(i)); }

// ---------------------------------------------------------------- sidebar resize, collapse, debug

static void on_handle_drag(GtkGestureDrag *g, double dx, double dy, gpointer d) {
  // The handle moves with the sidebar, so dx is already relative to the current width.
  sidebar_width = CLAMP(sidebar_width + (int)dx, 180, 480);
  gtk_widget_set_size_request(sidebar, sidebar_width, -1);
}

static void toggle_sidebar(void) {
  gtk_revealer_set_reveal_child(GTK_REVEALER(revealer), !gtk_revealer_get_reveal_child(GTK_REVEALER(revealer)));
}

static void toggle_translucency(void) {
  if (gtk_widget_has_css_class(chrome, "translucent")) gtk_widget_remove_css_class(chrome, "translucent");
  else gtk_widget_add_css_class(chrome, "translucent");
}

static void stress(void) {
  Space *s = &spaces[cur_space];
  gint64 t0 = g_get_monotonic_time();
  for (int i = 1; i <= 200; i++) {
    Site *site = g_new0(Site, 1);   // leaked on purpose: prototype
    site->title = g_strdup_printf("Stress tab %d", i);
    site->url = g_strdup_printf("https://example.com/?tab=%d", i);
    gtk_box_append(GTK_BOX(s->unpinned_box), make_tab(site, 0, s)->row);
  }
  // Widget creation only; layout and first draw of the new rows happen on the next frame.
  g_print("STRESS_BUILD_MS=%.1f\n", (g_get_monotonic_time() - t0) / 1000.0);
}

// ---------------------------------------------------------------- measurement harness

static double ms_since_process_start(void) {
  g_autofree char *stat = NULL;
  g_file_get_contents("/proc/self/stat", &stat, NULL, NULL);
  char *p = strrchr(stat, ')') + 2;            // field 3 (state) starts here; starttime is field 22
  for (int f = 3; f < 22; f++) p = strchr(p, ' ') + 1;
  double start = g_ascii_strtod(p, NULL) / sysconf(_SC_CLK_TCK);   // seconds after boot, 10 ms resolution
  struct timespec now;
  clock_gettime(CLOCK_BOOTTIME, &now);
  return (now.tv_sec + now.tv_nsec / 1e9 - start) * 1000;
}

static void on_first_frame(GdkFrameClock *clock, gpointer d) {
  g_signal_handlers_disconnect_by_func(clock, on_first_frame, d);
  g_print("FIRST_FRAME_MS=%.0f\n", ms_since_process_start());
}

// Main-loop frame pacing: drive something once per frame-clock tick for three seconds and record the
// gaps between ticks. Meaningless under a software-rendered headless display; run it on real hardware.
typedef struct { char *name; gint64 start, last; double gaps[2048]; int n, kind, w, h; double range; GtkAdjustment *adj; } Bench;

static int cmp_double(const void *a, const void *b) { double d = *(double *)a - *(double *)b; return (d > 0) - (d < 0); }

static gboolean bench_tick(GtkWidget *w, GdkFrameClock *clock, gpointer data) {
  Bench *b = data;
  gint64 now = g_get_monotonic_time();
  if (!b->start) b->start = now;
  else if (b->n < 2048) b->gaps[b->n++] = (now - b->last) / 1000.0;
  b->last = now;
  double t = (now - b->start) / 3e6;
  if (t >= 1) {
    gint64 interval = 0;
    gdk_frame_clock_get_refresh_info(clock, 0, &interval, NULL);
    double frame = interval / 1000.0;
    int late = 0;
    for (int i = 0; i < b->n; i++) late += b->gaps[i] > frame * 1.5;
    qsort(b->gaps, b->n, sizeof(double), cmp_double);
    g_print("PACING %s frames=%d display_frame_ms=%.1f median_ms=%.1f p95_ms=%.1f max_ms=%.1f late=%d\n", b->name, b->n,
            frame, b->gaps[b->n / 2], b->gaps[b->n * 95 / 100], b->gaps[b->n - 1], late);
    return G_SOURCE_REMOVE;
  }
  double f = t < 0.5 ? t * 2 : (1 - t) * 2;   // 0 -> 1 -> 0
  if (b->kind == 1) gtk_adjustment_set_value(b->adj, b->range * f);
  if (b->kind == 2) gtk_window_set_default_size(GTK_WINDOW(window), b->w - 400 * f, b->h - 250 * f);
  return G_SOURCE_CONTINUE;
}

static void bench(const char *name, int kind) {
  Bench *b = g_new0(Bench, 1);
  b->name = g_strdup(name);
  b->kind = kind;
  if (kind == 1) {
    b->adj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(spaces[cur_space].page));
    b->range = gtk_adjustment_get_upper(b->adj) - gtk_adjustment_get_page_size(b->adj);
    g_print("SCROLL_RANGE_PX=%.0f\n", b->range);
  }
  b->w = gtk_widget_get_width(window);
  b->h = gtk_widget_get_height(window);
  gtk_widget_add_tick_callback(window, bench_tick, b, NULL);
}

static gboolean run_action(gpointer data) {
  const char *a = data;
  g_print("ACTION %s\n", a);
  if (!strcmp(a, "stress")) stress();
  else if (!strcmp(a, "scroll")) bench(a, 1);
  else if (!strcmp(a, "resize")) bench(a, 2);
  else if (!strcmp(a, "collapse")) { toggle_sidebar(); bench(a, 0); }
  else if (!strcmp(a, "folder")) { toggle_folder(&spaces[cur_space]); bench(a, 0); }
  else if (g_str_has_prefix(a, "space")) { show_space(a[5] - '0'); bench(a, 0); }
  else if (!strcmp(a, "heavy")) select_tab(g_ptr_array_index(spaces[0].tabs, 6));
  else if (!strcmp(a, "newtab")) new_tab(&spaces[cur_space]);
  else if (!strcmp(a, "opaque")) toggle_translucency();
  else if (!strcmp(a, "quit")) exit(0);
  return G_SOURCE_REMOVE;
}

static void schedule_actions(void) {
  const char *env = g_getenv("PROTO_ACTIONS"), *delay = g_getenv("PROTO_ACTIONS_DELAY");
  if (!env) return;
  double at = delay ? g_ascii_strtod(delay, NULL) : 4;
  char **list = g_strsplit(env, ",", -1);
  for (int i = 0; list[i]; i++) {
    g_timeout_add((guint)(at * 1000), run_action, list[i]);
    gboolean timed = !strcmp(list[i], "scroll") || !strcmp(list[i], "resize") || !strcmp(list[i], "collapse") ||
                     !strcmp(list[i], "folder") || g_str_has_prefix(list[i], "space");
    at += timed ? 4 : 1.2;
  }
}

// ---------------------------------------------------------------- window

static void add_action(GtkApplication *app, const char *name, GCallback cb, gpointer data, const char *accel) {
  GSimpleAction *a = g_simple_action_new(name, NULL);
  g_signal_connect_swapped(a, "activate", cb, data);
  g_action_map_add_action(G_ACTION_MAP(app), G_ACTION(a));
  g_autofree char *full = g_strconcat("app.", name, NULL);
  gtk_application_set_accels_for_action(app, full, (const char *[]){accel, NULL});
}

static void focus_address(void) { gtk_widget_grab_focus(address); }

static void activate(GtkApplication *app, gpointer d) {
  adw_style_manager_set_color_scheme(adw_style_manager_get_default(), ADW_COLOR_SCHEME_FORCE_DARK);
  GtkCssProvider *css = gtk_css_provider_new();
  gtk_css_provider_load_from_string(css, CSS);
  gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(css),
                                             GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  window = adw_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "Coracle GTK 4 prototype");
  gtk_window_set_default_size(GTK_WINDOW(window), 1280, 820);
  gtk_widget_add_css_class(window, "coracle");

  chrome = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(chrome, "chrome");
  gtk_widget_add_css_class(chrome, "space-0");
  gtk_widget_add_css_class(chrome, "translucent");
  adw_application_window_set_content(ADW_APPLICATION_WINDOW(window), chrome);

  // Sidebar: a fixed-width box inside a revealer, so collapsing slides it out to the left.
  sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_size_request(sidebar, sidebar_width, -1);
  gtk_widget_set_margin_start(sidebar, 8);
  revealer = gtk_revealer_new();
  gtk_revealer_set_transition_type(GTK_REVEALER(revealer), GTK_REVEALER_TRANSITION_TYPE_SLIDE_RIGHT);
  gtk_revealer_set_transition_duration(GTK_REVEALER(revealer), 280);
  gtk_revealer_set_child(GTK_REVEALER(revealer), sidebar);
  gtk_revealer_set_reveal_child(GTK_REVEALER(revealer), TRUE);
  gtk_widget_set_hexpand(revealer, FALSE);   // stop the rows' expanding labels from widening the sidebar
  gtk_box_append(GTK_BOX(chrome), revealer);

  // No header bar: window buttons live at the top of the sidebar, in a strip that drags the window.
  GtkWidget *strip = gtk_window_handle_new();
  GtkWidget *strip_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_size_request(strip_box, -1, 38);
  gtk_box_append(GTK_BOX(strip_box), gtk_window_controls_new(GTK_PACK_START));
  gtk_window_handle_set_child(GTK_WINDOW_HANDLE(strip), strip_box);
  gtk_box_append(GTK_BOX(sidebar), strip);

  address = gtk_entry_new();
  gtk_widget_add_css_class(address, "address");
  gtk_entry_set_placeholder_text(GTK_ENTRY(address), "Search or enter address");
  g_signal_connect(address, "activate", G_CALLBACK(on_address), NULL);
  gtk_box_append(GTK_BOX(sidebar), address);

  GtkWidget *favs = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_box_set_homogeneous(GTK_BOX(favs), TRUE);
  gtk_widget_set_margin_top(favs, 8);
  for (guint i = 0; i < G_N_ELEMENTS(favorites); i++) gtk_box_append(GTK_BOX(favs), make_tab(&favorites[i], 0, NULL)->row);
  gtk_box_append(GTK_BOX(sidebar), favs);

  space_label = gtk_label_new("");
  gtk_widget_add_css_class(space_label, "spacename");
  gtk_label_set_xalign(GTK_LABEL(space_label), 0);
  gtk_widget_set_margin_start(space_label, 8);
  gtk_widget_set_margin_top(space_label, 12);
  gtk_widget_set_margin_bottom(space_label, 6);
  gtk_box_append(GTK_BOX(sidebar), space_label);

  space_stack = gtk_stack_new();
  gtk_stack_set_transition_type(GTK_STACK(space_stack), GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
  gtk_stack_set_transition_duration(GTK_STACK(space_stack), 320);
  gtk_widget_set_vexpand(space_stack, TRUE);
  gtk_box_append(GTK_BOX(sidebar), space_stack);
  for (int i = 0; i < N_SPACES; i++) build_space(i);

  GtkWidget *switcher = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  gtk_widget_set_halign(switcher, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_top(switcher, 12);
  gtk_widget_set_margin_bottom(switcher, 12);
  for (int i = 0; i < N_SPACES; i++) {
    dots[i] = gtk_button_new();
    g_autofree char *cls = g_strdup_printf("dot-%d", i);
    gtk_widget_add_css_class(dots[i], "dot");
    gtk_widget_add_css_class(dots[i], cls);
    gtk_widget_set_valign(dots[i], GTK_ALIGN_CENTER);
    gtk_widget_set_tooltip_text(dots[i], defs[i].name);
    g_signal_connect(dots[i], "clicked", G_CALLBACK(on_dot), GINT_TO_POINTER(i));
    gtk_box_append(GTK_BOX(switcher), dots[i]);
  }
  gtk_box_append(GTK_BOX(sidebar), switcher);

  GtkWidget *handle = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_size_request(handle, 8, -1);
  gtk_widget_set_cursor_from_name(handle, "col-resize");
  GtkGesture *drag = gtk_gesture_drag_new();
  g_signal_connect(drag, "drag-update", G_CALLBACK(on_handle_drag), NULL);
  gtk_widget_add_controller(handle, GTK_EVENT_CONTROLLER(drag));
  gtk_box_append(GTK_BOX(chrome), handle);

  // Web card: rounded corners come from CSS border-radius plus overflow clipping on the container.
  GtkWidget *card = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(card, "webcard");
  gtk_widget_set_overflow(card, GTK_OVERFLOW_HIDDEN);
  gtk_widget_set_hexpand(card, TRUE);
  gtk_widget_set_margin_top(card, 8);
  gtk_widget_set_margin_bottom(card, 8);
  gtk_widget_set_margin_end(card, 8);
  web_stack = gtk_stack_new();
  gtk_widget_set_hexpand(web_stack, TRUE);
  gtk_box_append(GTK_BOX(card), web_stack);
  gtk_box_append(GTK_BOX(chrome), card);

  add_action(app, "toggle-sidebar", G_CALLBACK(toggle_sidebar), NULL, "<Control>s");
  add_action(app, "focus-address", G_CALLBACK(focus_address), NULL, "<Control>l");
  add_action(app, "stress", G_CALLBACK(stress), NULL, "<Control><Shift>t");
  add_action(app, "translucency", G_CALLBACK(toggle_translucency), NULL, "<Control><Shift>o");
  for (int i = 0; i < N_SPACES; i++) {
    g_autofree char *name = g_strdup_printf("space%d", i), *accel = g_strdup_printf("<Control>%d", i + 1);
    add_action(app, name, G_CALLBACK(show_space), GINT_TO_POINTER(i), accel);
  }

  gtk_widget_add_css_class(dots[0], "current");
  show_space(0);
  const char *live = g_getenv("PROTO_LIVE_TABS");
  for (int i = 0; live && i < atoi(live) && i < (int)spaces[0].tabs->len; i++) ensure_web(g_ptr_array_index(spaces[0].tabs, i));

  gtk_window_present(GTK_WINDOW(window));
  g_signal_connect(gtk_widget_get_frame_clock(window), "after-paint", G_CALLBACK(on_first_frame), NULL);
  schedule_actions();
}

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  AdwApplication *app = adw_application_new("dev.coracle.Gtk4Prototype", G_APPLICATION_NON_UNIQUE);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
