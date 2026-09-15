// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOWLER — the notification daemon, and the only thing in this shell that
// talks to the freedesktop server. The toasts, the OSD and the bell's panel
// all read this; none of them owns a notification.
//
// WHAT LIVES WHERE. `live` is the server's own list — what is on screen right
// now, and what a dismiss acts on. `history` is a plain array of rows written
// to disk, which outlives both the notification and the session. They are
// deliberately different shapes: a Notification is an object owned by the
// server with methods and a lifetime, and a row is a fact about something
// that happened.
//
// THE PRESENTATION CONSTANTS ARE MAKO'S, ported one for one when this
// replaced it, and every one of them now reads out of oracle — so a setting
// is a binding away from the next toast rather than an edit and a reload.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import "../oracle"
import "../morpheus"
import "howler.js" as Wolf

Singleton {
  id: root

  // ── what is on screen ───────────────────────────────────────────────────
  readonly property var live: server.trackedNotifications

  // ── what is remembered ──────────────────────────────────────────────────
  // Newest first, so the panel draws it in the order it reads and the cap
  // takes from the end. Rows are plain objects — see Wolf.serialize for what
  // is allowed to be in one.
  property var history: []
  // Since the last time the panel was opened. The bell reads this.
  property int unread: 0

  // ── WHAT THIS SHELL SAYS TO ITSELF ──────────────────────────────────────
  // The app name morpheus' UpdateModule announces under — see its notify-send
  // call, which passes exactly this to -a. Named here rather than matched
  // inline so the two ends of the arrangement can be found from either side.
  readonly property string selfUpdateApp: "waybar-updates"

  // ── mako's config, as settings ──────────────────────────────────────────
  readonly property int maxVisible:   Oracle.notifMaxVisible
  readonly property bool iconsEnabled: Oracle.notifIcons
  readonly property int iconSize:     Oracle.notifIconSize
  readonly property int iconRadius:   Oracle.notifIconRadius
  readonly property int radius:       Oracle.notifRadius
  readonly property int padding:      Oracle.notifPadding
  // THE SIDES GET TWICE THE TOP. A card is wider than it is tall and a
  // gutter that reads as generous above a line of text reads as none at
  // all beside it — the bar's own tooltip is 20 and 10 for the same
  // reason. One knob still, doubled where it is spent horizontally.
  readonly property int hPadding:     Oracle.notifPadding * 2
  // AND THE PICTURE GETS HALF. Text needs air around it to stay off a
  // border; a picture has its own edge and only wants to be inside one.
  readonly property int iconPadding:  Math.round(Oracle.notifPadding / 2)
  readonly property int glowReach:    Oracle.notifGlowReach
  readonly property bool glowOn:      Oracle.notifGlow

  // ── A NAME OUT OF ORACLE, A COLOUR OUT OF ZENON ────────────────────────
  // Oracle offers the palette by name because it cannot import Zenon; this is
  // the other half of that. An unknown name falls back to white rather than
  // to nothing — a toast drawn in "transparent" would be a notification you
  // could not read, which is a worse answer than the wrong colour.
  function ink(name) {
    switch (String(name)) {
      case "white":   return Zenon.white;
      case "muted":   return Zenon.muted;
      case "surface": return Zenon.surface;
      case "red":     return Zenon.red;
      case "green":   return Zenon.green;
      case "yellow":  return Zenon.yellow;
      case "blue":    return Zenon.blue;
      case "magenta": return Zenon.magenta;
      case "cyan":    return Zenon.cyan;
      case "pink":    return Zenon.pink;
      case "sand":    return Zenon.sand;
    }
    return Zenon.white;
  }

  readonly property color accent:    Howler.ink(Oracle.notifAccent)
  readonly property color borderInk: Howler.ink(Oracle.notifBorderInk)
  readonly property color titleInk:  Howler.ink(Oracle.notifTitleInk)
  readonly property color bodyInk:   Howler.ink(Oracle.notifBodyInk)
  // Black at the chosen strength, which is what panelBgDeep was at a fixed
  // 0.70. Its own knob because a toast sits over whatever happens to be on
  // screen, which is not the job a panel has.
  readonly property color bg: Qt.rgba(0, 0, 0, Oracle.notifBgOpacity)

  // ── AND HOW IT ARRIVES ─────────────────────────────────────────────────
  // Zenon's own durations, scaled. Multiplied rather than replaced so the
  // shell's one motion setting still reaches the toasts — turn the desktop's
  // motion down and these come down with it.
  readonly property string animStyle: Oracle.notifAnimStyle
  readonly property int openMs:
    Math.max(1, Math.round(Zenon.normal * Oracle.notifAnimSpeed))
  readonly property int closeMs:
    Math.max(1, Math.round(Zenon.fast * Oracle.notifAnimSpeed))
  // Only a slide travels. The vertical throw keeps the proportion the two
  // were first tuned at — 36 against 64 — so one number moves both.
  readonly property real slideBy:
    Oracle.notifAnimStyle === "slide" ? Oracle.notifSlide : 0
  readonly property real slideByV:
    Math.round(Howler.slideBy * 0.5625)
  // Where `scale` starts from. Far enough under one to read as growth,
  // near enough that the text is never illegibly small on the way in.
  readonly property real growFrom:
    Oracle.notifAnimStyle === "scale" ? 0.88 : 1.0
  readonly property int margin:       Oracle.notifSpacing
  readonly property int borderSize:   Oracle.notifBorderSize
  readonly property int fontSize:     Oracle.notifFontSize
  readonly property int minHeight:    Oracle.notifMinHeight
  readonly property int maxHeight:    Oracle.notifMaxHeight
  readonly property int width:        Oracle.notifWidth
  readonly property int maxWidth:     Oracle.notifMaxWidth
  readonly property int lift:         Oracle.notifLift
  readonly property bool markup:      Oracle.notifMarkup

  // Named in oracle rather than numbered — "centre" is a thing a person can
  // choose, Text.AlignHCenter is a flag that happens to be 4 — so the
  // translation happens here, where Text is already in scope.
  readonly property int textAlign: {
    if (Oracle.notifTextAlign === "left") return Text.AlignLeft;
    if (Oracle.notifTextAlign === "right") return Text.AlignRight;
    return Text.AlignHCenter;
  }

  // mako's `[urgency=critical] default-timeout=0`. Off, a critical
  // notification expires on the ordinary timeout like anything else.
  function timeoutFor(urgency) {
    if (urgency === NotificationUrgency.Critical)
      return Oracle.notifCriticalSticky ? 0 : Oracle.notifTimeout;
    if (urgency === NotificationUrgency.Low) return Oracle.notifTimeoutLow;
    return Oracle.notifTimeout;
  }

  // ── WHICH NOTIFICATIONS CAME FROM A MUSIC PLAYER ───────────────────────
  // Matched against the MPRIS players actually running rather than against a
  // list of application names: the players that exist are knowable, and a
  // hardcoded list is wrong the moment somebody installs a different one.
  //
  // The answer is kept ON THE ROW, because it is a fact about the moment the
  // notification arrived — the player may well have exited by the time
  // anything reads the history back.
  function playerFor(notif) {
    const entry = String(notif.desktopEntry || "");
    const name = String(notif.appName || "").toLowerCase();
    const summary = String(notif.summary || "");
    const players = Mpris.players ? Mpris.players.values : [];
    for (let i = 0; i < players.length; ++i) {
      const p = players[i];
      if (!p) continue;
      const id = String(p.identity || "");
      // THE TRACK ITSELF IS THE MATCH, and it has to be — the client that
      // sends the notification and the one that owns the MPRIS name are
      // routinely different programs. Measured here: spoot posts the
      // notification, spotifyd holds the bus name, and no amount of comparing
      // those two names will ever agree. What they do agree on is the song.
      if (summary !== "" && String(p.trackTitle || "") === summary)
        return id !== "" ? id : name;
      if (entry !== "" && String(p.desktopEntry || "") === entry) return id;
      if (id !== "" && id.toLowerCase() === name) return id;
    }
    return "";
  }

  function rowOf(notif) {
    return {
      id: notif.id,
      time: Date.now(),
      appName: String(notif.appName || ""),
      appIcon: String(notif.appIcon || ""),
      image: String(notif.image || ""),
      summary: String(notif.summary || ""),
      body: String(notif.body || ""),
      urgency: notif.urgency,
      desktopEntry: String(notif.desktopEntry || ""),
      mprisPlayer: root.playerFor(notif)
    };
  }

  // ── the server ──────────────────────────────────────────────────────────
  NotificationServer {
    id: server
    // Survive a config reload: editing a QML file should not silently swallow
    // whatever is on screen at the time.
    keepOnReload: true
    actionsSupported: true
    actionIconsSupported: true
    bodySupported: true
    bodyMarkupSupported: true
    imageSupported: true
    persistenceSupported: true

    onNotification: (notif) => {
      // TRACKED FIRST. An untracked notification is closed the moment this
      // handler returns, so nothing downstream would ever see it.
      notif.tracked = true;
      if (!Oracle.showNotifications) { notif.dismiss(); return; }

      const row = root.rowOf(notif);
      // A track change is already spelled out in the bar, so by default it
      // toasts and is then forgotten rather than filling the bell with a
      // playlist.
      if (row.mprisPlayer !== "" && !Oracle.notifTrackMusic) return;

      // AND SO IS AN UPDATE COUNT, for the same reason and more strongly: this
      // one is not an application talking to you, it is this shell talking to
      // itself. The count is already on the bar and the full list is already
      // in its tooltip, so the bell was keeping a running tally of something
      // that is on screen anyway — and re-announcing it every time the number
      // moved, which on a rolling distribution is most days.
      //
      // It still TOASTS. The arrival is worth saying once; it is the keeping
      // that was wrong.
      if (row.appName === root.selfUpdateApp) return;

      const h = root.history.slice();
      h.unshift(row);
      while (h.length > Oracle.notifHistoryCap) h.pop();
      root.history = h;
      root.unread = root.unread + 1;
      saveTimer.restart();
      // AFTER the model has taken it. Called straight from here, trim counts
      // the list as it was a moment ago — the notification being handled is
      // not in trackedNotifications yet — so it always left one too many on
      // screen: measured 3 showing with maxVisible at 2.
      Qt.callLater(root.trim);
    }
  }

  // ── what the panels and the bar ask for ─────────────────────────────────
  // mako's max-visible, enforced where the list lives rather than by the view
  // slicing a copy. The stack can then be driven by the server's OWN model —
  // which is what makes a toast's arrival and departure animatable at all: a
  // JS array handed to a ListView is replaced wholesale on every change, and
  // a view that is reset has nothing to add or remove.
  function trim() {
    const v = root.live ? root.live.values : [];
    for (let i = 0; i < v.length - root.maxVisible; ++i)
      if (v[i]) v[i].expire();
  }

  function dismissAll() {
    // Backwards: dismissing mutates the list being walked.
    const v = root.live ? root.live.values : [];
    for (let i = v.length - 1; i >= 0; --i) if (v[i]) v[i].dismiss();
  }

  function clearHistory() {
    root.history = [];
    root.unread = 0;
    saveTimer.restart();
  }

  function markRead() { root.unread = 0; }

  // The bell's panel carries its own switch for this, because deciding that a
  // playlist should stop filling the history is a thing you decide WHILE
  // looking at a history full of playlist. The setting is oracle's; this is
  // the same setting, reachable from where the problem is.
  readonly property bool trackMusic: Oracle.notifTrackMusic
  function toggleMusicTracking() {
    Oracle.notifTrackMusic = !Oracle.notifTrackMusic;
  }

  function forget(id) {
    const h = [];
    for (let i = 0; i < root.history.length; ++i)
      if (root.history[i].id !== id) h.push(root.history[i]);
    root.history = h;
    saveTimer.restart();
  }

  // ── persistence ─────────────────────────────────────────────────────────
  // Debounced, because a burst of notifications is one write rather than one
  // per row — and the rule about which images may be written down lives in
  // Wolf, applied on the way out AND on the way back in.
  FileView {
    id: stateFile
    path: Quickshell.statePath("howler-history.json")
    blockLoading: true
    printErrors: false
    // NO onLoaded. FileView re-reads after a write, and that reload can land
    // with a snapshot older than what is in memory — which clobbers the list
    // it was supposed to be persisting. Measured: three rows saved, one row
    // left. It is read ONCE below and memory is the truth from then on, which
    // is the shape chronos uses for the same reason.
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: stateFile.setText(Wolf.serialize(root.history))
  }

  Component.onCompleted: root.history = Wolf.parse(stateFile.text())
}
