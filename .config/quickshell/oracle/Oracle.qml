// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE — the one place this shell keeps an answer it was asked for.
//
// Every layer in here already had its own settings; what none of them had was
// a way to CHANGE one. A toast timeout was a readonly property in Howler, the
// idle lock was a literal inside socordia's listener array, the pill's corner
// was a token in Zenon — each of them correct, each of them requiring a text
// editor and a shell restart. This is the same set of numbers with a dial on
// the front of it.
//
// THE SHAPE, and why it is this shape:
//
//   Each setting is a REAL QML PROPERTY, not a row in a map. That is the whole
//   reason the wiring elsewhere is one line per setting: Howler says
//   `timeoutNormal: Oracle.notifTimeout` and is done — a binding, so changing
//   it here reaches the next toast without anything being told to reload. A
//   map would have made every consumer call a function, and a function call is
//   not a dependency: nothing would have updated until something else happened
//   to change.
//
//   `specs` is the same set again, described rather than valued: what a
//   setting is called, what it does, what kind of thing it is, and what range
//   it may take. That is what the panel draws itself from, so adding a setting
//   is a property and a spec and no UI at all.
//
//   The DEFAULTS are not written twice. They are read off the properties
//   themselves at startup, before the file is loaded — the declaration IS the
//   default, and there is no second copy of 4000 to drift away from the first.
//
// WHAT IS WRITTEN TO DISK is only what has been changed. See Ora.serialize:
// a file holding every default would quietly pin an install to the day it was
// first opened, and never see a default improved afterwards.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "oracle.js" as Ora

Singleton {
  id: root

  // Bumped on every write. The panel's rows read their value through get(),
  // which is a function call and therefore NOT a binding dependency — this is
  // the dependency they take instead, so a row repaints when its setting
  // changes underneath it (a reset, the file being reloaded, another row's
  // action). Nothing outside the panel needs it: everything else binds to the
  // properties directly and is updated by QML itself.
  property int revision: 0
  signal settingChanged(string key)

  // ── the bar ───────────────────────────────────────────────────────────
  // morpheus, and the pill it lives in. The sizes are read through Zenon, so
  // every layer that measures itself against the bar follows them too.

  // The pill will not grow past this however much a layer asks for. 1000 is
  // what every layer was written against.
  property int barMaxWidth: 1000
  property int barRadius: 8
  property int barTextSize: 18
  property int barSlot: 32
  property int barGap: 8
  // How far the pill floats off the bottom of the screen, and how much room
  // is kept between it and the windows above it. TWO NUMBERS, because they
  // are two different gaps: one is under the pill and one is over it, and
  // wanting the bar tucked against the edge while still breathing away from
  // your windows is a perfectly ordinary thing to want.
  property int barScreenPad: 6
  property int barWindowGap: 0
  property bool barBlur: true

  // Which edge the whole shell hangs off. Every layer opens out of the pill,
  // so this moves all of them together — along with the toast stack and the
  // direction a tooltip opens in. See Zenon.barTop, which is what they all
  // actually read.
  property string barPosition: "bottom"
  // the pill's end caps, and a module's own breathing room inside its slot
  property int barPadBar: 12
  property int barPadModule: 4
  // Which output the pill lives on, by name. Empty means the one
  // QS_STATUS_SCREEN names, and failing that the first screen there is — the
  // same order shell.qml has always resolved it in.
  property string barMonitor: ""
  // Whether tiled windows are kept clear of the pill. Off, the pill floats
  // over whatever is underneath it and nothing on the desktop moves for it.
  property bool barReserveSpace: true

  // What the pill actually shows. Each of these is the module's own `active`
  // ANDed with the switch, so turning one off is the same motion the module
  // already makes when it has nothing to say — it eases to zero width and the
  // pill shrink-wraps around what is left.
  property bool showUpdates: true
  property bool showNotifications: true
  property bool showWorkspaces: true
  property bool showClock: true
  property bool showNetwork: true
  property bool showGpu: true
  property bool showCpu: true
  property bool showMemory: true
  property bool showVolume: true
  property bool showNowPlaying: true
  property bool showStatus: true
  // The system tray, which lives inside the workspace row and is revealed by
  // hovering it. Off, tray applications keep running and simply have nowhere
  // to appear.
  property bool showTray: true
  // The hover text on the bar's modules. Off, the bar is silent and you are
  // relying on the readings themselves — which for the meters is most of the
  // information anyway.
  property bool barTooltips: true

  // ── WHAT EVERY COMPONENT SHARES ───────────────────────────────────────
  // The Nerd Font FAMILY, without the cut. Zenon derives the three the shell
  // actually uses — " Propo" for labels, " Mono" for the lock's clock and the
  // mark, and the bare name for the column-aligned tables — because they have
  // to be one family or a panel looks like two fonts.
  //
  // It must be a Nerd Font: every icon in this shell is a glyph in the
  // private use area, and a face without them draws a column of empty boxes.
  property string fontFamily: "JetBrainsMono Nerd Font"

  // The corner a MENU is cut with. Deliberately not the panels' radius: a
  // menu is a small card over your work and a panel is a large surface at an
  // edge, and the corner that suits one looks wrong on the other.
  property int menuRadius: 6

  // ── how it is painted ─────────────────────────────────────────────────
  // Alpha over black, both of them. Hyprland's blur has an `ignore_alpha`
  // threshold — 0.5 on this machine — so a surface taken past that stops being
  // blurred and becomes a flat panel. That is a legitimate thing to want; it
  // is just worth knowing which side of the line you are on.
  property real barOpacity: 0.50
  property real panelOpacity: 0.80
  // How heavy a shadow a layer casts, and a menu. They are deliberately two
  // numbers: a layer sits near an edge and a shadow loud enough to lift it off
  // the desktop reads as a black halo, while a menu floats over a window and
  // the same number reads as no shadow at all.
  property real shadowStrength: 0.48
  // A menu's own ground. Opaque by default and deliberately so: a menu sits
  // ON what is behind it, and at the panels' alpha the wallpaper reads
  // straight through the rows.
  property real menuOpacity: 1.0

  // ── motion ────────────────────────────────────────────────────────────
  // One multiplier over Zenon's three durations, so the whole shell speeds up
  // or slows down together and the layers cannot fall out of step with the
  // pill they are morphing out of. Zero is not a degenerate case here: it is
  // the setting for a machine where every animation is one frame.
  property real motionScale: 1.0
  property bool arrivalEnabled: true
  property int arrivalDuration: 750
  // The deadline the session's first animation aims at — see Arrival, where
  // the measurements behind 2200 are written down.
  property int arrivalDeadline: 2200

  // ── notifications ─────────────────────────────────────────────────────
  // howler's ported mako config, with the parts worth changing brought out.
  property int notifTimeout: 4000
  property int notifTimeoutLow: 4000
  // mako's `[urgency=critical] default-timeout=0`. Off, a critical
  // notification expires on the ordinary timeout like anything else.
  property bool notifCriticalSticky: true
  property int notifMaxVisible: 5
  property bool notifIcons: true
  property int notifIconSize: 76
  property int notifWidth: 400
  property int notifMaxWidth: 800
  // how far the stack floats above the pill
  property int notifLift: 20
  // whether a music player's track change earns a row in the bell's history.
  // Off by default: the track name is already in the bar.
  property bool notifTrackMusic: false
  property int notifHistoryCap: 200
  property int notifRadius: 5
  property int notifPadding: 5
  // the space between two stacked toasts
  property int notifSpacing: 2
  property int notifFontSize: 16
  // mako's text-alignment
  property string notifTextAlign: "centre"
  // nothing shorter than this, so a one-word notification still reads as a
  // panel rather than as a strip
  property int notifMinHeight: 64
  property int notifBorderSize: 1
  property int notifIconRadius: 5
  // mako: markup=1 — whether an application's <b> and <i> are honoured or
  // shown as the characters they are
  property bool notifMarkup: true
  // A per-toast ceiling, not a height: a short notification stays short.
  property int notifMaxHeight: 400
  // WHICH CORNER, not which end. mako's `anchor` had both axes and so does
  // this: the toasts used to be pinned to whichever edge the bar was on, and
  // wanting them at the top of the screen with the bar at the bottom is a
  // perfectly ordinary thing to want.
  //
  // "auto" keeps the old behaviour — follow the bar — and stays the default,
  // because a stack at the far end of the screen from the thing that counts
  // them reads as a different application's.
  property string notifPosition: "auto"

  // ── the background ────────────────────────────────────────────────────
  // EMPTY BY DEFAULT, and that is the point. A default of
  // "$HOME/Pictures/Wallpapers" is a path that happens to be true on the
  // machine this was written on: the folder name is in no specification, so a
  // default naming it would be wrong on every machine that spells it
  // differently — while still being written into everyone's settings as
  // though it had been chosen.
  //
  // Empty means "ask XDG", which picasso does — see Picasso.defaultDir, which
  // reads the pictures directory out of user-dirs.dirs. A path is stored here
  // only once somebody has actually typed one.
  property string backgroundDir: ""
  // The DEFAULT fit. A monitor can be given its own in picasso's context
  // menu, and picasso keeps those beside the per-monitor images; this is what
  // every monitor that has not been given one uses.
  property string backgroundFit: "crop"
  // how far past the screen the background is drawn, which is the room the
  // arrival's zoom has to move in
  property real backgroundZoom: 1.08

  // ── idle, and the lock ────────────────────────────────────────────────
  // socordia's ported hypridle listeners. Each timeout is counted by the
  // compositor through ext-idle-notify, so these are deadlines rather than
  // polling intervals and a change takes effect on the next idle period.
  property bool idleEnabled: true
  property int idleLockSecs: 300
  property int idleScreenOffSecs: 600
  property int idleKeyboardSecs: 300
  // The keyboard solaar dims, by its solaar device name. EMPTY BY DEFAULT:
  // naming a particular keyboard here would be shipping one desk's hardware
  // as everybody's default, and on a machine without that device it is a
  // failing subprocess every five minutes for the life of the session.
  property string idleKeyboardName: ""
  property bool idleInhibitPlayback: true

  property bool lockHideCursor: true
  property real lockShade: 0.6
  property int lockFailLimit: 3
  // How hard the desktop behind the lock is blurred. See CerberusLock's
  // blurPipeline: the blur is done ONCE at capture by downsampling, blurring
  // and upsampling again, so this is the percentage the shot is reduced to —
  // smaller is blurrier, and the cost is paid at lock time rather than on
  // every frame.
  property int lockBlurStrength: 8
  property int lockClockSize: 18
  property int lockDateSize: 14
  // How wide the password field is, as a fraction of the monitor.
  property real lockFieldWidth: 0.20
  // Which output carries the lock's clock and widgets. Empty for the first
  // screen there is — again, not a particular monitor's name, which is the
  // most machine-specific thing a default could be.
  property string lockWidgetMonitor: ""

  // ── time and weather ──────────────────────────────────────────────────
  property bool clock24h: true
  // A second hand is a second of work every second — the clock re-renders at
  // 1Hz instead of once a minute — so it is off unless asked for.
  property bool clockSeconds: false
  property bool weatherFahrenheit: false
  property int weatherRefreshMins: 15
  // Off, nothing is fetched and nothing is geolocated — the forecast pane says
  // it is switched off rather than sitting empty and blaming the network.
  property bool weatherEnabled: true
  // How stale a forecast may get before opening the pane re-fetches it.
  property int weatherStaleMins: 10

  // ── what the machine is doing ─────────────────────────────────────────
  // Sysmon feeds both the bar's meters and zeus' graphs from one set of
  // samples, so this is the rate for both.
  property int sysmonInterval: 1000
  property int sysmonNetInterval: 3000
  // how many samples the graphs keep. Two minutes at 1Hz.
  property int sysmonSpan: 120
  property int updateCheckMins: 60
  property bool updateNotify: true
  // which of zeus' four views it lands on when opened without being told
  property string zeusDefaultView: "graphs"
  // How often the kill list re-reads the process table while it is open.
  // Nothing polls when it is not.
  property int zeusProcInterval: 2500

  // ── the desktop menu ──────────────────────────────────────────────────
  property bool menuShowFiles: true
  property bool menuShowApps: true
  property bool menuShowHome: true
  property bool menuShowRecent: true
  property int menuRecentCount: 12
  property bool menuShowTrash: true
  property bool menuShowBackground: true
  property int menuWidth: 220
  property int menuRowHeight: 30

  // ── how the panel describes itself ────────────────────────────────────
  // The order here is the order the sidebar reads, and it is deliberate: the
  // things you look at all day first, the things you set once at the end.
  readonly property var sections: [
    // FIRST, because it is the one that reaches everything else. Three of
    // these used to sit under Bar — the corner radius, the maximum width and
    // the screen clearance — which was where the code that reads them lives
    // rather than where they apply: every layer in the shell takes all three
    // through Zenon, not just the pill.
    { id: "look",   label: "Global",        icon: "\uF0AC",
      blurb: "what every component shares \u2014 the type, the corners, the surfaces" },
    { id: "bar",    label: "Bar",           icon: "",
      blurb: "morpheus — the pill and what it carries" },
    { id: "motion", label: "Motion",        icon: "",
      blurb: "how long everything in this shell takes" },
    { id: "notify", label: "Notifications", icon: "",
      blurb: "howler — toasts, and what the bell remembers" },
    { id: "paper",  label: "Background",    icon: "",
      blurb: "picasso — the background on every monitor" },
    { id: "idle",   label: "Idle & Lock",   icon: "",
      blurb: "socordia and cerberus — being away from the machine" },
    { id: "time",   label: "Time & Weather", icon: "",
      blurb: "chronos — the clock, the calendar, the forecast" },
    { id: "system", label: "System",        icon: "",
      blurb: "zeus and the update count — what is measured, how often" },
    { id: "menu",   label: "Desktop Menu",  icon: "",
      blurb: "icarus — what right-clicking the desktop offers" },
    { id: "about",  label: "About",         icon: "",
      blurb: "zenworks — this shell, and the whole of these settings" }
  ]

  // ── THE MARK ──────────────────────────────────────────────────────────
  // The banner at the head of every file in this shell, which spells
  // "zenworks" in box-drawing characters. It is written here as escapes and
  // not as the characters themselves for a practical reason: every tool that
  // has touched this repository — editors, heredocs, terminals — has at some
  // point mangled a pasted box-drawing or private-use glyph, and an escape
  // sequence is seven ASCII characters that cannot be mangled by any of them.
  //
  // Three lines of exactly 24 columns, so it MUST be set in a monospace face
  // and not the propo one the rest of the panel uses — the whole figure is
  // built out of the grid lining up.
  readonly property var mark: [
    "\u250C\u2500\u2510\u250C\u2500\u2510\u250C\u2510\u250C\u252C \u252C\u250C\u2500\u2510\u252C\u2500\u2510\u252C\u250C\u2500\u250C\u2500\u2510",
    "\u250C\u2500\u2518\u251C\u2524 \u2502\u2502\u2502\u2502\u2502\u2502\u2502 \u2502\u251C\u252C\u2518\u251C\u2534\u2510\u2514\u2500\u2510",
    "\u2514\u2500\u2518\u2514\u2500\u2518\u2518\u2514\u2518\u2514\u2534\u2518\u2514\u2500\u2518\u2534\u2514\u2500\u2534 \u2534\u2514\u2500\u2518"
  ]

  // Every setting, described. `fallback` is filled in at startup from the
  // property's own declared value — see buildSchema.
  readonly property var specs: [
    // ── bar ──
    { key: "barPosition", section: "bar", label: "Position", type: "enum",
      options: [ { value: "bottom", label: "Bottom" },
                 { value: "top",    label: "Top" } ],
      help: "Which edge the pill lives on. Every layer that opens out of it follows, and so do the toasts and the tooltips." },
    { key: "barMonitor", section: "bar", label: "Monitor", type: "enum",
      optionsFrom: "screens", open: true,
      help: "Which output the pill lives on. Automatic follows $QS_STATUS_SCREEN, then the first screen there is." },
    { key: "barSlot", section: "bar", label: "Row height", type: "int",
      min: 24, max: 48, step: 1, unit: "px",
      help: "The slot every bar module stands in." },
    { key: "barTextSize", section: "bar", label: "Text size", type: "int",
      min: 12, max: 26, step: 1, unit: "px",
      help: "The bar's own type size, read through BarText." },
    { key: "barGap", section: "bar", label: "Module spacing", type: "int",
      min: 0, max: 20, step: 1, unit: "px",
      help: "The space between two neighbouring modules." },
    { key: "barPadBar", section: "bar", label: "End caps", type: "int",
      min: 0, max: 32, step: 1, unit: "px",
      help: "How far the first and last module sit in from the pill's ends." },
    { key: "barPadModule", section: "bar", label: "Module padding", type: "int",
      min: 0, max: 16, step: 1, unit: "px",
      help: "A module's own breathing room inside its slot." },
    { key: "barWindowGap", section: "bar", label: "Gap to windows", type: "int",
      min: 0, max: 64, step: 1, unit: "px",
      help: "Extra room kept clear above the pill, on top of its own height. Nothing happens here if the bar is not reserving space." },
    { key: "barBlur", section: "bar", alias: "blur transparency frosted glass background hyprland",
      label: "Blur behind", type: "bool",
      help: "Keeps the desktop behind the pill frosted as you make it see-through. hyprland will not blur under a pixel below alpha 0.5, and Bar opacity starts at exactly that — so without this, every step towards transparent hands the blur back and the desktop reads through sharp. The cost is the floor itself: with this on, Bar opacity under 0.52 has nowhere further to go." },
    { key: "showUpdates", section: "bar", label: "Pending updates", type: "bool",
      help: "The count of packages waiting, at the far left." },
    { key: "showNotifications", section: "bar", label: "Notification bell", type: "bool",
      help: "The unread count, which opens howler." },
    { key: "showWorkspaces", section: "bar", label: "Workspaces", type: "bool",
      help: "The workspace row, and the system tray hidden behind it." },
    { key: "showClock", section: "bar", label: "Clock", type: "bool",
      help: "The seven-segment clock, which opens the calendar." },
    { key: "showNetwork", section: "bar", label: "Network meter", type: "bool",
      help: "Throughput up and down." },
    { key: "showGpu", section: "bar", label: "GPU meter", type: "bool" },
    { key: "showCpu", section: "bar", label: "CPU meter", type: "bool" },
    { key: "showMemory", section: "bar", label: "Memory meter", type: "bool" },
    { key: "showVolume", section: "bar", label: "Volume", type: "bool" },
    { key: "showNowPlaying", section: "bar", label: "Now playing", type: "bool",
      help: "The track name, and the green wash the pill takes on with it." },
    { key: "showStatus", section: "bar", label: "Microphone & recording", type: "bool",
      help: "The privacy indicators at the right end." },
    { key: "barTooltips", section: "bar", label: "Hover tooltips", type: "bool",
      help: "The hover text on the bar's modules." },
    { key: "showTray", section: "bar", label: "System tray", type: "bool",
      help: "Hidden inside the workspace row until you hover it. Off, tray applications keep running with nowhere to appear." },
    { key: "barReserveSpace", section: "bar", label: "Reserve space", type: "bool",
      help: "Keep tiled windows clear of the pill. Off, it floats over them and nothing on the desktop moves for it." },

    // ── appearance ──
    { key: "fontFamily", section: "look", label: "Font", type: "text",
      placeholder: "JetBrainsMono Nerd Font",
      help: "The Nerd Font family, without the Propo/Mono suffix — the shell picks the right cut per use. It must be a Nerd Font: every icon here is a glyph in one." },
    { key: "barRadius", section: "look", label: "Corner radius", type: "int",
      min: 0, max: 20, step: 1, unit: "px",
      help: "The pill, and every panel that opens out of it." },
    { key: "barMaxWidth", section: "look", label: "Maximum panel width", type: "int",
      min: 400, max: 2400, step: 20, unit: "px",
      help: "How wide any panel may grow. Always rounded down to an even number, so centring it lands on a whole pixel." },
    { key: "barScreenPad", section: "look", label: "Gap to screen edge", type: "int",
      min: 0, max: 48, step: 1, unit: "px",
      help: "How far the pill floats off whichever edge it lives on. Every layer that opens out of it follows, or they would not line up with it." },
    { key: "menuRadius", section: "look", label: "Menu corner radius", type: "int",
      min: 0, max: 16, step: 1, unit: "px",
      help: "Every menu on the desktop: icarus', the tray's, terminus' right-click menu, and the cards picasso and this panel open. Separate from the panels' radius — a small card over your work wants a different corner from a large surface at an edge." },
    { key: "barOpacity", section: "look", alias: "transparency translucency see-through morpheus pill bar background", label: "Bar opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The morpheus pill's own background, and the small furniture painted to match it: tooltips, the now-playing card, chronos' day cells. Alpha over black, so lower is more transparent. Under 0.5 hyprland stops blurring behind the pill — unless Blur behind, in morpheus, is holding it at that floor." },
    { key: "panelOpacity", section: "look", alias: "transparency translucency see-through panel layer background", label: "Panel opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The ground every layer that opens out of the pill is painted on. Alpha over black, so lower is more transparent." },
    { key: "menuOpacity", section: "look", alias: "transparency translucency see-through menu background", label: "Menu opacity", type: "real",
      min: 0.3, max: 1, step: 0.05,
      help: "The ground under the rows of every menu that opens on the DESKTOP — icarus', the tray's, picasso's, and the dropdowns in here. Alpha over black, so lower is more transparent, and hyprland frosts the wallpaper behind it. Terminus' right-click menu is solid whatever this says: it opens inside a window, so what is behind it is terminus' own rows, and nothing the compositor does can frost those." },
    { key: "shadowStrength", section: "look", label: "Shadow", type: "real",
      alias: "elevation depth lift drop shadow menu panel",
      min: 0, max: 0.48, step: 0.01,
      help: "How dark every shadow on this desktop is — panels, menus, terminus' dialogs, all of them. Alpha over black, and it stops at 0.48 deliberately: hyprland will not blur under a pixel below 0.5, so a shadow above that line is the one part of a surface the compositor blurs behind, which reads as a frosted ring around anything too transparent to be blurred itself. Under the line a shadow is free at any size — which is why this is capped and the spread is not." },
    { key: "motionScale", section: "motion", label: "Animation speed", type: "real",
      min: 0, max: 2.5, step: 0.05, unit: "x",
      help: "Multiplies every duration in the shell. Zero means no animation at all." },
    { key: "arrivalEnabled", section: "motion", label: "Play the arrival", type: "bool",
      help: "The pill's slide and the background's zoom, once, when the session starts." },
    { key: "arrivalDuration", section: "motion", label: "Arrival length", type: "int",
      min: 150, max: 2000, step: 50, unit: "ms" },
    { key: "arrivalDeadline", section: "motion", label: "Arrival deadline", type: "int",
      min: 0, max: 5000, step: 100, unit: "ms",
      help: "How long after launch the arrival aims to land. A deadline, not a wait." },

    // ── notifications ──
    { key: "notifTimeout", section: "notify", label: "Timeout", type: "int",
      min: 0, max: 30000, step: 500, unit: "ms",
      help: "How long an ordinary notification stays up when it names no timeout of its own." },
    { key: "notifTimeoutLow", section: "notify", label: "Low urgency timeout", type: "int",
      min: 0, max: 30000, step: 500, unit: "ms" },
    { key: "notifCriticalSticky", section: "notify", label: "Critical stays up", type: "bool",
      help: "A critical notification never expires on its own and waits to be dismissed." },
    { key: "notifMaxVisible", section: "notify", label: "Toasts on screen", type: "int",
      min: 1, max: 10, step: 1,
      help: "How many stack above the pill before the rest wait their turn." },
    { key: "notifIcons", section: "notify", label: "Show icons", type: "bool",
      help: "An app's icon, or the album art a music notification carries." },
    { key: "notifIconSize", section: "notify", label: "Icon size", type: "int",
      min: 24, max: 128, step: 4, unit: "px" },
    { key: "notifWidth", section: "notify", label: "Minimum width", type: "int",
      min: 200, max: 900, step: 20, unit: "px",
      help: "A toast grows with its text from here." },
    { key: "notifMaxWidth", section: "notify", label: "Maximum width", type: "int",
      min: 300, max: 1600, step: 20, unit: "px" },
    { key: "notifLift", section: "notify", label: "Gap above the pill", type: "int",
      min: 0, max: 120, step: 2, unit: "px" },
    { key: "notifTrackMusic", section: "notify", label: "Keep track changes", type: "bool",
      help: "Whether a music player's notifications earn a row in the bell's history." },
    { key: "notifHistoryCap", section: "notify", label: "History kept", type: "int",
      min: 10, max: 1000, step: 10,
      help: "How many notifications the bell remembers across restarts." },
    { key: "notifFontSize", section: "notify", label: "Text size", type: "int",
      min: 10, max: 28, step: 1, unit: "px" },
    { key: "notifTextAlign", section: "notify", label: "Text alignment", type: "enum",
      options: [ { value: "left",   label: "Left" },
                 { value: "centre", label: "Centre" },
                 { value: "right",  label: "Right" } ] },
    { key: "notifRadius", section: "notify", label: "Corner radius", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifPadding", section: "notify", label: "Padding", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifSpacing", section: "notify", label: "Gap between toasts", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifBorderSize", section: "notify", label: "Border", type: "int",
      min: 0, max: 6, step: 1, unit: "px" },
    { key: "notifIconRadius", section: "notify", label: "Icon corner radius", type: "int",
      min: 0, max: 40, step: 1, unit: "px" },
    { key: "notifMarkup", section: "notify", label: "Honour markup", type: "bool",
      help: "Whether an application's bold and italic are rendered, or shown as the characters they are." },
    { key: "notifPosition", section: "notify", label: "Position", type: "enum",
      // drawn as a six-cell grid with the chosen corner lit — see the
      // EnumControl, which renders `pictogram` specs itself
      pictogram: "corner",
      options: [ { value: "auto",          label: "Follow bar" },
                 { value: "top-left",      label: "Top left" },
                 { value: "top-centre",    label: "Top" },
                 { value: "top-right",     label: "Top right" },
                 { value: "bottom-left",   label: "Bottom left" },
                 { value: "bottom-centre", label: "Bottom" },
                 { value: "bottom-right",  label: "Bottom right" } ],
      help: "Which corner of the screen the toasts stack in. Follow bar puts them on whichever edge the pill is on." },
    { key: "notifMaxHeight", section: "notify", label: "Maximum height", type: "int",
      min: 80, max: 900, step: 20, unit: "px",
      help: "A ceiling per toast, not a height — a short one stays short." },
    { key: "notifMinHeight", section: "notify", label: "Minimum height", type: "int",
      min: 24, max: 200, step: 4, unit: "px",
      help: "So a one-word notification still reads as a panel rather than as a strip." },

    // ── background ──
    { key: "backgroundDir", section: "paper", label: "Folder", type: "text",
      placeholder: "your pictures folder, then /Wallpapers",
      help: "Where picasso looks for backgrounds. Rescanned when this changes. Empty asks XDG for your pictures directory." },
    { key: "backgroundFit", section: "paper", label: "Fit", type: "enum",
      options: [ { value: "crop",    label: "Crop" },
                 { value: "fit",     label: "Fit" },
                 { value: "stretch", label: "Stretch" },
                 { value: "pad",     label: "Centre" },
                 { value: "tile",    label: "Tile" } ],
      help: "How an image that is not the monitor's shape is made to fit it. The default — a monitor given its own fit in the picker keeps that one." },
    { key: "backgroundZoom", section: "paper", label: "Overscan", type: "real",
      min: 1.0, max: 1.4, step: 0.01, unit: "x",
      help: "How far past the screen the image is drawn — the room the arrival's zoom moves in." },

    // ── idle & lock ──
    { key: "idleEnabled", section: "idle", label: "Idle timers", type: "bool",
      help: "Off, nothing happens however long you are away. The lock still works by hand." },
    { key: "idleLockSecs", section: "idle", label: "Lock after", type: "int",
      min: 0, max: 3600, step: 30, unit: "s" },
    { key: "idleScreenOffSecs", section: "idle", label: "Screens off after", type: "int",
      min: 0, max: 7200, step: 30, unit: "s" },
    { key: "idleKeyboardSecs", section: "idle", label: "Keyboard backlight off after", type: "int",
      min: 0, max: 3600, step: 30, unit: "s" },
    { key: "idleKeyboardName", section: "idle", label: "Keyboard", type: "text",
      placeholder: "no keyboard — the backlight is left alone",
      help: "The solaar device name whose backlight is dimmed, as `solaar config` spells it." },
    { key: "idleInhibitPlayback", section: "idle", label: "Stay awake while playing", type: "bool",
      help: "Anything playing audio, holding an idle inhibitor, or publishing a media session holds the timers off." },
    { key: "lockHideCursor", section: "idle", label: "Hide the cursor", type: "bool",
      help: "On the lock screen." },
    { key: "lockShade", section: "idle", label: "Lock dimming", type: "real",
      min: 0, max: 1, step: 0.05,
      help: "How far the blurred desktop is darkened behind the lock." },
    { key: "lockFailLimit", section: "idle", label: "Attempts before lockout", type: "int",
      min: 1, max: 20, step: 1 },
    { key: "lockWidgetMonitor", section: "idle", label: "Lock screen monitor",
      type: "enum", optionsFrom: "screens", open: true,
      help: "Which output carries the clock and the password field. Automatic uses the first screen there is." },
    { key: "lockBlurStrength", section: "idle", label: "Lock blur", type: "int",
      min: 1, max: 40, step: 1, unit: "%",
      help: "The desktop is shrunk to this, blurred, and blown back up — once, at lock time. Smaller is blurrier." },
    { key: "lockClockSize", section: "idle", label: "Lock clock size", type: "int",
      min: 8, max: 48, step: 1, unit: "pt" },
    { key: "lockDateSize", section: "idle", label: "Lock date size", type: "int",
      min: 6, max: 36, step: 1, unit: "pt" },
    { key: "lockFieldWidth", section: "idle", label: "Password field width", type: "real",
      min: 0.1, max: 0.6, step: 0.01,
      help: "As a fraction of the monitor's width. It never goes below 240px whatever this says." },

    // ── time & weather ──
    { key: "clock24h", section: "time", label: "24-hour clock", type: "bool" },
    { key: "clockSeconds", section: "time", label: "Show seconds", type: "bool",
      help: "The clock then repaints once a second rather than once a minute." },
    { key: "weatherFahrenheit", section: "time", label: "Fahrenheit", type: "bool",
      help: "Every temperature chronos shows, in °F instead of °C." },
    { key: "weatherEnabled", section: "time", label: "Fetch the forecast", type: "bool",
      help: "Off, nothing is fetched and nothing is geolocated." },
    { key: "weatherRefreshMins", section: "time", label: "Forecast refresh", type: "int",
      min: 5, max: 180, step: 5, unit: "min" },
    { key: "weatherStaleMins", section: "time", label: "Refetch when older than", type: "int",
      min: 1, max: 120, step: 1, unit: "min",
      help: "Opening the forecast re-fetches it if what is cached is older than this." },

    // ── system ──
    { key: "sysmonInterval", section: "system", label: "Sample rate", type: "int",
      min: 250, max: 5000, step: 250, unit: "ms",
      help: "How often CPU, GPU, memory and disk are read. The bar's meters and zeus' graphs share these samples." },
    { key: "sysmonNetInterval", section: "system", label: "Interface check", type: "int",
      min: 1000, max: 30000, step: 500, unit: "ms",
      help: "How often the network interface and address are re-read. Throughput is sampled at the rate above." },
    { key: "sysmonSpan", section: "system", label: "Graph history", type: "int",
      min: 30, max: 600, step: 10,
      help: "How many samples zeus' graphs keep." },
    { key: "updateCheckMins", section: "system", label: "Check for updates", type: "int",
      min: 5, max: 1440, step: 5, unit: "min" },
    { key: "updateNotify", section: "system", label: "Announce updates", type: "bool",
      help: "A toast the first time a new set of pending updates appears." },
    { key: "zeusProcInterval", section: "system", label: "Process list refresh", type: "int",
      min: 500, max: 15000, step: 250, unit: "ms",
      help: "How often the kill list re-reads the process table while it is open. Nothing polls when it is not." },
    { key: "zeusDefaultView", section: "system", label: "Zeus opens on", type: "enum",
      options: [ { value: "graphs", label: "Graphs" },
                 { value: "list",   label: "Processes" },
                 { value: "net",    label: "Connections" },
                 { value: "sound",  label: "Sound" } ],
      help: "Which view the system panel lands on when opened without being told. Clicking a meter still goes to what that meter is about." },

    // ── desktop menu ──
    { key: "menuWidth", section: "menu", label: "Menu width", type: "int",
      min: 160, max: 400, step: 10, unit: "px",
      help: "The desktop menu's cards and every submenu that hangs off them, and the tray menu. Terminus' right-click menu measures itself against its own rows instead, because its entries carry key hints." },
    { key: "menuRowHeight", section: "menu", label: "Row height", type: "int",
      min: 22, max: 48, step: 1, unit: "px",
      help: "Every row in every menu — icarus', the tray's, terminus' right-click menu, and the cards picasso and this panel open." },
    { key: "menuShowFiles", section: "menu", label: "Files", type: "bool",
      help: "Opens terminus at the directory the desktop is showing." },
    { key: "menuShowApps", section: "menu", label: "Apps", type: "bool" },
    { key: "menuShowHome", section: "menu", label: "Home", type: "bool",
      help: "Browse the filesystem from inside the menu." },
    { key: "menuShowRecent", section: "menu", label: "Recent places", type: "bool",
      help: "What artemis has learned you open, as a submenu." },
    { key: "menuRecentCount", section: "menu", label: "Recent places shown", type: "int",
      min: 3, max: 24, step: 1 },
    { key: "menuShowTrash", section: "menu", label: "Trash", type: "bool" },
    { key: "menuShowBackground", section: "menu", label: "Set background", type: "bool" },

    // ── oracle itself ──
    // A READOUT, not a setting. "Where does this end up" is the first thing
    // anyone asks of a settings panel, and the answer was only discoverable by
    // reading the source — so the panel says it. `info` rows hold nothing, are
    // never written, and never count as changed; see Ora.stored.
    { key: "infoStatePath", section: "about", label: "Kept in", type: "info",
      // a path identifies itself by its END, so this one elides from the left
      elideLeft: true,
      help: "Only the settings you have changed are written. Delete this file and everything is back to its defaults." },
    // The names three of the settings above ask you to type. Having to run
    // hyprctl to find out what your own outputs are called, in order to fill
    // in a field in a settings panel, is the panel's failure rather than
    // yours.
    { key: "infoOutputs", section: "about", label: "Outputs", type: "info",
      help: "What to put in the monitor fields under Bar and Idle & Lock." },
    { key: "infoLaunched", section: "about", label: "Running since", type: "info",
      help: "When this shell last started." },
    { key: "actionReload", section: "about", label: "Reload from disk", type: "action",
      verb: "Reload",
      help: "Re-read oracle.json. Useful after editing it by hand." },
    // `context: true` — this one acts on the section you came here FROM, and
    // says which on its own button rather than making you remember. See
    // ActionControl, which is where that name is appended.
    { key: "actionResetSection", section: "about", label: "Reset one section",
      type: "action", verb: "Reset", context: true,
      help: "Put every setting in the section you were last in back to its default." },
    { key: "actionResetAll", section: "about", label: "Reset everything", type: "action",
      verb: "Reset all",
      help: "Every setting in every section back to its default." },
    { key: "actionRestart", section: "about", label: "Restart the shell", type: "action",
      verb: "Restart",
      help: "For the few settings that only take effect on a fresh start." }
  ]

  // ── THE OUTPUTS, AS THEY ARE RIGHT NOW ───────────────────────────────
  // Three settings name a monitor, and until now all three were text fields
  // you had to type a name into — having first gone and found out what your
  // own outputs are called. This is that list, live: it follows monitors
  // being plugged in and out, so it can never be a set of names written down
  // by somebody with a different desk.
  //
  // "" first, meaning let the shell decide. It is the default for all three
  // and the only one that is correct on every machine.
  readonly property var screenOptions: {
    const out = [{ value: "", label: "Automatic" }];
    const sc = Quickshell.screens;
    for (let i = 0; i < sc.length; ++i)
      out.push({ value: sc[i].name, label: sc[i].name });
    return out;
  }

  // specs with each one's default folded in, which is what the panel reads.
  // Built once at startup rather than declared, because the defaults come from
  // the properties above and cannot be known before they exist.
  property var schema: []

  // key -> the value the property was declared with
  property var defaults: ({})

  // Rebuilt whenever the live options change, which is why the DEFAULTS are
  // captured only once. Re-reading them here on a later pass would take
  // whatever the settings currently are as their defaults — so plugging in a
  // monitor would quietly redefine "default" as "whatever you have set", and
  // every reset after that would be a no-op.
  property bool defaultsTaken: false

  function buildSchema() {
    const d = root.defaultsTaken ? root.defaults : ({});
    const out = [];
    for (let i = 0; i < root.specs.length; ++i) {
      const s = root.specs[i];
      // a shallow copy, so `specs` stays exactly what was written above and
      // the panel never edits the description it is drawing from
      const c = ({});
      for (const k in s) c[k] = s[k];
      // a list that is a fact about this machine rather than about this shell
      if (s.optionsFrom === "screens") c.options = root.screenOptions;
      if (Ora.stored(s)) {
        if (!root.defaultsTaken) d[s.key] = root[s.key];
        c.fallback = d[s.key];
      }
      out.push(c);
    }
    root.defaults = d;
    root.defaultsTaken = true;
    root.schema = out;
  }

  // a monitor came or went; the pickers have to say so
  onScreenOptionsChanged: if (root.defaultsTaken) root.buildSchema();

  // "auto" resolved against where the bar actually is. Oracle cannot import
  // Zenon — Zenon imports Oracle — so the caller passes in what it knows.
  function notifCorner(barAtTop) {
    const p = root.notifPosition;
    if (p === "auto") return (barAtTop ? "top" : "bottom") + "-centre";
    return p;
  }

  // What a read-only row shows. Not a property, because these are facts about
  // the running shell rather than settings — there is nothing to store, reset
  // or compare, and giving them a property would have put them in the file.
  function info(key) {
    if (key === "infoStatePath") return root.statePath;
    if (key === "infoOutputs") {
      const sc = Quickshell.screens;
      const out = [];
      for (let i = 0; i < sc.length; ++i)
        out.push(sc[i].name + " " + sc[i].width + "\u00d7" + sc[i].height);
      return out.length ? out.join("   ") : "none";
    }
    if (key === "infoLaunched") {
      const d = Quickshell.launchTime;
      return d ? Qt.formatDateTime(d, "ddd d MMM, HH:mm") : "";
    }
    return "";
  }

  function spec(key) {
    for (let i = 0; i < root.schema.length; ++i)
      if (root.schema[i].key === key) return root.schema[i];
    return null;
  }

  // The panel's read. A function rather than a binding for the obvious reason
  // — the key is not known until the row exists — which is what `revision` is
  // for on the other side.
  function get(key) {
    return root[key];
  }

  function set(key, value) {
    const s = root.spec(key);
    if (!s || !Ora.stored(s)) return;
    const v = Ora.coerce(s, value);
    if (Ora.same(root[key], v)) return;
    root[key] = v;
    root.revision++;
    root.settingChanged(key);
    saveTimer.restart();
  }

  function nudge(key, dir) {
    const s = root.spec(key);
    if (!s) return;
    root.set(key, Ora.nudge(s, root[key], dir));
  }

  function isDefault(key) {
    return Ora.same(root[key], root.defaults[key]);
  }

  function reset(key) {
    if (key in root.defaults) root.set(key, root.defaults[key]);
  }

  function resetSection(section) {
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (!Ora.stored(s) || s.section !== section) continue;
      root.reset(s.key);
    }
  }

  function resetAll() {
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s)) root.reset(s.key);
    }
  }

  // How many settings in a section are no longer at their default. The sidebar
  // shows this, so a section that has been changed says so unopened.
  function changedIn(section) {
    const vals = ({});
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s)) vals[s.key] = root[s.key];
    }
    return Ora.changedIn(root.schema, vals, root.defaults, section);
  }

  // ── the actions ───────────────────────────────────────────────────────
  // `context` is whatever the panel was standing in when the row was clicked,
  // so "reset a section" can mean the one you are looking at without the
  // action needing a second control beside it.
  function run(key, context) {
    if (key === "actionReload") { root.reloadFromDisk(); return; }
    if (key === "actionResetSection") { root.resetSection(context); return; }
    if (key === "actionResetAll") { root.resetAll(); return; }
    if (key === "actionRestart") {
      // `qs kill` then `qs -d`, in a shell that has already been detached, so
      // the replacement is never a child of the instance it replaces. The same
      // line icarus' session menu uses.
      Quickshell.execDetached(["sh", "-c", "qs kill; sleep 0.4; qs -d"]);
      return;
    }
  }

  // ── persistence ───────────────────────────────────────────────────────
  // The same FileView + debounced setText shape chronos, picasso and artemis
  // use. blockLoading, because the first frame of the shell is drawn from
  // these values and a bar that arrives at its defaults and then jumps to
  // yours a frame later is worse than a few milliseconds at startup.
  readonly property string statePath: Quickshell.statePath("oracle.json")

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    printErrors: false
    // RELOAD IS ASYNCHRONOUS, and blockLoading does not change that — it
    // governs the FIRST read, not a later reload. The first version of the
    // reload action called reload() and then load() on the very next line,
    // which read the text that was already there: editing the file by hand and
    // pressing Reload did nothing at all, silently and repeatably. Measured by
    // writing the file from a subprocess and watching the values not move.
    //
    // So the apply happens HERE, when the bytes have actually arrived, and the
    // action below only asks for them.
    onLoaded: {
      if (!root._reloadWanted) return;
      root._reloadWanted = false;
      // A hand-edited file can have LOST a key as well as gained one, and
      // load() only applies what it finds — a setting deleted by hand would
      // otherwise keep whatever it currently held, which is not what the file
      // now says. Cleared first, so "reload" means the file and nothing else.
      root.resetAll();
      root.load();
    }
  }

  // Set while a reload is in flight, so onLoaded can tell one apart from the
  // read that happens at startup and from the reads our own setText provokes.
  property bool _reloadWanted: false

  function reloadFromDisk() {
    root._reloadWanted = true;
    stateFile.reload();
  }

  Timer {
    id: saveTimer
    // A slider dragged across its range is a burst of sets; this writes once
    // at the end of the gesture rather than on every pixel of it.
    interval: 400
    onTriggered: root.save()
  }

  function save() {
    const vals = ({});
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s)) vals[s.key] = root[s.key];
    }
    stateFile.setText(Ora.serialize(root.schema, vals, root.defaults));
  }

  // Applies the file over whatever is currently held. It is not a full
  // restore on its own — see actionReload, which clears first — because at
  // startup there is nothing to clear and a reset pass would write the file
  // back out for no reason.
  function load() {
    const j = Ora.parse(root.schema, stateFile.text());
    for (const k in j) {
      if (Ora.same(root[k], j[k])) continue;
      root[k] = j[k];
      root.settingChanged(k);
    }
    root.revision++;
  }

  // The STORE's ipc. The panel has its own handler under "Oracle", so that
  // `qs ipc call Oracle toggle` reads the way it does for every other layer in
  // this shell; this one is the half a script talks to.
  IpcHandler {
    target: "OracleSettings"

    // `qs ipc call OracleSettings get notifTimeout`, for a script that wants
    // to read one without parsing the file.
    function get(key: string): string {
      const s = root.spec(key);
      if (!s) return "no such setting: " + key;
      if (!Ora.stored(s)) return root.info(key);
      return String(root[key]);
    }

    // and the write, which takes the same coercion every other path does — so
    // `set barRadius 999` lands at the slider's own maximum rather than at 999.
    function set(key: string, value: string): string {
      const s = root.spec(key);
      if (!s || !Ora.stored(s)) return "no such setting: " + key;
      root.set(key, s.type === "bool"
        ? (value === "1" || value.toLowerCase() === "true" || value.toLowerCase() === "on")
        : (s.type === "int" || s.type === "real") ? Number(value) : value);
      return key + " = " + String(root[key]);
    }

    function reset(key: string): string {
      if (key === "" || key === "all") { root.resetAll(); return "reset everything"; }
      root.reset(key);
      return key + " = " + String(root[key]);
    }

    // every setting that is not at its default, one per line
    function changed(): string {
      const out = [];
      for (let i = 0; i < root.schema.length; ++i) {
        const s = root.schema[i];
        if (!Ora.stored(s) || root.isDefault(s.key)) continue;
        out.push(s.key + " = " + String(root[s.key])
          + "  (default " + String(root.defaults[s.key]) + ")");
      }
      return out.length === 0 ? "everything is at its default" : out.join("\n");
    }
  }

  // buildSchema BEFORE load, and load before anything else has had a chance to
  // write: the defaults are the properties as declared, so they have to be
  // read while that is still what they are.
  Component.onCompleted: {
    root.buildSchema();
    root.load();
  }
}
