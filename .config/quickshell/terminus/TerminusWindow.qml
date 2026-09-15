// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS — the file manager. God of boundaries, and of the stones that mark
// them: a directory is a boundary, a path is a line drawn between two of them,
// and the divider down the middle of a split view is the stone itself.
//
// It was called janus while it had one pane and two faces to look at it with.
// It has two panes now, so the boundary is the point.
//
// A FloatingWindow, NOT a PanelWindow. Every other surface in this shell is
// layer-shell: it floats above the desktop, hyprland cannot tile it, and it
// owns the keyboard through a focus grab until it closes. That is right for a
// launcher you use for four seconds and wrong for a window you work in — so
// this one is an ordinary xdg-toplevel. Hyprland tiles it, floats it, moves it
// between workspaces and applies window rules to it exactly as it would to a
// terminal, because from the compositor's side there is nothing to tell them
// apart. It carries a title so a rule can find it:
//
//     windowrulev2 = float, title:^(terminus)$
//
// Consequences of not being a layer, all deliberate: no morph into the pill,
// no HyprlandFocusGrab, no edgeLift, and no entry in shell.qml's height
// switch. It opens, it sits where the compositor puts it, and it closes.

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick.Effects
import "../morpheus"
import "../picasso"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs

FloatingWindow {
  id: root

  // A DIALOG IS NOT THE FILE MANAGER, and the window rules say so:
  //
  //     windowrulev2 = float, title:^(terminus)$          1000x1000
  //     windowrulev2 = float, title:^(terminus-picker)$   1000x450
  //
  // Both windows answered to "terminus", so the picker took the file manager's
  // rule and came up square. It has its own name whenever a portal request is
  // what put it on screen — which is set before `shown`, so the title is
  // already right when the surface is mapped and the rule is applied.
  title: root.picking ? "terminus-picker" : "terminus"
  // The manager that made this window, so a window can ask for another one
  // without knowing how they are kept.
  property var mgr: null
  property int winId: 0

  // The manager reaches in through these rather than through ids. An id is
  // private to the document that declares it — `w.content` from outside is
  // undefined, and reading `.activeFocus` off undefined is what made every
  // ipc call that touched focus return nothing at all.
  function takeFocus() { content.forceActiveFocus(); }
  // Ask for the keyboard and keep asking. The right entry point for anything
  // that has just made this window visible: a bare forceActiveFocus() on that
  // frame is dropped, because the surface has not been mapped yet.
  function claimFocus() { focusClaim.restart(); }

  // The context menu, reached through the root object.
  //
  // An INLINE COMPONENT cannot see the ids of the document that declares it —
  // only the root object, which is why everything in here goes through `root`.
  // EntryRow called `menu.openAt` directly, so right-clicking a row in list or
  // columns view threw ReferenceError and no menu ever came up; the grid's own
  // tiles are written at document scope, so the same gesture worked there and
  // the two halves disagreed for no visible reason.
  //
  // The bookmark sidebar had the identical bug against `bookmarkFile`, which
  // is what made removed bookmarks come back. One wrapper per id that a
  // delegate needs, and the trap is closed.
  function openMenuAt(item, mouse) { menu.openAt(item, mouse); }

  // ── the menu key ──────────────────────────────────────────────────────
  // The keyboard's own way of asking what the right button asks, about the row
  // the CURSOR is on — which is already the row the menu acts on. `menu.target`
  // is `root.currentRow()`, never a hit test against the pointer; right-click
  // only looks like it is about the row under the mouse because clickRow()
  // moves the cursor there first. So this needs no target plumbing at all,
  // only somewhere to put the card.
  //
  // The row has to be REALISED before the view will hand back its delegate, so
  // the cursor is scrolled into view first and the placing waits a tick — the
  // same shape as positionSel's other callers.
  function openMenuAtCursor() {
    // An empty directory has no row to ask about, so ask about the directory
    // instead: the row branch of the menu returns nothing without a target,
    // and an empty card is worse than the one that has something in it.
    if (root.view.length === 0 || !root.currentRow()) {
      menu.openHere(content, { x: content.width / 2, y: content.height / 3 });
      return;
    }
    root.positionSel();
    Qt.callLater(root._placeMenuAtCursor);
  }

  function _placeMenuAtCursor() {
    const v = root.viewMode === "grid" ? root.actGrid
            : root.viewMode === "columns" ? root.midCol.view : root.actList;
    const it = v ? v.itemAtIndex(root.sel) : null;
    // From the row's bottom-left, so the card drops out of the row the way a
    // menu drops out of the thing it belongs to. menuCard clamps itself inside
    // the window, so a row near the bottom pulls it back up on its own.
    if (it) menu.openAt(it, { x: 0, y: it.height });
    // A row the view still has not built — it can refuse even after
    // positionSel if the listing changed underneath. The menu is about the
    // cursor either way, so it opens against the view rather than not at all.
    else if (v) menu.openAt(v, { x: 0, y: 0 });
  }
  function setSaveName(n) { saveField.text = n; }

  // Zenon.layerBg's colour at Zenon.layerBg's alpha, until the settings panel
  // says otherwise — see winAlpha.
  color: Qt.rgba(Zenon.layerBg.r, Zenon.layerBg.g, Zenon.layerBg.b, root.winAlpha)
  minimumSize: Qt.size(560, 320)
  // An explicit size, because nothing else supplies one. Every item inside is
  // anchored to its parent, so no implicit size propagates up from the content
  // and the surface is created 0x0 — which a compositor is free to simply not
  // show. Tiled, hyprland overrides both of these immediately; floating, they
  // are the size it opens at.
  implicitWidth: 1100
  implicitHeight: 680

  // `shown` and `visible` are kept in step BOTH WAYS, and neither is a binding.
  //
  // Two bugs live here, and the second one hid behind the first.
  //
  // Writing `visible` directly did not stick: `visible: false` on the window is
  // a constant binding, and an imperative write races whatever re-evaluates it,
  // so toggle() answered "closed" having just set it true.
  //
  // Binding it the other way — `visible: root.shown` — fixed opening but broke
  // reopening. When the COMPOSITOR closes the window it writes `visible` itself,
  // and an imperative write to a bound property destroys the binding. `shown`
  // was then stuck true against a window that was gone, so the next `shown =
  // true` changed nothing at all and no surface was ever created. That is why
  // the portal accepted a request, reported picking=true, and showed nothing.
  //
  // Handlers in both directions, with no binding to break: setting `shown`
  // shows the window, and the window being closed by anything else puts `shown`
  // back. Neither can loop, because QML does not re-emit a change that did not
  // change anything.
  property bool shown: false
  onVisibleChanged: {
    if (root.shown !== root.visible) root.shown = root.visible;
    if (root.visible) focusClaim.restart();
  }

  // ── where we are ────────────────────────────────────────────────────────
  // THE ACTIVE PANE, READ THROUGH. Every one of these used to be storage and
  // is now a window onto whichever half the keyboard is in, so the four
  // hundred places in this file that ask "where are we" go on asking exactly
  // as they did — and a Tab changes the answer without moving a byte.
  //
  // Read-only on purpose: `root.cwd = x` would silently break the binding and
  // leave the pane holding something else. The writes all go to root.act.
  readonly property string cwd: root.act.cwd
  readonly property var rows: root.act.raw
  readonly property string query: root.act.query
  property bool showHidden: true
  property string sortKey: "name"
  property bool sortDesc: false
  readonly property int sel: root.act.sel
  // path -> true. A map rather than a list so a row can ask about itself in
  // constant time while the list is being drawn.
  readonly property var marked: root.act.marked
  // what y or d put down, waiting for a p somewhere else
  // What y or d put down, waiting for a p somewhere else — and "somewhere
  // else" now includes ANOTHER WINDOW. The buffer belongs to the manager, so
  // copying in one terminus and pasting in another is the same gesture it always
  // was. A binding rather than a copy, so both windows' status lines and menus
  // notice the moment either of them yanks. Written through setPending.
  readonly property var pending: root.mgr ? root.mgr.clipboard : null

  // The rows a pending CUT will take away, as a set.
  //
  // A copy leaves everything where it is, so it says nothing about the rows it
  // came from; a cut is a promise to remove them, and until it is paid the
  // listing was showing them exactly as solid as the files that are staying.
  // EntryRow has carried an unused `dim` for exactly this since it was
  // written.
  readonly property var cutSet: {
    const m = ({});
    const p = root.pending;
    if (p && p.op === "move")
      for (let i = 0; i < p.paths.length; ++i) m[p.paths[i]] = true;
    return m;
  }
  function setPending(v) { if (root.mgr) root.mgr.clipboard = v; }
  property string status: ""
  // ── and whether it is bad news ────────────────────────────────────────
  // The status line was drawn in red whatever it said, so "path copied",
  // "background set" and "3 to copy" arrived in the colour of a failure and
  // taught you to stop reading it. Red now means something went wrong or was
  // refused; everything else is an ordinary note.
  //
  // Cleared on EVERY status change and set again by warn() straight after —
  // which works because the change signal runs synchronously inside the
  // assignment, so warn's own flag lands last. That way a plain
  // `root.status = …` cannot inherit the red of whatever failed before it.
  property bool statusBad: false

  // ── and it goes away on its own ───────────────────────────────────────
  // "path copied" and "bookmark removed" are worth saying once; they are not
  // worth sitting in the bar until something else happens to overwrite them,
  // which is how a note becomes furniture you stop reading.
  //
  // EXCEPT WHEN IT ENDS IN AN ELLIPSIS. This window already uses that to mean
  // "still happening" — "searching…", "measuring 12 directories…" — and a
  // progress note that vanished while the work carried on would be a lie in
  // the other direction. Those stay until the thing they describe finishes
  // and replaces them.
  Timer {
    id: statusClear
    interval: 3000
    onTriggered: root.status = ""
  }

  onStatusChanged: {
    root.statusBad = false;
    // the chip keeps the words while it fades out; see its own note
    if (root.status !== "") statusChip.shown = root.status;
    if (root.status !== "" && !root.status.endsWith("\u2026")) statusClear.restart();
    else statusClear.stop();
  }

  function warn(t) { root.status = t; root.statusBad = true; }

  // Only while there is something on screen to be about. On the way out the
  // flag is reset and this deliberately does not follow it, so the chip fades
  // in the colour it arrived in — see the chip's own note.
  onStatusBadChanged: if (root.status !== "") statusChip.shownBad = root.statusBad;

  // ── watching the directory ──────────────────────────────────────────────
  // Until now the listing only changed when TERMINUS changed it: navigate, or
  // finish an action, and it re-read. Anything done by another program — a
  // download landing, a build writing output, a file removed in a terminal —
  // went unnoticed until you left the directory and came back.
  //
  // inotifywait, because there is no alternative in reach: quickshell exposes
  // no QFileSystemWatcher to QML, and FileView's `watchChanges` watches a
  // single named file rather than a directory's contents. inotify is the
  // kernel's own answer and inotify-tools is already installed.
  //
  // -m keeps it running and prints a line per event; -q drops the startup
  // banner so the only output is events. One directory, not recursive: this
  // is about the listing on screen, and -r on a deep tree costs a watch
  // descriptor per directory underneath it.
  Process {
    id: watchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => watchSettle.restart()
    }
  }

  // Coalesced. A single `cp` of a large file emits create, then a stream of
  // close_write/attrib events; re-reading the directory for each one would be
  // a find per event. One re-read once the noise stops is the same answer for
  // a fraction of the work.
  Timer {
    id: watchSettle
    interval: 250
    onTriggered: if (root.searchMode === "") root.refresh()
  }

  // ── THE PREVIEWED DIRECTORY, WATCHED THE SAME WAY ─────────────────────
  // The right-hand column is a directory as much as the middle one is, and it
  // was the only listing on screen with nothing watching it: a file written
  // into it by something else stayed invisible until you walked in and out
  // again. One watcher, re-aimed at whatever is being previewed.
  //
  // AIMED ON A DELAY, not on every cursor move. Re-aiming is a process spawn
  // and a kill, and holding Down through a folder of folders would do one per
  // row for answers nobody reads. The row you actually stop on is the only one
  // worth watching — the same argument the preview's own debounce makes.
  property string peekWatched: ""

  Process {
    id: peekWatchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => peekSettle.restart()
    }
  }

  Timer {
    id: peekAim
    interval: 220
    onTriggered: {
      const r = root.currentRow();
      root.watchPeek(root.viewMode === "columns" && r && r.isDir ? r.path : "");
    }
  }

  // Coalesced exactly as the listing's own watcher is, and for the same
  // reason: one `cp` is a stream of events and one re-read answers all of it.
  Timer {
    id: peekSettle
    interval: 250
    onTriggered: root.repeek()
  }

  function watchPeek(dir) {
    if (dir === root.peekWatched) return;
    root.peekWatched = dir;
    peekWatchProc.running = false;
    if (dir === "" || !root.shown) return;
    peekWatchProc.command = ["inotifywait", "-m", "-q",
      "-e", "create", "-e", "delete", "-e", "moved_to", "-e", "moved_from",
      "-e", "close_write", "-e", "attrib", "--", dir];
    peekWatchProc.running = true;
  }

  // Something changed in the folder being previewed, so the peek we hold of it
  // is a photograph of a scene that has moved. BOTH copies go: the parsed one
  // the pane draws from, and the raw one an arrival would be seeded with — a
  // stale seed is a stale listing, which is the worse of the two.
  function repeek() {
    const d = root.peekWatched;
    if (d === "") return;
    root.forgetListing(d);
    const r = root.currentRow();
    // The one case where the pane must be redrawn with the same row in it:
    // the folder it is showing has changed underneath. Saying so is what
    // gets it past the guard in loadPreview.
    if (r && r.path === d) { root.previewShown = ""; root.loadPreview(); }
  }

  function forgetListing(dir) {
    if (root.previewCache[dir] !== undefined) {
      const c = Object.assign({}, root.previewCache);
      delete c[dir];
      root.previewCache = c;
    }
    if (root.listingText[dir] !== undefined) {
      const t = Object.assign({}, root.listingText);
      delete t[dir];
      root.listingText = t;
    }
  }

  function watch() {
    watchProc.running = false;
    // nothing to watch while hidden, and nothing to watch while showing search
    // results, which are not a directory
    if (!root.shown || root.cwd === "" || root.searchMode !== "") return;
    watchProc.command = ["inotifywait", "-m", "-q",
      "-e", "create", "-e", "delete", "-e", "moved_to", "-e", "moved_from",
      "-e", "close_write", "-e", "attrib", "--", root.cwd];
    watchProc.running = true;
  }

  onCwdChanged: {
    // The anchor is a row INDEX, and the rows are about to be different ones.
    root.endVisual();
    // AND SO IS THE PREVIEW — USUALLY. Its peek is about a row in the
    // directory we have just left, and that row is not in this listing, so it
    // is wrong the instant cwd changes rather than merely stale. Cleared here
    // rather than left to the new listing, which is a whole process away:
    // that gap is exactly how long another folder's contents used to sit in
    // the right-hand column.
    //
    // NOT WHEN IT IS ALREADY ABOUT A ROW IN THIS LISTING. Walking UP lands on
    // the directory we came out of, so the preview should show precisely what
    // it is showing — millerStep has already handed that column those rows,
    // off the listing it had in hand. Blanking here threw them away and the
    // same thirty-two rows were built again a tick later: the third column
    // rebuilding on the way back, which rotation alone could never fix
    // because the rotation was never the thing destroying them.
    const shown = root.previewShown;
    if (shown === "" || Terminus.dirname(shown) !== root.cwd) {
      root.settlePreview("none", [], "");
      root.previewInfo = null;
      infoDelay.stop();
    }
    // before anything else: how this directory was left is part of arriving
    // in it, and applying it after the listing has drawn is a visible flip
    root.applyDirView();
    root.watch();
    // one handler per signal: remembering the open tabs lives here too
    viewSave.restart();
  }
  onSearchModeChanged: root.watch()
  onShownChanged: {
    root.visible = root.shown;
    // A HIDDEN DIALOG IS AN UNANSWERED ONE. However this window came to be
    // hidden — the compositor, a stray keybind, anything that does not go
    // through portalAnswer — something is still waiting on it, and a request
    // that is never answered is a dialog that can never be opened again.
    if (!root.shown && root.picking) { root.portalCancel(); return; }
    root.watch();
    // The peek watcher goes with it, and it has to be FORGOTTEN rather than
    // merely stopped: watchPeek does nothing when asked for the directory it
    // already holds, so a hidden window that kept the name would never re-aim
    // when it came back — the preview would be live until you closed it once
    // and dead ever after.
    root.peekWatched = "";
    peekWatchProc.running = false;
    if (root.shown) peekAim.restart();
    // "RESTORE SESSION" IS ABOUT WHAT YOU GET WHEN YOU OPEN IT.
    //
    // Gating only the restore-from-disk made the switch look broken, and
    // fairly: closing the window is how you close terminus, and the shell
    // still running underneath is an implementation detail nobody outside
    // this file should have to know about. Turned off, it kept every tab
    // across a hide and a show and only came up clean at the next login.
    //
    // So the clean slate happens on the way IN as well. Window 0 only —
    // the spare windows opened with N never restored anything to begin with.
    if (root.shown && !root.sessionReplay && root.winId === 0)
      root.resetSession();
  }

  // Back to one tab at home, which is what "do not restore" means when it is
  // asked of a window that is already open rather than of one being built.
  function resetSession() {
    if (root.tabs.length === 1 && root.tabs[0].cwd === Paths.home()
        && root.cwd === Paths.home() && !root.dual) return;
    root.tabs = [{ cwd: Paths.home(), sel: 0, dual: false, otherCwd: "",
                   otherSel: 0, paneSide: 0, view: root.viewMode }];
    root.tab = 0;
    root.dual = false;
    root.pas.cwd = "";
    root.act.marked = {};
    // enter, not goTo: this is where the window IS as far as history goes,
    // not somewhere it navigated to.
    root.enter(Paths.home());
  }

  // ── how each directory likes to be looked at ────────────────────────────
  // A pictures folder wants the grid and a source tree wants the list, and
  // having to say so every time you walk between them is the sort of small
  // repeated cost a file manager should absorb. So the view and the zoom are
  // remembered PER DIRECTORY: change either while standing somewhere, and
  // coming back puts it the way you left it.
  //
  // A directory nobody has expressed an opinion about simply keeps whatever
  // the last one used, which is the old behaviour — so this only ever adds a
  // memory, never a surprise.
  //
  // Capped, and oldest-first, because this rides along in the preferences file
  // and a map that only ever grows would be an unbounded write on every save.
  property var dirViews: ({})
  property var dirViewOrder: []
  // How many directories keep their remembered view. Not readonly any more:
  // three hundred was a number nobody could see, let alone choose, sitting
  // next to a button offering to forget all of them.
  property int dirViewCap: 300

  // ...and whether to do it at all.
  //
  // It is the kind of helpfulness that is either exactly right or quietly
  // maddening: a folder of photographs opening as thumbnails is the point,
  // and a view that changes as you walk a tree when you wanted one view
  // everywhere is the same feature being wrong. The map is kept either way —
  // turning it off stops it being written and stops it being applied, so
  // turning it back on returns the memory rather than starting again.
  property bool perDirView: true

  // ── THUMBNAILS IN THE GRID ─────────────────────────────────────────────
  // The grid decoded every picture it could see, always. That is what the
  // grid is FOR on a folder of photographs, and it is what makes it unusable
  // on a network mount or four thousand raws — so it is a switch. Off, a tile
  // is its glyph, which is what a tile with nothing decoded yet already is.
  // ── FOLDERS AT THE TOP, OR NOT ─────────────────────────────────────────
  // The listing pinned every directory above every file, in every view but
  // disk usage. It is a reasonable default and it is not everybody's: sorted
  // by date, a folder touched last year sitting above this morning's download
  // is the sort refusing to answer the question asked of it.
  property bool dirsFirst: true

  // See Terminus.sortEntries: "file2" before "file10", which a plain string
  // compare gets backwards.
  property bool naturalSort: true

  property bool thumbsOn: true

  // ── AND THE PREVIEW PANE ───────────────────────────────────────────────
  // The third column's media half: the picture, the film's frame, the PDF,
  // the archive's tree. Off, the column still lists a directory you point
  // at — that is navigation, not preview — but nothing is decoded, stat'd or
  // read for a FILE you are merely passing over, which is most of them.
  property bool previewOn: true

  // Guards the round trip, and it is a DEPTH rather than a flag.
  //
  // applyDirView writes viewMode and the zooms, whose own handlers call
  // rememberView — which would write the very entry being read. A bool was
  // enough for that and wrong for everything since: exchangePanes sets it,
  // then changes cwd, whose handler calls applyDirView, which set it again and
  // then cleared it — releasing a guard its caller was still standing behind,
  // and applying the destination directory's view in the middle of a pane
  // swap. That is what made stepping between two panes with two different
  // views rearrange both of them.
  //
  // Counted, so an inner guard cannot end an outer one. Nothing terminus writes
  // to itself is recorded as a preference while this is above zero.
  property int applyDepth: 0
  readonly property bool applyingDirView: root.applyDepth > 0

  function rememberView() {
    if (!root.perDirView) return;
    if (root.applyingDirView || root.cwd === "" || root.picking) return;
    const m = root.dirViews;
    const o = root.dirViewOrder.slice();
    if (m[root.cwd] === undefined) o.push(root.cwd);
    // The SORT travels with the view, and for the same reason the view does:
    // how a folder wants to be read is a fact about the folder. A source tree
    // sorts by name and a downloads folder sorts by date, and having to say so
    // again every time you walk in is the window forgetting something you have
    // already told it twice.
    m[root.cwd] = { view: root.viewMode, zoom: root.zoom,
                    thumbZoom: root.thumbZoom,
                    sort: root.sortKey, desc: root.sortDesc };
    while (o.length > root.dirViewCap) delete m[o.shift()];
    root.dirViews = m;
    root.dirViewOrder = o;
    viewSave.restart();
  }

  // Every directory's remembered view, sort and zoom, forgotten at once.
  //
  // The per-directory memory is a convenience that quietly accumulates: three
  // hundred folders, each insisting on the arrangement you gave it once
  // months ago. There was no way to say "start again" short of deleting the
  // preferences file, which takes the bookmarks and the tabs with it.
  //
  // What is on screen is left alone. Forgetting how this folder liked to be
  // read is not a reason to rearrange it while you are looking at it — the
  // next visit is when the difference should show.
  // Brought down to the cap when the cap comes down. Without this, moving the
  // slider left recorded a smaller number and kept every entry already over
  // it — the setting would only bite on the next directory visited.
  function trimDirViews() {
    const m = root.dirViews;
    const o = root.dirViewOrder.slice();
    while (o.length > root.dirViewCap) delete m[o.shift()];
    root.dirViews = m;
    root.dirViewOrder = o;
    viewSave.restart();
  }

  function forgetDirViews() {
    root.dirViews = ({});
    root.dirViewOrder = [];
    viewSave.restart();
    root.status = "remembered views cleared";
  }

  function applyDirView() {
    if (!root.perDirView) return;
    // Already inside something terminus is doing to itself — a pane exchange, a
    // tab load — so the directory's own preference is not what is wanted.
    if (root.applyDepth > 0) return;
    const v = root.dirViews[root.cwd];
    if (!v) return;
    root.applyDepth++;
    if (root.viewRing.indexOf(v.view) >= 0) root.act.viewMode = v.view;
    const z = Number(v.zoom);
    if (!isNaN(z) && z > 0) root.zoom = root.zoomClamp(z);
    const tz = Number(v.thumbZoom);
    if (!isNaN(tz) && tz > 0) root.act.zoom = root.zoomClamp(tz);
    // Older records have no sort in them, and a missing answer must not be
    // read as "name ascending" — that would quietly re-sort every folder
    // remembered before this existed.
    if (typeof v.sort === "string" && v.sort !== "") root.sortKey = v.sort;
    if (typeof v.desc === "boolean") root.sortDesc = v.desc;
    root.applyDepth--;
  }

  // ── the second pane ─────────────────────────────────────────────────────
  // Optional, and off by default: terminus is a one-pane file manager that can
  // become a two-pane one, not the other way round.
  //
  // The trick is that there is still only ONE pane's worth of live state. The
  // active side is the window — cwd, rows, sel, marks, filter, history, the
  // lot, exactly as before — and the other side is a listing and a cursor and
  // nothing else. `o` SWAPS them, which is the same move switchTab makes
  // between tabs, so both sides get the full window in turn and neither needs
  // a second copy of every property in this file.
  //
  // What that buys: no branch in any existing key, verb or view. What it
  // costs: the inactive side cannot be filtered or marked until you step into
  // it, which is what stepping into it is for.
  property bool dual: false
  // THE OTHER HALF, READ THROUGH — the mirror of the block above. It owns
  // its listing the same way the active one does, so this is a window onto
  // it rather than a second copy kept in step by hand.
  readonly property string otherCwd: root.pas.cwd
  readonly property int otherSel: root.pas.sel
  readonly property var otherRaw: root.pas.raw
  readonly property var otherRows: root.pas.view

  // The two halves, as objects. Both exist whether or not the window is
  // split: with one pane the right-hand one is simply not drawn, which is
  // cheaper than creating and destroying a pane every time `dual` is
  // toggled and means the second side remembers where it was.
  // The left one starts where the window starts, in columns — the view a
  // file manager should open in, because it is the one you navigate in. The
  // right one starts empty, and an empty cwd is what "there is no second
  // pane yet" has always meant here: see toggleDual, which fills it with
  // wherever you are standing the first time you ask for a split.
  Pane { id: paneL; side: 0; cwd: Paths.home(); viewMode: "columns" }
  Pane { id: paneR; side: 1; viewMode: "list" }

  // WHICH ONE THE KEYBOARD IS IN, and which one it is not. Every verb in
  // this window acts on `act`; the other side is read, never written, except
  // by the two functions that deliberately reach across it.
  // GUARDED ON `dual`, and that guard is not decoration. With one pane
  // there is no other side to be in, but paneSide is remembered across a
  // session — so a window saved while the keyboard was on the right, then
  // reopened unsplit, would make paneR the active pane and draw paneL's
  // empty half. It cost an evening: the listing arrived, the model filled,
  // and the view on screen was bound to the other one.
  readonly property Pane act: (root.dual && root.paneSide === 1) ? paneR : paneL
  readonly property Pane pas: (root.dual && root.paneSide === 1) ? paneL : paneR

  // ── WHERE EACH HALF IS, as the views ask it ───────────────────────────
  // With one pane, side 0 is the whole body and side 1 is not drawn. These
  // are functions rather than four more properties because a binding that
  // calls one still depends on everything the call reads.
  function paneX(side) {
    if (!root.dual) return 0;
    return side === 0 ? 0 : root.paneSplit + 1;
  }
  function paneW(side) {
    if (!root.dual) return bodyBox.width;
    return side === 0 ? root.leftPaneW : root.rightPaneW;
  }
  // 22px of headings when this half is a list, nothing when it is not. With
  // one pane the strip above the body does this job; with two it has to
  // happen per pane, or the two halves cannot differ.
  function paneHeadH(side) {
    if (!root.dual) return 0;
    const p = side === 0 ? paneL : paneR;
    return p.viewMode === "list" ? 22 : 0;
  }

  // The two views of whichever half the keyboard is in. Everything that used
  // to name `list` or `grid` outright means this.
  // ASKED, NOT ASSUMED. listA is not always the left half: `o` swaps the two
  // directories between the sides, and a pane carries the side it is drawn on
  // rather than being defined by it — see paneSide.
  //
  // Hardcoding the map cost the whole of list and grid their mouse. With the
  // active pane on side 1 and only one pane open, this handed back listB —
  // empty and not even drawn — so rowUnder asked an invisible view where the
  // pointer was, always heard -1, and `overEmpty` stayed true. The empty-space
  // MouseArea sits ABOVE the views, so it then swallowed every left click and
  // answered every right click with the paste-here menu for the row the cursor
  // was already on. Column view was unaffected, which is why it survived
  // unnoticed: rowUnder measures that one against the middle column directly.
  //
  // Written as expressions rather than through listOf(): a binding does not
  // re-evaluate on a FUNCTION call, so it would never notice a swap.
  // THE LIST WHOSE PANE IS THE ACTIVE PANE. Not "the list for paneSide":
  // `act` is `(dual && paneSide === 1) ? paneR : paneL`, so with one pane open
  // it is ALWAYS paneL however stale paneSide happens to be — and paneSide
  // does go stale, because closing the second half leaves it at 1 while the
  // only pane drawn is side 0. Following the number rather than the pane was
  // the whole bug: rowUnder asked an empty, undrawn view where the pointer
  // was, heard -1 forever, and the empty-space MouseArea that sits ABOVE the
  // views then ate every click in list and grid.
  readonly property var actList: listA.pane === root.act ? listA : listB
  readonly property var actGrid: gridA.pane === root.act ? gridA : gridB
  function listOf(side) { return listA.side === side ? listA : listB; }
  function gridOf(side) { return gridA.side === side ? gridA : gridB; }

  // A click in the half the keyboard is not in: land on the row, then come
  // over. Both halves are real panes, so this is the whole of what makes
  // them interchangeable rather than one of them being second class.
  // THE SAME RULE, FOR A CLICK THAT LANDS ON NOTHING.
  //
  // focusPane below is a click on a ROW in the other half: take the row, then
  // come over. Empty space had no equivalent, and the empty-space overlay is
  // one item across the whole body with no idea which half the pointer is in
  // — so clicking the background of the inactive half cleared the ACTIVE
  // pane's marks and opened the paste menu for the ACTIVE pane's directory,
  // from a click made in the other one. Nothing moved, which read as the mouse
  // being unable to choose a pane at all: only rows could, and only by being
  // rows.
  //
  // No `sel` here — clicking empty space is not choosing a row, so the cursor
  // stays where that half left it.
  function comeOverAt(bx) {
    const v = root.viewUnder(bx);
    if (!v || !v.pane || v.pane.active) return;
    if (root.dual && v.pane.side !== root.paneSide) root.stepOver();
  }

  function focusPane(pane, i) {
    if (!pane) return;
    pane.sel = i;
    if (root.dual && pane.side !== root.paneSide) root.stepOver();
  }

  // One half's views, back to the top. Called from the wholesale branch of
  // that pane's diff, before the model is cleared.
  function rewindPane(side) {
    root.listOf(side).positionViewAtBeginning();
    root.gridOf(side).positionViewAtBeginning();
    if (side === root.paneSide) {
      root.midCol.view.positionViewAtBeginning();
    }
  }

  // WHICH HALF the active pane occupies: 0 left, 1 right.
  //
  // Without this, `o` swapped the two directories between the sides and the
  // active pane was always the left one — so pressing it made the contents
  // jump across the window, and a border marking "the live side" would have
  // been a border that never moved. With it, the exchange and the flip happen
  // together: the state moves one way, the side it is drawn on moves the
  // other, and the visible result is that the contents stay exactly where they
  // are while the focus crosses over. Which is what Tab is expected to do.
  property int paneSide: 0
  // AN INVARIANT, NOT A TIDY-UP. With one pane, side 0 is the only half drawn
  // — PaneList and PaneGrid are both `dual || side === 0` — so a paneSide of 1
  // while unsplit names a half that does not exist.
  //
  // It happens: toggleDual puts the window back to one pane and leaves this
  // wherever the keyboard was. `act` guards against it (`dual && paneSide === 1`)
  // and so does everything reached through `act`, but anything reading the
  // number directly is looking at a lie. It already cost list and grid their
  // mouse once, through actList — which picked the list for paneSide rather
  // than the list belonging to the active pane, and so answered with an empty,
  // undrawn view.
  //
  // Enforced where the state changes rather than at each of the four places
  // that unsplit. loadTab writes `dual` before `paneSide`, so a tab that was
  // saved split still restores its side.
  onDualChanged: if (!root.dual) root.paneSide = 0

  // WHAT EACH SIDE IS SHOWING is the pane's own business now. paneViews and
  // paneZooms were two arrays indexed by side, kept in step by hand at every
  // exchange because the state crossed the divider and the view had to be
  // held back from crossing with it. Nothing crosses any more.
  //
  // TOTAL, on purpose: grid or list and nothing else. A stored value can be
  // "columns" — from a session before there were two panes, or a tab saved
  // while there was only one — and a third answer here renders neither view,
  // which is a pane that goes blank the moment you step out of it.
  readonly property string otherViewMode:
    root.pas.viewMode === "grid" ? "grid" : "list"
  readonly property real otherThumbZoom: root.pas.zoom > 0 ? root.pas.zoom : 1.0

  // Where the divider sits, as a FRACTION of the body rather than a pixel
  // count, so resizing the window keeps the proportion you chose instead of
  // pinning one pane to a width and giving every new pixel to the other.
  property real paneFrac: 0.5
  // Eased when the divider is SENT somewhere — a keyed step, the double-click
  // back to even — and never while it is under the pointer. A behaviour left
  // running through a drag puts the split a frame behind the mouse, which
  // reads as the window resisting you rather than as smoothness. Exactly the
  // rule the sidebar's own Behavior follows; see `side`.
  Behavior on paneFrac {
    enabled: !splitGrip.pressed
    NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
  }
  readonly property real paneMinFrac: 0.15
  readonly property real paneMaxFrac: 0.85

  // The divider's x, and the two halves either side of it.
  readonly property real paneSplit: Math.floor(bodyBox.width * root.paneFrac)
  readonly property real leftPaneW: root.paneSplit
  readonly property real rightPaneW: Math.max(0, bodyBox.width - root.paneSplit - 1)

  // The half the keyboard is in, for the things that still follow it around
  // rather than belonging to a side: the miller frame, the drop target, the
  // rubber band. Both are paneX/paneW asked about the active side.
  readonly property real activePaneW: root.paneW(root.act.side)
  readonly property real activePaneX: root.paneX(root.act.side)

  Process {
    id: otherProc
    // A directory that has gone since the window was last open — an unmounted
    // disk, a deleted download — falls back to home rather than leaving the
    // pane blank with nothing to say for itself. `find` exits non-zero on a
    // path that is not there, which is the whole test. Guarded against home
    // itself so a failure there cannot loop.
    onExited: (code) => {
      if (code === 0 || root.otherCwd === Paths.home()) return;
      root.pas.cwd = Paths.home();
      root.pas.sel = 0;
      root.refreshOther();
    }
    stdout: StdioCollector {
      id: otherOut
      waitForEnd: true
      onStreamFinished: {
        // ENRICHED HERE, where the other half's listing is parsed. It used
        // to be decorated by the otherRows binding instead — that binding is
        // the pane's own `sorted` now, shared with the active half, and a
        // listing that arrived undecorated drew rows with no glyph and no
        // ink at all.
        root.pas.raw = root.enrich(
          Terminus.parseListing(otherOut.text, root.otherCwd));
        if (root.otherSel >= root.otherRows.length)
          root.pas.sel = Math.max(0, root.otherRows.length - 1);
      }
    }
  }

  Timer {
    id: thumbRetry
    interval: 250
    onTriggered: root.makeThumbs()
  }

  function refreshOther() {
    if (!root.dual || root.otherCwd === "") return;
    otherProc.command = ["sh", "-c", Terminus.listCommand(root.otherCwd)];
    otherProc.running = true;
  }

  function toggleDual() {
    if (root.picking) return;   // see loadViewPrefs: a dialog has one pane
    if (root.dual) {
      root.dual = false;
      viewSave.restart();
      return;
    }
    // Opens where you are standing, like a new tab does and for the same
    // reason: you split the window because you want a second view of what is
    // already in front of you.
    if (root.otherCwd === "") root.pas.cwd = root.cwd;
    root.dual = true;
    root.demoteColumns();
    root.refreshOther();
    viewSave.restart();
  }

  // FOCUS THE OTHER SIDE, WHICH IS NOW ONE ASSIGNMENT. What `o`, Tab and a
  // click over there all do.
  //
  // It used to be twenty lines: the two listings changed hands, the side they
  // were drawn on flipped the other way so the screen held still, and the
  // view and the zoom of each half had to be saved, restored and written back
  // whole with the per-directory handlers muted throughout — because the
  // state was crossing the divider and everything that belonged to the HALF
  // rather than to the state had to be held back from crossing with it.
  //
  // Nothing crosses now. Each half owns its directory, its cursor, its view,
  // its zoom and its model, permanently; `paneSide` says only which of the
  // two the keyboard is in. So the whole of stepping across is moving that
  // flag — no listing changes hands, no model is rebuilt, and not one
  // delegate in either pane is destroyed.
  function stepOver() {
    if (!root.dual) return;
    // A filter belongs to the pane it was typed in and to the moment you were
    // in it — the same rule tabs follow. Cleared on the way OUT, so the side
    // you arrive at is whatever you left it as rather than something that
    // rearranges itself under you as you get there.
    root.act.query = "";
    root.act.marked = {};
    // MUTED ACROSS THE FLIP, and this is not optional. `cwd` is a window onto
    // the active pane, so moving the flag changes it — and onCwdChanged
    // applies the DIRECTORY's remembered view. Without the guard, stepping
    // across overwrote the half you arrived in with whatever the half you
    // left had last recorded against that path, and the change to viewMode
    // recorded it right back: the two panes traded views, every press, for as
    // long as you kept pressing.
    root.applyDepth++;
    root.paneSide = root.paneSide === 0 ? 1 : 0;
    root.applyDepth--;
    // The field shows the half you are now in. It will be empty, because
    // leaving a pane clears its filter — but reading it back rather than
    // blanking it means the field can never disagree with the listing.
    filterField.text = root.act.query;
    // Whatever the half you have arrived in is showing, it is a grid or a
    // list: columns is a three-column layout and there is not room for two of
    // them. A stored "columns" — from a session before the split was opened —
    // would otherwise draw nothing at all.
    if (root.act.viewMode === "columns") root.act.viewMode = "list";
    root.saveTab();
    root.makeThumbs();
  }

  // THE TWO DIRECTORIES CHANGE SIDES and the focus stays where it is. The
  // only thing left in this window that moves a listing across the divider,
  // and the only thing that should: `o` is a request to swap them.
  function swapSides() {
    if (!root.dual) return;
    root.exchangePanes();
  }

  // The whole second pane, in one function. Everything a pane owns goes with
  // it, because the point of the gesture is that the two halves trade places
  // entirely — not that two directories are moved between two sets of
  // settings that stay put.
  function exchangePanes() {
    if (!root.dual) return;
    // The remembered view belongs to NAVIGATION, not to a swap: arriving in a
    // directory last looked at as a grid must not flip the pane it lands in.
    root.applyDepth++;
    const a = paneL;
    const b = paneR;
    const cwd = a.cwd, sel = a.sel, raw = a.raw, vm = a.viewMode;
    const zoom = a.zoom, q = a.query, mk = a.marked, ll = a.lastListing;
    a.cwd = b.cwd; a.sel = b.sel; a.raw = b.raw; a.viewMode = b.viewMode;
    a.zoom = b.zoom; a.query = b.query; a.marked = b.marked;
    a.lastListing = b.lastListing;
    b.cwd = cwd; b.sel = sel; b.raw = raw; b.viewMode = vm;
    b.zoom = zoom; b.query = q; b.marked = mk; b.lastListing = ll;
    filterField.text = root.act.query;
    root.saveTab();
    // inotify follows the cwd (onCwdChanged), so anything that changes over
    // here while you were over there still arrives on its own.
    root.makeThumbs();
    root.applyDepth--;
  }

  // F5 and F6, the two keys every dual-pane file manager has had since the
  // eighties. They are the yank buffer and a paste, with the destination
  // pointed at the other side rather than at where you are standing.
  function sendToOther(op) {
    if (!root.dual || root.otherCwd === "") {
      root.warn("no second pane");
      return;
    }
    if (root.otherCwd === root.cwd) {
      root.warn("both panes are here");
      return;
    }
    const rows = root.acting();
    if (rows.length === 0) return;
    root.setPending({ op: op, paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    root.pasteDest = root.otherCwd;
    root.paste();
  }

  // Where a paste LANDS. Normally where you are standing; the other pane's
  // directory for the one gesture that deliberately acts somewhere else. It is
  // cleared the moment the job is handed over, so nothing can inherit it.
  property string pasteDest: ""
  readonly property string destDir:
    root.pasteDest !== "" ? root.pasteDest : root.cwd

  // ── the sidebar ─────────────────────────────────────────────────────────
  // Bookmarks and disks, in a column you can put away. It replaces the strip
  // of bookmark chips that used to sit across the top: chips were fine for
  // four and useless for twenty, and there was nowhere to put a disk.
  property bool sidebar: false
  // How wide it is when open. Dragged by the divider, kept between sessions
  // with the other view preferences, and clamped so it can be neither a sliver
  // nor most of the window.
  property real sidebarWidth: 200
  // A shade under the list, and the number is small because it COMPOSITES.
  //
  // The sidebar is painted over the window's own ground, which is layerBg —
  // 80% black over the blurred desktop. An alpha of 0.90 here does not mean
  // "90% black on screen", it means 0.90 laid over 0.80, which comes out at
  // 0.98: near enough solid, and the reason the sidebar read as a hole cut in
  // the window. 0.25 over 0.80 lands at 0.85 — a shade under the listing,
  // which is all that was wanted, and the blur still carries through.
  readonly property color sidebarBg: Qt.rgba(0, 0, 0, 0.25)
  readonly property real sidebarMin: 130
  readonly property real sidebarMax: 420

  property var disks: []
  property string diskKey: ""
  // false until the first poll has landed, so the machine's own disks are not
  // mistaken for something you just plugged in
  property bool diskSeen: false

  Process {
    id: diskProc
    stdout: StdioCollector {
      id: diskOut
      waitForEnd: true
      onStreamFinished: {
        const found = Terminus.parseDisks(diskOut.text);
        const key = Terminus.diskKey(found);
        if (key === root.diskKey) return;
        // Something appeared or was mounted. Opening the sidebar unasked is
        // justified exactly once — when a disk shows up that was NOT THERE A
        // MOMENT AGO, which is the moment you want to see it.
        //
        // `seen` is what makes that "a moment ago" real. Without it the first
        // poll of the session counted every disk in the machine as newly
        // arrived and threw the sidebar open on startup, every time.
        const grew = root.diskSeen && found.length > root.disks.length;
        root.disks = found;
        root.diskKey = key;
        root.diskSeen = true;
        if (grew && root.visible) root.sidebar = true;
      }
    }
  }

  // Polled rather than watched. udisks has a D-Bus signal for this and
  // quickshell can listen to D-Bus — but the polling costs one lsblk every
  // four seconds and needs no service to be running, and a file manager that
  // notices a USB stick three seconds late has still noticed it.
  Timer {
    interval: 4000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!diskProc.running) {
      diskProc.command = ["sh", "-c", Terminus.disksCommand()];
      diskProc.running = true;
    }
  }

  Process {
    id: mountProc
    stdout: StdioCollector {
      id: mountOut
      waitForEnd: true
      onStreamFinished: {
        const t = String(mountOut.text || "").trim();
        root.warn(t.split("\n")[0]);
        // re-read straight away rather than waiting for the next tick, so the
        // row stops saying "mount" the instant it is mounted
        root.diskKey = "";
        diskProc.command = ["sh", "-c", Terminus.disksCommand()];
        diskProc.running = true;
      }
    }
  }

  function mountDisk(d) {
    mountProc.command = ["sh", "-c", d.mount === ""
      ? Terminus.mountCommand(d.path) : Terminus.unmountCommand(d.path)];
    mountProc.running = true;
  }

  // ── how big a folder really is ──────────────────────────────────────────
  // The listing shows a dash for a directory, because a directory's own size
  // is the size of its record and never the number anybody means. `z` asks for
  // the real one, and the answer replaces the dash for as long as the window
  // is open.
  //
  // On demand, and it has to be: `du` over a home directory is a walk of every
  // inode under it, which is seconds of disk for a column nobody had asked
  // about. Measured folders are remembered by path, so the answer survives
  // walking away and coming back.
  property var dirSizes: ({})

  Process {
    id: duProc
    stdout: StdioCollector {
      id: duOut
      waitForEnd: true
      onStreamFinished: {
        const got = Terminus.parseDirSizes(duOut.text);
        const next = Object.assign({}, root.dirSizes, got);
        root.dirSizes = next;
        const n = Object.keys(got).length;
        // In the usage view the bars ARE the report, and a line reading
        // "measured 22" left over from the directory before this one is just
        // a wrong caption under a right picture.
        if (root.usage) {
          root.status = "";
          // whatever this batch could not reach, and anything listed since it
          // started — see measureAll's note about being busy
          Qt.callLater(root.measureAll);
        } else {
          // only the nothing-measured case is bad news; the others are counts
          if (n === 0) root.warn("could not measure");
          else root.status = (n === 1 ? "measured" : "measured " + n);
        }
      }
    }
  }

  // ── git status ──────────────────────────────────────────────────────────
  //
  // A gutter beside the name, one character wide, saying what git thinks of
  // each row. Everything it needs was already here and tested — the command,
  // the porcelain parser, the roll-up that folds a repository's whole answer
  // down to the rows on screen — and none of it had ever been called; the mode
  // is what connects them.
  //
  // OFF BY DEFAULT and asked for explicitly, the same as disk usage, because
  // it costs a process per directory and most directories are not in a
  // repository at all.
  property bool git: false
  // path -> state, already rolled up: a directory carries the worst state of
  // everything beneath it, so the mark on a folder means "something in here".
  property var gitMarks: ({})
  // What repository, and which branch of it. Empty when the directory is not
  // in one, which is also how the bar knows to say nothing.
  property string gitRoot: ""
  property string gitBranch: ""

  Process {
    id: gitProc
    stdout: StdioCollector {
      id: gitOut
      waitForEnd: true
      onStreamFinished: {
        // Asked about the directory we were in when the scan started, not the
        // one we are in now: a reply that arrives after you have walked on
        // would otherwise be rolled up against the wrong base and mark rows it
        // knows nothing about.
        const asked = root.gitAsked;
        root.gitAsked = "";
        if (asked !== root.cwd) return;
        const g = Terminus.parseGit(gitOut.text);
        root.gitRoot = g.root;
        root.gitBranch = g.branch;
        root.gitMarks = g.root === "" ? ({})
                                      : Terminus.gitRollup(g.entries, root.cwd);
      }
    }
  }

  property string gitAsked: ""

  function scanGit() {
    if (!root.git) return;
    // One at a time. A directory of directories walked quickly would otherwise
    // start a `git status` per keystroke and the answers would land in an order
    // nobody controls.
    if (gitProc.running) return;
    root.gitAsked = root.cwd;
    gitProc.command = ["sh", "-c", Terminus.gitCommand(root.cwd)];
    gitProc.running = true;
  }

  function toggleGit() {
    root.git = !root.git;
    if (root.git) { root.scanGit(); return; }
    root.gitMarks = ({});
    root.gitRoot = "";
    root.gitBranch = "";
  }

  // What a state is worth looking at in. Red for the two that cost you
  // something, green for what is already safely staged, and the rest below
  // the names they sit beside — a gutter that shouted would be a listing you
  // read the gutter of.
  function gitInk(state) {
    if (state === "conflict" || state === "deleted") return Zenon.red;
    if (state === "modified") return Zenon.sand;
    if (state === "staged") return Zenon.green;
    if (state === "untracked") return Zenon.blue;
    return Zenon.muted;
  }

  // ── disk usage ──────────────────────────────────────────────────────────
  //
  // ncdu's question, asked without leaving the directory you are in: what in
  // here is actually taking up the room. Everything it needs already existed —
  // `du` and its parser, the recursive sizes cache, the sort — so the mode is
  // mostly a matter of measuring every directory instead of the selected one
  // and drawing the answer as a length rather than only as a number.
  property bool usage: false
  // What the mode overrides, so leaving it puts things back rather than
  // leaving you in an order and a view you did not choose.
  property string usagePrevSort: ""
  property bool usagePrevDesc: false
  property string usagePrevView: ""

  // The measured size of a row: a walked directory, or a file, which is
  // already its own whole answer. Undefined until du has been round.
  function usageOf(r) {
    if (!r) return 0;
    if (!r.isDir) return r.size;
    const v = root.dirSizes[r.path];
    return v === undefined ? 0 : v;
  }

  // The biggest thing on screen, which is what every bar is drawn against.
  readonly property real usageMax: {
    if (!root.usage) return 0;
    // The array in a LOCAL. `root.view` is a QML property, and reading it in
    // the loop condition and again in the body is two property lookups per
    // row — on a four-thousand-entry directory, eight thousand of them every
    // time a measurement lands.
    const v = root.view;
    let m = 0;
    for (let i = 0; i < v.length; ++i) {
      const b = root.usageOf(v[i]);
      if (b > m) m = b;
    }
    return m;
  }

  // AND THE SAME QUESTION ASKED OF THE OTHER HALF.
  //
  // Both panes drew their bars against usageMax, which is computed from the
  // ACTIVE listing — so walking through one half rescaled every bar in the
  // other and moved the sand-coloured "biggest here" mark onto a row that is
  // not the biggest there. A bar is a proportion, and a proportion is only
  // meaningful against the things beside it: each half is measured against
  // what is IN that half.
  //
  // The measurements themselves stay shared — dirSizes is keyed by path and a
  // folder is the same size whichever pane is looking at it. It is only the
  // yardstick that is per-pane.
  readonly property real otherUsageMax: {
    if (!root.usage || !root.dual) return 0;
    const v = root.otherRows;
    let m = 0;
    for (let i = 0; i < v.length; ++i) {
      const b = root.usageOf(v[i]);
      if (b > m) m = b;
    }
    return m;
  }

  function toggleUsage() {
    root.usage = !root.usage;
    if (root.usage) {
      root.usagePrevSort = root.sortKey;
      root.usagePrevDesc = root.sortDesc;
      root.usagePrevView = root.viewMode;
      root.sortKey = "usage";
      root.sortDesc = true;
      root.duTried = ({});
      // A FRESH ANSWER, because that is what turning the mode on is asking
      // for. Sizes are cached by path and outlive the listing, which is right
      // for navigating — but a folder measured an hour and several downloads
      // ago would be reported here as though it were current.
      root.dirSizes = ({});
      // The column this mode is about only exists in the list. Toggling it in
      // the grid would reorder tiles that show no sizes, which reads as
      // nothing having happened.
      if (root.viewMode !== "list") root.act.viewMode = "list";
      root.measureAll();
    } else {
      root.sortKey = root.usagePrevSort !== "" ? root.usagePrevSort : "name";
      root.sortDesc = root.usagePrevDesc;
      if (root.usagePrevView !== "" && root.usagePrevView !== root.viewMode)
        root.act.viewMode = root.usagePrevView;
      root.status = "";
    }
  }

  // Every directory here, not just the selected one — the mode is a picture of
  // the whole directory and a picture with holes in it is worse than none.
  // Already-measured folders are skipped: dirSizes outlives the listing, so
  // coming back to a directory you have already looked at costs nothing.
  // Paths du has already been asked about, so one it cannot answer for — a
  // directory that is not readable — is asked once and then left alone.
  // Without this the retry below would ask about it forever.
  property var duTried: ({})

  function measureAll() {
    if (!root.usage) return;
    // Busy is not the same as done. This used to just give up, and since the
    // only caller was the listing, nothing ever came back to it: walk into a
    // directory while the previous one is still being measured and its folders
    // kept their dashes for as long as the window stayed open. The retry now
    // lives in duProc's completion, so being busy costs a wait rather than the
    // whole answer.
    if (duProc.running) return;
    const tried = root.duTried;
    const sizes = root.dirSizes;
    const todo = root.rows.filter((r) => r.isDir
      && sizes[r.path] === undefined && tried[r.path] !== true);
    if (todo.length === 0) { root.status = ""; return; }
    const next = Object.assign({}, tried);
    for (const r of todo) next[r.path] = true;
    root.duTried = next;
    root.status = "measuring " + todo.length
      + (todo.length === 1 ? " directory\u2026" : " directories\u2026");
    duProc.command = ["sh", "-c",
      Terminus.dirSizeCommand(todo.map((r) => r.path))];
    duProc.running = true;
  }

  function measureDirs() {
    const dirs = root.acting().filter((r) => r.isDir);
    if (dirs.length === 0) { root.warn("no directory to measure"); return; }
    if (duProc.running) { root.status = "still measuring\u2026"; return; }
    root.status = "measuring " + (dirs.length === 1 ? dirs[0].name
      : dirs.length + " directories") + "\u2026";
    duProc.command = ["sh", "-c",
      Terminus.dirSizeCommand(dirs.map((r) => r.path))];
    duProc.running = true;
  }

  // ── thumbnails ──────────────────────────────────────────────────────────
  // Generated for the whole directory at once when the grid is what is on
  // screen, and only then: a folder you are looking at as a list does not need
  // 256px PNGs of everything in it. `thumbTick` is what tells the tiles to
  // look again once the batch has finished.
  // path -> true once a batch has actually produced its thumbnail. A tile
  // points at the original until its entry appears here.
  //
  // Without this the tiles guessed, and every guess that lost printed
  // "Cannot open: …/thumbs/xxxx.png" into the log — one line per image per
  // visit, for a file that was about to exist. Asking the batch what it made
  // is the difference between a fallback and a warning.
  // path -> the thumbnail that exists for it, as the generator REPORTED it.
  //
  // Terminus used to work the filename out itself and assume the batch had made
  // it. Two things were wrong with that: a file that yields no picture — a
  // track with no cover — was marked ready and pointed an Image at a path
  // nothing had written, and the name could only ever be computed by terminus, so
  // Picasso could not find a thumbnail terminus had already made of the same
  // wallpaper. The pool is shared now and the shell names the files; this is
  // what came back. See morpheus/thumbs.js.
  property var thumbFile: ({})
  property var thumbJobs: []
  // Insertion order, so the map can be bounded. Without it this grew by one
  // entry for every image, video and track the window ever showed and never
  // gave one back — the same shape of leak the navigation history had, and the
  // odd one out among this window's caches, which are all capped (see
  // cachePreview and dirViewCap).
  //
  // Evicting is cheap and safe: the entry only says "a thumbnail for this path
  // exists", the file it names is still on disk, and the generator skips work
  // for a thumbnail that is already there. Losing an entry costs one stat, not
  // one decode.
  property var thumbOrder: []
  // Far more than a directory of photographs, so ordinary browsing never
  // evicts and the cap is only felt by a session that has walked past tens of
  // thousands of files.
  readonly property int thumbCap: 4000

  Process {
    id: thumbProc
    // What the batch actually MADE, not what it was asked for.
    //
    // This used to mark every job it sent, which was near enough true while
    // the jobs were only pictures and videos. Audio broke it: a track with no
    // cover art produces no file, so the preview pointed an Image at a path
    // that was never written and Qt logged "Cannot open" for it on every
    // visit. The batch now prints the source of each thumbnail that exists
    // when it finishes, and only those are marked.
    stdout: StdioCollector {
      id: thumbOut
      waitForEnd: true
      onStreamFinished: {
        const made = Thumbs.parseMade(thumbOut.text);
        const c = Object.assign({}, root.thumbFile);
        const o = root.thumbOrder.slice();
        for (const k in made) {
          if (c[k] === undefined) o.push(k);
          c[k] = made[k];
        }
        while (o.length > root.thumbCap) delete c[o.shift()];
        root.thumbFile = c;
        root.thumbOrder = o;
      }
    }
    onExited: root.thumbJobs = []
  }

  function makeThumbs() {
    // A batch already running is not a reason to skip: it may have been asked
    // for the OTHER pane's rows, and dropping this request left the pane you
    // just stepped into showing glyphs. Deferred rather than dropped.
    if (thumbProc.running) { thumbRetry.restart(); return; }
    // BOTH panes, because either can be the grid. The second pane's tiles
    // read the same cache and would otherwise sit on their glyphs forever
    // while the pane beside them was full of pictures.
    let want = [];
    if (root.viewMode === "grid") want = want.concat(root.view);
    if (root.dual && root.otherViewMode === "grid")
      want = want.concat(root.otherRows);
    if (want.length === 0) return;
    const jobs = [];
    for (const r of want) {
      if (r.isDir) continue;
      // Audio joins the grid for the same reason it joined the preview: a
      // folder of albums is a folder of covers, and showing eight identical
      // note glyphs is showing nothing. A track without art keeps its glyph.
      const kind = Terminus.isVideo(r.name) ? "v"
        : (Terminus.isAudio(r.name) ? "a" : (Terminus.isImage(r.name) ? "i" : ""));
      if (kind === "") continue;
      if (root.thumbFile[r.path]) continue;
      jobs.push({ src: r.path, kind: kind });
    }
    if (jobs.length === 0) return;
    root.thumbJobs = jobs;
    thumbProc.command = ["sh", "-c", Thumbs.generate(jobs)];
    thumbProc.running = true;
  }

  // ── searching ───────────────────────────────────────────────────────────
  // "" while browsing, "find" or "grep" while showing results. Results replace
  // the listing rather than opening a pane: they ARE what you are looking at,
  // and every verb should act on them exactly as it acts on a directory.
  property string searchMode: ""
  property string searchQuery: ""

  Process {
    id: searchProc
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: {
        const paths = String(searchOut.text || "").split("\u0000")
          .map((x) => x.replace(/\/+$/, ""))
          .filter((x) => x !== "");
        if (paths.length === 0) {
          root.act.raw = [];
          root.status = "no matches";
          return;
        }
        statProc.command = Terminus.statArgv(paths);
        statProc.running = true;
      }
    }
  }

  Process {
    id: statProc
    stdout: StdioCollector {
      id: statOut
      waitForEnd: true
      onStreamFinished: {
        root.act.raw = root.enrich(Terminus.parseStat(statOut.text));
        root.act.sel = 0;
        root.status = root.rows.length + " matches";
        Qt.callLater(root.positionSel);
      }
    }
  }

  function search(mode, query) {
    if (query === "") return;
    // WHERE YOU WERE, so Escape can put you back there.
    //
    // Results are a page of their own, not a directory: they come from all
    // over the tree and the cursor lands on whichever of them ranked first.
    // Leaving them used to re-list wherever you happened to be with the cursor
    // wherever the results had left it, so a search you decided against cost
    // you your place. Recorded only on the way IN, so refining a search twice
    // still returns to where the first one started.
    if (root.searchMode === "") {
      const r = root.currentRow();
      root.searchBackCwd = root.cwd;
      root.searchBackSel = r ? r.path : "";
    }
    root.searchMode = mode;
    root.searchQuery = query;
    root.act.raw = [];
    root.status = "searching…";
    searchProc.command = ["sh", "-c", mode === "grep"
      ? Terminus.grepCommand(root.cwd, query)
      : Terminus.findCommand(root.cwd, query)];
    searchProc.running = true;
  }

  property string searchBackCwd: ""
  property string searchBackSel: ""

  function clearSearch() {
    if (root.searchMode === "") return;
    root.searchMode = "";
    root.searchQuery = "";
    const backCwd = root.searchBackCwd;
    const backSel = root.searchBackSel;
    root.searchBackCwd = "";
    root.searchBackSel = "";
    if (backSel !== "") root.wantSel = backSel;
    // THE STALE-LISTING GUARD HAS TO BE STOOD DOWN FIRST.
    //
    // Results replace `root.rows` without touching `lastListing`, so after a
    // search that guard still holds the text of the directory you searched
    // FROM. Escaping out of results re-lists that same directory, the output
    // matches byte for byte, and the "nothing changed" early return leaves the
    // RESULTS on screen — so Escape appeared to do nothing but drop the WHERE
    // column. null can never be a listing, which is the whole reason it is the
    // sentinel.
    root.act.lastListing = null;
    // A result you opened may have moved you somewhere else entirely, so this
    // is a navigation back rather than a re-listing of wherever you are.
    if (backCwd !== "" && backCwd !== root.cwd) root.enter(backCwd);
    else root.refresh(true);
  }

  // ── tabs ────────────────────────────────────────────────────────────────
  // `cwd` and `sel` stay the live values rather than being read out of the tab
  // array, because every binding in this window already reads them. A switch
  // saves the pair into the tab being left and loads the pair from the tab
  // being entered — so tabs cost one array and two assignments, and nothing
  // downstream has to know they exist.
  property var tabs: [{ cwd: Paths.home(), sel: 0, dual: false, otherCwd: "",
                       otherSel: 0, paneSide: 0, view: "columns" }]
  property int tab: 0

  // Whether the tabs come back at all. Some people want the file manager to
  // open where they left it and some want it to open clean every time, and
  // neither is wrong — so it is a switch rather than a decision made here.
  //
  // Only the RESTORE is gated — the tabs go on being recorded either way, so
  // switching this back on takes effect from the session you are in rather
  // than needing one more restart before it has anything to remember. It does
  // mean the session saved before you turned it off is written over by the
  // next one, which is the right way round: what comes back should be where
  // you actually were last, not where you were the last time you happened to
  // have the setting on.
  property bool sessionReplay: true

  // `tabs` only learns the current tab's cwd when you switch away from it, so
  // the live one is folded in here rather than trusting the stored copy.
  // Everything a tab is, in one object.
  //
  // A tab used to be a directory and a cursor, which was the whole of a pane's
  // state at the time. It is not any more: the second pane, which side the
  // keyboard is on and what each side is looking at all belong to the tab as
  // well, because a tab is meant to be a separate window — split in one and a
  // single pane in the next, neither disturbing the other.
  function tabState() {
    return {
      cwd: root.cwd,
      sel: root.sel,
      // A tab is a place you were, which means it is also the places you were
      // before it. Without this, stepping between tabs would hand one tab's
      // trail to the next and `H` would walk out of a directory this tab has
      // never been in.
      trail: root.act.trail,
      trailAt: root.act.trailAt,
      trailSel: root.act.trailSel,
      // The listing itself travels with the tab. Without it every switch threw
      // the model away and ran `find` again, so a tab emptied and refilled for
      // a keystroke that changed nothing about what was in it — the flicker,
      // and the same one the pane exchange had.
      rows: root.rows,
      // WHERE IT WAS SCROLLED TO, which is not the same as which row the
      // cursor was on. A tab remembered `sel` and nothing else, and the view
      // used to keep its offset across the switch by accident — the origin
      // drifted instead of resetting, which is exactly the bug the rewind in
      // syncView fixes. With the rewind honest about resetting, the offset has
      // to be carried deliberately or every switch lands you at the top.
      scroll: root.keepScroll(),
      // and the bytes they were parsed from, so the refresh that follows a
      // switch can recognise an unchanged directory and leave the model alone.
      // Restoring the rows without this only moved the flicker later: the
      // guard compares against the last listing THIS side read, which would
      // have been the other tab's, so every switch counted as a change and
      // rebuilt every delegate anyway.
      listing: root.lastListing,
      dual: root.dual,
      otherCwd: root.otherCwd,
      otherSel: root.otherSel,
      otherRaw: root.otherRaw,
      paneSide: root.paneSide,
      // What each HALF was showing, read off the halves themselves. It used
      // to be two arrays kept in step by hand at every exchange.
      paneViews: [paneL.viewMode, paneR.viewMode],
      paneZooms: [paneL.zoom, paneR.zoom],
      otherView: root.pas.viewMode,
      view: root.viewMode
    };
  }

  // Put a saved tab back on screen. `otherRaw` travels with it so stepping
  // between tabs does not re-list a directory that was already listed —
  // refreshOther catches anything that changed while it was away.
  function loadTab(t) {
    // ── NOTHING IN HERE IS A PREFERENCE ──────────────────────────────────
    // Loading a tab is terminus rearranging itself, which is exactly what
    // applyDepth exists to say — and it was only being said around the one
    // line that sets the view. The lines above it were not covered, and they
    // are the ones that did the damage: paneViews puts the OLD tab's view on
    // the pane, and the cwd is changed a moment later, so for that moment the
    // window is standing in the new directory wearing the old directory's
    // view. rememberView is unguarded there, and wrote it down.
    //
    // Every new tab therefore recorded its own destination as whatever you
    // happened to be looking at, one step before correcting the view on
    // screen — under a guard, so the correction was never recorded. Opening a
    // tab at home from the grid set home to grid and left it that way, which
    // is the inheritance that survived fixing newTab: the tab was asking the
    // right question and being handed an answer it had just spoiled itself.
    //
    // Raised for the whole function, which is also what makes the comment
    // below true: the tab's own view wins, so the destination's own record
    // must not be applied on the way in either. No early returns, so the
    // release at the end always runs.
    root.applyDepth++;
    if (root.renaming) root.endRename(false);
    root.dual = t.dual === true;
    root.pas.cwd = typeof t.otherCwd === "string" ? t.otherCwd : "";
    root.pas.sel = t.otherSel || 0;
    root.pas.raw = t.otherRaw || [];
    root.paneSide = t.paneSide === 1 ? 1 : 0;
    if (t.paneViews && t.paneViews.length === 2) {
      paneL.viewMode = t.paneViews[0];
      paneR.viewMode = t.paneViews[1];
    }
    if (t.paneZooms && t.paneZooms.length === 2) {
      if (t.paneZooms[0] > 0) paneL.zoom = t.paneZooms[0];
      if (t.paneZooms[1] > 0) paneR.zoom = t.paneZooms[1];
    }
    root.demoteColumns();
    root.act.trail = (t.trail && t.trail.length !== undefined) ? t.trail : [];
    root.act.trailAt = (typeof t.trailAt === "number") ? t.trailAt : -1;
    root.act.trailSel = t.trailSel ? t.trailSel : ({});
    root.act.cwd = t.cwd;
    root.act.query = "";
    filterField.text = "";
    root.act.marked = {};
    root.act.sel = t.sel || 0;
    // Handed back rather than re-read. `lastListing` is cleared with it so the
    // byte-identical guard cannot mistake the next real refresh for a no-op.
    if (t.rows && t.rows.length > 0) {
      root.act.raw = t.rows;
      root.act.lastListing = (t.listing === undefined) ? null : t.listing;
    } else {
      root.act.lastListing = null;
    }
    // The tab's own view, not the destination directory's: arriving in a tab
    // is arriving back where you were, and a tab that rearranged itself on the
    // way in would not be the window you left.
    if (root.viewRing.indexOf(t.view) >= 0) {
      root.applyDepth++;
      root.act.viewMode = t.view;
      root.applyDepth--;
    }
    // AFTER the model has been rebuilt, which is why it is deferred: handing
    // back the rows above runs syncView, and syncView rewinds the views to the
    // top on a wholesale change so their origin cannot drift. That rewind is
    // what keeps the listing from arriving with a band of nothing above it —
    // and it is also what would leave you at the top of every tab you step
    // back into. So the rewind puts the ORIGIN back and this puts YOU back,
    // in that order.
    if (t.scroll) Qt.callLater(root.restoreScroll, t.scroll);
    // The directory is still re-read, but the rows it had are already on
    // screen while that happens, so nothing blinks.
    root.refresh(true);
    root.refreshOther();
    root.applyDepth--;
  }

  function tabList() {
    const out = [];
    for (let i = 0; i < root.tabs.length; ++i)
      out.push(i === root.tab ? root.tabState() : root.tabs[i]);
    return out;
  }

  // WHAT A TAB IS WORTH KEEPING, which is not everything a tab is.
  //
  // A tab carries its listings so switching between them costs no process and
  // no rebuild — and those listings have no business in a preferences file.
  // They are a cache of what is on the disk right now, they are megabytes on a
  // deep directory, and they would be rewritten on every debounced save. What
  // survives a restart is where the tab was pointing and how it was set up;
  // the rows come back from the disk, which is where they came from.
  function tabsForDisk() {
    return root.tabList().map((t) => ({
      cwd: t.cwd, sel: t.sel, view: t.view,
      dual: t.dual, otherCwd: t.otherCwd, otherSel: t.otherSel,
      paneSide: t.paneSide, paneViews: t.paneViews, paneZooms: t.paneZooms
    }));
  }

  function saveTab() {
    const next = root.tabs.slice();
    next[root.tab] = root.tabState();
    root.tabs = next;
  }

  onTabsChanged: viewSave.restart()
  onTabChanged: viewSave.restart()

  // ── rearranging them ────────────────────────────────────────────────────
  // The record moves; the CURSOR follows the record rather than the position.
  // Dragging the tab you are standing in must leave you standing in it, and
  // dragging one past you must not quietly move you to a different directory —
  // which is what happens if `tab` is left pointing at an index whose occupant
  // has changed underneath it.
  //
  // saveTab first, because the live tab's state (its cwd, its selection, its
  // split) lives in the window until something writes it back, and moving the
  // records around before that would file it under the wrong one.
  function moveTab(from, to) {
    if (from < 0 || to < 0 || from === to) return;
    if (from >= root.tabs.length || to >= root.tabs.length) return;
    root.saveTab();
    const next = root.tabs.slice();
    const rec = next.splice(from, 1)[0];
    next.splice(to, 0, rec);
    // the three cases: you moved the tab you are on, you moved one from
    // before you to after you, or the other way round
    let cur = root.tab;
    if (cur === from) cur = to;
    else if (from < cur && cur <= to) cur -= 1;
    else if (to <= cur && cur < from) cur += 1;
    root.tabs = next;
    // set AFTER the list, and deliberately not through switchTab: nothing has
    // been entered or left, so there is nothing to load — reloading here would
    // throw away the listing and rebuild the identical one.
    root.tab = cur;
  }

  function switchTab(i) {
    if (i === root.tab || i < 0 || i >= root.tabs.length) return;
    root.saveTab();
    root.tab = i;
    root.loadTab(root.tabs[i]);
  }

  // A NEW TAB IS A NEW WINDOW: one pane, at home. It used to inherit the
  // current tab's directory and its split, which made "give me a clean sheet"
  // impossible — you got another copy of where you already were.
  // `t` opens at home; middle click and the menu entry open at a directory.
  // Both are the same tab, so they are the same function with an argument
  // rather than two that drift apart.
  function newTab(path) {
    root.saveTab();
    const t = root.tabState();
    t.cwd = (path && path !== "") ? path : Paths.home();
    t.sel = 0;
    // A NEW TAB HAS NOT BEEN ANYWHERE. The state was copied off the tab you
    // are standing in, and its trail came with it — so `H` in a brand new tab
    // would have walked back through somewhere else's history.
    t.trail = [];
    t.trailAt = -1;
    t.trailSel = ({});
    // ── A NEW TAB DOES NOT INHERIT THE VIEW ──────────────────────────────
    // The state is copied off the tab you are standing in, and the view came
    // with it: opening a tab from a pictures folder in the grid put home in
    // the grid too, and kept it there. Nothing was wrong with home's own
    // record — loadTab raises applyDepth, which is what stops applyDirView
    // from asking, so the answer was never read rather than being wrong.
    //
    // Asked here instead, where the destination is already known. How a
    // folder wants to be read is a fact about that folder, so a tab opening
    // onto it starts the way that folder was left, and a folder with no
    // record starts in the plainest view the current layout has rather than
    // in whatever the last one happened to be showing.
    //
    // Only while the memory is on: switched off there is no other source of
    // truth, and inheriting is then the only thing left to do.
    if (root.perDirView) {
      const v = root.dirViews[t.cwd];
      t.view = (v && root.viewRing.indexOf(v.view) >= 0)
        ? v.view : root.viewRing[0];
    }
    // and at the top of it. The state was copied off the tab you are standing
    // in, so without this a new tab opens scrolled to wherever that one was.
    t.scroll = null;
    t.dual = false;
    t.otherCwd = "";
    t.otherSel = 0;
    t.otherRaw = [];
    t.paneSide = 0;
    const next = root.tabs.slice();
    next.push(t);
    root.tabs = next;
    root.tab = next.length - 1;
    root.loadTab(t);
  }

  // A directory in a new tab, leaving this one exactly where it was — which
  // is the whole point of the gesture, so a file (which has no listing to
  // show) is quietly ignored rather than opening a tab onto nothing.
  function openInNewTab(path) {
    if (!path || path === "") return;
    root.newTab(path);
  }

  // Close a tab BY INDEX, which is NOT "step into it and then close the one
  // you are in". Middle click did it that second way — switchTab followed by
  // closeTab — and it was wrong twice over. It paid for a full load of a tab
  // that was about to be thrown away; and switchTab rewrites `tabs`, which is
  // the strip Repeater's model, so replacing it destroyed the delegate whose
  // click handler was still running. Everything after that line was
  // unreachable — it threw "root is not defined" rather than running — so the
  // close simply never happened and the gesture read as "select".
  function closeTabAt(i) {
    if (root.tabs.length < 2) return;   // the last tab is just the window
    if (i < 0 || i >= root.tabs.length) return;
    // The tab you are STANDING IN lives in the window rather than in the
    // array, so its record is written back before anything is removed.
    // Without this, closing a background tab rolled the current one back to
    // whatever it looked like the last time you left it.
    const next = root.tabs.slice();
    next[root.tab] = root.tabState();
    next.splice(i, 1);
    if (i === root.tab) {
      // The one you are in: land on its neighbour, which is what `w` means.
      const land = Math.min(i, next.length - 1);
      root.tabs = next;
      root.tab = -1;          // force the load even when the index is the same
      root.tab = land;
      root.loadTab(next[land]);
      return;
    }
    // ANY OTHER TAB IS ONLY A RECORD. Drop it and stay exactly where you are:
    // nothing about the window changes except which index the current tab
    // sits at, so there is no directory to re-read and nothing to load.
    if (i < root.tab) root.tab = root.tab - 1;
    root.tabs = next;
  }

  function closeTab() { root.closeTabAt(root.tab); }

  // ── zoom ────────────────────────────────────────────────────────────────
  // One number, applied to the sizes that carry information — row height, the
  // glyph, the name, and the grid's cell. Not a scale transform on the whole
  // window: that would blur the text and enlarge the chrome, and the chrome is
  // not what you are trying to see more of.
  // TWO zooms, because they are two different questions.
  //
  // `zoom` scales the rows and the type in list and columns view — how much
  // text fits. `thumbZoom` scales the tiles in the grid — how big the pictures
  // are. One shared number meant sizing your thumbnails up to look at a photo
  // also blew up every row in the other two views, and each had to be undone
  // separately on the way back.
  //
  // Which one a zoom gesture moves is decided by the view you are in, so
  // ctrl+= means "more of what I am looking at" wherever you are.
  // Eased, so a burst of ctrl-+ is one continuous change of scale rather than
  // a stack of steps. Everything sized off zoom — row height, glyphs, names,
  // the grid's cells — moves together because they all read this one number,
  // which is the whole reason it is one number.
  property real zoom: 1.0
  Behavior on zoom {
    NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
  }
  // Eased on the PANE, not here: this is a window onto whichever half is
  // active, and an animation on a binding that changes target when the
  // keyboard moves would slide the number across on every Tab.
  readonly property real thumbZoom: root.act.zoom
  readonly property real zoomMin: 0.7
  readonly property real zoomMax: 2.4

  // The zoom that the view on screen is actually using.
  readonly property real activeZoom: root.viewMode === "grid" ? root.thumbZoom : root.zoom

  function zoomClamp(v) {
    return Math.max(root.zoomMin, Math.min(root.zoomMax, v));
  }

  function zoomBy(step) {
    if (root.viewMode === "grid") root.act.zoom = root.zoomClamp(root.thumbZoom + step);
    else root.zoom = root.zoomClamp(root.zoom + step);
    Qt.callLater(root.positionSel);
  }

  function zoomReset() {
    if (root.viewMode === "grid") root.act.zoom = 1.0;
    else root.zoom = 1.0;
    Qt.callLater(root.positionSel);
  }

  // Straight to a value, for the settings panel's slider — the keys step, and
  // stepping is the wrong gesture when the whole range is drawn in front of
  // you. Which zoom it lands on follows the same rule zoomBy uses: the grid
  // scales its pictures, everything else scales its text, and the two are
  // deliberately independent.
  function setZoom(v) {
    const z = root.zoomClamp(v);
    if (root.viewMode === "grid") root.act.zoom = z;
    else root.zoom = z;
    Qt.callLater(root.positionSel);
  }

  // ── bookmarks ───────────────────────────────────────────────────────────
  // Kept in the shell's own state directory, not next to the config: it is
  // something you accumulate by using terminus, not something you write by hand.
  property var bookmarks: []

  FileView {
    id: bookmarkFile
    path: Quickshell.statePath("terminus-bookmarks")
    blockLoading: true
    printErrors: false
    // FileView can watch its own file, which is the one kind of watching
    // quickshell does offer — so a bookmark added in another terminus window,
    // or edited by hand, shows up here without a restart.
    watchChanges: true

    // TWO SIGNALS, AND THEY ARE NOT THE SAME EVENT. This took three goes.
    //
    // `fileChanged` says the file on disk is no longer what we hold. It
    // refreshes nothing by itself, so it has to ask — and `reload()` only
    // QUEUES the read. text() immediately afterwards still answers with the
    // copy we already had, which is what defeated every previous attempt
    // here: a "we are writing" flag that got stuck and swallowed other
    // windows' changes, and then a comparison against the text we last wrote
    // which compared the OLD content against the NEW and concluded it was
    // somebody else's news — so it re-derived the list from the stale bytes
    // and put back the bookmark you had just removed, about a second after
    // you removed it. That was the "not instant".
    //
    // `textChanged` is where the new bytes actually arrive. By then the
    // question "what does the file say" has an answer, and it does not matter
    // who wrote it: our own write lands here too and simply re-derives the
    // array the sidebar is already showing. There is no state left to get
    // stuck, and nothing to compare.
    onFileChanged: bookmarkFile.reload()
    onTextChanged: root.loadBookmarks()
  }

  function loadBookmarks() {
    const raw = String(bookmarkFile.text() || "").split("\n")
      .map((l) => l.trim()).filter((l) => l !== "");
    root.bookmarks = raw;
  }

  function isBookmarked(path) { return root.bookmarks.indexOf(path) >= 0; }

  // Every change goes through here, and it re-reads before it writes.
  //
  // The list is shared by every terminus window, so "what I think it is" is not
  // good enough to base a write on — the copy in hand can be stale, and a
  // read-modify-write on a stale copy silently reverts whatever another window
  // did. Re-reading immediately before mutating makes the last write win on
  // the CURRENT list rather than on an old one.
  function editBookmarks(mutate) {
    // Re-read before mutating, FOR REAL. reload() queues the read and
    // waitForJob() is what blocks until it has landed — without it, the
    // "modify the CURRENT list rather than an old one" this function exists
    // for was operating on exactly the old one it was trying to avoid.
    // Blocking is already the deal here: blockLoading is on, and this is one
    // short line-per-path file.
    bookmarkFile.reload();
    bookmarkFile.waitForJob();
    root.loadBookmarks();
    const next = root.bookmarks.slice();
    mutate(next);
    // In memory first, so the sidebar changes on this frame. The write comes
    // back round through onTextChanged and re-derives the same array.
    root.bookmarks = next;
    bookmarkFile.setText(next.join("\n") + "\n");
  }

  // One key, both directions: bookmarking the folder you are in and removing
  // it again are the same gesture, and a separate "unbookmark" would need you
  // to know which one you had. Takes any folder, not just the one you are
  // standing in.
  function toggleBookmarkFor(path) {
    let removed = false;
    root.editBookmarks((list) => {
      const at = list.indexOf(path);
      removed = at >= 0;
      if (removed) list.splice(at, 1);
      else list.push(path);
    });
    root.status = removed ? "bookmark removed" : "bookmarked";
  }

  // Which bookmark is being carried and where it would land, held on the
  // window because the row being dragged and the row drawing the drop line are
  // two different rows and neither can see the other.
  // The sidebar row the listing is currently standing in, published by the
  // row itself — see SideRow. Held here because the bar that marks it is a
  // sibling of the Column the rows are in and cannot see inside it.
  property var sideAt: null

  property int markDragFrom: -1
  property int markDragTo: -1

  // ONE MOVE, wherever it was asked for. The sidebar drags and the bookmark
  // sheet presses alt-arrows, and both mean "put this one there" — the file is
  // the order, so whichever does it, both lists follow.
  // `to` is the INDEX it ends up at, which is what the sheet's alt-arrows
  // already mean. A drag speaks in insertion points instead — where the line
  // is drawn, 0..n — and converts before it calls this; see the handler.
  function moveBookmark(from, to) {
    const n = root.bookmarks.length;
    const t = Math.max(0, Math.min(n - 1, to));
    if (from < 0 || from >= n || from === t) return;
    root.editBookmarks((list) => {
      const item = list.splice(from, 1)[0];
      list.splice(t, 0, item);
    });
    root.status = "bookmark moved";
  }

  function removeBookmark(path) {
    root.editBookmarks((list) => {
      const at = list.indexOf(path);
      if (at >= 0) list.splice(at, 1);
    });
    root.status = "bookmark removed";
  }

  function toggleBookmark() { root.toggleBookmarkFor(root.cwd); }

  // What the hint bar should CALL that toggle, which depends on which way it
  // is about to go. A key that does two opposite things should not describe
  // itself with one of them.
  function bookmarkVerb() {
    const r = root.currentRow();
    const onRow = !!(r && r.isDir);
    const path = onRow ? r.path : root.cwd;
    if (root.isBookmarked(path)) return "remove bookmark";
    return onRow ? "bookmark item" : "bookmark this directory";
  }

  // What `b b` acts on: the directory under the cursor if there is one, and
  // otherwise the directory you are standing in. A file cannot be bookmarked —
  // the sidebar navigates to what it lists — so the cursor being on one falls
  // through to the containing directory rather than doing nothing.
  function toggleBookmarkHere() {
    const r = root.currentRow();
    if (r && r.isDir) root.toggleBookmarkFor(r.path);
    else root.toggleBookmark();
  }

  // ── taking the keyboard ─────────────────────────────────────────────────
  // forceActiveFocus() on the frame `visible` is set does nothing: the surface
  // has not been mapped yet, so there is no window for the focus to be active
  // IN, and the call is silently dropped. Every caller here used to make it
  // anyway, which is why the window opened and then ignored every key — the
  // compositor had focused it and Qt had no focus item inside it.
  //
  // So it asks until it has it, the same way cerberus does, and stops the
  // moment it does. Twelve tries at 60ms is well past the point a surface that
  // is going to map has mapped.
  Timer {
    id: focusClaim
    interval: 60
    repeat: true
    property int tries: 0
    // A save dialog wants the NAME FIELD, not the listing — you are there to
    // type a filename. Asked each tick rather than latched at restart, because
    // `portal` is assigned in the same breath as `shown`.
    // THE LISTING, even for a save.
    //
    // It used to be the name field, on the reasoning that you are here to type
    // a filename — but the name is already filled in, and WHERE it goes is the
    // question you actually have to answer. With the keyboard in the field,
    // Return wrote the file wherever the dialog happened to open. With it in
    // the listing, the arrows and the letters do what they do everywhere else
    // in this window and the field is one Tab away when you want it.
    readonly property Item want: content
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      if (!root.shown || focusClaim.want.activeFocus || focusClaim.tries++ > 12) {
        focusClaim.stop();
        return;
      }
      focusClaim.want.forceActiveFocus();
    }
  }

  // ── portal mode ─────────────────────────────────────────────────────────
  // What xdg-desktop-portal-termfilechooser asks for when an application says
  // "open a file". The portal runs a wrapper script, the wrapper hands the
  // request here over ipc and then waits, and terminus answers by writing the
  // chosen paths — one per line — into the file the portal named.
  //
  // Three shapes of request, and they are genuinely different tasks:
  //   open   pick one or more existing things
  //   dir    pick a directory, which means the one you are IN counts
  //   save   type a name for something that does not exist yet
  //
  // A `done` marker is written beside the output file whether the pick was
  // confirmed or cancelled. Without it the wrapper cannot tell "still
  // choosing" from "chose nothing", and a cancel would hang the application
  // that asked until the wrapper's patience ran out.
  property var portal: null   // { multiple, directory, save, out }
  readonly property bool picking: root.portal !== null

  // WHERE YOU LAST SAVED SOMETHING.
  //
  // A save request arrives with a directory the ASKING PROGRAM chose, which is
  // its own download folder or whatever it had open — almost never where you
  // keep things. Landing there and putting the keyboard in the name field
  // meant the obvious gesture, type a name and press Return, wrote the file
  // into the application's idea of a good place; sorting it out afterwards was
  // a cut and a paste in a file manager, which is the thing this dialog was
  // supposed to save you.
  //
  // Where YOU last saved is a far better guess than where the program suggests,
  // and it survives a restart because the habit does. The VALUE lives on the
  // manager — see lastSaveDir there — because a dialog does not outlive its
  // own answer. This is only the door to the preferences file.
  function persistPrefs() { viewSave.restart(); }

  readonly property string portalTitle: {
    if (!root.portal) return "";
    if (root.portal.save) return "Save as";
    if (root.portal.directory) return "Choose a directory";
    return root.portal.multiple ? "Choose files" : "Choose a file";
  }

  // What confirming would hand back, so the button can say how many and refuse
  // when there is nothing to give.
  readonly property var portalChoice: {
    if (!root.portal) return [];
    if (root.portal.save) {
      const n = saveField.text;
      return Terminus.nameError(n) === "" ? [Terminus.joinPath(root.cwd, n)] : [];
    }
    if (root.portal.directory) {
      // a marked directory if you marked one, otherwise the one you are
      // standing in — which is what "choose this directory" means
      const dirs = root.markedRows().filter((r) => r.isDir);
      if (dirs.length > 0) return dirs.map((r) => r.path);
      const c = root.currentRow();
      if (c && c.isDir) return [c.path];
      return [root.cwd];
    }
    const files = root.acting().filter((r) => !r.isDir);
    if (files.length === 0) return [];
    return root.portal.multiple ? files.map((r) => r.path) : [files[0].path];
  }

  Process {
    id: sizeProc
    stdout: StdioCollector {
      id: sizeOut
      waitForEnd: true
      onStreamFinished: props.walked = parseFloat(String(sizeOut.text).trim()) || 0
    }
  }

  // HOW MANY, beside how big. A size answers "will this fit"; a count answers
  // "what am I about to move", and for a directory those are different
  // questions — 30GB in four files and 30GB in ninety thousand are the same
  // row on this card and nothing alike to copy.
  Process {
    id: countProc
    stdout: StdioCollector {
      id: countOut
      waitForEnd: true
      onStreamFinished: {
        const n = String(countOut.text || "").trim().split("\n");
        const f = parseInt(n[0], 10);
        const d = parseInt(n[1], 10);
        props.files = isNaN(f) ? -1 : f;
        props.dirs = isNaN(d) ? -1 : d;
      }
    }
  }

  Process {
    id: ownerProc
    stdout: StdioCollector {
      id: ownerOut
      waitForEnd: true
      onStreamFinished: props.owner = String(ownerOut.text || "").trim()
    }
  }

  // The window decides WHAT the answer is; the manager writes it.
  //
  // A picker window is destroyed the moment it answers, and a Process owned by
  // it would be torn down mid-write — leaving the portal waiting forever on a
  // `.done` marker that never arrived. So the reply goes out through the
  // manager, which outlives the dialog.
  Process {
    id: imageProc
    stdout: StdioCollector {
      id: imageOut
      waitForEnd: true
      onStreamFinished: props.imageInfo = Terminus.parseImageInfo(imageOut.text)
    }
  }

  Process {
    id: sumProc
    stdout: StdioCollector {
      id: sumOut
      waitForEnd: true
      onStreamFinished: {
        const t = String(sumOut.text || "").trim();
        props.checksum = t === "" ? "unreadable" : t;
      }
    }
  }

  function portalAnswer(paths) {
    if (!root.portal) return;
    // Recorded on the way out rather than on every step, so cancelling a
    // dialog does not teach it anything.
    if (root.portal.save && paths.length > 0 && root.mgr)
      root.mgr.noteSaveDir(Terminus.dirname(paths[0]));
    const out = root.portal.out;
    root.portal = null;
    if (root.mgr) {
      root.mgr.answerPortal(out, paths);
      // a dedicated dialog is done existing, not merely hidden
      if (root.mgr.pickerWin === root) { root.mgr.retirePicker(); return; }
    }
    root.shown = false;
  }

  function portalConfirm() {
    const c = root.portalChoice;
    if (c.length === 0) return;
    root.portalAnswer(c);
  }

  function portalCancel() { root.portalAnswer([]); }

  // ── which way it is laid out ────────────────────────────────────────────
  //   list    one row per entry, with size and date. What you want when the
  //           question is "how big" or "when did I touch this".
  //   columns yazi's miller layout — parent, here, and a preview of whatever
  //           is under the cursor. What you want while NAVIGATING, because
  //           you can see where you came from and where you are about to go
  //           without moving.
  //   grid    thumbnails. What you want in a folder of pictures, where the
  //           filename is the least useful thing about the file.
  readonly property string viewMode: root.act.viewMode
  // MILLER COLUMNS IS A THREE-COLUMN LAYOUT, and two of them side by side is
  // six columns of listing in half a window each. So while the second pane is
  // open the ring is list and grid — the two views that are a single column
  // and therefore mean the same thing at half width. Closing the pane brings
  // columns back.
  readonly property var viewRing: root.dual
    ? ["list", "grid"] : ["columns", "list", "grid"]

  // syncPaneView STOOD HERE and copied the active half's view and zoom into
  // the arrays indexed by side, on every change, so that stepping away and
  // back returned to it. The pane holds them itself now; there is nothing to
  // copy and nothing that can fall out of step.

  // Whatever was on columns when the second pane opened lands on list: a
  // three-column layout in half a window is six columns of listing at a
  // quarter width each. Guarded like every other view written by terminus
  // rather than by you, so it is not recorded as the directory's preference.
  function demoteColumns() {
    if (!root.dual) return;
    root.applyDepth++;
    if (paneL.viewMode === "columns") paneL.viewMode = "list";
    if (paneR.viewMode === "columns") paneR.viewMode = "list";
    root.applyDepth--;
  }

  function cycleView() {
    const i = root.viewRing.indexOf(root.viewMode);
    root.act.viewMode = root.viewRing[(i + 1) % root.viewRing.length];
    Qt.callLater(root.positionSel);
  }

  // Straight to a named view, for the settings panel's three buttons. `v`
  // cycles, and cycling is the wrong gesture when the thing you want is
  // written on screen in front of you. A view that is not in the ring is
  // REFUSED rather than set and quietly undone — while the window is split,
  // columns is not one of the three, and demoteColumns says why.
  function setView(v) {
    if (root.viewRing.indexOf(v) < 0) return;
    root.act.viewMode = v;
    Qt.callLater(root.positionSel);
  }

  // ── how solid the window is ─────────────────────────────────────────────
  //
  // Zenon.layerBg is 0xcc black, the ground every layer in this shell sits on,
  // and this is that alpha made adjustable: a file manager is a window you
  // keep open OVER other windows, and how much of them you want to see through
  // it depends on what you are doing rather than on a constant in a cmdPalette.
  //
  // Floored well short of nothing. A window you cannot read is not a setting
  // anyone wants, and the slider has no way back once the text is gone.
  property real winAlpha: 0.80
  readonly property real winAlphaMin: 0.35
  function setAlpha(a) {
    if (isNaN(a)) return;
    root.winAlpha = Math.max(root.winAlphaMin, Math.min(1.0, a));
    viewSave.restart();
  }

  // ── what it opens as ────────────────────────────────────────────────────
  // The view you were last in, not the one the file happens to declare above.
  // Columns is the right DEFAULT — it is what you want while navigating — but
  // it is a poor thing to be dropped back into every single time when you live
  // in thumbnails, and re-pressing `v` twice on every launch is not a setting.
  //
  // The view PREFERENCES travel together because they are one answer to "how
  // do I like looking at files": which layout, how big, sorted how, and
  // whether the dotfiles are in. Where you were is deliberately not in here —
  // a file manager that reopens in last week's directory is a surprise, not a
  // convenience.
  FileView {
    id: viewFile
    path: Quickshell.statePath("terminus-view.json")
    blockLoading: true
    printErrors: false
  }

  // Debounced, because zoom arrives as a burst of ctrl-+ and writing the file
  // on every step would be a dozen writes for one gesture.
  Timer {
    id: viewSave
    interval: 400
    onTriggered: {
      // A PICKER is not a preference. pick() forces columns so the dialog is
      // always laid out the way a dialog should be, and letting that overwrite
      // the view you actually chose would mean every save dialog reset it.
      if (root.picking) return;
      // The OPEN TABS travel with the view preferences, because they are the
      // same question: how was this window set up when I left it. Only window 0
      // restores them — a spare window you opened with N is a scratch view, and
      // a picker is not a window you own at all.
      viewFile.setText(JSON.stringify({
        tabs: root.winId === 0 ? root.tabsForDisk() : undefined,
        tab: root.winId === 0 ? root.tab : undefined,
        view: root.viewMode,
        zoom: root.zoom,
        sidebar: root.sidebar,
        sidebarWidth: root.sidebarWidth,
        thumbsOn: root.thumbsOn,
        dirsFirst: root.dirsFirst,
        naturalSort: root.naturalSort,
        alwaysTabs: root.alwaysTabs,
        colHeadsOn: root.colHeadsOn,
        confirmTrash: root.confirmTrash,
        cursorSlide: root.cursorSlide,
        termCmd: root.termCmd,
        previewOn: root.previewOn,
        dirViewCap: root.dirViewCap,
        thumbZoom: root.thumbZoom,
        sortKey: root.sortKey,
        sortDesc: root.sortDesc,
        usage: root.usage,
        git: root.git,
        showHidden: root.showHidden,
        winAlpha: root.winAlpha,
        perDirView: root.perDirView,
        lastSaveDir: root.mgr ? root.mgr.lastSaveDir : "",
        sessionReplay: root.sessionReplay,
        dual: root.dual,
        otherCwd: root.otherCwd,
        paneSide: root.paneSide,
        paneViews: [paneL.viewMode, paneR.viewMode],
        paneZooms: [paneL.zoom, paneR.zoom],
        paneFrac: root.paneFrac,
        dirViews: root.dirViews
      }) + "\n");
    }
  }

  function loadViewPrefs() {
    const raw = String(viewFile.text() || "").trim();
    if (raw === "") return;
    let s = null;
    // A half-written or hand-edited file must not take the window down with
    // it: bad preferences are worth less than a working file manager.
    try { s = JSON.parse(raw); } catch (e) { return; }
    if (!s) return;
    if (root.viewRing.indexOf(s.view) >= 0) root.act.viewMode = s.view;
    const z = Number(s.zoom);
    if (!isNaN(z) && z > 0) root.zoom = root.zoomClamp(z);
    const tz = Number(s.thumbZoom);
    if (!isNaN(tz) && tz > 0) root.act.zoom = root.zoomClamp(tz);
    if (typeof s.sidebar === "boolean") root.sidebar = s.sidebar;
    const sw = Number(s.sidebarWidth);
    if (!isNaN(sw) && sw > 0)
      root.sidebarWidth = Math.max(root.sidebarMin, Math.min(root.sidebarMax, sw));
    root.usage = s.usage === true;
    // The flag alone, with no scan: loadViewPrefs runs before the first
    // refresh (see Component.onCompleted) and refresh is what asks git. Calling
    // toggleGit here would scan a directory the window has not listed yet.
    root.git = s.git === true;
    // "usage" is the mode's own sort key and means nothing without the mode.
    // Restoring one without the other would leave the window in an order with
    // no bars and no explanation for it.
    if (typeof s.sortKey === "string" && s.sortKey !== ""
        && (s.sortKey !== "usage" || root.usage))
      root.sortKey = s.sortKey;
    if (typeof s.sortDesc === "boolean") root.sortDesc = s.sortDesc;
    if (typeof s.showHidden === "boolean") root.showHidden = s.showHidden;
    if (typeof s.perDirView === "boolean") root.perDirView = s.perDirView;
    if (typeof s.thumbsOn === "boolean") root.thumbsOn = s.thumbsOn;
    if (typeof s.dirsFirst === "boolean") root.dirsFirst = s.dirsFirst;
    if (typeof s.naturalSort === "boolean") root.naturalSort = s.naturalSort;
    if (typeof s.alwaysTabs === "boolean") root.alwaysTabs = s.alwaysTabs;
    if (typeof s.colHeadsOn === "boolean") root.colHeadsOn = s.colHeadsOn;
    if (typeof s.confirmTrash === "boolean") root.confirmTrash = s.confirmTrash;
    if (typeof s.cursorSlide === "boolean") root.cursorSlide = s.cursorSlide;
    if (typeof s.termCmd === "string") root.termCmd = s.termCmd;
    if (typeof s.previewOn === "boolean") root.previewOn = s.previewOn;
    if (typeof s.dirViewCap === "number" && s.dirViewCap > 0)
      root.dirViewCap = Math.round(s.dirViewCap);
    if (typeof s.lastSaveDir === "string" && root.mgr
        && root.mgr.lastSaveDir === "") root.mgr.lastSaveDir = s.lastSaveDir;
    if (typeof s.sessionReplay === "boolean") root.sessionReplay = s.sessionReplay;
    const wa = Number(s.winAlpha);
    if (!isNaN(wa) && wa > 0)
      root.winAlpha = Math.max(root.winAlphaMin, Math.min(1.0, wa));
    // The second pane comes back the way it was left, and its directory with
    // it — but only if that directory still exists, for the same reason the
    // tabs are checked: a pane opening on a removed download is a pane opening
    // on an error.
    if (typeof s.otherCwd === "string") root.pas.cwd = s.otherCwd;
    if (s.paneSide === 1) root.paneSide = 1;
    if (s.paneViews && s.paneViews.length === 2) {
      paneL.viewMode = s.paneViews[0];
      paneR.viewMode = s.paneViews[1];
    }
    if (s.paneZooms && s.paneZooms.length === 2) {
      if (s.paneZooms[0] > 0) paneL.zoom = s.paneZooms[0];
      if (s.paneZooms[1] > 0) paneR.zoom = s.paneZooms[1];
    }
    root.demoteColumns();
    const pf = Number(s.paneFrac);
    if (!isNaN(pf) && pf > 0)
      root.paneFrac = Math.max(root.paneMinFrac, Math.min(root.paneMaxFrac, pf));
    if (s.dirViews && typeof s.dirViews === "object") {
      root.dirViews = s.dirViews;
      root.dirViewOrder = Object.keys(s.dirViews);
    }
    // A PICKER IS NOT A FILE MANAGER. It is a dialog with one job — say which
    // file — and a second pane is a place to put things, which is the one
    // thing it must never be. winId is -1 for the portal's own window and is
    // set before this runs, so the preference is simply not read for it.
    if (root.winId >= 0 && s.dual === true && root.otherCwd !== "") {
      root.dual = true;
      root.refreshOther();
    }
    root.restoreTabs(s);
  }

  // Reopening where you left off, but only the tabs whose directories are still
  // there — a tab pointing at a removed download or an unmounted disk would be
  // a window that opens on an error. Checked by the caller, which is why this
  // hands the surviving list to a process rather than trusting the file.
  function restoreTabs(st) {
    if (root.winId !== 0) return;
    if (!root.sessionReplay) return;
    if (!st.tabs || st.tabs.length === 0) return;
    const want = [];
    for (let i = 0; i < st.tabs.length; ++i) {
      const t = st.tabs[i];
      if (t && typeof t.cwd === "string" && t.cwd !== "") want.push(t);
    }
    if (want.length === 0) return;
    root.pendingTabs = want;
    root.pendingTabIndex = (typeof st.tab === "number") ? st.tab : 0;
    tabCheckProc.command = ["sh", "-c",
      "for d in " + want.map((t) => Strings.shellQuote(t.cwd)).join(" ")
        + "; do [ -d \"$d\" ] && printf '%s\\036' \"$d\"; done"];
    tabCheckProc.running = true;
  }

  property var pendingTabs: []
  property int pendingTabIndex: 0

  Process {
    id: tabCheckProc
    stdout: StdioCollector {
      id: tabCheckOut
      waitForEnd: true
      onStreamFinished: {
        const alive = {};
        for (const d of String(tabCheckOut.text || "").split("\u001e")) {
          if (d !== "") alive[d] = true;
        }
        const kept = root.pendingTabs.filter((t) => alive[t.cwd]);
        root.pendingTabs = [];
        if (kept.length === 0) return;
        root.tabs = kept;
        root.tab = Math.max(0, Math.min(kept.length - 1, root.pendingTabIndex));
        const t = kept[root.tab];
        root.act.sel = t.sel || 0;
        // enter() rather than goTo(): this is where the window already is as
        // far as history is concerned, not somewhere it navigated to.
        root.enter(t.cwd);
      }
    }
  }

  // rememberView restarts the save itself — see how each directory likes to
  // be looked at, above
  onZoomChanged: root.rememberView()
  onThumbZoomChanged: root.rememberView()
  onSidebarChanged: viewSave.restart()
  onSidebarWidthChanged: viewSave.restart()
  // Both write the directory's record, the same way a view change does. The
  // applyDirView guard inside rememberView is what stops this echoing back
  // while a record is being applied.
  onSortKeyChanged: { root.rememberView(); viewSave.restart(); }
  onSortDescChanged: { root.rememberView(); viewSave.restart(); }
  onShowHiddenChanged: viewSave.restart()

  // Every view scrolls its own way, and only one of them is on screen — but
  // telling all three is cheaper than asking which, and means switching view
  // never lands you somewhere other than where the cursor was.
  // ── holding your place while the listing is rebuilt ─────────────────────
  // THE MODEL IS AN ARRAY, and handing a view a new one is a full reset: Qt
  // rebuilds every delegate and, often enough, drops the scroll to zero.
  // Measured in /tmp, which changes every second or two — contentY went 784
  // to 0, then 2352 to 0, on refreshes that moved no cursor and asked for no
  // repositioning. Anything you had scrolled to was gone, and the row under
  // the pointer with it.
  //
  // The proper cure is a model the view can be told about incrementally
  // rather than handed wholesale, which is a much larger change than this
  // window wants right now. Putting the offset back is the small one, and it
  // is what the symptom actually asks for.
  function keepScroll() {
    return { list: root.actList.contentY, mid: root.midCol.view.contentY,
             parent: root.parCol.view.contentY, grid: root.actGrid.contentY };
  }

  function restoreScroll(keep) {
    if (!keep) return;
    root.putScroll(root.actList, keep.list);
    root.putScroll(root.midCol.view, keep.mid);
    root.putScroll(root.parCol.view, keep.parent);
    root.putScroll(root.actGrid, keep.grid);
  }

  // Clamped, because the listing that came back may be shorter than the one
  // that went in — scrolled to the bottom of a directory that just lost forty
  // rows, the old offset is past the end of the new one.
  function putScroll(v, y) {
    if (!v || y === undefined || y === v.contentY) return;
    const most = Math.max(0, v.contentHeight - v.height);
    v.contentY = Math.max(0, Math.min(most, y));
  }

  function positionSel() {
    root.actList.positionViewAtIndex(root.sel, ListView.Contain);
    root.midCol.view.positionViewAtIndex(root.sel, ListView.Contain);
    root.actGrid.positionViewAtIndex(root.sel, GridView.Contain);
  }

  // A LISTING'S BYTES, ARRANGED THE WAY THIS WINDOW ARRANGES LISTINGS. The
  // middle column, the left column and the preview all turn `find` output
  // into rows, and all three had their own copy of the same four calls. One
  // of them is also what lets a column be filled from the remembered bytes
  // rather than from a process — see seedParent and the preview.
  function rowsFromListing(text, dir) {
    return root.enrich(Terminus.sortEntries(
      Terminus.filterEntries(Terminus.parseListing(text, dir), "",
                             root.showHidden),
      root.sortKey, root.sortDesc, root.dirsFirst, root.naturalSort));
  }


  // ── the parent, for the left column ─────────────────────────────────────
  property var parentRows: []
  // The bytes the left column was built from, so an answer that says nothing
  // new leaves it alone. Same guard, same reason, as the listing's own.
  property var parentListing: null

  // THE COLUMN YOU CAME FROM IS ALWAYS ALREADY KNOWN. Entering a directory
  // makes its parent the directory you were just standing in, and every
  // listing this window reads is remembered as the bytes it came back as —
  // so the left column can be drawn in the same frame as the step instead of
  // a process later. Without this it went on showing the GRANDPARENT until
  // `find` answered, which is the list that flashed on the way in.
  function seedParent() {
    if (root.cwd === "/") { root.parentRows = []; root.parentListing = null; return; }
    const dir = Terminus.dirname(root.cwd);
    const seen = root.listingText[dir];
    if (seen === undefined || seen === root.parentListing) return;
    root.parentListing = seen;
    root.parentRows = root.rowsFromListing(seen, dir);
  }

  Process {
    id: parentProc
    stdout: StdioCollector {
      id: parentOut
      waitForEnd: true
      onStreamFinished: {
        // A listing for a directory we have since left the root of — same
        // guard as the launch above, for an answer that was already in flight.
        if (root.cwd === "/") { root.parentRows = []; root.parentListing = null; return; }
        const dir = Terminus.dirname(root.cwd);
        root.rememberListing(dir, parentOut.text);
        // Byte-identical to what the column is already drawing — which is the
        // ordinary case now that it is seeded, since the seed IS the bytes
        // this process was about to return. Rebuilding every row to arrive at
        // the same rows is the redraw this guard exists to refuse.
        if (parentOut.text === root.parentListing) return;
        root.parentListing = parentOut.text;
        root.parentRows = root.rowsFromListing(parentOut.text, dir);
        Qt.callLater(() => root.parCol.view.positionViewAtIndex(root.parentIndex, ListView.Contain));
      }
    }
  }

  // where the directory we are IN sits in its own parent, so the left column
  // can mark it the way the middle column marks the cursor
  readonly property int parentIndex: {
    for (let i = 0; i < root.parentRows.length; ++i)
      if (root.parentRows[i].path === root.cwd) return i;
    return -1;
  }

  // ── the preview, for the right column ───────────────────────────────────
  // What the preview has already produced, keyed by path. Walking back up a
  // list re-selects rows you were just on, and re-running bat and re-laying
  // out its markup to show you the same thing again is the delay you feel.
  // Capped, because a preview of a big file is a big string.
  // ── ARRIVING SOMEWHERE YOU HAVE ALREADY SEEN ────────────────────────────
  // Raw `find` output by directory. Miller's whole shape is that the column on
  // the right is ALREADY the directory you are about to step into — the peek
  // that drew it is the same command, with the same flags, that listing it
  // would run. Stepping in threw that away and waited for a process to tell it
  // again, which is most of the lag on every `l` and every click.
  //
  // Kept as TEXT rather than as parsed rows, so the seed is byte-identical to
  // what the refresh behind it will return: lastListing is set from the same
  // string, so the confirming listing recognises itself and returns without
  // touching the model at all. Arriving costs a parse instead of a process.
  //
  // Small and short: sixteen directories, nothing over 64KB. This is a way of
  // not waiting, not a cache of the filesystem.
  property var listingText: ({})
  property var listingOrder: []

  function rememberListing(dir, text) {
    if (!dir || dir === "" || text.length > 65536) return;
    const c = Object.assign({}, root.listingText);
    const o = root.listingOrder.slice();
    if (c[dir] === undefined) o.push(dir);
    c[dir] = text;
    while (o.length > 16) delete c[o.shift()];
    root.listingText = c;
    root.listingOrder = o;
  }

  property var previewCache: ({})
  property var previewOrder: []

  function cachePreview(path, entry) {
    const c = Object.assign({}, root.previewCache);
    const o = root.previewOrder.slice();
    c[path] = entry;
    o.push(path);
    while (o.length > 24) delete c[o.shift()];
    root.previewCache = c;
    root.previewOrder = o;
  }

  // ── THE SETTINGS PANEL'S CURSOR ────────────────────────────────────────
  // The panel used to say of itself that it "has no keyboard of its own — it
  // is a panel of switches you point at", and that is true right up until the
  // moment your hands are already on the keys. Tab walks it now.
  //
  // THE ROWS ENROL THEMSELVES rather than being listed here: they are written
  // inline in two columns and there are twenty-two of them, and a hand-kept
  // index beside that is a second list to forget to update.
  //
  // AND THEN THEY ARE SORTED BY WHERE THEY ARE. Enrolment order is completion
  // order, and Component.onCompleted is emitted children-before-parents with
  // no promise about siblings — so the registry came out backwards and Tab
  // started at the bottom of the right-hand column. Position is the only thing
  // that agrees with what the eye is going to do: down the left column, then
  // down the right.
  property var prefRows: []
  property int prefCursor: -1

  function prefEnrol(item) {
    const a = root.prefRows.slice();
    a.push(item);
    root.prefRows = a;
  }

  function prefOrder() {
    const rows = root.prefRows.slice();
    rows.sort((a, b) => {
      const pa = a.mapToItem(prefsCol, 0, 0);
      const pb = b.mapToItem(prefsCol, 0, 0);
      // The column first — a row in the left one comes before every row in the
      // right, however far down it sits. Compared with a tolerance because the
      // two columns are placed by arithmetic on the sheet's width and need not
      // land on whole pixels.
      if (Math.abs(pa.x - pb.x) > 1) return pa.x - pb.x;
      return pa.y - pb.y;
    });
    root.prefRows = rows;
  }

  function prefAt() {
    return (root.prefCursor >= 0 && root.prefCursor < root.prefRows.length)
      ? root.prefRows[root.prefCursor] : null;
  }

  // Past anything not reachable — the one action row switches itself off when
  // there is nothing left to forget — and bounded by the list's own length so
  // a panel of nothing reachable cannot spin.
  function prefStep(d) {
    const n = root.prefRows.length;
    if (n === 0) return;
    let i = root.prefCursor;
    for (let t = 0; t < n; t++) {
      i = (i + d + n) % n;
      if (root.prefRows[i].reachable) break;
    }
    root.prefCursor = i;
  }

  // ── THE KEYMAP ─────────────────────────────────────────────────────────
  // This was the F1 page's own table and it is the only copy of it now. The
  // page is gone: it and the palette were the same list twice — one you read
  // and closed and then pressed the key, one you typed into and ran — and the
  // palette was already drawing the key beside every verb. So the keymap IS
  // the palette, and there is one thing to open instead of two.
  //
  // STILL GROUPED, because ninety keys in a flat list is a wall. The palette
  // shows these headings when nothing is typed and drops them when something
  // is: grouped to read, ranked to search.
  //
  // Nothing here carries a verb, and most of it CANNOT. j and k are the
  // cursor, escape means four different things depending on what is up, and
  // the mouse gestures are not keys at all. The ones that can are matched to
  // the verb table by KEY, below, so the runnable half stays runnable and
  // nothing is listed twice.
  readonly property var keyGroups: [
    // No back/forward row: they are verbs, so the palette lists them itself
    // rather than this writing the same pair down a second time.
    ["move", [["j / k  ↓ ↑", "down / up"],
              ["←  backspace", "parent"], ["→", "enter a directory"],
              ["↵", "open"], ["i", "quick look"],
              ["g g", "top"], ["G", "bottom"],
              ["ctrl u / d", "half page"], ["ctrl b / f", "page"],
              [root.mouseKey(4) + " / " + root.mouseKey(5),
               "back / forward"]]],
    ["select", [["space", "toggle and move on"],
                ["v", "visual select"],
                ["ctrl a", "select all"],
                ["ctrl r", "invert selection"],
                ["esc", "leave visual, then clear"]]],
    ["act", [["y y", "copy"], ["y s", "copy to"],
             ["x x", "cut"], ["x s", "move to"], ["p", "paste"],
             ["d", "trash"], ["D", "delete for good"],
             ["a", "create (end in / for a directory)"], ["r", "rename"],
             ["c m", "permissions"], [";  ctrl s", "shell here"],
             ["u", "undo trash / move / rename"],
             ["z", "measure directory size"],
             ["c a", "archive selection"]]],
    ["look", [["f  /", "filter"], ["s", "search names"],
              ["S", "search contents"], [".", "hidden"],
              [", n / s / m / k", "sort name / size / time / kind"],
              [", !", "reverse"],
              ["V", "view: columns · list · grid"], ["+ / -", "zoom"],
              ["ctrl 0", "reset zoom"]]],
    ["go", [["g space", "go to\u2026 (tab completes)"],
            ["g h", "home"], ["g c", "config"], ["g d", "downloads"],
            ["g D", "documents"], ["g p", "pictures"], ["g v", "videos"],
            ["g t", "trash"], ["g m", "media"], ["g /", "root"]]],
    ["copy", [["c c", "full path"], ["c d", "directory"],
              ["c f", "filename"], ["c n", "name without extension"]]],
    ["tabs", [["t", "new"], ["w", "close"], ["1 - 9", "switch"],
              ["shift return", "open a directory in a new tab"],
              [root.mouseKey(3), "open a directory in a new tab"],
              ["[  ]", "previous / next"]]],
    ["panes", [["\\", "second pane on / off"],
               ["tab  o", "step into the other side"],
               ["alt \u2190 \u2192", "resize the split"],
               ["|", "sidebar on / off"],
               ["alt shift \u2190 \u2192", "resize the sidebar"],
               ["f5", "copy to the other side"],
               ["f6", "move to the other side"],
               [root.mouseKey(1), "step into the other side"]]],
    ["marks", [["b a", "bookmark this directory"],
               ["b b", "bookmark the item under the cursor"]]],
    ["dialogs", [["esc", "close"], ["return", "accept"],
                 ["\u2190 \u2192 \u2191 \u2193", "move (permissions)"],
                 ["space", "toggle a bit"],
                 ["s", "checksum (properties)"]]],
    ["menu", [["menu key", "actions for the row"],
              [root.mouseKey(2), "actions for the row"],
              ["\u2014", "extract · archive · open with"],
              ["\u2014", "bulk rename · links · restore"],
              ["\u2014", "sort, as a submenu"]]],
    ["window", [["q", "close"],
                ["esc", "clear filter / selection"],
                [root.mouseKey(4) + " / " + root.mouseKey(5),
                 "back / forward"]]],
    // THE LIST DESCRIBING ITSELF, which is not as odd as it looks: it is the
    // keymap, and the keys that drive it are keys. They were the one set that
    // was only ever printed along its own footer, where a hint strip is read
    // once and then stops being looked at.
    //
    // F1 is not among them any more. It opened a separate keymap page, that
    // page is this list, and a second key to the same door is a key to
    // remember for nothing.
    ["palette", [["F1 / ~ / ctrl p", "open this list"],
                 ["\u2014", "type to filter"],
                 ["\u2191 \u2193", "move"],
                 ["\u21b5", "run the highlighted verb"],
                 ["esc", "close"]]]
  ]

  // ── EVERY VERB, BY NAME ────────────────────────────────────────────────
  // The two-key sequences come from `content.sequences`, which already pairs
  // a label with the function it calls, so those cannot drift from what the
  // keys actually do. The single-key verbs are a switch rather than a table
  // and are named here — the one list in this file that has to be kept in
  // step by hand, and the smaller half of the job.
  //
  // A label that is a FUNCTION is called: `b b` says "bookmark" or "remove
  // bookmark" depending on the row, and a palette that said one of those when
  // it meant the other would be worse than not listing it.
  //
  // THE KEYMAP DECIDES THE ORDER AND THE VERB TABLE DECIDES WHAT RUNS. Read
  // the groups in order, hand each row the verb that shares its key, and put
  // whatever verb the keymap never mentioned in a group of its own at the end
  // — so a thing that can be done is never unreachable just because the page
  // it was written for did not list it.
  readonly property var commands: {
    const verbs = [];
    const seqs = content.sequences;
    for (const prefix in seqs) {
      const rows = seqs[prefix];
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const label = (typeof r[1] === "function") ? r[1]() : r[1];
        const key = prefix + " " + (r[0] === " " ? "space" : r[0]);
        verbs.push({ label: label, key: key, act: r[2], used: false });
      }
    }
    const one = [
      ["open",              "\u21b5", () => root.activate()],
      ["open with",         "",        () => root.beginOpenWith(
                                              root.currentRow()
                                                ? root.currentRow().path : "")],
      ["quick look",        "i",       () => root.quickLook()],
      // BOTH KEYS ON THE VERB, not a verb keyed `h` and a keymap row saying
      // `h / l  ← →` beside it. They were the same two things listed twice —
      // once as something you could run and once as something to read — and
      // the palette drew them as two rows a few lines apart.
      ["back",              "h",       () => root.back()],
      ["forward",           "l",       () => root.forward()],
      ["up a directory",    "h",       () => root.goUp()],
      ["rename",            "r",       () => root.beginRename()],
      ["bulk rename",       "r",       () => root.beginBulkRename()],
      ["duplicate",         "y d",     () => root.duplicate()],
      ["paste",             "p",       () => root.paste()],
      ["new file or folder", "a",      () => root.beginCreate()],
      ["trash",             "d",       () => root.trash()],
      ["delete for good",   "D",       () => root.deleteForever()],
      ["undo",              "u",       () => root.undo()],
      ["select all",        "ctrl a",  () => root.selectAll()],
      ["invert selection",  "ctrl r",  () => root.invertSelection()],
      ["find by name",      "f",       () => searchBar.begin("find")],
      ["search contents",   "s",       () => searchBar.begin("grep")],
      // alt return, which is the key it has always answered to and the only
      // verb here listed with no key at all — the palette drew it with an
      // empty chip while the keymap wrote the key down separately, so neither
      // half said the whole thing.
      ["properties",        "alt \u21b5",  () => props.ask()],
      ["permissions",       "c m",     () => perms.ask()],
      ["new tab",           "t",       () => root.newTab()],
      ["close tab",         "ctrl c",  () => root.closeTab()],
      ["split view",        "\\",      () => root.toggleDual()],
      ["step to other pane", "o",      () => root.stepOver()],
      ["sidebar",           "|",       () => root.sidebar = !root.sidebar],
      ["cycle view",        "V",       () => root.cycleView()],
      ["hidden files",      ".",       () => root.showHidden = !root.showHidden],
      ["disk usage",        ", u",     () => root.toggleUsage()],
      ["git status",        ", g",     () => root.toggleGit()],
      ["open a shell here", "ctrl s",  () => root.openShell()],
      ["settings",          "",        () => prefs.open = true]
    ];
    for (let i = 0; i < one.length; i++)
      verbs.push({ label: one[i][0], key: one[i][1], act: one[i][2],
                   used: false });

    // FIRST VERB PER KEY, and only for a key that is one. Two verbs can share
    // a key — `r` is rename on one row and bulk rename on several — and three
    // have no key at all, so a plain map keyed by key would have silently
    // dropped the second of each pair. The keymap row takes the first; the
    // rest come back below, unclaimed and still listed.
    const byKey = ({});
    for (let i = 0; i < verbs.length; i++) {
      const k = verbs[i].key;
      if (k !== "" && byKey[k] === undefined) byKey[k] = verbs[i];
    }

    const out = [];
    const gs = root.keyGroups;
    for (let g = 0; g < gs.length; g++) {
      const name = gs[g][0];
      const rows = gs[g][1];
      // ── WHAT A ROW CLAIMS, AND WHAT IT ONLY SHOWS ─────────────────
      // A row is paired to a verb by KEY, which is convenient and is held
      // together by two strings agreeing. Two things went wrong with that and
      // both are answered here.
      //
      // FIRST, keys mean different things in different places. `dialogs` and
      // `menu` describe keys that work INSIDE something else — a card that is
      // up, or the row menu — so `s`, which is "checksum" under the properties
      // card, claimed the listing's SEARCH CONTENTS verb: the row came up
      // yellow and return on it would have started a filename search. The same
      // trap sat on `esc`, `return` and `space`. Those two groups claim
      // nothing.
      //
      // SECOND, a row that writes its key the way a READER wants it — `h  ←`,
      // `g / G` — no longer matches the verb's own key and silently stops
      // claiming. So a row may NAME the verb it claims as a third element, and
      // then the two are tied by something written down rather than by two
      // strings happening to agree.
      const modal = name === "dialogs" || name === "menu";
      for (let i = 0; i < rows.length; i++) {
        const claim = rows[i].length > 2 ? rows[i][2] : rows[i][0];
        const v = (modal && rows[i].length <= 2) ? undefined : byKey[claim];
        if (v !== undefined) v.used = true;
        // THE KEYMAP'S WORDING IS WHAT IS SHOWN, THE VERB'S IS STILL FOUND.
        // The two tables name the same thing differently on purpose: the
        // keymap is read under a heading, so `\\` is "second pane on / off"
        // under panes, while the verb has to stand alone and is called "split
        // view". Taking the keymap's label alone lost the other name — typing
        // "split" found the row that RESIZES one and not the one that opens
        // it. So the verb's name rides along as something to match against.
        out.push({ section: name, label: rows[i][1], key: rows[i][0],
                   alias: v !== undefined ? v.label : "",
                   act: v !== undefined ? v.act : null });
      }
    }
    for (let i = 0; i < verbs.length; i++)
      if (!verbs[i].used)
        out.push({ section: "more", label: verbs[i].label,
                   key: verbs[i].key, alias: "", act: verbs[i].act });

    // ── THE ONES THAT DO SOMETHING FIRST ──────────────────────────────
    // Two kinds of row live in this list and they are different in kind: a
    // verb you can press return on, and a key the window already answers to.
    // Read in group order they were shuffled together, so the half you can
    // act on was something you found by scanning for the colour.
    //
    // A STABLE PARTITION, not a sort: inside each half the groups keep their
    // order, so the keymap still reads as move, then select, then act — it is
    // the same page with the verbs lifted to the top of it.
    const runs = [];
    const refs = [];
    for (let i = 0; i < out.length; i++)
      (out[i].act ? runs : refs).push(out[i]);
    return runs.concat(refs);
  }

  // ── LOOKING PROPERLY, WITHOUT OPENING ANYTHING ─────────────────────────
  // The preview column is a column: a photograph in it is a stamp, and the
  // only way to actually SEE a file was to open the application that owns it
  // and then close it again. This is the same preview the pane already
  // computes — previewKind, previewText, the cached frame — drawn at the size
  // of the window instead of the size of a column.
  //
  // It reads that state rather than starting any of its own: whatever the
  // cursor is on has already been worked out by the time you ask.
  property bool looking: false

  function quickLook() {
    const r = root.currentRow();
    if (!r || r.isDir) return;
    // A film whose frame has not been pulled yet: ask for it now. This is the
    // one moment somebody is actually looking, so it is the one moment worth
    // making them wait a beat for.
    if (!root.thumbFile[r.path] && !thumbProc.running
        && (Terminus.isVideo(r.name) || Terminus.isAudio(r.name))) {
      // The same one-off the preview pane makes for a film it has not seen —
      // see the note beside previewKind = "video".
      root.thumbJobs = [{ src: r.path,
                          kind: Terminus.isVideo(r.name) ? "v" : "a" }];
      thumbProc.command = ["sh", "-c", Thumbs.generate(root.thumbJobs)];
      thumbProc.running = true;
    }
    root.looking = true;
  }

  property string previewKind: "none"   // none | dir | image | video | audio | font | pdf | text | archive | binary
  // Where a rendered PDF page lands. One name, reused: only one preview is on
  // screen at a time, so keeping every page ever looked at would be a cache
  // nobody reads. `previewStamp` busts Qt's image cache, which would otherwise
  // show the previous PDF at the same path.
  // Beside the thumbnails, not loose in the cache root: everything terminus
  // renders is one directory, so clearing it is one rm.
  readonly property string pdfStem: Terminus.terminusCacheDir() + "/preview"
  property int previewStamp: 0
  property var previewRows: []
  // AN ARCHIVE'S TREE IS NOT A LISTING'S ROWS, and they used to share this
  // property. A tree entry has a glyph, an ink and a depth; it has no `path`,
  // so nothing that expects an entry can read one — and everything that reads
  // the preview had to ask `previewKind` first and remember to. The file
  // already carries the scar: an invisible ListView "quietly instantiated a
  // column of rows against the wrong shape of data".
  //
  // Two properties, so the question cannot be forgotten. Each is emptied when
  // the other is filled — see settlePreview, which is the one place both are
  // written.
  property var previewTree: []

  property string previewText: ""

  // Debounced, not immediate. Holding Down through a directory would otherwise
  // start a process per row and finish them in an order nobody asked for; this
  // way only the row you actually stopped on is ever read.
  Timer {
    id: previewDelay
    // shorter than it was: the work behind a landing is now capped output, a
    // smaller relayout and often a cache hit, so waiting 110ms to start it was
    // most of the delay rather than a guard against it
    interval: 30
    // The metadata rides along, because `sel` is not the only thing that
    // changes what is being previewed. Entering a directory whose first row is
    // already the cursor fires no onSelChanged at all — the whole listing
    // changed underneath a cursor that never moved — and the panel came up
    // with a size and a date and no dimensions. Everything that restarts this
    // timer means "the preview is now of something else", which is exactly
    // when the probe has to run too.
    onTriggered: { root.loadPreview(); infoDelay.restart(); }
  }

  // The cache is tried SYNCHRONOUSLY, before the debounce. A row you have
  // already looked at needs no process and no parse, so making it wait 55ms
  // behind a timer that exists to avoid spawning things was the one delay with
  // nothing behind it — walking back up a list is now instant.
  onSelChanged: {
    // Before the early return below: the range follows the cursor in every
    // view, not only the one that draws a preview.
    if (root.visualOn) root.extendVisual();
    if (root.viewMode !== "columns") return;
    root.refreshPreview();
  }

  // WHAT THE PANE SHOULD BE SHOWING NOW, cache first.
  //
  // Pulled out of onSelChanged because the cursor moving is not the only thing
  // that changes what is under it. Walking INTO a directory usually leaves
  // `sel` exactly where it was — 0 to 0 — so nothing fired, and the pane went
  // on showing the previous directory's peek until something else happened to
  // restart the timer. That is the list that flashes in the right-hand column
  // on the way in: not a flicker of the new preview, but the old one still
  // being drawn.
  // ── NOT WHILE THE COLUMNS ARE MOVING ──────────────────────────────────
  // XAnimator survives GUI-thread work: it keeps its own time on the render
  // thread. What it cannot survive is a scene-graph SYNC, and filling the
  // preview pane builds a column's worth of delegates — which is one.
  //
  // Stepping into a directory asks at once for a peek of whatever row is
  // selected in the new one, and that answer lands a hundred-odd milliseconds
  // later: right at the tail of the slide. One dropped frame, at the same
  // point every time, which is why it reads as a rhythm rather than as jank.
  //
  // THE WHOLE PIPELINE PAUSES, not just its answers. Holding only the settle
  // was the first try and it cost more than it bought: the clearing and the
  // re-fetching still ran mid-slide, so a peek cancelled by one call and
  // re-armed by another could land after the held one was replayed, and the
  // preview of the first row in a directory you had just opened became a coin
  // toss. Nothing is asked for while the columns move, and exactly one
  // request goes out when they stop — which is also the moment the answer
  // could first have been seen.
  property bool previewWanted: false

  Connections {
    target: millerAnim
    // callLater because millerStep stops the animator and starts it again in
    // the same breath: stepping twice quickly would otherwise resume in the
    // gap between the two and land the sync inside the next slide, which is
    // the bump this exists to remove.
    function onRunningChanged() {
      if (!millerAnim.running) Qt.callLater(root.resumePreview);
    }
  }

  // UNCONDITIONAL, and that is the point. Resuming only when something had
  // asked during the slide left the gap this was reported as: the paths that
  // ask BEFORE stepping, and the step that leaves `sel` at 0 so nothing fires
  // at all, both ended a slide with no request outstanding and no preview.
  // Every slide now ends with exactly one refresh; refreshPreview returns
  // immediately when the pane is already showing the right row, so asking
  // when the answer is already in costs nothing.


  function resumePreview() {
    if (millerAnim.running) return;
    // BELT AND BRACES on the fade. millerStep drops the columns to nothing
    // and the animator carries them back, so anything that stops that
    // animator without letting it finish would leave the file list invisible
    // — the worst failure this transition could have. Every slide ends here.
    miller.opacity = 1;
    root.previewWanted = false;
    // AND THE ONE REQUEST THE SLIDE WAS HOLDING BACK. Unconditional, because
    // the paths that ask BEFORE stepping and the step that leaves `sel` at 0
    // both end a slide with nothing outstanding — and then the row under the
    // cursor never gets previewed at all. A directory with a single file in
    // it has no second row to move to and would never show one.
    //
    // refreshPreview returns immediately when the pane is already showing the
    // right row, so asking when the answer is in costs nothing.
    root.refreshPreview();
  }

  function refreshPreview() {
    if (millerAnim.running || root.stepping) { root.previewWanted = true; return; }
    peekAim.restart();
    const r = root.currentRow();
    // The rows under this cursor are the ones being left — see `arriving`.
    if (root.arriving) return;
    // ALREADY ANSWERED, OR ALREADY BEING ANSWERED — see previewShown. The
    // row has not changed, so neither the pane nor the metadata beside it
    // has anything to be told.
    if (r && (r.path === root.previewShown || r.path === root.previewFor))
      return;
    // Metadata takes the same shape as the preview itself: the cache answers
    // in the same frame and only a miss waits behind the debounce. Reading it
    // here rather than leaving it all to loadPreviewInfo is what stops the
    // panel blanking for a tenth of a second every time the cursor walks back
    // over a row it has already been on.
    const known = r ? root.infoCache[r.path] : undefined;
    root.previewInfo = known === undefined ? null : known;
    if (known === undefined) infoDelay.restart(); else infoDelay.stop();
    const hit = r ? root.previewCache[r.path] : undefined;
    if (hit !== undefined) {
      root.settlePreview(hit.kind, hit.rows, hit.text, r.path);
      return;
    }
    // an image needs no process either: the pane points Qt at the file
    if (r && !r.isDir && Terminus.isImage(r.name)) {
      root.settlePreview("image", [], "", r.path);
      return;
    }
    // A DIRECTORY WE HAVE ALREADY READ NEEDS NO PROCESS AND NO GAP. The
    // window remembers the last sixteen listings as the bytes they came back
    // as — for seeding a navigation — and a peek wants exactly the same
    // bytes. Without this, walking down a column of directories you have just
    // walked up emptied the pane and refilled it a frame later for every
    // single row, which is the flicker: not a wrong listing, an absent one.
    if (r && r.isDir) {
      const seen = root.listingText[r.path];
      if (seen !== undefined) {
        const rows = root.rowsFromListing(seen, r.path);
        root.settlePreview("dir", rows, "", r.path);
        root.cachePreview(r.path, { kind: "dir", rows: rows });
        return;
      }
    }
    // NOTHING RATHER THAN THE LAST ANSWER while the new one is fetched. The
    // pane held whatever it had until the replacement arrived, which meant a
    // directory's listing sat under a filename it has nothing to do with for
    // as long as the peek took. Empty is honest and it is one frame.
    previewProc.running = false;
    root.previewFor = "";
    root.previewShown = "";
    // Only if there is something to clear. refreshPreview and loadPreview
    // both reach here for the same row — one off the keystroke, one off the
    // debounce behind it — and the second was assigning an empty array over
    // an empty array, which is a full model reset of the pane for no change
    // at all.
    if (root.previewRows.length > 0) root.previewRows = [];
    if (root.previewText !== "") root.previewText = "";
    previewDelay.restart();
  }
  onViewModeChanged: {
    if (root.viewMode === "columns") { previewDelay.restart(); infoDelay.restart(); }
    else { root.previewInfo = null; root.watchPeek(""); }
    root.rememberView();
    root.makeThumbs();
    // one handler per signal, so remembering the view lives here too
    viewSave.restart();
  }

  // WHICH ROW THE RUNNING PEEK IS ABOUT. "" when nothing is in flight.
  //
  // previewProc is one process reused for every peek, and its output used to
  // be applied to whatever the cursor happened to be sitting on when it
  // finished. Walk down a column faster than a peek returns and the answer for
  // the row you left lands on the row you are on — a directory's listing drawn
  // as if it were this directory's, or as the text of a file. Worse, it was
  // then CACHED under the wrong path, so the ghost outlived the moment: the
  // row went on showing another folder's contents until the cache was dropped.
  // That is the "random dir" the preview sometimes shows, and it is the same
  // fault in the picker, which draws the same pane.
  property string previewFor: ""

  // WHILE THE ROWS ON SCREEN ARE THE ONES BEING LEFT.
  //
  // enter() moves the cursor to the top before it replaces the listing,
  // because the two cannot be written in one statement — and between those
  // two lines `sel` is 0 against the OLD directory's rows. Everything that
  // watches the cursor fired there: the preview settled on row 0 of the place
  // you were leaving, drew its contents in the last column, and was corrected
  // seventy milliseconds later when the real rows arrived. Measured at 1ms
  // in and 77ms out of that wrong listing, every single step.
  //
  // That is the list that flashes. It is not a stale frame and not a missing
  // one: it is a correct preview of the wrong row.
  property bool arriving: false

  // WHICH ROW THE PANE IS ALREADY SHOWING. "" when it is showing nothing.
  //
  // ONE navigation calls into the preview four or five times: the cwd
  // changing, the cursor landing on row 0, the rows themselves arriving, the
  // 30ms debounce behind all three, and the peek watcher aiming at the new
  // row. Each of those called refreshPreview or loadPreview, and each call
  // that did not hit the cache emptied the pane and refilled it a moment
  // later — so opening a directory wrote the preview column four times:
  // blank, right, blank, blank, right. Measured with a counter on every
  // assignment; the two blanks in the middle are the flash.
  //
  // Nothing about the row has changed between those calls, so nothing should
  // be redrawn. This is what they check.
  property string previewShown: ""

  Process {
    id: previewProc
    stdout: StdioCollector {
      id: previewOut
      waitForEnd: true
      onStreamFinished: {
        const t = previewOut.text;
        const cur = root.currentRow();
        // The answer is about a row we have since left. Nothing to draw and
        // above all nothing to cache: a wrong entry here is permanent.
        if (!cur || cur.path !== root.previewFor) return;
        root.previewFor = "";
        if (root.previewKind === "dir") {
          // the same output listing it would produce — see listingText
          root.rememberListing(cur.path, t);
          const rows = cur ? root.rowsFromListing(t, cur.path) : [];
          root.previewRows = rows;
          root.previewShown = cur.path;
          if (cur) root.cachePreview(cur.path, { kind: "dir", rows: rows });
        } else if (root.previewKind === "archive") {
          // Rows, not a block of text: the tree wants a glyph and a colour per
          // entry, the same two a listing gives its rows, and those come from
          // the same enrichment the listing uses rather than from a second
          // idea of what a .rs file looks like. The "and more" marker is not a
          // file and gets neither.
          const rows = Terminus.archiveTree(t);
          for (const e of rows) {
            e.ink = e.more ? Zenon.muted : root.inkOf(e);
            e.glyph = e.more ? "" : Icons.glyphFor(e);
          }
          root.previewTree = rows;
          root.previewRows = [];
          root.previewShown = cur.path;
          // an unreadable or empty archive is still not text
          if (rows.length === 0) root.previewKind = "binary";
          if (cur) root.cachePreview(cur.path,
            { kind: root.previewKind, rows: rows });
        } else if (Terminus.looksBinary(t)) {
          root.previewKind = "binary";
          root.previewShown = cur.path;
          root.previewText = "";
          if (cur) root.cachePreview(cur.path, { kind: "binary" });
        } else {
          root.previewKind = "text";
          root.previewShown = cur.path;
          const rich = Terminus.ansiToRich(t);
          root.previewText = rich;
          if (cur) root.cachePreview(cur.path, { kind: "text", text: rich });
        }
      }
    }
  }

  function loadPreview() {
    // Same reason as refreshPreview: the columns are mid-slide and this would
    // sync the scene graph underneath them. refreshPreview reaches here once
    // they stop.
    if (millerAnim.running) { root.previewWanted = true; return; }
    if (root.viewMode !== "columns") return;
    const r = root.currentRow();
    // the same three questions refreshPreview asks, for the path that
    // arrives here through the debounce
    if (root.arriving) return;
    if (r && (r.path === root.previewShown || r.path === root.previewFor))
      return;
    if (!r) {
      root.previewKind = "none";
      root.previewRows = [];
      root.previewText = "";
      return;
    }

    // already known: no process, no parse, no relayout
    const hit = root.previewCache[r.path];
    if (hit !== undefined) {
      root.settlePreview(hit.kind, hit.rows, hit.text, r.path);
      return;
    }
    // and a directory whose bytes are remembered needs none of the three
    // either — the same seed refreshPreview takes, for the path that gets
    // here through the debounce rather than straight off a keystroke.
    if (r.isDir) {
      const seen = root.listingText[r.path];
      if (seen !== undefined) {
        const rows = root.rowsFromListing(seen, r.path);
        root.settlePreview("dir", rows, "", r.path);
        root.cachePreview(r.path, { kind: "dir", rows: rows });
        return;
      }
    }

    root.previewShown = "";
    if (root.previewRows.length > 0) root.previewRows = [];
    if (root.previewText !== "") root.previewText = "";
    if (r.isDir) {
      root.previewKind = "dir";
      root.beginPeek(r.path, Terminus.peekCommand(r.path));
      return;
    }
    // NOTHING IS READ FOR A FILE WHEN THE PREVIEW IS OFF. Stopped here
    // rather than at the pane that draws it: what costs is the stat, the
    // thumbnail and the decode this dispatcher sets in motion, not the
    // rectangle at the end of it.
    if (!root.previewOn) { root.previewKind = "none"; return; }
    if (Terminus.isImage(r.name)) { root.previewKind = "image"; return; }
    if (Terminus.isVideo(r.name)) {
      root.previewKind = "video";
      // the same cached frame the grid uses, made on demand if the grid has
      // not already asked for it
      if (!root.thumbFile[r.path]) {
        root.thumbJobs = [{ src: r.path, kind: "v" }];
        thumbProc.command = ["sh", "-c", Thumbs.generate(root.thumbJobs)];
        thumbProc.running = true;
      }
      return;
    }
    if (Terminus.isAudio(r.name)) {
      root.previewKind = "audio";
      // Cover art, through the same cache and the same batch as a video's
      // frame — it is a picture pulled out of a file either way. A track with
      // no art writes nothing and the panel shows its tags alone.
      if (!root.thumbFile[r.path]) {
        root.thumbJobs = [{ src: r.path, kind: "a" }];
        thumbProc.command = ["sh", "-c", Thumbs.generate(root.thumbJobs)];
        thumbProc.running = true;
      }
      return;
    }
    // A typeface is previewed by BEING the preview: Qt loads the file and the
    // specimen below is drawn with it. Nothing to run, nothing to parse.
    if (Terminus.isFont(r.name)) { root.previewKind = "font"; return; }
    // An archive shows what is inside it. "binary" is true of a .tar.zst and
    // tells you nothing you wanted to know before extracting it.
    if (Terminus.isArchive(r.name)) {
      root.previewKind = "archive";
      root.beginPeek(r.path, Terminus.archiveListCommand(r.path));
      return;
    }
    if (Terminus.isPdf(r.name)) {
      root.previewKind = "pdf";
      pdfProc.command = ["sh", "-c", Terminus.pdfCommand(r.path, root.pdfStem)];
      pdfProc.running = true;
      return;
    }
    root.previewKind = "text";
    root.beginPeek(r.path, Terminus.batCommand(r.path));
  }

  // One way in, so no peek can ever be started without saying what it is for.
  // The old run is stopped first: the collector gathers until the stream ends,
  // and two runs feeding one collector is how half of one listing arrives
  // stapled to half of another.
  function beginPeek(path, command) {
    previewProc.running = false;
    root.previewFor = path;
    previewProc.command = ["sh", "-c", command];
    previewProc.running = true;
  }

  // Deciding a preview WITHOUT a process has to cancel the one in flight, or
  // the answer to a question nobody is asking any more arrives and overwrites
  // the one that is on screen.
  function settlePreview(kind, rows, text, path) {
    // Only when the pane is actually changing subject. Arrowing down a list
    // of already-cached rows settles constantly, and fading on every one of
    // those would turn a crisp cursor into a flicker.
    if ((path || "") !== root.previewShown) {
      previewFade.stop();
      previewPane.opacity = 0;
      previewFade.restart();
    }
    previewProc.running = false;
    root.previewFor = "";
    previewDelay.stop();
    root.previewShown = path || "";
    root.previewKind = kind;
    // ROUTED BY KIND, and the other one emptied. A cached archive comes back
    // through here exactly as a cached directory does, so this is where the
    // two shapes have to be told apart or they never are.
    if (kind === "archive") {
      root.previewTree = rows || [];
      root.previewRows = [];
    } else {
      root.previewRows = rows || [];
      root.previewTree = [];
    }
    root.previewText = text || "";
  }



  // ── what the picture IS ──────────────────────────────────────────────────
  // The preview pane used to show a picture and nothing else, which answers
  // "which file is this" and none of the questions you actually open a folder
  // of media to ask — how big, how long, what codec.
  //
  // Two probes, one panel: `magick identify` for a still and `ffprobe` for a
  // video. Both were already installed for the thumbnails, so neither adds a
  // dependency, and both are quick enough to run per row PROVIDED they are not
  // run per row — hence the debounce and the cache below.
  property var previewInfo: null
  // Which path the answer on its way belongs to, and which probe was asked.
  // A reply arriving after the cursor has moved on is dropped rather than
  // shown against the wrong file: ffprobe on a large mkv can outlive several
  // keystrokes.
  property string previewInfoFor: ""
  property string previewInfoKind: ""
  property var infoCache: ({})
  property var infoOrder: []

  function cacheInfo(path, info) {
    const c = root.infoCache;
    const o = root.infoOrder.slice();
    if (c[path] === undefined) o.push(path);
    c[path] = info;
    while (o.length > 48) delete c[o.shift()];
    root.infoCache = c;
    root.infoOrder = o;
  }

  Timer {
    id: infoDelay
    // longer than the preview's 55ms: this is the one probe with no cheap
    // path. A picture's own preview is just Qt pointed at the file, but its
    // dimensions cost a process either way, so holding Down through a
    // wallpaper folder should start none of them.
    interval: 110
    onTriggered: root.loadPreviewInfo()
  }

  Process {
    id: infoProc
    stdout: StdioCollector {
      id: infoOut
      waitForEnd: true
      onStreamFinished: {
        const r = root.currentRow();
        const info = root.previewInfoKind === "video"
          ? Terminus.parseVideoInfo(infoOut.text)
          : (root.previewInfoKind === "audio"
            ? Terminus.parseAudioInfo(infoOut.text)
            : Terminus.parseImageInfo(infoOut.text));
        // Cached even when the cursor has moved on: the work is already done,
        // and walking back up the list should not pay for it twice.
        //
        // A FAILURE is not cached. Remembering a null would turn one probe
        // that lost a race — against a file still being written, most often —
        // into a file that has no metadata for as long as the window is open.
        if (info && root.previewInfoFor !== "")
          root.cacheInfo(root.previewInfoFor, info);
        if (r && r.path === root.previewInfoFor) root.previewInfo = info;
      }
    }
  }

  function loadPreviewInfo() {
    root.previewInfo = null;
    if (root.viewMode !== "columns") return;
    const r = root.currentRow();
    if (!r || r.isDir) return;
    const kind = Terminus.isVideo(r.name) ? "video"
      : (Terminus.isAudio(r.name) ? "audio"
        : (Terminus.isImage(r.name) ? "image" : ""));
    if (kind === "") return;
    const hit = root.infoCache[r.path];
    if (hit !== undefined) { root.previewInfo = hit; return; }
    root.previewInfoFor = r.path;
    root.previewInfoKind = kind;
    infoProc.command = ["sh", "-c",
      kind === "video" ? Terminus.videoInfoCommand(r.path)
        : (kind === "audio" ? Terminus.audioInfoCommand(r.path)
          : Terminus.imageInfoCommand(r.path))];
    infoProc.running = true;
  }

  Process {
    id: pdfProc
    onExited: (code) => {
      // the stamp is what makes Qt reload a file it has already cached under
      // this exact name
      if (code === 0 && root.previewKind === "pdf") root.previewStamp++;
    }
  }

  // Two steps, so a keystroke does not re-sort.
  //
  // `sorted` changes when the directory, the sort or the hidden toggle changes
  // — rarely. `view` is that list filtered by what you have typed, and a
  // filter cannot change the order of what survives it. One expression did
  // both, so every character re-sorted the whole directory.
  // SEARCH RESULTS ARE NOT SORTED, and that is the whole of the second half of
  // the search fix.
  //
  // fzf ranks its answers best-first, and this then threw that away and put
  // them back in alphabetical order — so the most relevant hit was wherever
  // its name happened to fall in the alphabet. Between matching whole paths
  // and re-sorting the result, "find" was returning good answers and
  // presenting them as noise.
  //
  // A search result is an ANSWER, not a directory; the hidden-file toggle
  // still applies, because that is about what you want to see rather than
  // about order.
  // Both derived per pane now — see the Pane component, which holds the
  // arrangement, the model and the index for its own half. These two are
  // what the rest of the window means by "the listing": the active one.
  readonly property var sorted: root.act.sorted
  readonly property var view: root.act.view

  // ── the listing, as something the views can be TOLD ABOUT ───────────────
  // The model, its index and the diff that keeps them in step all moved into
  // Pane, because there are two of them now and a window-wide one could only
  // ever describe the half the keyboard was in. The argument for them has not
  // changed and lives there; what changed is that each half has its own, so
  // the item drawing a directory is the same item from the moment it is
  // listed until the moment you leave it.
  function rowFor(path) { return root.act.rowFor(path); }

  // FUNCTIONS, not bindings. As properties these recomputed whenever `marked`
  // changed — every pointer move of a drag-select — and the context menu's
  // item list depended on `acting`, so it rebuilt its labels each time even
  // while closed. Nothing needs either until something acts.
  function markedRows() {
    const out = [];
    const v = root.view;
    const m = root.marked;
    for (let i = 0; i < v.length; ++i)
      if (m[v[i].path]) out.push(v[i]);
    return out;
  }

  // What a verb acts on: everything ticked, or the row under the cursor when
  // nothing is. The same rule zeus' kill list uses, and the reason you can
  // rename a file without marking it first.
  function acting() {
    const m = root.markedRows();
    if (m.length > 0) return m;
    const r = root.view[root.sel];
    return r ? [r] : [];
  }

  // THROUGH THE PANE, NOT THROUGH THE PROXY, and the difference is not
  // cosmetic. `root.view` is a binding onto the active pane's own `view`, and
  // inside that pane's onViewChanged handler the binding has not been
  // re-evaluated yet — the pane's rows are the new ones and root.view still
  // answers with the old. Measured: the handler that fires the instant a
  // directory's rows land read 29 rows and a cursor on the directory we had
  // just LEFT, settled the preview on it, and was corrected sixty
  // milliseconds later when something else touched the binding.
  //
  // That is the list that flashes in the last column. Reading the pane
  // directly cannot be a frame behind it.
  function currentRow() { return root.act.view[root.act.sel] || null; }

  // The colour and the glyph are worked out ONCE PER LISTING and stored on the
  // row, not asked for every time a delegate is drawn.
  //
  // They used to be functions called from bindings, which means once per row
  // per repaint: categoryOf does string work and glyphFor does map lookups,
  // and in a directory of a couple of thousand entries that is the frame
  // budget spent on answers that cannot change. `enrich` runs over the rows as
  // they arrive and the delegates read a field.
  function inkFor(e) {
    if (!e) return Zenon.muted;
    return e.ink !== undefined ? e.ink : Zenon.white;
  }

  function inkOf(e) {
    if (e.isDir) return Zenon.cyan;
    const cat = Terminus.categoryOf(e.name);
    if (cat === "image") return Zenon.green;
    if (cat === "media") return Zenon.sand;
    if (cat === "archive") return Zenon.yellow;
    if (cat === "document") return Zenon.cyan;
    if (e.broken) return Zenon.red;
    if (e.isLink) return Zenon.magenta;
    if (e.isExec) return Zenon.yellow;
    if (e.size === 0) return Zenon.muted;
    return Zenon.white;
  }

  function enrich(rows) {
    for (const r of rows) {
      r.ink = root.inkOf(r);
      r.glyph = Icons.glyphFor(r);
      // The metadata cells USED to be computed here as well — kind, the
      // relative time and the size string. They are not any more; see kindOf
      // below. ink and glyph stay, because every view draws those for every
      // row and there is no listing where they are not wanted.
    }
    return rows;
  }

  // ── the metadata cells, worked out ON FIRST SIGHT ───────────────────────
  //
  // These three were moved INTO enrich once, for a good reason: `reuseItems`
  // rebinds `entry` on every recycled delegate, and a function call in a
  // binding is interpreted every time. The reason was good and the placement
  // was wrong, because enrich runs over the WHOLE listing the moment it is
  // parsed — so a four thousand entry directory paid four thousand date
  // calculations, four thousand walks of five extension tables and four
  // thousand size formats before it could draw anything, to fill in cells
  // that only the list view's metadata columns ever read. The grid draws none
  // of them. The miller middle column draws none of them. Even in the list
  // only the rows actually on screen are ever bound. Measured, that pass was
  // most of the cost of arriving in a large directory.
  //
  // MEMOISED ONTO THE ROW, so the original argument still holds: the first
  // delegate to want a cell pays for it, every rebind after that is a property
  // read, and a row nobody looks at costs nothing at all.
  function kindOf(e) {
    if (e.kind === undefined)
      e.kind = e.isDir ? "directory"
        : (e.isLink && e.broken ? "broken link" : Terminus.kindOf(e.name));
    return e.kind;
  }

  // A relative time freezes until the next listing rather than refreshing
  // whenever a row happens to be recycled. Nothing was refreshing it on a
  // clock before either — bindings do not re-evaluate because time passed —
  // so this only makes the column CONSISTENT: the rows you scroll to do not
  // read a few minutes fresher than the rows you started on.
  function whenOf(e) {
    if (e.when === undefined) e.when = Terminus.formatTime(e.mtime);
    return e.when;
  }

  // Directories have no honest size until du has been round, so theirs stays
  // the size cell's business.
  function sizeTextOf(e) {
    if (e.sizeText === undefined)
      e.sizeText = e.isDir ? "" : Terminus.formatSize(e.size);
    return e.sizeText;
  }

  Component.onCompleted: {
    // A FloatingWindow is visible by default, and `shown` starts false, so a
    // freshly created window came up ON SCREEN with nothing having asked for
    // it — the manager makes one at load so SUPER+E always has something to
    // reveal, and that one flashed up on every quickshell start. Nothing
    // synced the two: onShownChanged only fires on a CHANGE, and false never
    // changed. So sync it once here, at construction, before spawn() or pick()
    // has had the chance to set `shown`.
    root.visible = root.shown;
    root.loadBookmarks();
    // before the first listing: the sort and the hidden-file setting decide
    // what that listing turns into, so reading them afterwards would show one
    // arrangement and then rearrange it in front of you
    root.loadViewPrefs();
    root.refresh(true);
  }

  // ── reading the directory ───────────────────────────────────────────────
  Process {
    id: listProc
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
      onStreamFinished: {
        // Byte-identical output means nothing in this directory changed, so
        // there is nothing to redraw. inotify fires close_write and attrib for
        // files whose presence, size and mtime are all unchanged, and
        // rebuilding the model for those was pure churn — one string compare
        // makes them free.
        // null, never "", is the "nothing loaded yet" sentinel — see the
        // property's own note. An EMPTY DIRECTORY prints nothing, so an empty
        // string is a perfectly real listing and must not read as "unchanged".
        if (listOut.text === root.lastListing) return;
        root.act.lastListing = listOut.text;
        root.rememberListing(root.cwd, listOut.text);
        // WHICH FILE the cursor was on, not which index. A directory that
        // other programs are writing to — /tmp above all — reorders under you,
        // and an index that survives a rebuild points at whatever moved into
        // that slot. The cursor is what `d`, Return and the menu act on, so
        // letting it drift is letting those act on a file you did not choose.
        const wasOn = root.view[root.sel] ? root.view[root.sel].path : "";
        const keep = root.keepScroll();
        // The same hold enter() takes, for the other way rows arrive — see
        // `arriving`. Between the assignment below and the cursor being put
        // back a few lines later, "what is under the cursor" has a complete
        // and wrong answer, and everything watching the cursor believed it.
        root.arriving = true;
        root.act.raw = root.enrich(Terminus.parseListing(listOut.text, root.cwd));
        // a directory you walk into while the mode is on measures itself,
        // because a usage view of a folder it has not looked at is a column
        // of dashes
        if (root.usage) Qt.callLater(root.measureAll);
        // Land on the directory we just came out of rather than on the first
        // row: walking up and back down a tree should return you to where you
        // were, not to the top of every level on the way.
        // Whether this listing is one the CURSOR should be moved for. A
        // deliberate landing — arriving in a directory, or a file just made —
        // scrolls to the row. A directory that merely changed underneath does
        // not: you may have scrolled somewhere on purpose, and dragging the
        // view back to the cursor every time inotify fires is what made a busy
        // directory impossible to read.
        let land = false;
        if (root.wantSel !== "") land = root.landWanted();
        else if (wasOn !== "") {
          // the same file, wherever it ended up. THROUGH THE PANE: the rows
          // were written two statements ago and `root.view` is a binding onto
          // them, which has not been re-evaluated yet — it still answers with
          // the listing this one replaced. See currentRow.
          const v = root.act.view;
          for (let i = 0; i < v.length; ++i) {
            if (v[i].path === wasOn) { root.act.sel = i; break; }
          }
        }
        Qt.callLater(root.makeThumbs);
        if (root.act.sel >= root.act.view.length)
          root.act.sel = Math.max(0, root.act.view.length - 1);
        // Rows in, cursor placed: one preview, of the right row.
        root.arriving = false;
        if (root.viewMode === "columns") root.refreshPreview();
        if (land) Qt.callLater(root.positionSel);
        else {
          // SYNCHRONOUSLY, in the same tick as the assignment above. The view
          // drops its offset the moment the model is replaced — which happens
          // inside `root.act.raw = ...`, before this function returns — so
          // putting it back here means no frame is ever drawn at the wrong
          // place. Deferring it to a callLater also worked, and you could see
          // it work: the listing jumped to the top and then snapped back.
          root.restoreScroll(keep);
          // and again once the view has settled its own contentHeight, which
          // it may still have been estimating a moment ago. putScroll returns
          // immediately when there is nothing to change, so this is free in
          // the ordinary case.
          Qt.callLater(() => root.restoreScroll(keep));
        }
      }
    }
  }

  // `full` means the DIRECTORY changed. A plain refresh — after an action, or
  // when inotify says something moved in the current directory — re-reads only
  // the current listing.
  //
  // It used to do all three every time: current listing, parent listing and a
  // preview reload. The parent cannot have changed unless you moved, and the
  // preview cannot have changed unless the cursor moved, so an event in the
  // current directory cost three processes and three model swaps to answer a
  // question about one of them. That was the redraw in the split view.
  function refresh(full) {
    if (root.searchMode !== "") return;   // results are not a directory
    listProc.command = ["sh", "-c", Terminus.listCommand(root.cwd)];
    listProc.running = true;
    // Together with the listing, so the marks arrive with the rows they are
    // about — and again after every job, because this is the one view in the
    // window that a `git commit` in another terminal can make wrong.
    root.scanGit();
    if (full) {
      // THE ROOT HAS NO PARENT, and dirname("/") is "/" — so asking for it
      // listed the root twice, once in the column you are standing in and
      // again in the column that is meant to say where you came from. An
      // empty column is the truth: there is nothing above this.
      // Drawn from what is already known FIRST, and confirmed by the
      // process behind it — which usually has nothing to add.
      root.seedParent();
      if (root.cwd === "/") { root.parentRows = []; root.parentListing = null; }
      else {
        parentProc.command = ["sh", "-c", Terminus.listCommand(Terminus.dirname(root.cwd))];
        parentProc.running = true;
      }
      previewDelay.restart();
    }
  }

  // ── the slide ───────────────────────────────────────────────────────────
  // The columns are dropped to one side by a step and carried home.
  //
  // AN ANIMATOR, NOT A NUMBERANIMATION, and that is the whole of why this
  // used to look like it was running at a third of the frame rate. A
  // NumberAnimation is ticked on the GUI thread — the same thread that, at
  // the exact moment of a step, is parsing a listing, rebuilding a model,
  // enriching a few hundred rows and starting a preview. Every frame that
  // work overran was a frame the slide did not get, so a 260ms travel
  // arrived in four or five visible jumps.
  //
  // XAnimator runs on the RENDER thread. It keeps its own time and moves the
  // item whether or not QML is busy, so the same gesture is smooth through
  // the very work that used to interrupt it. The cost is that `miller.x` is
  // no longer a binding — nothing else writes or reads it, which is what
  // makes that safe.
  //
  // Zenon.travelEase, not Zenon.ease: this is a thing crossing a pane and it
  // is watched the whole way, where the shell's quintic is a curve for things
  // arriving. See the note on the token — quintic here read as a lurch and
  // then a drift, which is what "not tight" was.
  XAnimator {
    id: millerAnim
    target: miller
    to: 0
    // Through Zenon, so the shell's one motion setting reaches it — this was
    // the last animation in terminus still carrying its own number, which
    // meant turning the whole desktop's motion down left the columns sliding
    // at their old speed.
    //
    duration: Zenon.normal
    easing.type: Zenon.travelEase
  }

  // ── AND IT FADES IN AS IT COMES ──────────────────────────────────────
  // The eye tracks a hard-edged boundary moving across a pane very precisely
  // — precisely enough to read a single late frame as a bump — and cannot do
  // the same to one that is changing opacity. So the arrival is made less
  // trackable exactly where it is least reliable: the first frames, where
  // three models have just been swapped and the scene graph is rebuilding.
  //
  // OpacityAnimator, like the slide, so it runs on the RENDER thread and the
  // two cannot drift apart under GUI-thread work. A fade driven from QML
  // would be the one thing in this transition that could stutter.
  //
  // A CROSS-FADE NOW, NOT A REVEAL. It used to start from nothing, because it
  // was hiding three columns' worth of delegates being rebuilt on every step.
  // They are not rebuilt any more — walking up, two of the three columns keep
  // the rows they already had — so fading all the way out was covering work
  // that no longer happens, and a view that blinks to black and back is doing
  // more to the eye than the movement itself.
  //
  // From millerDim instead: enough to soften the one column that genuinely
  // does change, not enough to read as the view disappearing. Over the FULL
  // length of the slide, so the opacity and the travel finish together —
  // arriving at 0.9 and climbing is invisible, where a fade that ended early
  // left the last stretch of movement at full contrast and drew the eye
  // straight back to it.
  readonly property real millerDim: 0.35

  OpacityAnimator {
    id: millerFade
    target: miller
    to: 1
    duration: Zenon.normal
    easing.type: Zenon.travelEase
  }

  // The preview pane's own arrival.
  //
  // This had two speeds once — a longer one for arriving in a directory, a
  // short one for walking the cursor down it. The long one was covering a pop
  // that came from the column being EMPTIED mid-navigation, and that stopped
  // happening when syncPreviewRows learnt to leave a hidden column alone. A
  // fade tuned to hide a bug should not outlive the bug.
  //
  // Render thread, so a directory heavy enough to be worth easing in is not
  // the thing that makes its own easing stutter.
  OpacityAnimator {
    id: previewFade
    target: previewPane
    to: 1
    duration: Zenon.fast
    easing.type: Zenon.travelEase
  }

  // WHICH WAY THE TREE MOVED, from the two paths alone: into a child and the
  // columns travel left, out to a parent and they travel right. A jump to
  // somewhere unrelated — a bookmark, a search result, a tab — is not a step
  // and gets no slide: there is no direction to show, and animating one would
  // claim a relationship between the two places that does not exist.
  readonly property real millerTravel: 0.25

  // ── WHICH COLUMN STANDS WHERE ─────────────────────────────────────────
  // millerOrder[slot] names the INSTANCE in that slot. A step rotates this
  // rather than each column re-deriving its content: walking down, the
  // preview becomes the middle and the middle becomes the parent, and only
  // the far column is handed something it has never held. Two of the three
  // then sync against rows they already have, which is a diff that finds
  // nothing to do — where before all three rebuilt.
  //
  // The rotation must happen BEFORE the row sources move, or the column about
  // to leave the middle would first sync itself to the new directory and
  // rebuild for nothing. millerStep runs at the top of enter(), ahead of the
  // cwd and the seed, which is why it lives there.
  property var millerOrder: [0, 1, 2]

  function millerRotate(down) {
    const o = root.millerOrder;
    root.millerOrder = down ? [o[1], o[2], o[0]] : [o[2], o[0], o[1]];
  }

  // The rows each SLOT shows. Bound by slot rather than by instance, so a
  // column picks up whatever its new slot is about the moment it rotates.
  readonly property var millerRowsParent: root.viewMode === "columns"
    ? (root.parentRows || []) : []
  readonly property var millerRowsCurrent: root.viewMode === "columns"
    ? (root.act.view || []) : []
  readonly property var millerRowsPreview:
    (root.viewMode === "columns" && root.previewKind === "dir")
      ? (root.previewRows || []) : []

  // The instance standing in a given slot, for the code that needs to measure
  // the middle column or scroll the parent. Expressions, not a function: a
  // binding does not re-evaluate on a call, so it would never see a rotation.
  readonly property var parCol: root.millerOrder[0] === 0 ? colA
    : (root.millerOrder[0] === 1 ? colB : colC)
  readonly property var midCol: root.millerOrder[1] === 0 ? colA
    : (root.millerOrder[1] === 1 ? colB : colC)
  readonly property var prevCol: root.millerOrder[2] === 0 ? colA
    : (root.millerOrder[2] === 1 ? colB : colC)

  // True from the moment a step is taken until the slide it starts has
  // finished. The travel is queued a tick late now (see millerStep), so
  // millerAnim.running is briefly false during a step it is about to run —
  // and everything that defers work "while the columns move" has to keep
  // deferring across that gap or it will fire in it.
  property bool stepping: false

  // A QUARTER of the pane, not a third. Distance is the other half of how
  // tight a move feels: the same duration over less ground reads as
  // controlled, and over more ground as a swing. Far enough to still say
  // which way the tree went.
  function startTravel(down) {
    millerAnim.stop();
    millerFade.stop();
    miller.x = (down ? 1 : -1) * Math.round(millerBox.width * root.millerTravel);
    miller.opacity = root.millerDim;
    millerAnim.start();
    millerFade.start();
    // The animator is running now, so millerAnim.running does the guarding
    // from here. This flag only ever covered the tick between the step and
    // this call — clearing it anywhere later would deadlock resumePreview,
    // which is the one thing that ends a slide.
    root.stepping = false;
  }

  function millerStep(from, to) {
    if (root.viewMode !== "columns" || from === "" || from === to) return;
    const down = to.indexOf(from === "/" ? "/" : from + "/") === 0;
    const up = from.indexOf(to === "/" ? "/" : to + "/") === 0;
    if (!down && !up) return;

    // THE COLUMNS CHANGE SEATS. Walking down, the preview becomes the middle
    // and the middle becomes the parent; walking up, the other way. Only the
    // far column is handed a directory it has never held, so the other two
    // sync against rows they already have and find nothing to do.
    //
    // Ahead of everything else in enter(): the cwd and the seed have not
    // moved yet, so no column has been told about the new directory. Rotate
    // afterwards and the column about to leave the middle would rebuild
    // itself for the new listing and then rotate away from it.
    // WHAT THE KEEPING COLUMNS ARE ABOUT, said before they are asked.
    //
    // Rotating is only half of it. A column's rows are bound BY SLOT, so the
    // one moving out of the middle immediately re-reads whichever source its
    // new slot names — and at this instant those sources still describe the
    // old position. Walking up, the column carrying the directory we are
    // leaving lands in the preview slot and reads previewRows, which is still
    // the child it was showing a moment ago: it would rebuild to the wrong
    // rows and then rebuild again when the real answer arrived.
    //
    // The directory being left is in hand right now, so the source is told
    // first and the binding finds the rows already there. The confirming pass
    // behind it writes the same thing and the diff finds nothing to do.
    const leaving = (root.act.view || []).slice();
    root.millerRotate(down);
    if (down) {
      root.parentRows = leaving;
    } else {
      root.previewRows = leaving;
      root.previewKind = "dir";
      // It IS showing this directory, so refreshPreview has nothing to ask
      // for and previewFade has no change of subject to announce.
      root.previewShown = from;
    }

    // ── THE SLIDE STARTS WITH THE COLUMNS, NOT AHEAD OF THEM ────────────
    // Setting the offset here put the travel on the frame BEFORE the columns
    // had taken their new seats. Caught on a capture: one frame showed the
    // OLD arrangement — parent, current and preview exactly as they were —
    // displaced bodily by a quarter of a pane, and the next frame snapped
    // into the new arrangement at a different offset. The whole tree leaping
    // sideways and back is the flicker that replaced the stale-rows one.
    //
    // Queued BEHIND the columns' own sync, which is a callLater queued a
    // moment ago by the rotation above, so the seats, the rows and the offset
    // all land on the same frame. By function reference rather than a closure
    // so that two quick steps coalesce to one travel, in the direction of the
    // second.
    root.stepping = true;
    Qt.callLater(root.startTravel, down);
  }

  // WHERE THE CURSOR WAS ASKED TO GO once the rows are actually in.
  //
  // Pulled out of the listing handler because rows now arrive two ways: from
  // the `find` behind a refresh, and from the peek the miller preview had
  // already taken of the directory you were about to step into. Going back UP
  // is the case that showed it — goUp arms wantSel with the folder you are
  // leaving so the cursor lands back on it, and a seeded arrival drew the rows
  // without ever consulting it.
  //
  // SPENT ONLY WHEN IT LANDS. It used to be cleared the moment any listing
  // arrived, found or not — and the listing that arrives first is very often
  // the one that raced a creation and does not have the new file in it yet.
  // The landing was thrown away, the rename opened on whatever row the cursor
  // happened to be on, and the new file sat there under its generic name. That
  // was the "sometimes" in inline creation. Left armed, the next listing takes
  // it, and there is always a next one: inotify fires when the file appears
  // and the command runner refreshes when it exits.
  function landWanted() {
    if (root.wantSel === "") return false;
    const want = root.wantSel;
    let at = -1;
    // through the pane, not the proxy — landWanted is called in the same
    // statement run that wrote the rows, and the proxy is one evaluation
    // behind there. See currentRow.
    const v = root.act.view;
    for (let i = 0; i < v.length; ++i)
      if (v[i].path === want) { at = i; break; }
    if (at < 0) return false;
    root.wantSel = "";
    root.act.sel = at;
    root.anchor = at;
    // Something just made: land on it, flash it, and open the name for
    // editing — the second half of `a`, once the row it is about exists.
    if (want === root.freshPath) {
      root.madePulse++;
      root.renamePath = want;
      root.renaming = true;
    }
    return true;
  }

  function goTo(path) {
    if (path === root.cwd) return;
    root.pushTrail(path);
    root.enter(path);
  }

  // ── THE HISTORY, WRITTEN HERE AND NOWHERE ELSE ─────────────────────────
  // goTo is every navigation you asked for; enter is the move itself. The
  // split was already here — enter's own note says it is "what back and
  // forward use" — with nothing yet on the other side of it. This is that.
  //
  // The FIRST push seeds the pane's current directory as well, because a
  // trail that starts at the second place you visited cannot take you to the
  // first.
  // What the cursor is on, remembered against the directory being left.
  function markTrailSel() {
    const p = root.act;
    if (p.cwd === "") return;
    const r = root.currentRow();
    const m = p.trailSel;
    m[p.cwd] = r ? r.path : "";
    p.trailSel = m;
  }

  function pushTrail(path) {
    const p = root.act;
    root.markTrailSel();
    const t = p.trailAt < 0 ? [] : p.trail.slice(0, p.trailAt + 1);
    if (t.length === 0 && p.cwd !== "") t.push(p.cwd);
    if (t.length > 0 && t[t.length - 1] === path) return;
    t.push(path);
    // A wall you cannot see the end of is a leak. Two hundred is more places
    // than anybody walks back through, and the oldest is the least missed.
    while (t.length > 200) t.shift();
    p.trail = t;
    p.trailAt = t.length - 1;
  }

  readonly property bool canBack: root.act.trailAt > 0
  readonly property bool canForward:
    root.act.trailAt >= 0 && root.act.trailAt < root.act.trail.length - 1

  // SAYS SO WHEN THERE IS NOWHERE TO GO. These were silent at the ends of
  // the trail, which was fine while the keys that carried them were H and L —
  // a shifted letter you press deliberately. They are h, l and the arrows now,
  // which is the pair a hand reaches for by reflex, and a key that does
  // nothing and says nothing reads as a key that is not bound.
  function back() {
    if (!root.canBack) { root.warn("nothing to go back to"); return; }
    const p = root.act;
    root.markTrailSel();
    p.trailAt -= 1;
    root.aimAt(p.trail[p.trailAt]);
    // enter, not goTo: walking the trail is not a new place to record, and
    // recording it would make forward unreachable the moment you used back.
    root.enter(p.trail[p.trailAt]);
  }

  function forward() {
    if (!root.canForward) { root.warn("nothing to go forward to"); return; }
    const p = root.act;
    root.markTrailSel();
    p.trailAt += 1;
    root.aimAt(p.trail[p.trailAt]);
    root.enter(p.trail[p.trailAt]);
  }

  // Armed BEFORE the move, because landWanted runs against the rows as they
  // arrive — see its note. Empty is not an answer worth arming: it would
  // clear an aim something else had a better reason to set.
  function aimAt(dir) {
    const want = root.act.trailSel[dir];
    if (want !== undefined && want !== "") root.wantSel = want;
  }

  // the move itself, with no history bookkeeping — what back and forward use
  function enter(path) {
    // An edit belongs to the row it was opened on, and that row is about to
    // stop existing. Not a cancel-with-delete: leaving a directory is not a
    // decision about the thing you were naming, so whatever it is called now
    // is what it keeps.
    if (root.renaming) root.endRename(false);
    root.searchMode = "";
    root.searchQuery = "";
    // Navigating out of results is leaving them behind, not going back: the
    // way back was to where the search STARTED, and you have since gone
    // somewhere on purpose.
    root.searchBackCwd = "";
    root.searchBackSel = "";
    root.millerStep(root.cwd, path);
    // Held across the cursor reset below — see `arriving`. Dropped the
    // instant there are real rows to be about, which is the seed if there is
    // one and the listing if there is not.
    root.arriving = true;
    root.act.lastListing = null;   // a new directory is always a change
    root.act.cwd = path;
    root.act.query = "";
    filterField.text = "";
    root.act.marked = {};
    root.act.sel = 0;
    // Already in hand: draw it now and let the refresh behind it agree. The
    // seed is the exact bytes the refresh will return, so it recognises itself
    // and stops — the listing is never built twice.
    const seed = root.listingText[path];
    if (seed !== undefined) {
      root.act.raw = root.enrich(Terminus.parseListing(seed, path));
      // the cursor goes where it was asked to go in the same frame the rows do
      if (root.landWanted()) Qt.callLater(root.positionSel);
    }
    // HELD UNTIL BOTH HAVE SETTLED, then asked once. The rows and the cursor
    // cannot be written in one statement, and each of them on its own is a
    // complete answer to "what is under the cursor" — a wrong one. Going back
    // UP showed it worst: the rows arrive, the cursor is still at the top, so
    // the preview drew row zero of the parent; landWanted then moved it to
    // the directory you came out of and the preview was drawn a second time.
    // Measured at 27ms of the wrong folder, every step.
    root.arriving = false;
    if (root.viewMode === "columns") root.refreshPreview();
    // AND lastListing IS LEFT NULL ON PURPOSE. Marking the seed as the last
    // listing made the confirming `find` recognise itself and return early —
    // which skipped the whole of the handler behind that check, not just the
    // model write: landing the cursor where you asked for it, measuring the
    // directory when the usage mode is on, asking for thumbnails, putting the
    // scroll back. The seed exists to draw the rows a frame sooner, not to
    // stand in for the listing. The confirming pass writes the same rows, and
    // syncView compares them and finds nothing to do.
    root.refresh(true);
  }

  // The path to put the cursor on once the next listing arrives. A directory
  // is not in the list yet when you ask to leave it, so the wish is recorded
  // and the listing honours it.
  property string wantSel: ""

  // The raw output the current rows were built from, for the comparison above.
  //
  // `var` holding null rather than an empty string, and that is not a style
  // choice. "" was the sentinel for "nothing loaded yet" — but "" is also
  // exactly what `find` prints for an EMPTY DIRECTORY, so walking into one
  // compared "" against "", decided nothing had changed, and left the previous
  // directory's rows on screen under the new breadcrumb. null can never be a
  // listing, so it can never collide with one.
  readonly property var lastListing: root.act.lastListing

  function goUp() {
    const from = root.cwd;
    if (from === "/") return;
    root.wantSel = from;
    root.goTo(Terminus.dirname(from));
  }

  // Bumped every time something is OPENED — Return, or a double click. A
  // counter rather than a signal because a delegate can bind to a property and
  // cannot connect to a signal it has no reference to — see the note over
  // openMenuAt for the same trap.
  //
  // This is the only thing the row sweep and the tile flare hang off, and it
  // took two goes to get there. The sweep was fired by the CURSOR MOVING, on
  // the theory that a highlight arriving fully formed is hard to follow at
  // speed. But moving the cursor is not an event worth animating: it happens
  // on every j and k, on every click, and on the pointer drifting across the
  // list — and a light washing over a row you were only passing through reads
  // as the list flashing at the pointer. Opening something is the event. The
  // grid's tiles had always been drawn this way; the list rows now agree.
  property int openPulse: 0
  // and one for a row that has just been created, so it can announce itself
  property int madePulse: 0

  function activate() {
    const r = root.currentRow();
    if (!r) return;
    root.openPulse++;
    if (r.isDir) { root.goTo(r.path); return; }

    // While a portal request is open, opening a FILE means something else.
    // Handing it to xdg-open would launch an application on top of a dialog
    // the caller is still blocked on — the one thing a picker must not do.
    if (root.picking) {
      if (root.portal.save) {
        // saving: the file you opened is the one you mean to replace, so its
        // name goes in the field and the overwrite is yours to confirm
        saveField.text = r.name;
        saveField.forceActiveFocus();
      } else {
        root.portalConfirm();
      }
      return;
    }

    root.run(Terminus.openCommand(r.path));
  }

  // ── running things ──────────────────────────────────────────────────────
  // One process with a queue, so two verbs fired in quick succession cannot
  // interleave their output or race each other onto the same directory. Every
  // one of them re-reads the directory when it lands, because all of them
  // change what is in it.
  property var queue: []

  Process {
    id: actProc
    stderr: StdioCollector {
      id: actErr
      waitForEnd: true
      onStreamFinished: {
        const e = String(actErr.text || "").trim();
        if (e !== "") root.warn(e.split("\n")[0]);
      }
    }
    onExited: (code) => {
      if (code === 0 && root.status !== "") root.status = "";
      // emptying or restoring changes what the trash holds
      if (root.inTrash && !trashSizeProc.running) trashSizeProc.running = true;
      // A PEEK IS A PHOTOGRAPH and something has just changed the scene. The
      // cache is keyed by path with no notion of when it was taken, so a
      // folder previewed before a paste went on showing what it held before
      // it — for as long as it stayed in the cache. Dropped wholesale rather
      // than picked over: it holds two dozen entries and exists to make
      // walking back up a column instant, not to survive a write.
      root.previewCache = ({});
      root.previewOrder = [];
      if (root.viewMode === "columns") root.refreshPreview();
      root.refresh();
      root.drain();
    }
  }

  function run(cmd) {
    root.queue.push(cmd);
    root.drain();
  }

  function drain() {
    if (root.queue.length === 0 || actProc.running) return;
    actProc.command = ["sh", "-c", root.queue.shift()];
    actProc.running = true;
  }

  // ── selection ───────────────────────────────────────────────────────────
  // Where a shift-range starts. Moved by a plain click and by nothing else,
  // so shift-clicking twice extends from the same place both times rather
  // than walking the anchor along behind you.
  property int anchor: 0

  // True while the pointer is over a row or a tile. The drag box asks this
  // rather than guessing from coordinates: "was the cursor actually on top of
  // the item" is exactly the question, and the items themselves know.
  property bool hoverRow: false
  // Set by the body's HoverHandler from the view's own hit test. Starts true so
  // a click that arrives before any hover still reaches the empty-space
  // handler rather than falling into a gap.
  property bool overEmpty: true
  // Whether the pointer is somewhere a rubber band would mean anything. See
  // band.zoneL/zoneR — written by the hover handler that watches the body.
  property bool overBandZone: true
  // The narrowest a listing can be and still hold three columns. Below it the
  // size and date are dropped rather than squeezed into each other.
  readonly property real metaMinWidth: 420

  // The ink the CURRENT path segment is written in. Named because the hint
  // bars use it too: a bind's description and the folder you are standing in
  // are both "the thing this window is about right now", and they were two
  // hard-coded greys that happened to differ.
  readonly property color crumbInk: "#a3a9bd"

  // ── the mouse, as a glyph ─────────────────────────────────────────────
  // "middle click" is three syllables of hint sitting next to a two-word
  // entry, and the F1 list had "right click", "click" and "mouse 4 / 5" all
  // saying the same noun a different way.
  //
  // There is no per-button mouse glyph in the font, so the button is the
  // NUMBER beside it — the notation the keymap was already using for
  // "mouse 4 / 5", and the numbering this machine actually uses: evdev orders
  // them BTN_LEFT, BTN_RIGHT, BTN_MIDDLE (272, 273, 274), which is what
  // hyprland binds against. So 1 left, 2 RIGHT, 3 MIDDLE — not X11's order,
  // where 2 and 3 are the other way round.
  readonly property string mouseGlyph: "\uEFBA"
  function mouseKey(button) { return root.mouseGlyph + " " + button; }

  // ── the list's columns ──────────────────────────────────────────────────
  //
  // ONE set of fractions, read by the headings and by the rows, so a cell is
  // always under the heading that names it. Fractions of the INNER width: a
  // Row's padding comes out of its children's space, so subtracting the 24px
  // first is what makes the arithmetic exact at any width.
  //
  // Search gets a set of its own. A result is a PATH, not a name — where it
  // was found is half the answer and the reason the search was run — so the
  // column appears with the results and goes away with them. NAME gives up the
  // room for it: the numbers were already the narrowest things on the row.
  readonly property var colPlain:
    ({ name: 0.44, where: 0.0, kind: 0.14, size: 0.18, time: 0.24 })
  readonly property var colFound:
    ({ name: 0.30, where: 0.24, kind: 0.10, size: 0.16, time: 0.20 })
  // AND THE SAME ANSWER FOR A NARROW PANE. The miller layout's middle column
  // is a third of a pane wide, so it has always been drawn with no metadata at
  // all — which is right for a directory, where the name is the whole of what
  // distinguishes a row, and wrong for RESULTS, where it is not. A search in
  // columns view showed two files of the same name as two identical rows and
  // no way to tell which was which; that is the exact failure the WHERE column
  // was written for, and it was the one view that could not draw it.
  //
  // The numbers give up their room rather than the name: a size and a date are
  // what you can still get from the preview pane beside it, and where the file
  // actually is, is not.
  // Half and half. The first split gave WHERE the larger share on the grounds
  // that it is the disambiguating column — and turned "terminus.js" into
  // "ter….js", which disambiguates nothing because you can no longer read what
  // it is. A name has a length a file type puts a floor under; WHERE elides
  // from the FRONT and stays useful at any width, so it is the one that can
  // afford to give room back.
  readonly property var colFoundNarrow:
    ({ name: 0.52, where: 0.48, kind: 0.0, size: 0.0, time: 0.0 })
  // True while a scrollbar has the pointer. The rubber band stands down for
  // it — see ScrollRail's own note.
  property bool railDragging: false
  // True while the pointer is ON a scrollbar. The rail lies OVER the rows, so
  // a press there is also a press on a row — and a row's DragHandler is
  // allowed to take a grab away from the MouseArea that already accepted it,
  // which is why the first stroke down the bar also picked the file up and
  // started carrying it. preventStealing holds off the Flickable but says
  // nothing to a handler. Arming on HOVER rather than on the drag closes the
  // window entirely: by the time a drag is recognised the grab is long gone.
  property bool railHover: false

  // How far one notch of the wheel moves the list. Rows are root.rowH tall, so
  // this is "about four rows" at the default zoom — enough that a long folder
  // does not need a dozen strokes, short enough to stop where you meant to.
  readonly property real wheelStep: Math.round(root.rowH * 4)

  // ── the wheel MOVES rather than jumps ──────────────────────────────────
  //
  // Setting contentY outright covers the distance instantly, and at four rows
  // a notch that reads as a teleport: nothing travels, so there is nothing for
  // the eye to follow and you arrive having lost your place. The distance is
  // the same, it just takes 130ms to happen.
  //
  // ONE animation, retargeted, rather than one per view. Only one view is ever
  // being scrolled, and two animations racing on the same property is how a
  // list ends up stuttering. It works for all three views and for the second
  // pane for the same reason wheelTarget does: they are all Flickables and
  // contentY is contentY.
  NumberAnimation {
    id: wheelAnim
    property: "contentY"
    duration: 130
    easing.type: Easing.OutCubic
  }

  // Consecutive notches accumulate from where the animation is GOING, not from
  // where it currently is — otherwise spinning the wheel restarts the journey
  // on every notch and covers a fraction of what was asked for.
  function wheelScroll(v, delta) {
    if (!v) return;
    const most = Math.max(0, v.contentHeight - v.height);
    const from = (wheelAnim.running && wheelAnim.target === v)
      ? wheelAnim.to : v.contentY;
    const to = Math.max(0, Math.min(most, from + delta));
    if (to === v.contentY && !wheelAnim.running) return;
    wheelAnim.stop();
    wheelAnim.target = v;
    wheelAnim.to = to;
    wheelAnim.start();
  }

  // The view a wheel event belongs to. Only the split case needs thinking
  // about: with one pane there is one view, and with two the pointer decides,
  // because scrolling the pane you are NOT pointing at is never what was
  // meant. Coordinates are the body's, as everywhere else here.
  function wheelTarget(bx, by) {
    const onActive = !root.dual
      || (bx >= root.activePaneX && bx < root.activePaneX + root.activePaneW);
    if (!onActive)
      return root.otherViewMode === "grid" ? root.gridOf(root.pas.side) : root.listOf(root.pas.side);
    // Miller's preview is a pane of its own, and a long file shown in it is a
    // thing you scroll. The wheel used to reach the listing no matter which
    // column the pointer was over, so spinning it on a forty-line preview
    // moved the middle column instead and the preview sat there unread.
    //
    // Only when there is somewhere to scroll TO: a preview that fits would
    // otherwise swallow the wheel and leave the listing beside it stuck.
    // WHICHEVER PREVIEW IS ON SCREEN, not only the text one. The pane shows a
    // file's contents OR an archive's tree, and the wheel was offered to the
    // first and never the second — so spinning it over a long archive listing
    // scrolled the middle column instead and the tree sat there unread.
    if (root.viewMode === "columns"
        && bx - root.activePaneX >= previewPane.x) {
      if (textScroll.visible
          && textScroll.contentHeight > textScroll.height)
        return textScroll;
      if (archiveList.visible
          && archiveList.contentHeight > archiveList.height)
        return archiveList;
    }
    return root.viewMode === "grid" ? root.actGrid
         : (root.viewMode === "columns" ? root.midCol.view : root.actList);
  }

  // Which row is under a point in the body, or -1 for none.
  //
  // Asked of the VIEW, not of hover state. `hoverRow` is a single flag written
  // by every delegate's HoverHandler, so two of them crossing over write it in
  // an order nobody controls, and anything above the views that consumes hover
  // can leave it false while the pointer is plainly on a row. Routing clicks
  // through it made them land on nothing — items would not open. indexAt is
  // the view's own hit test and cannot disagree with what is drawn.
  //
  // Coordinates are the body's; each view converts to its own content space.
  function rowUnder(bx, by) {
    // ASKED OF THE VIEW UNDER THE POINTER — found by its own geometry, not
    // worked out from which pane is active or what mode that pane is in.
    //
    // Two goes at this were wrong in the same way the actList note above
    // describes. It used to return 0 ("over something") for the whole passive
    // half, so the empty-space overlay switched off and the click fell through
    // to the row underneath — right over that half's ROWS, wrong over its
    // empty space, where there is no row to fall through to and the click
    // simply vanished. Answering per side fixed that and broke more: it picked
    // the other half's view by root.viewMode, which is the ACTIVE pane's mode,
    // so with one half in list and the other in grid it questioned a view that
    // is not drawn, heard -1 everywhere, and the overlay ate every click in
    // that half instead.
    //
    // The views know where they are and whether they are on. Asking them is
    // the only form of this that cannot go stale.
    const v = root.viewUnder(bx);
    if (v) return v.indexAt(bx - v.x + v.contentX, by - v.y + v.contentY);

    // Not over a list or a grid. The only other thing holding rows is miller,
    // and miller only ever opens on the active half.
    if (root.viewMode !== "columns") return 0;
    if (root.dual && (bx < root.activePaneX
                      || bx > root.activePaneX + root.activePaneW)) return 0;
    const x = bx - root.activePaneX;
    const y = by - bodyBox.topH;
    if (x < root.midCol.x || x > root.midCol.x + root.midCol.width) return 0;
    return root.midCol.view.indexAt(x - root.midCol.x + root.midCol.view.contentX,
                           y + root.midCol.view.contentY);
  }

  // Whichever of the four views the pointer is inside, or null.
  //
  // `on` is the same gate the views draw themselves by — one pane's list and
  // grid are never both on — so this needs to know nothing about sides, modes
  // or which half has the keyboard. Written as a function because it reads
  // geometry that moves; every caller is an event handler, not a binding.
  function viewUnder(bx) {
    const vs = [listA, listB, gridA, gridB];
    for (let i = 0; i < vs.length; i++) {
      const v = vs[i];
      if (v.on && bx >= v.x && bx < v.x + v.width) return v;
    }
    return null;
  }
  // true for the whole of a row being dragged out, so the overlays that watch
  // hoverRow do not wake up when the pointer leaves the row it picked up
  property bool draggingRow: false

  // ── while a card has the screen ─────────────────────────────────────────
  //
  // Three layers keep a dialog modal and this is the third. InputShield stops
  // the POINTER, dialogKeys stops the KEYBOARD, and neither stops a
  // DragHandler: a pointer handler is allowed to take a grab away from an item
  // that has already accepted the press, and rowDrag/tileDrag are declared
  // with permissive enough grabs to do exactly that. So a press on a row
  // behind an open dialog still started a drag, complete with the card
  // following the cursor over the top of the panel.
  //
  // Handlers cannot be shielded, only switched off — so they read this.
  // ── HOW SOFT THE WINDOW GOES BEHIND A CARD ─────────────────────────────
  // The keymap already did this and it was the right idea in the wrong number
  // of places: a card standing on a flat wash of black has no depth behind it,
  // and dimming hides the thing you are deciding about instead of setting it
  // back. So every card that takes the window over softens it, and by its OWN
  // fade — the strongest one wins, so two cards overlapping never double the
  // blur or flicker as one of them leaves.
  //
  // sendTo is deliberately NOT here. A picker is about the listing behind it;
  // blurring that would hide the thing the choice is being made against, which
  // is the same reason it has no scrim.
  // WHAT IS LEFT OF THE SCRIM. It was 0.55 on six cards, written out six
  // times, and at that strength it was doing the whole job of setting the
  // window back — which is why the listing behind a dialog read as gone
  // rather than as behind. With the blur carrying the separation this only
  // has to take the contrast out of what is already soft.
  readonly property color cardScrim: Qt.rgba(0, 0, 0, 0.32)

  // ── WHAT THE OPEN SHEET IS ABOUT, SAID ON THE BAR ──────────────────────
  // Every one of these cards opened with a coloured caption band across its
  // own top — the same idea the send picker had before its header moved to
  // the chrome. A sheet hangs FROM the bar, so the bar is where it says what
  // it is: the band comes off the card, the breadcrumb steps aside, and the
  // sheet is left as the thing it actually is rather than a titled box.
  //
  // THE THING, NOT THE WORD, everywhere it can be. "Properties" tells you
  // what you already know; the filename is the one fact the card is about.
  readonly property string sheetTitle: {
    if (confirm.open) return confirm.heading;
    if (prompt.open) return prompt.heading;
    if (props.open)
      return props.many ? props.rows.length + " items"
        : (props.rows[0] ? props.rows[0].name : "Properties");
    if (perms.open)
      return perms.paths.length === 1
        ? Terminus.basename(perms.paths[0])
        : perms.paths.length + " items";
    if (bulk.open)
      return root.bulkNames.length === 1 ? "Rename 1 item"
        : "Rename " + root.bulkNames.length + " items";
    // THE FILE, not its type. The card led with the mime — "Open text/plain
    // with" — on the reasoning that the choice outlives this one file, and
    // what that actually put on the bar was a string with a slash in it where
    // a filename was expected.
    if (appPick.open)
      return appPick.paths.length > 1 ? "(multiple files)"
        : Terminus.basename(appPick.path);
    // The one sheet that is about the WINDOW rather than about a file, so it
    // is the one whose title is a word.
    if (prefs.open) return "Settings";
    if (cmdPalette.open) return "Commands";
    if (marks.open) return "Bookmarks";
    return "";
  }

  // A glyph ahead of the title, for the sheets that want one. Empty is the
  // answer for most of them: a card about a file says so by naming it, and
  // a picture beside the name would be saying it twice.
  //
  // Properties and permissions are the exception, and only for a single item.
  // The name in the bar is the whole of what those two cards are about, and
  // the glyph is how the row beside it was already being read — so the header
  // shows the file the way the listing showed it. Several at once have no one
  // glyph, and the title says "6 items" rather than a name.
  readonly property string sheetGlyph: {
    // The question's own mark — see confirm.verbGlyph, which keys it off the
    // same word verbInk keys the colour off.
    if (confirm.open)
      return confirm.choices.length > 0
        ? confirm.verbGlyph(confirm.choices[0].label) : "";
    // The file's own glyph when there is one file. The generic mark is for
    // the case that has no file to show — several of them at once.
    if (appPick.open)
      return appPick.icon !== "" ? appPick.icon : "\uEC65";
    if (props.open && !props.many && props.rows[0])
      return props.rows[0].glyph !== undefined ? props.rows[0].glyph : "";
    if (perms.open && perms.paths.length === 1) return perms.icon;
    // A VERB, not a file. Rename is always about several — one name is the
    // in-place edit — so there is no row's glyph to show and this says what
    // the card does instead.
    if (bulk.open) return "\uEC61";
    // The mark itself, the one the listing and the sidebar put beside a
    // bookmarked row — so the sheet is labelled with the thing it holds.
    if (marks.open) return "\uF02E";
    return "";
  }

  // PUNCTUATION IS NOT THE SUBJECT. Where the glyph is the row's own it wears
  // the row's ink with the name — but rename's is a verb standing in for a
  // row that does not exist, so it takes crumbInk, the ink the step you are
  // standing on uses. The send header's verb and arrow are inked the same way
  // and for the same reason.
  readonly property color sheetGlyphInk:
    bulk.open ? root.crumbInk : root.sheetTitleInk



  // ── THE HEADER IS INKED LIKE THE ROW IT IS ABOUT ───────────────────────
  // Glyph and name together, the way a row is inked everywhere else in this
  // window: a directory cyan, an archive yellow, a broken link red. The bar
  // was titling everything cyan, which made a card about a tarball look like
  // a card about a folder.
  //
  // Only where there IS one row. Several at once have no colour of their own
  // — the title says "6 items", which is not a file and is not inked like one.
  //
  // The confirm card is the exception it always was: its band wore the
  // PRIMARY choice's colour so the card read as dangerous exactly when what
  // it offered was, and that survives the move to the bar.
  readonly property color sheetTitleInk: {
    if (confirm.open)
      return confirm.choices.length > 0 ? confirm.choices[0].ink : Zenon.sand;
    if (appPick.open && appPick.icon !== "") return appPick.iconInk;
    if (props.open && !props.many && props.rows[0])
      return root.inkFor(props.rows[0]);
    if (perms.open && perms.paths.length === 1) return perms.iconInk;
    // SAND, which is what a bookmark is inked everywhere else in this window:
    // the ribbon on a listing row, the one in the sidebar, the one in the go
    // sheet. Cyan is the ink of a place you are going; this card is about the
    // marks themselves, so it wears their colour.
    if (marks.open) return Zenon.sand;
    return Zenon.cyan;
  }

  // Ramped by the sheets' own arrival, so the bar changes its mind at exactly
  // the speed the sheet does.
  readonly property real sheetHeadOn: Math.max(
    confirmSheet.cardInk, propsSheet.cardInk, permsSheet.cardInk,
    bulkSheet.cardInk, promptSheet.cardInk, appSheet.cardInk,
    prefsSheet.cardInk, paletteSheet.cardInk, marksSheet.cardInk)

  // ── WHICHEVER SHEET IS ON THE BAR ──────────────────────────────────────
  // Picked by how far along its arrival is rather than by `open`, because a
  // sheet on its way out has already stopped being open and is still hanging
  // there — the bar has to keep its gap for as long as there is something in
  // it. Only one is ever up, so the strongest is the one.
  readonly property var liveSheet: {
    const all = [confirmSheet, propsSheet, permsSheet,
                 bulkSheet, promptSheet, appSheet, prefsSheet,
                 paletteSheet, marksSheet];
    let best = null;
    for (let i = 0; i < all.length; i++)
      if (all[i] && (best === null || all[i].cardInk > best.cardInk))
        best = all[i];
    return (best !== null && best.cardInk > 0.01) ? best : null;
  }

  // ── AND WHERE THE BAR OPENS FOR IT ─────────────────────────────────────
  // The send picker had this to itself, as three properties on the picker.
  // They are the window's now, answered by the picker or by whichever dialog
  // sheet is up, so the bar splices for all of them through one rule instead
  // of the dialogs hanging under an unbroken hairline while the picker alone
  // got a gap.
  readonly property bool splicing:
    sendTo.splicing || root.liveSheet !== null
  readonly property real spliceX: root.liveSheet !== null
    ? root.liveSheet.drawnX : sendTo.spliceX
  readonly property real spliceW: root.liveSheet !== null
    ? root.liveSheet.drawnW : sendTo.spliceW

  // ONE ANSWER TO "IS A SHEET UP", and everything the bar does about it reads
  // this. The strip goes black, the breadcrumb stands down and the sheet's own
  // title fades in — three effects of one fact, which were three expressions
  // naming the picker and the dialogs separately until they disagreed.
  readonly property real sheetInk:
    Math.max(sendToCard.opacity, root.sheetHeadOn)

  // ── THE BAND A SHEET HANGS FROM ────────────────────────────────────────
  // Every strip of chrome above an open sheet goes the sheet's own colour, so
  // the header and the card read as one piece with a seam in it rather than
  // as a black card under a grey bar. Tinted rather than switched, off the
  // sheet's arrival, so it darkens at exactly the rate the sheet does — and
  // at full strength the tint is opaque black, which is what Zenon.black is
  // and therefore what the card is.
  //
  // One expression, because there is more than one strip: the path bar always,
  // the tab strip whenever there are two tabs, and they must not disagree.
  readonly property color chromeBg:
    Qt.tint(Zenon.headBg, Qt.rgba(0, 0, 0, root.sheetInk))

  // sendTo is read off its CARD, not off its overlay. The picker's overlay is
  // always fully opaque — it is a click catcher that paints nothing — so
  // asking it would have held the window soft for the whole session.
  readonly property real cardSoft: Math.max(
    confirm.opacity, props.opacity, perms.opacity,
    bulk.opacity, prompt.opacity, appPick.opacity, prefsSheet.cardInk,
    paletteSheet.cardInk, marksSheet.cardInk, sendToCard.opacity)

  readonly property bool modal: root.looking || cmdPalette.open || marks.open
    || props.open || perms.open || confirm.open
    || sendTo.open
    || prompt.open || bulk.open || prefs.open
    || appPick.open

  // Built when the path changes, not when a crumb is drawn. The delegate asked
  // crumbs() for its own length, so rendering n crumbs cost n+1 walks of the
  // path on every repaint.
  readonly property var crumbList: Terminus.crumbs(root.cwd, Paths.home())

  // How many are ticked, without building the list of them. The status line
  // wants a number, and markedRows scans the whole view to produce an array —
  // which it was doing on every pointer move of a drag-select.
  // Counted against the VIEW, not against the raw map.
  //
  // A filter narrows what every verb acts on — markedRows() has always walked
  // the view — so a header reading "12 selected" while `d` would trash three
  // of them was the window misreporting its own state. Marks made before the
  // filter was typed are KEPT rather than dropped: they stop being counted
  // while they are out of sight and come back the moment it clears.
  readonly property int markedCount: {
    const v = root.view;
    const m = root.marked;
    let n = 0;
    for (let i = 0; i < v.length; ++i) if (m[v[i].path]) n++;
    return n;
  }

  function markRange(a, b) {
    const lo = Math.min(a, b), hi = Math.max(a, b);
    const next = Object.assign({}, root.marked);
    const v = root.view;
    for (let i = lo; i <= hi; ++i)
      if (v[i]) next[v[i].path] = true;
    root.act.marked = next;
  }

  function markAt(i) {
    const r = root.view[i];
    if (!r) return;
    const next = Object.assign({}, root.marked);
    if (next[r.path]) delete next[r.path];
    else next[r.path] = true;
    root.act.marked = next;
  }

  // The three clicks every list in every file manager has:
  //   plain  — go here, and drop whatever was selected
  //   ctrl   — add or remove this one, keep the rest
  //   shift  — everything from the anchor to here
  //
  // Right-click is deliberately none of them: you right-click a selection to
  // act on it, so clearing it first would make the menu act on one file.
  function clickRow(i, right, shift, ctrl) {
    if (shift) { root.markRange(root.anchor, i); root.act.sel = i; }
    else if (ctrl) { root.markAt(i); root.act.sel = i; }
    else {
      if (!right) root.act.marked = {};
      root.act.sel = i;
      root.anchor = i;
    }
    content.forceActiveFocus();
  }

  // ── visual mode ───────────────────────────────────────────────────────
  // yazi's `v`. An anchor is dropped where the cursor stands and everything
  // between it and the cursor is selected as the cursor moves; `v` again stops
  // extending and leaves the selection exactly as it is, and Escape does the
  // same before it gets as far as clearing anything.
  //
  // WHAT WAS ALREADY MARKED IS KEPT SEPARATELY, in `visualBase`, and the range
  // is laid over a copy of it on every move. That is the difference between a
  // selection you can extend and one that only ever grows: walking back down
  // the range releases the rows the range no longer covers, without releasing
  // the ones that were marked before visual mode started.
  //
  // The anchor is its own property rather than the `anchor` shift-click uses,
  // because the two are live at the same time and mean different things — one
  // is where the last plain click landed, this one is where `v` was pressed.
  property int visualAt: -1
  property var visualBase: ({})
  readonly property bool visualOn: root.visualAt >= 0

  function toggleVisual() {
    if (root.visualOn) { root.endVisual(); return; }
    if (root.view.length === 0) return;
    root.visualBase = Object.assign({}, root.marked);
    root.visualAt = root.sel;
    root.extendVisual();
  }

  function endVisual() { root.visualAt = -1; root.visualBase = ({}); }

  // A RUN IN A LIST, A RECTANGLE IN A GRID.
  //
  // The range between two indices is the right answer in a list, where the
  // rows ARE the order. In a grid it is a snake: anchor on the third tile,
  // move down one row, and everything from there to the far edge and back
  // round comes with you, because index 3 to index 12 is twelve consecutive
  // tiles wrapping across the rows. Nobody dragging a mouse across a grid of
  // icons means that.
  //
  // So the grid takes the two corners and marks what lies BETWEEN them — the
  // same region a rubber band would cover, in whichever direction you moved,
  // and only the tiles inside it rather than the whole rows they sit on.
  function extendVisual() {
    if (!root.visualOn) return;
    const v = root.view;
    const next = Object.assign({}, root.visualBase);

    if (root.viewMode === "grid") {
      const cols = Math.max(1, root.gridCols());
      const ar = Math.floor(root.visualAt / cols), ac = root.visualAt % cols;
      const br = Math.floor(root.sel / cols),      bc = root.sel % cols;
      const r0 = Math.min(ar, br), r1 = Math.max(ar, br);
      const c0 = Math.min(ac, bc), c1 = Math.max(ac, bc);
      for (let r = r0; r <= r1; ++r) {
        for (let c = c0; c <= c1; ++c) {
          const i = r * cols + c;
          if (v[i]) next[v[i].path] = true;
        }
      }
    } else {
      const lo = Math.min(root.visualAt, root.sel);
      const hi = Math.max(root.visualAt, root.sel);
      for (let i = lo; i <= hi; ++i) if (v[i]) next[v[i].path] = true;
    }
    root.act.marked = next;
  }

  function toggleMark() {
    const r = root.currentRow();
    if (!r) return;
    const next = Object.assign({}, root.marked);
    if (next[r.path]) delete next[r.path];
    else next[r.path] = true;
    root.act.marked = next;
  }

  // How many tiles fit across, which is what up and down have to step by.
  // Asked of the view rather than recomputed from targetCell: the cell width
  // is rounded to divide the pane exactly, so dividing the pane by the TARGET
  // gives a different number at some widths.
  function gridCols() {
    return Math.max(1, Math.floor(root.actGrid.width
                    / Math.max(1, root.actGrid.cellWidth)));
  }

  function moveSel(delta) {
    const n = root.view.length;
    if (n === 0) return;
    // WRAPS, but only off the end it is already standing on.
    //
    // Down at the bottom is the top again and up at the top is the bottom —
    // which is what a list of thirty items with the one you want at the other
    // end wants. A page or a half page from the MIDDLE still lands on the end
    // rather than jumping past it to the far side: "down sixteen" from row
    // four means row twenty or the bottom, never the top.
    let i = root.sel + delta;
    if (i < 0) i = root.sel === 0 ? n - 1 : 0;
    else if (i > n - 1) i = root.sel === n - 1 ? 0 : n - 1;
    root.act.sel = i;
    Qt.callLater(root.positionSel);
  }


  // ── the verbs ───────────────────────────────────────────────────────────
  function yank(op) {
    const rows = root.acting();
    if (rows.length === 0) return;
    root.setPending({ op: op, paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    // AND ON THE SYSTEM CLIPBOARD, so a copy here means something everywhere
    // else — see clipboardCopyCommand. Its own process rather than the action
    // queue: that queue refreshes the listing and clears the status line when
    // it drains, and putting a clipboard write through it would make `y` blink
    // the directory and wipe the message it had just set.
    clipCopyProc.command = ["sh", "-c",
      Terminus.clipboardCopyCommand(rows.map((r) => r.path))];
    clipCopyProc.running = true;
    root.status = rows.length + (op === "copy" ? " to copy" : " to move");
  }

  Process { id: clipCopyProc }

  // ── what the SYSTEM clipboard is holding ────────────────────────────────
  // Consulted only when terminus has nothing of its own pending, so an
  // operation started here always wins over whatever else has been copied
  // since — the internal list knows the difference between a copy and a move
  // and a clipboard mostly does not.
  Process {
    id: clipProc
    stdout: StdioCollector {
      id: clipOut
      waitForEnd: true
      onStreamFinished: {
        const parts = String(clipOut.text || "").split("\u001e");
        const kind = parts[0];
        // An image that exists only on the clipboard has already been written
        // by the script — there was no file to copy, so there was one to make.
        if (kind === "wrote") {
          const name = parts[1] || "";
          root.wantSel = Terminus.joinPath(root.destDir, name);
          root.status = "pasted " + name;
          root.refresh();
          return;
        }
        if (kind === "gnome" || kind === "uris") {
          const lines = String(parts[1] || "").split("\n")
            .map((x) => x.trim()).filter((x) => x !== "");
          // GNOME's format leads with the word for the operation; a bare
          // uri-list says nothing about it, and copy is the safe reading.
          let op = "copy";
          if (kind === "gnome" && lines.length > 0) {
            op = lines[0] === "cut" ? "move" : "copy";
            lines.shift();
          }
          const paths = [];
          for (const l of lines) {
            if (l.indexOf("file://") !== 0) continue;
            let pth = l.slice(7);
            try { pth = decodeURIComponent(pth); } catch (e) { /* as it came */ }
            paths.push(pth);
          }
          if (paths.length === 0) { root.warn("nothing to paste"); return; }
          root.setPending({ op: op, paths: paths,
                            names: paths.map((x) => Terminus.basename(x)) });
          // Straight back through the ordinary path, conflict scan and all.
          root.paste();
          return;
        }
        root.warn("nothing to paste");
      }
    }
  }

  // Nothing is written until the answer to "what is already there" comes back.
  // cp and mv overwrite in silence, so asking first is the only thing standing
  // between a paste and losing the file that was already in the destination.
  Process {
    id: conflictProc
    stdout: StdioCollector {
      id: conflictOut
      waitForEnd: true
      onStreamFinished: {
        const clash = Terminus.parseConflicts(conflictOut.text);
        // The mode is a plain string, not Terminus.CLASH.overwrite: a QML .js
        // import does not reliably expose top-level `const` bindings on its
        // namespace, and nothing else in this window reads one that way. The
        // names live in CLASH inside terminus.js, where the comparisons are.
        if (clash.length === 0) { root.commitPaste("overwrite"); return; }
        // Three answers, and Overwrite is deliberately NOT the one Enter takes
        // by reflex being listed first — it is, because it is the one you
        // usually mean, but it wears the alarm colour so a blind Enter is at
        // least an informed one. "Keep both" renames the incoming copy; "Skip"
        // keeps what is already there and takes the rest of the selection.
        confirm.askMany(
          (root.pending.op === "copy" ? "Copy" : "Move") + " over "
            + clash.length + (clash.length === 1 ? " item" : " items") + "?",
          clash.join("   "),
          [{ label: "Overwrite", ink: Zenon.red,
             act: () => root.commitPaste("overwrite") },
           { label: "Keep both", ink: Zenon.green,
             act: () => root.commitPaste("keep") },
           { label: "Skip", ink: Zenon.blue,
             act: () => root.commitPaste("skip") }]);
      }
    }
  }

  function paste() {
    if (!root.pending || root.pending.paths.length === 0) {
      // Nothing of ours. Ask the system what it has — files copied in another
      // file manager, or an image that only exists on the clipboard.
      clipProc.command = ["sh", "-c",
        Terminus.clipboardPasteCommand(root.destDir)];
      clipProc.running = true;
      return;
    }
    conflictProc.command = ["sh", "-c",
      Terminus.conflictCommand(root.pending.names, root.destDir)];
    conflictProc.running = true;
  }

  // ── transfers in flight, all of them at once ────────────────────────────
  //
  // They used to QUEUE: one Process, one `job`, and anything started while it
  // ran went into a list and waited. That was the safe reading of "two rsyncs
  // writing the same destination race over the same names", and it cost you
  // the obvious thing — a copy off a slow disk and an extract on a fast one
  // have nothing to do with each other, and making the second wait for the
  // first is the file manager inventing a dependency that does not exist.
  //
  // So: one Process PER JOB, created when the job starts and destroyed when it
  // exits. Nothing is serialised.
  //
  // THE RACE IS REAL AND IT IS NARROW. Two jobs landing in the same directory
  // can each be told a name is free, because the conflict scan that answered
  // ran before the other job had written it. That needs both to be aimed at
  // one directory AND to carry a colliding basename; short of that they touch
  // nothing in common. It is worth knowing about and it is not worth making
  // every unrelated pair of transfers take turns.
  //
  // ── why a ListModel and not a list ────────────────────────────────────
  // A `property var` holding an array has to be REPLACED to be seen changing,
  // and a Repeater over a replaced array rebuilds every delegate. rsync
  // reports progress several times a second, so the drawer would have thrown
  // its rows away and built new ones at that rate: the width animation on
  // each bar would never once get to run, and a row highlighted under the
  // pointer would drop its highlight on the next line of output.
  //
  // A ListModel is edited in PLACE. set() touches the roles it is given and
  // the delegate that is already on screen simply re-reads them.
  ListModel { id: jobsModel }

  // What the drawer never draws, kept out of the model: a QObject does not
  // belong in a ListModel row, and `names` is an array, which does not either.
  // Written at start, read at exit, and nothing binds to it — so it is a plain
  // map rather than a property that has to be reassigned to be noticed.
  property var jobMeta: ({})
  property int jobSeq: 0
  // Bumped when a job STARTS, and read by nothing except the drawer's glow.
  // A counter rather than a signal so a Connections can watch it without the
  // window having to declare a signal for one animation.
  property int jobStarted: 0
  // Bumped when one ends BADLY, which the glow reads the same way it reads
  // jobStarted — one burst, one colour, two different pieces of news.
  property int jobFaulted: 0
  // How many rows in the drawer are a job that failed or was stopped. A count
  // rather than a search, because the glyph's colour is a binding and a
  // binding cannot walk a ListModel and notice when it changes.
  property int jobFaults: 0
  // Whether the pointer is on the drawer's glyph, and whether it is on the
  // card. Two items, one question — the drawer stays open while the pointer
  // is over EITHER, which is what lets you move from the button to the list
  // without crossing a gap that closes it.
  property bool jobsOverGlyph: false
  property bool jobsOverCard: false

  // Every Process the window runs for a job is one of these. Made at start,
  // destroyed at exit — a pool would only be a set of Processes to keep track
  // of on top of the jobs they are running.
  Component {
    id: jobRunner

    Process {
      id: proc
      property int jobId: -1

      // rsync writes its progress to stdout and rewrites the line with \r, so
      // this is a stream of one growing line rather than a sequence of them.
      stdout: SplitParser {
        splitMarker: "\r"
        onRead: (line) => root.jobLine(proc.jobId, line)
      }
      stderr: StdioCollector {
        id: procErr
        waitForEnd: true
        onStreamFinished: {
          const e = String(procErr.text || "").trim();
          if (e !== "") root.warn(e.split("\n")[0]);
        }
      }
      onExited: (code) => root.jobExited(proc.jobId, code)
    }
  }

  // By id, never by position: a row can be removed while another job is
  // mid-flight, and an index held across that is pointing at the wrong job.
  function jobRowAt(id) {
    for (let i = 0; i < jobsModel.count; ++i)
      if (jobsModel.get(i).id === id) return i;
    return -1;
  }

  // set() leaves the roles it is not given alone, which is the whole reason
  // this is one call and not a read-modify-write of the row.
  function updateJob(id, patch) {
    const i = root.jobRowAt(id);
    if (i >= 0) jobsModel.set(i, patch);
  }

  function jobLine(id, line) {
    const i = root.jobRowAt(id);
    if (i < 0) return;
    const j = jobsModel.get(i);

    // an archive job counts entries; the percentage is derived from the total
    // it announced before it started
    if (j.op === "archive" || j.op === "extract") {
      const rec = Terminus.parseArchiveProgress(line);
      if (!rec) return;
      const entries = rec.total !== undefined ? rec.total : j.entries;
      const seen = rec.at !== undefined ? rec.at : j.seen;
      // an empty archive is finished the moment it starts, and 0/0 would
      // otherwise sit at nothing until the process exited
      const pct = entries > 0
        ? Math.max(0, Math.min(100, Math.round(seen * 100 / entries)))
        : (seen > 0 ? 100 : 0);
      root.updateJob(id, { entries: entries, seen: seen, pct: pct });
      return;
    }

    // "Keep both" copies one item at a time and announces each one, so the
    // row can say which of them it is on rather than letting the percentage
    // drop to zero once per item with no explanation.
    const item = Terminus.parseItem(line);
    if (item > 0) { root.updateJob(id, { index: item, pct: 0 }); return; }
    const pct = Terminus.parseProgress(line);
    if (pct < 0) return;
    root.updateJob(id, { pct: pct });
  }

  function jobExited(id, code) {
    const i = root.jobRowAt(id);
    if (i < 0) return;
    // read BEFORE the row goes: the message below is about the job that just
    // ended, and by the next line there is no job to ask
    const row = jobsModel.get(i);
    const op = row.op;
    const cancelled = row.cancelled;
    const meta = root.jobMeta[id] || { names: [], started: 0, proc: null };

    // A JOB THAT ENDED BADLY STAYS IN THE DRAWER.
    //
    // A transfer that worked has nothing left to say and its row goes, which
    // is what makes the drawer empty itself. One that failed or was stopped is
    // the opposite: it is the only thing you would have opened the drawer to
    // find out, and dropping it means the news is a red flash you may have
    // been looking away from. So the row is kept, marked, and cleared when it
    // has been read — see clearJobFaults.
    if (code !== 0) {
      jobsModel.set(i, { state: cancelled ? "stopped" : "failed", pct: 100 });
      root.jobFaults = root.jobFaults + 1;
      root.jobFaulted = root.jobFaulted + 1;
      jobFaultLinger.restart();
    } else {
      jobsModel.remove(i);
    }
    delete root.jobMeta[id];

    // Not here and now: the stderr collector's stream may still be closing,
    // and destroying the Process out from under it loses the one line that
    // says what went wrong.
    if (meta.proc) Qt.callLater(() => { if (meta.proc) meta.proc.destroy(); });

    // A cancel is a nonzero exit too, and reporting it as "transfer failed"
    // would be telling you something went wrong when you are the thing that
    // went wrong. Read off the ROW rather than off the status line, which now
    // belongs to whichever job spoke last.
    if (code !== 0 && !cancelled)
      root.warn(op === "archive" ? "archive failed"
                   : op === "extract" ? "extract failed" : "transfer failed");
    // SUCCESS USED TO SAY NOTHING AT ALL. Failure set the status line and
    // the panel simply vanished when a copy worked, which is fine while you
    // are watching it and useless the moment you are not — and a copy worth
    // starting is very often one you walk away from.
    //
    // Announced through notify-send rather than by reaching into howler,
    // for the reason chronos/Chronos.qml gives where it does the same: it
    // goes out over DBus and comes back through the same server every other
    // application uses, so it lands in the history and the bell counts it.
    // (Reaching in directly is not an option either — quickshell's
    // Notification type is not creatable, and Howler.record would add a
    // history row that never becomes a toast.)
    //
    // ONLY IF IT TOOK LONG ENOUGH TO LOSE INTEREST IN. A toast for every
    // two-file copy is noise you learn to dismiss without reading, which
    // costs the toasts that matter their credibility. The rest is left to
    // the drawer, which was the right answer for a job you watched.
    if (code === 0 && Date.now() - (meta.started || 0) > 3000) {
      Quickshell.execDetached(["notify-send", "-a", "terminus",
        Terminus.jobSummary(op, meta.names)]);
    }
    // and clear the note the job was started with — `status` is sticky, so
    // "3 to copy" would otherwise outlive the copy by the rest of the session
    if (code === 0 && root.status !== "") root.status = "";
    root.act.marked = {};
    root.refresh();
    // the second pane is very often the destination, and a destination that
    // does not show what just arrived in it is the whole point missed
    root.refreshOther();
  }

  function startJob(op, paths, dest, clash) {
    const id = ++root.jobSeq;
    const proc = jobRunner.createObject(root, { jobId: id });
    if (!proc) { root.warn("could not start"); return; }

    // setsid, so the job gets a process group of its own and CANCELLING it can
    // take the whole tree down. Signalling the Process itself would only reach
    // the shell and leave rsync running orphaned, still writing files.
    //
    // Archive and extract go through the same row, the same drawer and the
    // same cancel as a transfer does: it is the same question — something is
    // working, how far along is it — and a second set of machinery to answer
    // it would only be a second set to keep in step.
    proc.command = ["setsid", "sh", "-c",
      op === "archive" ? Terminus.archiveJobCommand(paths, dest)
        : op === "extract" ? Terminus.extractJobCommand(paths[0], dest)
        : Terminus.transferCommand(paths, dest, op === "move", clash)];

    const names = paths.map((p) => Terminus.basename(p));
    root.jobMeta[id] = { proc: proc, names: names,
                         // when it began, which is the only thing that can
                         // tell a job worth announcing from one you watched
                         // finish
                         started: Date.now() };
    jobsModel.append({
      id: id, op: op,
      // Settled once, here: the names cannot change while the job runs, and
      // a delegate recomputing this on every progress line would be doing
      // string work several times a second to reach the same answer.
      what: names.length === 1 ? names[0] : names.length + " items",
      pct: 0, index: 0, total: paths.length,
      // entries counted rather than bytes measured, for the two ops whose
      // tools report no percentage of their own
      entries: 0, seen: 0, cancelled: false,
      // "running" until it ends; "failed" or "stopped" if it ends badly, in
      // which case the row outlives the job — see jobExited.
      state: "running" });
    // after the row is in, so anything watching this finds the job there
    root.jobStarted = root.jobStarted + 1;
    proc.running = true;
  }

  // Kill the job's whole process group. The negative pid is the group, which
  // is why the job was started under setsid in the first place.
  //
  // execDetached rather than a Process of its own: cancelling two jobs in the
  // same breath would overwrite the command of a single shared killer before
  // it had run, and the second cancel would kill the first job twice while the
  // second went on working.
  function cancelJob(id) {
    const i = root.jobRowAt(id);
    if (i < 0) return;
    // marked before the signal lands, so the exit that follows knows it was
    // asked for rather than reporting a failure
    jobsModel.set(i, { cancelled: true });
    const meta = root.jobMeta[id];
    const pid = (meta && meta.proc) ? meta.proc.processId : 0;
    if (pid > 0)
      Quickshell.execDetached(["sh", "-c", "kill -TERM -" + pid + " 2>/dev/null"]);
    root.status = "cancelled";
  }

  // The rows for jobs that ended badly, dropped. Called when the drawer has
  // been opened and closed again — you have read it — and by the timer below
  // for the case where you never looked.
  function clearJobFaults() {
    if (root.jobFaults === 0) return;
    for (let i = jobsModel.count - 1; i >= 0; --i)
      if (jobsModel.get(i).state !== "running") jobsModel.remove(i);
    root.jobFaults = 0;
    jobFaultLinger.stop();
  }

  // Long enough to notice from across the room, short enough that a failure
  // half an hour ago is not still shouting at you.
  Timer {
    id: jobFaultLinger
    interval: 12000
    onTriggered: root.clearJobFaults()
  }

  function cancelAllJobs() {
    // the ids FIRST, into an array of their own: each cancel touches the
    // model, and walking a model that is being written is how you skip every
    // second row
    const ids = [];
    for (let i = 0; i < jobsModel.count; ++i) ids.push(jobsModel.get(i).id);
    for (const id of ids) root.cancelJob(id);
  }

  // ── ANOTHER ONE OF THESE, HERE ─────────────────────────────────────────
  // `y y` then `p` already does it in two gestures. This is the one gesture,
  // and it is not a new mechanism: a duplicate IS a copy into the directory
  // you are already standing in, with the clash resolved rather than asked
  // about — because the clash is the whole point. terminus_free turns
  // "report.pdf" into "report (1).pdf" the same way "Keep both" does, at the
  // moment of writing rather than from a listing that may be stale.
  //
  // Straight to commitPaste, skipping paste()'s question: there is nothing to
  // ask. Every item collides, by construction.
  function duplicate() {
    const rows = root.acting();
    if (rows.length === 0) return;
    root.setPending({ op: "copy",
                      paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    root.pasteDest = root.cwd;
    root.commitPaste("keep");
    root.act.marked = {};
    root.status = rows.length === 1 ? "duplicated"
      : "duplicated " + rows.length;
  }

  function commitPaste(clash) {
    const p = root.pending;
    if (!p) return;
    // A move is recorded as where each item was and where it is about to be,
    // so undo can put it back precisely. A copy is not recorded at all — see
    // the undo stack's own note.
    if (p.op === "move") {
      const pairs = [];
      for (let i = 0; i < p.paths.length; ++i) {
        pairs.push([p.paths[i],
          Terminus.joinPath(root.destDir, Terminus.basename(p.paths[i]))]);
      }
      root.pushUndo({ kind: "move", pairs: pairs });
    }
    root.startJob(p.op, p.paths, root.destDir, clash);
    // spent: the next paste is a paste into where you are standing again
    root.pasteDest = "";
    // a move is spent once it lands; a copy can be pasted again elsewhere
    if (p.op === "move") root.setPending(null);
    root.act.marked = {};
  }

  // ── ASKING ABOUT THE TRASH ─────────────────────────────────────────────
  // Only this one is optional. Trash is recoverable — the undo record below
  // is what recovers it — so being asked every time is a keystroke spent on a
  // decision that can be unmade. deleteForever() has no such switch and never
  // will: that is the difference between the two verbs.
  property bool confirmTrash: true

  // ── WHETHER THE CURSOR SLIDES ──────────────────────────────────────────
  // Every list in this window marks its cursor with one bar that travels
  // between rows rather than a fill that blinks from one to the next. It is
  // 110ms and it is the difference between a cursor that moves and a cursor
  // that teleports — but it is also a thing that moves on screen every time
  // you press j, and that is not to everyone's taste on a list you drive at
  // speed. Off, the bar still marks the row; it simply arrives there.
  //
  // NOT a motion-scale setting: Zenon already has one of those and turning the
  // whole desktop's motion down to nothing is a different request from wanting
  // this one thing to stop sliding.
  property bool cursorSlide: true

  // The strip comes and goes with the second tab, so the body jumps by its
  // height the moment one is opened and again when it is closed. On, it is
  // simply always there.
  property bool alwaysTabs: false

  // The sort strip over a single-pane list. Twenty-two pixels, and sorting is
  // reachable from this panel and from the `,` keys either way.
  property bool colHeadsOn: true

  function trash() {
    const rows = root.acting();
    if (rows.length === 0) return;
    if (!root.confirmTrash) { root.doTrash(rows); return; }
    confirm.ask(
      "Trash " + rows.length + (rows.length === 1 ? " item" : " items") + "?",
      rows.map((r) => r.name).join("   "), "Trash",
      () => root.doTrash(rows));
  }

  // The doing, apart from the asking, so both routes run exactly the same
  // thing — including the undo record, which is the whole reason the ask can
  // be skipped at all.
  function doTrash(rows) {
    const paths = rows.map((r) => r.path);
    root.run(Terminus.trashCommand(paths));
    // recorded by where they CAME FROM: that is what undo can look up
    root.pushUndo({ kind: "trash", paths: paths });
    root.act.marked = {};
  }

  // ── renaming ────────────────────────────────────────────────────────────
  // In place, on the row itself. `renaming` is a window-level flag rather than
  // per-row state because only one row can be the cursor, and the cursor is
  // the only row this is ever about — so the delegate that happens to be
  // current picks it up and everything else ignores it, including the rows in
  // the other pane and in the columns beside it.
  property bool renaming: false

  // WHICH ROW IS BEING NAMED, by path.
  //
  // The field used to be tied to `current` — the row the cursor is on — and a
  // rename is not about the cursor, it is about a row. Any flicker in `sel`
  // while a listing settled took `current` away for a frame, the Loader
  // holding the field deactivated, the field was destroyed, and destruction
  // reads as "focus lost" — which commits and closes. That is the whole of
  // "inline creation sometimes works": the box opened and was torn down again
  // before you could type into it, leaving the file under its generic name.
  //
  // A path does not flicker. Every view checks its own row against it, so the
  // list, the miller middle column and the grid all open the same box on the
  // same row without any of them knowing about the others.
  property string renamePath: ""

  function beginRename() {
    if (!root.currentRow()) return;
    root.renamePath = root.currentRow().path;
    // `r` is never a creation, so Escape out of it must not delete anything —
    // and a create whose listing never came back would otherwise leave its
    // path armed behind an unrelated rename.
    root.freshPath = "";
    root.renaming = true;
  }

  // `cancelled` is Escape rather than Return, and for something that was
  // created a moment ago that means "I did not want this after all" — so it
  // goes away again. Anything older is left exactly as it was.
  function endRename(cancelled) {
    if (!root.renaming) return;
    root.renaming = false;
    root.renamePath = "";
    const fresh = root.freshPath;
    root.freshPath = "";
    if (cancelled === true && fresh !== "")
      root.run(Terminus.deleteCommand([fresh]));
    content.forceActiveFocus();
  }

  function commitRename(entry, name) {
    // Read BEFORE endRename, which is what clears it.
    const fresh = root.freshPath;
    const wasFresh = fresh !== "" && !!entry && entry.path === fresh;
    root.endRename(false);
    const typed = String(name || "").trim();
    // An empty answer on a thing that was just created keeps the name it
    // arrived with, which is the whole point of it arriving with one.
    if (!entry || typed === "" || typed === entry.name) return;
    // ENDING IN A SLASH MEANS A DIRECTORY, which is what the keymap has
    // promised `a` does all along and what the field used to refuse outright.
    // It is only offered for something JUST CREATED: on an existing file a
    // trailing slash would mean replacing it with a folder, which is a request
    // to destroy whatever is in it, and nobody types that on purpose.
    const asDir = /\/+$/.test(typed);
    const want = typed.replace(/\/+$/, "");
    if (want === "") return;
    // A name is a name, not a path: a slash inside it would move the file
    // somewhere else under the guise of renaming it.
    if (want.indexOf("/") >= 0) { root.warn("a name cannot contain /"); return; }
    const to = Terminus.joinPath(Terminus.dirname(entry.path), want);
    if (asDir) {
      if (!wasFresh) { root.warn("a name cannot contain /"); return; }
      root.run(Terminus.recreateAsDir(fresh, to));
      root.wantSel = to;
      return;
    }
    root.run(Terminus.renameCommand(entry.path, want));
    root.pushUndo({ kind: "rename", from: entry.path, to: to });
    // land on it under its new name rather than wherever the old one sorted
    root.wantSel = to;
  }

  // wl-copy, the same way folio puts a clip back on the clipboard
  function copyPath() {
    const rows = root.acting();
    if (rows.length === 0) return;
    root.run("printf '%s' " + Strings.shellQuote(rows.map((r) => r.path).join("\n"))
      + " | wl-copy >/dev/null 2>&1");
    root.status = "path copied";
  }

  // Straight into picasso's own store, not a command. It is a singleton in
  // this same shell, so setting a wallpaper from here is a property write and
  // the daemon repaints from the same binding the picker uses — no file to
  // hand over and nothing to keep in step.
  function setWallpaper(screenName) {
    const r = root.currentRow();
    if (!r || r.isDir || !Terminus.isImage(r.name)) return;
    if (screenName) Picasso.setFor(screenName, r.path);
    else Picasso.setAll(r.path);
    root.status = "background set";
  }

  // Which rows a rubber band covers. Worked out from the geometry rather than
  // by asking each delegate whether it intersects: a ListView only realises
  // the delegates near the viewport, so anything scrolled out has no item to
  // ask — but it still has an index, and the index is what the band is really
  // selecting.
  function applyBand(x1, y1, x2, y2, base) {
    const next = Object.assign({}, base);
    let lo = -1, hi = -1;

    // MEASURED FROM THE ACTIVE PANE, not from the body. band.x1/x2 are body
    // coordinates — zoneL is activePaneX — and a grid is placed at the pane's
    // own left edge. On the left half activePaneX is 0 and the two agree; on
    // the RIGHT half every column index came out a pane's width too far along,
    // past the end of the row, and the band selected nothing at all.
    const bx1 = x1 - root.activePaneX;
    const bx2 = x2 - root.activePaneX;

    if (root.viewMode === "grid") {
      const g = root.actGrid;
      const cols = Math.max(1, Math.floor(g.width / g.cellWidth));
      const r1 = Math.floor((y1 + g.contentY) / g.cellHeight);
      const r2 = Math.floor((y2 + g.contentY) / g.cellHeight);
      const c1 = Math.floor(bx1 / g.cellWidth);
      const c2 = Math.floor(bx2 / g.cellWidth);
      for (let r = Math.max(0, r1); r <= r2; ++r) {
        for (let c = Math.max(0, c1); c <= Math.min(cols - 1, c2); ++c) {
          const i = r * cols + c;
          if (i >= 0 && i < root.view.length) next[root.view[i].path] = true;
        }
      }
      root.act.marked = next;
      return;
    }

    // both single-column views: the band is a range of rows
    const view = root.viewMode === "list" ? root.actList : root.midCol.view;
    // In the miller layout the middle column is inset by the parent column, so
    // a drag started over the parent or the preview is not a selection of
    // anything in the middle one and must not act like it.
    if (root.viewMode === "columns") {
      // Same correction: these widths are inside the pane, the band's x is not.
      const left = root.parCol.width + 1;
      const right = left + root.midCol.width;
      if (bx2 < left || bx1 > right) { root.act.marked = next; return; }
    }
    lo = Math.floor((y1 + view.contentY) / root.rowH);
    hi = Math.floor((y2 + view.contentY) / root.rowH);
    // a drag that has not crossed a row boundary selects the same rows it
    // already did, and rebuilding the map for that is work with no result
    if (lo === band.lastLo && hi === band.lastHi) return;
    band.lastLo = lo;
    band.lastHi = hi;
    const v = root.view;
    for (let i = Math.max(0, lo); i <= Math.min(v.length - 1, hi); ++i)
      next[v[i].path] = true;
    root.act.marked = next;
  }

  // ── dragging in and out ─────────────────────────────────────────────────
  // text/uri-list is the one thing every file-aware application on the desktop
  // agrees on, so dragging a row into Firefox or a terminal hands over the
  // same list a file manager would. Dragging the CURSOR row alone would be
  // wrong when a selection exists — you dragged the selection.
  // What the drag card says, and the grab that turns it into a picture.
  property string dragLabel: ""
  property string dragGlyph: ""
  property color dragInk: Zenon.white
  property int dragCount: 0
  // Held so the grab result is not collected: Drag.imageSource points at a
  // url that lives exactly as long as this object does.
  property var dragGrab: null

  // Fills the card in for whatever is about to be dragged, renders it, and
  // hands the url back. Asynchronous by nature — grabToImage answers on the
  // next frame — so the caller starts the drag from inside the callback, with
  // the button still held, which is all the platform needs.
  function dragPicture(entry, then) {
    const rows = root.dragRows(entry);
    const first = rows[0] || entry;
    root.dragCount = rows.length;
    root.dragLabel = rows.length === 1
      ? (first ? first.name : "") : rows.length + " items";
    root.dragGlyph = (first && first.glyph) ? first.glyph : "";
    root.dragInk = (first && first.ink !== undefined) ? first.ink : Zenon.white;
    // A failed grab is not a reason to refuse the drag; it just goes without
    // a picture, which is what it did before there was one.
    if (!dragCard.grabToImage((res) => { root.dragGrab = res; then(res.url); }))
      then("");
  }

  // The rows a drag is actually about: the marked set when there is one, and
  // otherwise the row under the pointer. Exactly the rule dragUris always
  // used — written once now, because the picture and the payload have to
  // agree about what is being dragged or the card lies about the drop.
  function dragRows(entry) {
    const marked = root.markedRows();
    return marked.length > 0 ? marked : (entry ? [entry] : []);
  }

  function dragUris(entry) {
    return root.dragRows(entry).filter((r) => !!r)
      .map((r) => "file://" + encodeURI(r.path)).join("\r\n");
  }

  // What arrives from elsewhere. A copy unless the source asked for a move,
  // which is what dragging between two directories of the same disk means.
  // A drop ASKS whether it is a copy or a move.
  //
  // The action the drag carries is a guess — it comes from which modifier
  // happened to be held, and between two windows of the same application it is
  // whatever the compositor decided to propose. Copying when you meant to move
  // leaves a duplicate you have to find; moving when you meant to copy takes
  // the original away. Neither is worth inferring, so the drop says what it is
  // about to do and lets you pick. The conflict check still runs afterwards.
  // The directory currently under a drag, or "" for the space between rows.
  property string dropDir: ""

  // WHICH directory a drop means is a question about where the pointer is,
  // not about which item accepted it — there is one DropArea over the whole
  // body (see dropHint), and it already answers the same question for which
  // PANE the drop lands in. This just asks it one level finer.
  //
  // mapFromItem rather than hand-rolled offsets: the second pane's views are
  // nested a level deeper than the first pane's, and arithmetic written here
  // would have to know that and would break the day it moves. indexAt wants
  // CONTENT coordinates, which is what contentX/contentY add back.
  function dropDirAt(x, y) {
    const other = root.dual && (x < root.activePaneX
                             || x > root.activePaneX + root.activePaneW);
    if (other) {
      return root.dropRowAt(root.otherViewMode === "grid" ? root.gridOf(root.pas.side) : root.listOf(root.pas.side),
                            root.otherRows, x, y);
    }
    // MILLER HAS THREE LISTINGS ON SCREEN and the drop belongs to whichever
    // one the pointer is over. This used to ask `list`, which is not the view
    // columns mode draws with and is not even visible in it — so every drop
    // resolved to the pane's own directory, and dropUris then discarded it as
    // a file dropped into the folder it was already in. That is why dragging
    // onto a folder in the same directory did nothing here and worked
    // everywhere else.
    if (root.viewMode === "columns") {
      const inMid = root.dropRowAt(root.midCol.view, root.view, x, y);
      if (inMid !== "") return inMid;
      const inParent = root.dropRowAt(root.parCol.view, root.parentRows, x, y);
      if (inParent !== "") return inParent;
      // The preview column is a directory rather than a row in one — the same
      // reading a click there gets, so a drop and a click mean the same thing.
      if (root.previewKind === "dir" && previewPane.visible) {
        const q = previewPane.mapFromItem(dropHint, x, y);
        if (q.x >= 0 && q.y >= 0 && q.x <= previewPane.width
            && q.y <= previewPane.height) {
          const cur = root.currentRow();
          if (cur && cur.isDir) return cur.path;
        }
      }
      return "";
    }
    return root.dropRowAt(root.viewMode === "grid" ? root.actGrid : root.actList,
                          root.view, x, y);
  }

  // The row under the pointer in one particular view, or "" for none of it.
  //
  // mapFromItem rather than hand-rolled offsets: the second pane's views are
  // nested a level deeper than the first pane's, and arithmetic written here
  // would have to know that and would break the day it moves. indexAt wants
  // CONTENT coordinates, which is what contentX/contentY add back.
  function dropRowAt(v, rows, x, y) {
    if (!v || !v.visible || !rows) return "";
    const p = v.mapFromItem(dropHint, x, y);
    if (p.x < 0 || p.y < 0 || p.x > v.width || p.y > v.height) return "";
    const i = v.indexAt(p.x + v.contentX, p.y + v.contentY);
    if (i < 0 || i >= rows.length) return "";
    const r = rows[i];
    // only a directory can be dropped INTO; anything else means the folder
    // it is sitting in, which is what the empty space already means
    return (r && r.isDir) ? r.path : "";
  }

  // One curl per URL, through the ordinary action queue so they arrive in the
  // order they were dropped and the listing refreshes when each one lands.
  //
  // The LAST one is the one landed on, which is the one you were looking at
  // when you let go of a single drop and a reasonable answer for several.
  function fetchInto(urls, dest) {
    for (const u of urls) {
      const name = Terminus.urlFallbackName(u);
      root.wantSel = Terminus.joinPath(dest, name);
      root.run(Terminus.fetchUrlCommand(u, dest, name));
    }
    root.status = urls.length === 1 ? "fetching\u2026"
      : "fetching " + urls.length + "\u2026";
  }

  // EVERY WAY A DRAG CAN NAME WHAT IT IS CARRYING.
  //
  // `urls` is the parsed list and it is the right answer when there is one.
  // But a picture dragged off a web page does not always arrive that way:
  // Firefox offers text/x-moz-url, which is the address on one line and the
  // page's title on the next, and a drag carrying only that left `urls` empty
  // — so the drop was read as "nothing we can use" and silently ignored. That
  // is most of why dragging an image in from a browser did nothing.
  function urlsFrom(d) {
    if (d.urls && d.urls.length > 0) return d.urls;
    const out = [];
    const take = (text) => {
      for (const line of String(text || "").split(/[\r\n]+/)) {
        const t = line.trim();
        // The title line of a moz-url, and the comment lines a uri-list is
        // allowed to carry, are not addresses.
        if (t === "" || t.charAt(0) === "#") continue;
        if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0
            || t.indexOf("file://") === 0) out.push(t);
      }
    };
    if (d.hasUrls) take(d.text);
    for (const f of ["text/uri-list", "text/x-moz-url", "text/plain"]) {
      if (out.length > 0) break;
      if (d.formats && d.formats.indexOf(f) >= 0) take(d.getDataAsString(f));
    }
    return out;
  }

  function dropUris(urls, action, dest, atItem, atX, atY) {
    const into = (dest && dest !== "") ? dest : root.cwd;
    const paths = [];
    // THINGS DROPPED IN FROM OUTSIDE THE MACHINE. An image dragged off a web
    // page is not a file and never was — it arrives as an http address, and
    // this used to discard it along with the text selections and the colours,
    // so dragging a picture out of a browser into a file manager did nothing
    // at all. Dropping one HERE plainly means "keep this here", so it is
    // fetched into the directory it landed on.
    const remote = [];
    // A drop with nothing we can use — a text selection, a colour — is not
    // for us. Now that the DropArea takes everything, this is the filter.
    if (!urls || urls.length === 0) return;
    for (const u of urls) {
      const t = String(u);
      if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0) {
        remote.push(t);
        continue;
      }
      if (t.indexOf("file://") !== 0) continue;
      const path = decodeURIComponent(t.slice(7));
      // dropping a directory into itself is not a move, it is a mistake —
      // and neither is dropping one into something it contains, which mv
      // refuses anyway ("cannot move a directory into itself"). Catching it
      // here means the answer is nothing happening rather than an error.
      if (path === into || Terminus.dirname(path) === into) continue;
      if (into.indexOf(path + "/") === 0) continue;
      paths.push(path);
    }
    if (remote.length > 0) root.fetchInto(remote, into);
    if (paths.length === 0) return;
    const names = paths.map((p) => Terminus.basename(p));
    const drop = (op) => {
      root.setPending({ op: op, paths: paths, names: names });
      root.pasteDest = into === root.cwd ? "" : into;
      root.paste();
    };
    // ASKED WHERE IT WAS DROPPED, not in the middle of the screen.
    //
    // This was a confirm card: a drop that had just landed on a particular
    // folder threw a dialog into the centre of the window, and answering it
    // meant travelling back from where the pointer already was. A small menu
    // at the release point is the same question asked in the place the answer
    // is about — and it is dismissed the way every other menu is, so letting
    // go of the idea costs an Escape or a click rather than finding "Cancel".
    //
    // The dragged action is still offered FIRST, so the modifier held during
    // the drag is the one Return takes: the menu confirms the guess rather
    // than discarding it.
    const moving = action === Qt.MoveAction;
    const moveHere = { label: "Move here", act: () => drop("move") };
    const copyHere = { label: "Copy here", act: () => drop("copy") };
    const order = moving ? [moveHere, copyHere] : [copyHere, moveHere];
    order.push({ sep: true });
    // Abort is spelled out rather than left to Escape: a menu that appeared
    // under your hand should be dismissable by the same hand.
    order.push({ label: "Abort", act: () => {} });
    menu.openCustom(atItem, { x: atX, y: atY }, order);
  }

  // ── undo ────────────────────────────────────────────────────────────────
  // The three things that move a file out from under you, and nothing else.
  //
  // A COPY is not on the list: undoing one means deleting the copies, and a
  // stack that deletes files is a worse hazard than the mistake it fixes.
  // Trash, move and rename all have an exact inverse, which is the test for
  // belonging here.
  property var undoStack: []

  function pushUndo(entry) {
    const next = root.undoStack.slice();
    next.push(entry);
    // deep enough to cover a session's worth of slips, shallow enough that it
    // never becomes a second filesystem held in memory
    while (next.length > 20) next.shift();
    root.undoStack = next;
  }

  readonly property string undoLabel: {
    const n = root.undoStack.length;
    if (n === 0) return "";
    const e = root.undoStack[n - 1];
    if (e.kind === "trash") return "Undo trash";
    if (e.kind === "move") return "Undo move";
    return "Undo rename";
  }

  function undo() {
    if (root.undoStack.length === 0) { root.warn("nothing to undo"); return; }
    const next = root.undoStack.slice();
    const e = next.pop();
    root.undoStack = next;

    if (e.kind === "trash") {
      // by ORIGINAL PATH, not by the name in the trash: gio appends a suffix
      // when the name is already taken there, so the two are not the same
      // string and only the path is something we actually know.
      root.run(Terminus.restoreCommand(e.paths, "path"));
      root.status = "restored " + e.paths.length;
      return;
    }
    if (e.kind === "move") {
      let cmd = "";
      for (let i = 0; i < e.pairs.length; ++i) {
        const from = e.pairs[i][1], to = e.pairs[i][0];
        cmd += "mkdir -p -- " + Strings.shellQuote(Terminus.dirname(to))
          + " && mv -n -- " + Strings.shellQuote(from) + " "
          + Strings.shellQuote(to) + "\n";
      }
      root.run(cmd);
      root.status = "moved back " + e.pairs.length;
      return;
    }
    root.run(Terminus.renameCommand(e.to, Terminus.basename(e.from)));
    root.status = "rename undone";
  }

  // ── the trash, in both directions ───────────────────────────────────────
  readonly property bool inTrash: Terminus.isTrashDir(root.cwd)

  // How much the trash holds, asked when you are standing in it.
  property string trashSize: ""

  Process {
    id: trashSizeProc
    command: ["sh", "-c", Terminus.trashSizeCommand()]
    stdout: StdioCollector {
      id: trashSizeOut
      waitForEnd: true
      onStreamFinished: root.trashSize = String(trashSizeOut.text || "").trim()
    }
  }

  onInTrashChanged: {
    if (!root.inTrash) { root.trashSize = ""; return; }
    if (!trashSizeProc.running) trashSizeProc.running = true;
  }

  function emptyTrash() {
    confirm.ask("Empty the trash?",
      root.trashSize !== "" ? root.trashSize + " will be deleted for good"
                            : "Everything in it is deleted for good",
      "Delete", () => {
        root.run(Terminus.emptyTrashCommand());
        root.act.marked = {};
        root.status = "trash emptied";
      });
  }

  function restoreSelected() {
    const rows = root.acting();
    if (rows.length === 0) return;
    root.run(Terminus.restoreCommand(rows.map((r) => r.name), "name"));
    root.act.marked = {};
    root.status = "restoring " + rows.length;
  }

  // ── archives ────────────────────────────────────────────────────────────
  function extractSelected() {
    const rows = root.acting().filter((r) => !r.isDir && Terminus.isArchive(r.name));
    if (rows.length === 0) { root.warn("not an archive"); return; }
    // ONE JOB PER ARCHIVE, handed to the queue that already serialises work.
    // A single script over all of them could only report one count across
    // archives of wildly different sizes, and the panel would step backwards
    // every time it reached the next one.
    for (const r of rows) root.startJob("extract", [r.path], root.cwd, "");
    root.act.marked = {};
  }

  // yazi's `c a`. The name carries the format: ".tar.zst", ".zip", ".7z" —
  // bsdtar reads the extension and picks the writer, so there is no format
  // menu to get out of step with what the tools can actually produce.
  // The format is CHOSEN, not typed. It was a single "Compress…" that guessed
  // .tar.zst and left you to retype the extension for anything else — which
  // meant knowing which spellings bsdtar accepts. The name is still yours to
  // edit; only the extension comes from the menu.
  readonly property var archiveFormats: [
    [".tar.zst", "tar · zstd — fast, small"],
    [".tar.gz",  "tar · gzip — most portable"],
    [".tar.xz",  "tar · xz — smallest, slowest"],
    [".zip",     "zip — for other systems"],
    [".7z",      "7z — 7-Zip"]
  ]

  // What is being archived and what it will be called, held while the answer
  // to "is that name taken" comes back. Null at every other moment.
  property var archivePending: null

  // THE NAME IS NOT ASKED FOR ANY MORE.
  //
  // It was a prompt with the answer already typed into it, and the answer was
  // accepted as-is nearly every time — a dialog charging a keystroke for the
  // privilege of agreeing with it. The suggestion IS the name now: a directory
  // archives under its own name, and a handful of loose files archive under
  // the name of the directory they were sitting in, which is the only name
  // they have in common.
  //
  // What made the prompt worth its keystroke was the chance to notice you were
  // about to write over an archive that was already there. That question has
  // not gone away — it is just only asked when it is a real question, and it
  // is asked in the words a paste already uses.
  function beginArchive(ext) {
    const rows = root.acting();
    if (rows.length === 0) return;
    const e = (ext && ext !== "") ? ext : ".tar.zst";
    const name = (rows.length === 1 ? Terminus.stem(rows[0].name)
                                    : Terminus.basename(root.cwd)) + e;
    root.archivePending = { paths: rows.map((r) => r.path), name: name };
    archiveClashProc.command = ["sh", "-c",
      Terminus.archiveTargetCommand(root.cwd, name, e)];
    archiveClashProc.running = true;
  }

  // Nothing is written until that answer is in — bsdtar and 7z overwrite in
  // silence, exactly as cp and mv do, so the scan is the whole difference
  // between archiving and losing the archive that was already there.
  Process {
    id: archiveClashProc
    stdout: StdioCollector {
      id: archiveClashOut
      waitForEnd: true
      onStreamFinished: {
        const a = root.archivePending;
        if (!a) return;
        // Empty means the name is free. Otherwise: the name that is taken,
        // and the first one that is not.
        const answer = Terminus.parseConflicts(archiveClashOut.text);
        if (answer.length < 2) { root.commitArchive(a.name); return; }
        // The paste's own three answers, minus the one that would be a second
        // Cancel: SKIP and CANCEL are the same act when there is a single
        // thing to skip, and two buttons that do nothing is not a choice.
        // Overwrite wears the alarm colour here for the reason it does there.
        confirm.askMany(
          "Archive over " + answer[0] + "?",
          "keep both \u2192 " + answer[1],
          [{ label: "Overwrite", ink: Zenon.red,
             act: () => root.commitArchive(answer[0]) },
           { label: "Keep both", ink: Zenon.green,
             act: () => root.commitArchive(answer[1]) }]);
      }
    }
  }

  function commitArchive(name) {
    const a = root.archivePending;
    if (!a) return;
    root.archivePending = null;
    root.startJob("archive", a.paths, Terminus.joinPath(root.cwd, name), "");
    root.act.marked = {};
  }

  // ── links ───────────────────────────────────────────────────────────────
  // Paste, but leaving the file where it is. Uses the same yank buffer as a
  // normal paste, because "what am I about to put down" is the same question.
  function pasteLink(symbolic) {
    if (!root.pending || root.pending.paths.length === 0) return;
    root.run(Terminus.linkCommand(root.pending.paths, root.cwd, symbolic));
    root.status = symbolic ? "symlinked" : "hard linked";
  }

  // ── bulk rename ─────────────────────────────────────────────────────────
  // It used to open $EDITOR in a terminal with one name per line. That is a
  // good way to rename forty files and a poor way to find out you cannot:
  // the window was somewhere else, the rules were only checked after you had
  // closed it, and the whole feature depended on having an editor configured.
  // The editing happens in the card below now — see `bulk`.
  property var bulkNames: []
  // What they WOULD be called. Replaced whole rather than written into: a QML
  // property only reports a change when the reference changes, so mutating the
  // array in place left every row showing what it showed before.
  property var bulkEdits: []
  property string bulkDir: ""

  function beginBulkRename() {
    const rows = root.acting();
    if (rows.length === 0) return;
    root.bulkNames = rows.map((r) => r.name);
    root.bulkEdits = root.bulkNames.slice();
    root.bulkHistory = [];
    root.bulkDir = root.cwd;
    bulk.open = true;
  }

  function setBulkEdit(i, text) {
    if (i < 0 || i >= root.bulkEdits.length) return;
    if (root.bulkEdits[i] === text) return;
    const next = root.bulkEdits.slice();
    next[i] = text;
    root.bulkEdits = next;
  }

  // Find-and-replace across the whole set, from the ORIGINAL names.
  //
  // From the originals rather than from what is on screen, so running it twice
  // is the same as running it once — a replace that fed on its own output
  // turned "a-a" into "b-b" and then into "c-c" as you typed. The cost is that
  // it discards hand edits, which is why it is a button and not a live
  // binding: an edit you made by hand should not evaporate because the caret
  // moved through the pattern field.
  // How the two pattern fields are read, and how much of the name they touch.
  // Both live on root rather than on the card so the transforms below can read
  // them without knowing anything about where the buttons are.
  property bool bulkRegex: false
  property bool bulkStemOnly: true

  function applyBulkReplace(find, repl) {
    if (find === "") return;
    root.pushBulkHistory();
    root.bulkEdits = Terminus.bulkReplaceIn(root.bulkNames, find, repl,
                                            root.bulkRegex, root.bulkStemOnly);
  }

  // ── the transforms ──────────────────────────────────────────────────────
  // These read what is ON SCREEN and write it back, unlike the replace above,
  // which always works from the original names. The difference is deliberate
  // and it is the difference between a pattern and a verb: a replace run twice
  // should mean the same as run once, and "lowercase" run after "number" has
  // to see the numbers or the two cannot be combined at all.
  function applyBulkCase(mode) {
    root.pushBulkHistory();
    root.bulkEdits = Terminus.bulkCase(root.bulkEdits, mode, root.bulkStemOnly);
  }
  function applyBulkTidy() {
    root.pushBulkHistory();
    root.bulkEdits = Terminus.bulkTidy(root.bulkEdits, root.bulkStemOnly);
  }
  function applyBulkNumber(where) {
    root.pushBulkHistory();
    root.bulkEdits = Terminus.bulkNumber(root.bulkEdits, 1, 0, where, " ",
                                         root.bulkStemOnly);
  }
  // ── stepping back ───────────────────────────────────────────────────────
  // Every verb above is destructive of the one before it, and the useful way
  // to work is to try one, look at the rows, and try another. Without a way
  // back, "try" means "commit to", and the only escape was all the way to the
  // original names — which throws away the four presses that were right along
  // with the fifth that was not.
  //
  // A STACK rather than a single previous state, because the verbs are meant
  // to be stacked: number, then tidy, then lowercase is three presses and
  // stepping back through them one at a time is the same three in reverse.
  property var bulkHistory: []

  function pushBulkHistory() {
    const h = root.bulkHistory.slice();
    h.push(root.bulkEdits.slice());
    // Twenty is far past what anyone stacks by hand, and it keeps a card that
    // is open on four thousand rows from quietly holding forty copies of them.
    while (h.length > 20) h.shift();
    root.bulkHistory = h;
  }

  function undoBulkEdit() {
    if (root.bulkHistory.length === 0) return;
    const h = root.bulkHistory.slice();
    root.bulkEdits = h.pop();
    root.bulkHistory = h;
  }

  // Back to where the card opened, in one press, from however deep.
  function resetBulkEdits() {
    if (root.bulkEdits.join("\u0000") !== root.bulkNames.join("\u0000"))
      root.pushBulkHistory();
    root.bulkEdits = root.bulkNames.slice();
  }

  function commitBulkRename() {
    const pairs = Terminus.bulkPairs(root.bulkNames, root.bulkEdits);
    // Refused rather than half-applied — see bulkIssues for the rules. The
    // card disables its own button on the same test, so getting here with a
    // null means something changed underneath it.
    if (pairs === null) { root.warn("bulk rename refused"); return; }
    bulk.open = false;
    content.forceActiveFocus();
    if (pairs.length === 0) { root.status = "no names changed"; return; }
    root.run(Terminus.bulkRenameApply(root.bulkDir, pairs));
    root.status = "renamed " + pairs.length;
  }

  // ── open with ───────────────────────────────────────────────────────────
  // Filled in when the menu opens, because it costs a process and almost every
  // right-click is not about this.
  property var openWithApps: []
  // Whether the scan has ANSWERED, which is a different question from whether
  // it found anything — an empty list means "nothing handles this" only after
  // the process has been and gone, and the menu decides between a submenu and
  // a card on the strength of that distinction.
  property bool appsScanned: false
  // The file's type, which the same scan now leads with. Kept because the
  // answer to "nothing opens this" is to register something against the TYPE,
  // and by then the file that raised the question is beside the point.
  property string openWithMime: ""

  Process {
    id: appsProc
    stdout: StdioCollector {
      id: appsOut
      waitForEnd: true
      onStreamFinished: {
        root.openWithApps = Terminus.parseApps(appsOut.text);
        root.openWithMime = Terminus.parseAppsMime(appsOut.text);
        root.appsScanned = true;
      }
    }
  }

  function findApps(path) {
    root.openWithApps = [];
    root.openWithMime = "";
    root.appsScanned = false;
    // A directory, or a scan already in flight: either way nothing further is
    // coming, so the answer is in — there is nothing to open this with.
    if (!path || appsProc.running) { root.appsScanned = true; return; }
    appsProc.command = ["sh", "-c", Terminus.appsCommand(path)];
    appsProc.running = true;
  }

  function openWith(id, path) {
    root.run(Terminus.openWithCommand(id, path));
  }

  // ── and choosing one by hand ────────────────────────────────────────────
  // For the file nothing claims. The card lists everything installed rather
  // than everything that matches, because "nothing matches" is precisely how
  // you got here.
  function beginOpenWith(path) {
    if (!path) return;
    // THE SELECTION, with the pointer's row as the fallback — which is what
    // acting() means everywhere else in this window. The row the menu opened
    // on leads, so the type that gets adopted is the one that was asked about.
    const rows = root.acting();
    const out = [path];
    for (let i = 0; i < rows.length; ++i)
      if (rows[i].path !== path && !rows[i].isDir) out.push(rows[i].path);
    appPick.ask(out, root.openWithMime);
  }

  function selectAll() {
    const next = {};
    for (const r of root.view) next[r.path] = true;
    root.act.marked = next;
  }

  function invertSelection() {
    const next = {};
    for (const r of root.view) if (!root.marked[r.path]) next[r.path] = true;
    root.act.marked = next;
  }

  function setSort(key) {
    if (root.sortKey === key) root.sortDesc = !root.sortDesc;
    else { root.sortKey = key; root.sortDesc = false; }
  }

  function copyText(text, note) {
    root.run("printf '%s' " + Strings.shellQuote(text) + " | wl-copy >/dev/null 2>&1");
    root.status = note;
  }

  // Empty means xdg-terminal-exec, which is what it always did — see
  // Terminus.shellCommand for the two shapes a value can take.
  property string termCmd: ""

  function openShell() {
    root.run(Terminus.shellCommand(root.cwd, root.termCmd));
  }

  // yazi's `a`. One prompt for both, because the only difference is whether
  // the name ends in a slash — which is how yazi says it too.
  // ── creating ────────────────────────────────────────────────────────────
  // MAKE IT, THEN NAME IT — which is the order every file manager that feels
  // direct does it in, and the order a phantom row asking for a name up front
  // was pretending to.
  //
  // The item is created immediately under a free default name, the listing
  // brings it back, the cursor lands on it and the row goes straight into the
  // same inline edit `r` uses. So there is one naming interaction in this
  // window, not two, and the thing being named is on screen while you name it.
  //
  // Return with the name untouched keeps the default. Escape UNDOES the
  // creation rather than leaving a "new file" behind, which is what makes it
  // safe to press `a` to see what happens.
  property string freshPath: ""

  function beginCreate() { root.startCreate("file"); }
  function beginMkdir() { root.startCreate("dir"); }

  function startCreate(kind) {
    if (root.picking) return;
    // Finish whatever name is being typed rather than refusing: `a` twice in
    // a row is a reasonable thing to do, and the first one silently doing
    // nothing is not a reasonable answer to it.
    if (root.renaming) root.endRename(false);
    const name = Terminus.freeName(root.rows,
      kind === "dir" ? "new directory" : "new file");
    const path = Terminus.joinPath(root.cwd, name);
    root.freshPath = path;
    root.wantSel = path;
    root.run(kind === "dir" ? Terminus.mkdirCommand(root.cwd, name)
                            : Terminus.createCommand(root.cwd, name));
  }

  // yazi's `D`. Not the trash, and worded so the card cannot be mistaken for
  // the one that is recoverable.
  function deleteForever() {
    const rows = root.acting();
    if (rows.length === 0) return;
    confirm.ask(
      "Delete " + rows.length + (rows.length === 1 ? " item" : " items")
        + " permanently?",
      "This does not go to the trash.  "
        + rows.map((r) => r.name).join("   "),
      "Delete", () => {
        root.run(Terminus.deleteCommand(rows.map((r) => r.path)));
        root.act.marked = {};
      });
  }

  function beginSearch(mode) { searchBar.begin(mode); }



  // ── chrome ──────────────────────────────────────────────────────────────
  readonly property int rowH: Math.round(28 * root.zoom)

  // WHEN THE CURSOR IS AN OUTLINE RATHER THAN A BAR, asked by the SelectBar
  // over each list. EntryRow decides this per row as `cursorOnly`; the bar is
  // outside the delegates and has to ask the same question of the pane.
  function cursorOutline(p) {
    if (!p) return true;
    return !p.active || root.markedCount > 0;
  }

  // ── on partial rows at the edges of a listing, and on elastic ───────────
  // Neither is here, both were, and this is why — so the next attempt starts
  // from what was measured rather than from what looks obvious.
  //
  // A pane is whatever height the window is; a row is a fixed rowH. The last
  // row is therefore usually cut, and the tidy-looking fix is to make the rows
  // divide the pane exactly. They cannot: Qt lays delegates out on whole
  // pixels, so a fractional row height is rounded on the way to the screen and
  // the view's own bookkeeping drifts with it. Measured — a directory of 2299
  // rows asked to be 28.606 tall reported a contentHeight of 2330 rows' worth,
  // an average of 29.0, and an originY that wandered by half a row, which ate
  // rows off the top of the listing. Padding the pane down to a whole number
  // of rows instead only trades the clipped row for a strip of dead space.
  //
  // Elastic hit the same wall from the other side: any give displaces the
  // rows, and displacing rows in a viewport that is not an exact number of
  // them tall is that clipping again. It is also unreachable by the obvious
  // route — a WheelHandler declared inside a Flickable never fires at all,
  // because Flickable's default property parents non-Item children to
  // contentItem as a plain QObject — and Qt's own overshoot never runs here
  // either, since the overlay below takes the wheel before the flick engine
  // sees it.
  //
  // Both worked, in the sense of doing what they said. Both cost more in
  // machinery and edge cases than a clipped row at the bottom of a list is
  // worth.

  // Tight. One line of type, so 40 was leaving a band of air under the text
  // once the separator at the bottom was counted as part of the bar.
  readonly property int headH: 34

  Item {
    id: content
    anchors.fill: parent
    focus: true

    // Keys land here, not on the filter field: the field only takes them while
    // it has focus, and it only has focus while you are filtering. That is what
    // buys the bare-letter verbs — y, d, p, n — that a permanently focused
    // field would have swallowed. Zeus had to put its sort on Alt+S for exactly
    // that reason; this window does not have to.
    // Mouse 4 goes UP a directory — the same thing backspace does. Up is where
    // you almost always mean to go, and it is predictable: back depends on the
    // path you took to get here, which you cannot see.
    //
    // There is no mouse 5. There WAS, walking a forward history, and it could
    // never do anything: forward is only ever filled by going back, going back
    // was what mouse 4 gave up to go up instead, so the stack was empty for the
    // life of the window while every navigation still pushed a path onto its
    // twin. The button is gone and so are both stacks.
    //
    // On the whole surface rather than a row: which directory you are in is
    // about the window, not about whatever the pointer happens to be over, and
    // over an empty listing there is no row to be over.
    MouseArea {
      anchors.fill: parent
      // ── THE SIDE BUTTONS ARE THE TRAIL, NOT THE TREE ─────────────────
      // Back used to go UP a directory, which is the other axis entirely: up
      // is the parent, back is where you were. With a history to walk they do
      // what the same two buttons do in every browser, and `h` is still there
      // for the parent.
      acceptedButtons: Qt.BackButton | Qt.ForwardButton
      onPressed: (m) => {
        if (m.button === Qt.BackButton) root.back();
        else if (m.button === Qt.ForwardButton) root.forward();
      }
    }

    // ── the keymap ────────────────────────────────────────────────────
    // Yazi's, because that is the muscle memory this replaces. Including its
    // SEQUENCES: g d, c m, b a and so on are two keystrokes, so a pending
    // prefix has to be held between them, and any key that is not a valid
    // continuation cancels it rather than doing something else.
    property string pending: ""

    // The sequences, once. The bar along the bottom renders these and the key
    // handler dispatches them, so a destination cannot be listed without
    // working or work without being listed — they were two lists before, which
    // is two chances to disagree.
    readonly property var sequences: ({
      g: [
        ["g", "top",       () => { root.act.sel = 0; root.positionSel(); }],
        ["h", "home",      () => root.goTo(Paths.home())],
        ["c", "config",    () => root.goTo(Paths.configDir())],
        ["d", "downloads", () => root.goTo(Paths.home() + "/Downloads")],
        ["D", "documents", () => root.goTo(Paths.home() + "/Documents")],
        ["p", "pictures",  () => root.goTo(Paths.home() + "/Pictures")],
        ["v", "videos",    () => root.goTo(Paths.home() + "/Videos")],
        ["t", "trash",     () => root.goTo(Paths.home() + "/.local/share/Trash/files")],
        ["b", "bookmarks", () => marks.ask()],
        ["m", "media",     () => root.goTo("/run/media")],
        ["/", "root",      () => root.goTo("/")],
        // THE SAME SHEET THAT SENDS, ASKED TO GO INSTEAD. Picking a place
        // out of a tree you can filter is the same act whether something is
        // travelling with you or not, and it was already built — so this is
        // the picker with its destination handed to goTo rather than to
        // paste, not a second picker that happens to look like it.
        [" ", "go to", () => sendTo.ask("go")]
      ],
      c: [
        ["c", "copy path",     () => { const r = root.currentRow();
                                       if (r) root.copyText(r.path, "path copied"); }],
        ["d", "copy dirname",  () => { const r = root.currentRow();
                                       if (r) root.copyText(Terminus.dirname(r.path), "dirname copied"); }],
        ["f", "copy filename", () => { const r = root.currentRow();
                                       if (r) root.copyText(r.name, "filename copied"); }],
        ["n", "copy name",     () => { const r = root.currentRow();
                                       if (r) root.copyText(Terminus.stem(r.name), "name copied"); }],
        ["m", "permissions",   () => perms.ask()],
        ["a", "archive",       () => root.beginArchive("")]
      ],
      b: [
        ["a", "bookmark here",   () => root.toggleBookmark()],
        // ONE key that goes both ways, on whatever the cursor is on. `b d`
        // used to sit beside `b a` as "remove bookmark" and called exactly the
        // same function — two entries in the hint bar for one toggle, neither
        // of which could act on the row you were looking at. This one does:
        // a directory under the cursor is what you are pointing at, and the
        // glyph beside its name says which way the toggle will go.
        // A FUNCTION rather than a string, because this label is not fixed —
        // see bookmarkVerb. The hint bar calls it if it is callable, so any
        // other entry that wants to describe itself by the state it is in can
        // do the same without a second mechanism.
        ["b", () => root.bookmarkVerb(), () => root.toggleBookmarkHere()]
      ],
      // TAKING AND SENDING ARE THE SAME VERB. `y` is "copy this" and `x` is
      // "move this"; what follows says WHERE — doubled means the clipboard,
      // `s` means pick a destination and send it there without going. Both
      // prefixes are shaped the same way, so knowing one is knowing the
      // other.
      y: [
        ["y", "copy",    () => root.yank("copy")],
        ["s", "copy to", () => sendTo.ask("copy")],
        // Under the copy prefix because that is what it is: a copy whose
        // destination is where you already are.
        ["d", "duplicate", () => root.duplicate()]
      ],
      x: [
        ["x", "cut",     () => root.yank("move")],
        ["s", "move to", () => sendTo.ask("move")]
      ],
      ",": [
        ["u", "disk usage",  () => root.toggleUsage()],
        ["g", "git status",  () => root.toggleGit()],
        ["n", "by name",     () => root.setSort("name")],
        ["s", "by size",     () => root.setSort("size")],
        ["m", "by modified", () => root.setSort("time")],
        ["k", "by kind",     () => root.setSort("kind")],
        ["!", "reverse",     () => root.sortDesc = !root.sortDesc]
      ]
    })

    // No timer. It used to give up after 1200ms, which meant a menu you were
    // still reading closed itself; it now stays until you choose or press
    // escape, and a key that is not one of the choices is ignored rather than
    // taken as a reason to dismiss.
    function seq(prefix) { content.pending = prefix; }
    function done() { content.pending = ""; }

    Keys.onPressed: (event) => {
      // ── while a dialog is up ──────────────────────────────────────
      // It takes the keyboard and the listing behind it gets nothing: acting
      // on a file while a question about that file is still on screen is the
      // one thing this must not do.
      //
      // confirm and prompt hold focus in controls of their own and never
      // reach here — this is the keyboard for the two that had none at all,
      // and Escape for both of them.
      // Dialogs are handled by dialogKeys, which takes the keyboard for as
      // long as one is up — see its own note. Nothing here may act while a
      // question is on screen.
      if (confirm.open || prompt.open || perms.open || props.open
          || appPick.open || sendTo.open) return;

      // ── AND WHILE A NAME IS BEING TYPED IN THE LISTING ────────────
      // An inline rename holds the keyboard in a TextInput ON a row, and a
      // TextInput passes on any key it did not use. Right at the END of the
      // text is exactly that: the caret cannot go further, so the key came up
      // here, moved the cursor to the next row, destroyed the delegate being
      // edited and took the rename down with it — reaching for a file
      // extension aborted the edit.
      //
      // Swallowed rather than returned, so nothing behind acts on it either.
      // Return and Escape never arrive: the field consumes both, to commit and
      // to cancel.
      if (root.renaming) { event.accepted = true; return; }

      if (menu.open) {
        // EVERY key belongs to the menu while it is up — the listing behind
        // it must not act on anything — but they no longer all mean "nothing".
        // The card is navigable from the keyboard now, which is the other half
        // of being able to open it from the keyboard.
        event.accepted = true;
        // the key that opened it closes it
        if (event.key === Qt.Key_Menu) { menu.close(); return; }
        // Escape backs out ONE LEVEL, the way it does everywhere else in this
        // window: out of the submenu first, and only then out of the menu.
        if (event.key === Qt.Key_Escape) {
          if (menu.subSel >= 0) { menu.subSel = -1; menu.subAt = -1; }
          else menu.close();
          return;
        }
        // j/k as well as the arrows, because the listing behind it moves that
        // way and a menu that did not would be the one place it does not.
        if (event.key === Qt.Key_Down || event.text === "j") { menu.move(1); return; }
        if (event.key === Qt.Key_Up || event.text === "k") { menu.move(-1); return; }
        // right steps INTO the children, left comes back out — the same shape
        // as h/l walking the tree in the listing
        if (event.key === Qt.Key_Right || event.text === "l") {
          if (menu.subSel < 0) {
            const it = menu.items[menu.at];
            if (it && it.sub) {
              menu.subAt = menu.at;
              menu.subSel = menu.step(it.sub, -1, 1);
            }
          }
          return;
        }
        if (event.key === Qt.Key_Left || event.text === "h") {
          if (menu.subSel >= 0) { menu.subSel = -1; menu.subAt = -1; }
          return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (menu.subSel >= 0) menu.activateSub();
          else menu.activateAt();
          return;
        }
        return;
      }

      // A portal request outranks everything: an application is blocked on the
      // answer, so return hands it over and escape tells it no.
      //
      // EXCEPT OVER A DIRECTORY YOU HAVE NOT CHOSEN YET. Return used to answer
      // the request no matter what the cursor was on, which made a save dialog
      // impossible to navigate with the keyboard: the one key that means "go
      // in" meant "write it here" instead, so the only way to reach the folder
      // you wanted was to answer in the wrong one and move the file afterwards.
      //
      // A DIRECTORY request is the exception to the exception — there, a
      // directory under the cursor IS the answer, so Return gives it.
      if (root.picking) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          const pr = root.currentRow();
          if (pr && pr.isDir && !root.portal.directory) root.enter(pr.path);
          else root.portalConfirm();
          return;
        }
        if (event.key === Qt.Key_Escape) {
          event.accepted = true; root.portalCancel(); return;
        }
      }

      // F1 AS THE ONE KEY NOBODY HAS TO BE TOLD. ctrl P is the palette's key
      // and ~ is the one this window has always used, and both of them are
      // things you have to already know. F1 is the key a person presses when
      // they have no idea what the keys are, which is exactly the state this
      // list exists for — so it opens it too, and earns its place by being
      // guessable rather than by being fast.
      if (event.key === Qt.Key_F1) {
        event.accepted = true; cmdPalette.ask(); return;
      }

      // ── a pending prefix owns the next key ──────────────────────────
      if (content.pending !== "") {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { content.done(); return; }
        // A bare modifier is a key event of its own with no text, and holding
        // shift to reach an upper-case destination sends one before the letter
        // arrives. Treating that as "not a choice, so dismiss" is what made
        // `g` then shift-D impossible: the menu was gone before the D landed.
        if (event.text === "") return;
        const list = content.sequences[content.pending] || [];
        for (const entry of list) {
          if (entry[0] === event.text) {
            content.done();
            entry[2]();
            return;
          }
        }
        // not one of the choices: leave the menu up rather than closing on a
        // stray keystroke
        return;
      }

      // ── escape, in the order things unwind ──────────────────────────
      // Escape unwinds what you are in the middle of, and stops there. It does
      // NOT close the window: a file manager you are browsing should not
      // vanish because you dismissed a filter twice. `q` quits, the way it
      // does in yazi, and a PICKER still cancels on escape — an application is
      // blocked on that answer, so escape means "no" and is handled above.
      if (event.key === Qt.Key_Escape) {
        event.accepted = true;
        if (root.searchMode !== "") root.clearSearch();
        else if (root.query !== "") { filterField.text = ""; root.act.query = ""; }
        else if (root.visualOn) root.endVisual();
        else if (Object.keys(root.marked).length > 0) root.act.marked = {};
        return;
      }

      // ── the two dividers, from the keyboard ─────────────────────────
      // Alt walks the split, alt+shift walks the sidebar's edge — one hand
      // shape for both lines, and the ARROW POINTS THE WAY THE LINE TRAVELS
      // rather than at whichever pane grows. Which pane grows depends on which
      // side of the divider you are asking about; the divider itself only ever
      // goes left or right, so that is what the key says.
      //
      // BEFORE the movement block below, which takes a bare Left and Right and
      // never looks at the modifiers — so with alt held they meant "up a
      // directory" and "open the file", neither of which is a thing to do by
      // accident while reaching for a resize.
      //
      // Both consume the key even when there is nothing to resize. A binding
      // that quietly turns into a different verb whenever the sidebar happens
      // to be closed is worse than one that does nothing.
      if ((event.modifiers & Qt.AltModifier)
          && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
        event.accepted = true;
        const grow = event.key === Qt.Key_Right ? 1 : -1;
        if (event.modifiers & Qt.ShiftModifier) {
          // PIXELS, because that is what the sidebar is measured in — it is a
          // column of fixed things rather than a share of the window, which is
          // the whole reason sidebarWidth is not a fraction. Clamped to the
          // same bounds the grip drags between, and onSidebarWidthChanged
          // writes it to disk without being asked.
          if (root.sidebar)
            root.sidebarWidth = Math.max(root.sidebarMin,
              Math.min(root.sidebarMax, root.sidebarWidth + grow * 20));
        } else if (root.dual) {
          // A FRACTION, because the split is one — see paneFrac. Stepping in
          // pixels would drift the proportion every time the window resized,
          // which is the thing paneFrac exists to prevent. 2% lands where you
          // meant without making the trip across the pane a drum roll.
          root.paneFrac = Math.max(root.paneMinFrac,
            Math.min(root.paneMaxFrac, root.paneFrac + grow * 0.02));
          viewSave.restart();
        }
        return;
      }

      // ── movement ────────────────────────────────────────────────────
      // The GRID IS TWO-DIMENSIONAL, and it has to be asked first.
      //
      // This block used to sit below the plain up/down handlers, which meant
      // it could never run for them: they matched, moved by one tile, and
      // returned. So the grid navigated in a straight line through a layout
      // that is laid out in rows — down moved you one tile sideways instead of
      // one row down. Left and right reached here only because nothing above
      // claimed them.
      //
      // The letters are not in this block at all: h and l are back and
      // forward in every layout now, so there is no case where they need a
      // second meaning, and only the arrows have two axes to worry about.
      if (root.viewMode === "grid") {
        if (event.key === Qt.Key_Left) {
          event.accepted = true; root.moveSel(-1); return;
        }
        if (event.key === Qt.Key_Right) {
          event.accepted = true; root.moveSel(1); return;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          event.accepted = true; root.moveSel(-root.gridCols()); return;
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          event.accepted = true; root.moveSel(root.gridCols()); return;
        }
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
        event.accepted = true; root.moveSel(-1); return;
      }
      if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
        event.accepted = true; root.moveSel(1); return;
      }
      // ── THE LETTERS ARE THE TRAIL, THE ARROWS ARE THE TREE ──────────
      // These were yazi's pair for a long time — h up, H back, one the tree
      // and the other the trail.
      //
      // WHAT SHIFT IS FOR. g and G are top and bottom: two ends of ONE axis,
      // and the case is which end. h and H were not that — going up a
      // directory and going back through the trail are two different verbs
      // that happen to start with the same letter, so the capital promised a
      // relationship that is not there and read as "up, but more". Back and
      // forward are their own pair and take their own lowercase keys.
      //
      // BY TEXT, not by key: Key_H is the same code with shift or without, so
      // matching on the key would take H and L as well. Nothing claims the
      // capitals any more.
      //
      // Parent and enter keep the arrows, which is where they were always
      // written down beside the letters anyway — see the keymap's move group.
      // ── THE LETTERS ARE THE TRAIL, THE ARROWS ARE THE TREE ──────────
      // BY TEXT, not by key: Key_H is the same code with shift or without, so
      // matching on the key would take H and L as well.
      //
      // AND THE ARROWS ARE NOT IN IT. They were briefly, on the reasoning that
      // one axis should mean one thing whichever key you reach for — and that
      // is the wrong axis. Left and right are where you ARE, a step out of a
      // folder and a step into the one under the cursor; back and forward are
      // where you have BEEN. Hovering .claude and pressing right has to open
      // .claude, not jump to wherever you were before.
      if (event.text === "h") { event.accepted = true; root.back(); return; }
      if (event.text === "l") { event.accepted = true; root.forward(); return; }
      if (event.key === Qt.Key_Left) {
        event.accepted = true; root.goUp(); return;
      }
      // Alt+Return opens the properties of what is selected. It has to be
      // tested BEFORE the plain Return below, which takes any Return at all
      // and opens the file — modifiers and all.
      if ((event.modifiers & Qt.AltModifier)
          && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        event.accepted = true; props.ask(); return;
      }
      // SHIFT+RETURN IS THE OTHER WAY TO OPEN IT. Before the plain Return
      // below, which takes any Return at all and opens the row in place,
      // modifiers and all.
      //
      // ON A DIRECTORY, in a tab of its own — the keyboard's version of the
      // middle click that already does it. ON A FILE, the open-with sheet:
      // plain Return hands it to whatever owns that kind of file, and the
      // shifted one is where you say which. It used to open the same way
      // Return does, which made the modifier mean nothing over half the rows
      // in the window.
      if ((event.modifiers & Qt.ShiftModifier)
          && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        event.accepted = true;
        const r = root.currentRow();
        if (r && r.isDir) root.openInNewTab(r.path);
        else if (r) root.beginOpenWith(r.path);
        return;
      }
      // RETURN OPENS. Whatever is under the cursor, file or directory — it is
      // the key that means "do the thing", and over a file the thing is to
      // open it in whatever owns that kind of file.
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true; root.activate(); return;
      }
      // RIGHT WALKS THE TREE, and only that. It is the other half of left,
      // which goes up; a key whose whole meaning is "go deeper" should not
      // also be able to launch a PDF in a reader. Over a file it does nothing
      // rather than something surprising, and Return is a key away.
      //
      // In grid the arrow has already moved the cursor sideways above — this
      // is the list and the columns, where there is no second axis for it.
      if (event.key === Qt.Key_Right) {
        event.accepted = true;
        const rr = root.currentRow();
        if (rr && rr.isDir) root.activate();
        return;
      }
      if (event.key === Qt.Key_G) {
        event.accepted = true;
        if (event.modifiers & Qt.ShiftModifier) {
          root.act.sel = Math.max(0, root.view.length - 1);
          root.positionSel();
        } else content.seq("g");
        return;
      }
      if (event.modifiers & Qt.ControlModifier) {
        // Tab cycling and closing, where a browser puts them. Backtab is what
        // Qt reports for ctrl+shift+tab — shift turns the key itself into a
        // different one rather than only appearing in the modifiers.
        if (event.key === Qt.Key_Tab) {
          event.accepted = true;
          root.switchTab((root.tab + 1) % root.tabs.length);
          return;
        }
        if (event.key === Qt.Key_Backtab) {
          event.accepted = true;
          root.switchTab((root.tab - 1 + root.tabs.length) % root.tabs.length);
          return;
        }
        if (event.key === Qt.Key_P) { event.accepted = true; cmdPalette.ask(); return; }
        if (event.key === Qt.Key_C) { event.accepted = true; root.closeTab(); return; }
        if (event.key === Qt.Key_U) { event.accepted = true; root.moveSel(-8); return; }
        if (event.key === Qt.Key_D) { event.accepted = true; root.moveSel(8); return; }
        if (event.key === Qt.Key_B) { event.accepted = true; root.moveSel(-16); return; }
        if (event.key === Qt.Key_F) { event.accepted = true; root.moveSel(16); return; }
        if (event.key === Qt.Key_A) { event.accepted = true; root.selectAll(); return; }
        if (event.key === Qt.Key_R) { event.accepted = true; root.invertSelection(); return; }
        if (event.key === Qt.Key_S) { event.accepted = true; root.openShell(); return; }
        if (event.key === Qt.Key_0) { event.accepted = true; root.zoomReset(); return; }
        // ctrl +/- as well as the bare keys: in the grid these are thumbnail
        // size, and ctrl is where every application puts that
        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          event.accepted = true; root.zoomBy(0.1); return;
        }
        if (event.key === Qt.Key_Minus) {
          event.accepted = true; root.zoomBy(-0.1); return;
        }
      }
      if (event.key === Qt.Key_PageUp)   { event.accepted = true; root.moveSel(-16); return; }
      if (event.key === Qt.Key_PageDown) { event.accepted = true; root.moveSel(16); return; }
      // The Menu (Application) key. No text of its own, so it belongs up here
      // with the named keys rather than in the switch below.
      if (event.key === Qt.Key_Menu)     { event.accepted = true; root.openMenuAtCursor(); return; }
      if (event.key === Qt.Key_Home)     { event.accepted = true; root.act.sel = 0; root.positionSel(); return; }
      if (event.key === Qt.Key_End) {
        event.accepted = true;
        root.act.sel = Math.max(0, root.view.length - 1);
        root.positionSel();
        return;
      }
      if (event.key === Qt.Key_Backspace) { event.accepted = true; root.goUp(); return; }
      // Tab crosses to the other pane, and only when there is one — with a
      // single pane it is left alone rather than bound to something else.
      // TAB REACHES THE NAME FIELD in a save dialog. The keyboard starts in
      // the listing now, because WHERE is the question you are there to
      // answer — but the name still has to be reachable without the mouse,
      // and Tab is the key that moves between the halves of a form. A picker
      // has one pane, so the step-over below is inert in it anyway.
      if (event.key === Qt.Key_Tab && root.picking
          && root.portal.save) {
        event.accepted = true;
        saveField.forceActiveFocus();
        saveField.selectAll();
        return;
      }
      if (event.key === Qt.Key_Tab && root.dual) {
        event.accepted = true; root.stepOver(); return;
      }
      // F5 and F6, where every dual-pane file manager has kept them since the
      // eighties. Inert with one pane rather than bound to something else,
      // because a key that means "to the other side" should not quietly mean
      // something different when there is no other side.
      if (event.key === Qt.Key_F5) { event.accepted = true; root.sendToOther("copy"); return; }
      if (event.key === Qt.Key_F6) { event.accepted = true; root.sendToOther("move"); return; }

      // ── zoom, on the keys everything else uses ──────────────────────
      if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
        event.accepted = true; root.zoomBy(0.1); return;
      }
      if (event.key === Qt.Key_Minus) {
        event.accepted = true; root.zoomBy(-0.1); return;
      }

      // ── tabs ────────────────────────────────────────────────────────
      if ((event.modifiers & Qt.AltModifier)
          && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
        event.accepted = true; root.switchTab(event.key - Qt.Key_1); return;
      }
      if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.text !== "") {
        event.accepted = true; root.switchTab(event.key - Qt.Key_1); return;
      }
      if (event.key === Qt.Key_BracketLeft) {
        event.accepted = true;
        root.switchTab((root.tab - 1 + root.tabs.length) % root.tabs.length);
        return;
      }
      if (event.key === Qt.Key_BracketRight) {
        event.accepted = true;
        root.switchTab((root.tab + 1) % root.tabs.length);
        return;
      }

      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;

      // ── everything else, by character so shift is a different key ───
      switch (event.text) {
      case " ":  event.accepted = true; root.toggleMark(); root.moveSel(1); break;
      case "y":  event.accepted = true; content.seq("y"); break;
      case "x":  event.accepted = true; content.seq("x"); break;
      case "p":  event.accepted = true; root.paste(); break;
      case "d":  event.accepted = true; root.trash(); break;
      case "D":  event.accepted = true; root.deleteForever(); break;
      case "a":  event.accepted = true; root.beginCreate(); break;
      // ONE KEY, and it does what the selection says. `r` on a row opens that
      // row's name; `r` on nine rows opens the card that renames nine. Having
      // it mean "rename the row under the cursor" while nine were ticked was
      // the one verb in this window that ignored the selection every other
      // verb acts on.
      case "r":
        event.accepted = true;
        if (root.acting().length > 1) root.beginBulkRename();
        else root.beginRename();
        break;
      case ".":  event.accepted = true; root.showHidden = !root.showHidden; break;
      case ";":  event.accepted = true; root.openShell(); break;
      case "f":  event.accepted = true; filterField.forceActiveFocus(); break;
      case "/":  event.accepted = true; filterField.forceActiveFocus(); break;
      case "s":  event.accepted = true; root.beginSearch("find"); break;
      case "S":  event.accepted = true; root.beginSearch("grep"); break;
      case "t":  event.accepted = true; root.newTab(); break;
      case "w":  event.accepted = true; root.closeTab(); break;
      case "v":  event.accepted = true; root.toggleVisual(); break;
      case "V":  event.accepted = true; root.cycleView(); break;
      case "u":  event.accepted = true; root.undo(); break;
      case "z":  event.accepted = true; root.measureDirs(); break;
      case "\\": event.accepted = true; root.toggleDual(); break;
      // The SAME KEY WITH SHIFT, because it is the same gesture about the
      // other vertical division of the window: `\` splits the body in two,
      // `|` puts the places column back beside it. onSidebarChanged writes
      // the new state to disk without being asked.
      case "|":  event.accepted = true; root.sidebar = !root.sidebar; break;
      case "i":  event.accepted = true; root.quickLook(); break;
      case "o":  event.accepted = true; root.stepOver(); break;
      case "q":
        event.accepted = true;
        // A DIALOG ANSWERS RATHER THAN CLOSING. Something is blocked waiting
        // on this window, so walking away from it has to say "no" — and it
        // took the branch below instead, which asks retire() to drop a window
        // that was never in `wins`. That did nothing at all: the dialog stayed
        // open with its request still pending, and the manager went on
        // believing it had a live picker.
        if (root.picking) { root.portalCancel(); break; }
        // the first window hides; a spare one goes away, because a pile of
        // hidden windows nobody can reach is a leak with a keybind
        if (root.winId === 0 || !root.mgr) root.shown = false;
        else root.mgr.retire(root.winId);
        break;
      case "N":
        event.accepted = true;
        if (root.mgr) root.mgr.spawn(root.cwd);
        break;
      case "~":  event.accepted = true; cmdPalette.ask(); break;
      case "g":  event.accepted = true; content.seq("g"); break;
      case "c":  event.accepted = true; content.seq("c"); break;
      case "b":  event.accepted = true; content.seq("b"); break;
      case ",":  event.accepted = true; content.seq(","); break;
      }
    }

    Column {
      id: chrome
      anchors.fill: parent

      // ── tabs ──────────────────────────────────────────────────────
      // Hidden while there is one, because a single tab is just the window and
      // a strip saying so is a strip of nothing.
      Rectangle {
        id: tabStrip
        width: parent.width
        // the path bar's height, so the two strips stack as one band of chrome
        // rather than two of slightly different depths
        height: (root.alwaysTabs || root.tabs.length > 1) ? root.headH : 0
        visible: height > 0
        clip: true
        // The path bar's own colour. Leaving the strip transparent removed the
        // 1px separator but not the LINE: the transparent strip showed the
        // window's ground (layerBg) while the bar below was headBg, and two
        // different colours meeting across the full width is a line whether or
        // not anyone drew one. With the strip painted the same as the bar, the
        // active tab is simply the strip showing through and the boundary
        // disappears; the inactive ones darken instead.
        //
        // And it goes black with the path bar under it while a sheet is open,
        // or the band above the sheet would be grey on top of black.
        color: root.chromeBg

        // ── dragging one along the strip ────────────────────────────
        // Which tab is being carried, and where it would land. -1 for neither,
        // which is nearly always.
        //
        // The ORDER IS NOT TOUCHED UNTIL YOU LET GO. It is tempting to shuffle
        // `root.tabs` as the pointer crosses each boundary, and it does not
        // work: the Repeater's model is a plain array, so replacing it destroys
        // and rebuilds every delegate — including the one under the pointer,
        // mid-gesture. So the drag moves PIXELS, the other tabs slide into the
        // gap it leaves, and the array is rewritten exactly once, on release,
        // by which time every tab is already sitting where it will end up.
        property int dragFrom: -1
        property int dragTo: -1
        // where the carried tab's left edge is, in strip coordinates
        property real dragX: 0

        function endDrag() {
          tabStrip.dragFrom = -1;
          tabStrip.dragTo = -1;
        }

        // A tab opened or closed while one is being carried leaves dragFrom
        // pointing into a list that no longer has that shape. Nothing good
        // comes of guessing which tab it used to mean.
        Connections {
          target: root
          function onTabsChanged() { tabStrip.endDrag(); }
        }

        // The strip spans the window and the tabs divide it, the way a browser
        // does it: a tab's position stops moving every time a directory with a
        // longer name is opened in one of them.
        //
        // An Item and not a Row, because a Row positions its children and the
        // whole point here is that one of them follows the pointer while the
        // others animate around it. The arithmetic a Row was doing is one line.
        Item {
          anchors.fill: parent
          anchors.bottomMargin: 1

          Repeater {
            model: root.tabs

            delegate: Rectangle {
              id: tabCell
              required property var modelData
              required property int index
              readonly property bool here: index === root.tab
              readonly property bool lifted: tabStrip.dragFrom === tabCell.index
                && tabStrip.dragFrom < root.tabs.length

              // WHERE THIS TAB SITS WHILE ANOTHER IS BEING CARRIED. Everything
              // between the tab's old place and the pointer's shifts one step
              // the other way, which is what opens the gap the carried tab
              // will drop into.
              readonly property int slot: {
                const f = tabStrip.dragFrom, t = tabStrip.dragTo;
                if (f < 0 || tabCell.index === f) return tabCell.index;
                if (f < t) return (tabCell.index > f && tabCell.index <= t)
                  ? tabCell.index - 1 : tabCell.index;
                return (tabCell.index >= t && tabCell.index < f)
                  ? tabCell.index + 1 : tabCell.index;
              }

              x: tabCell.lifted ? tabStrip.dragX : tabCell.slot * tabCell.width
              // the carried one rides over the rest
              z: tabCell.lifted ? 2 : 0
              // The slide. Switched off for the tab under the pointer: that one
              // is following a finger, and an animation between the finger and
              // the tab is lag with a curve on it.
              Behavior on x {
                enabled: !tabCell.lifted
                NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
              }

              // A new tab grows into place rather than appearing, and the
              // active one lifts a little — the strip is the one part of the
              // chrome that changes while you are looking straight at it.
              opacity: 0
              Component.onCompleted: tabIn.start()
              NumberAnimation {
                id: tabIn
                target: tabCell
                property: "opacity"
                to: 1
                duration: Zenon.normal
                easing.type: Easing.OutCubic
              }
              Behavior on color {
                ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }
              width: tabStrip.width / Math.max(1, root.tabs.length)
              height: parent.height
              // The active tab paints nothing — it is the strip, which is the
              // bar — so it runs into the path bar with no seam at all. The
              // inactive ones are shaded back, which is what separates them.
              //
              // A tab being CARRIED looks exactly like a tab. It was given a
              // ground and a cyan edge while dragging, on the theory that a
              // lifted thing should look lifted; it read as a different tab
              // rather than as the one you had hold of. The movement is the
              // feedback — nothing else is needed to say which one is moving.
              // AND A CARRIED ONE HAS TO BE OPAQUE. The active tab paints
              // nothing on purpose — being the strip is how it joins the bar
              // below without a seam — but a transparent thing cannot be
              // picked up: lifting it moved the label alone, sliding across
              // the tabs it passed over with no body of its own. In hand it
              // takes the strip's own colour, the one it has been showing
              // through all along, and is a solid object for as long as it is
              // moving.
              color: tabCell.lifted ? Zenon.headBg
                : (here ? "transparent" : Qt.rgba(0, 0, 0, 0.28))

              Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                // by the tab's PLACE, not its index — mid-drag those differ,
                // and a separator drawn by index lands inside the gap
                visible: !tabCell.lifted && tabCell.slot < root.tabs.length - 1
                color: Zenon.msgBorder
              }

              Text {
                id: tabLabel
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: Terminus.basename(here ? root.cwd : modelData.cwd)
                // The active crumb's ink. The tab and the last path segment
                // are the same claim made twice — this is where you are — and
                // they were two different greys saying it.
                color: here ? root.crumbInk : Zenon.muted
                font.family: Zenon.face
                // the body's row size, written the same way rather than as a
                // number that happens to match — zoom then moves both together
                font.pixelSize: Math.round(16 * root.zoom)
              }

              HoverHandler { id: tabHov }
              MouseArea {
                id: tabMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                // How far into the tab you took hold of it, so the tab does not
                // jump its own width the moment the drag begins.
                property real grabDx: 0
                property bool dragging: false

                // ── THE STRIP, HELD RATHER THAN LOOKED UP ────────────────
                // A press outlives its delegate: on a config reload the tab
                // is torn down with the button still held, and the release
                // and the cancel are both delivered to what is left of it. By
                // then `tabStrip` cannot be named — a QML id resolves through
                // the component's context and not through JS scope, so once
                // that context is gone the name does not evaluate to null, it
                // fails to evaluate at all. Which is why guarding it did not
                // work: `!tabStrip` threw the error it was testing for, and
                // `typeof tabStrip` threw it too. typeof only forgives a name
                // JS itself has never heard of, and this one is not that.
                //
                // So the reference is taken ONCE, while the context is
                // certainly alive, and read as a plain property afterwards.
                // Reading a property of a half-dead object is allowed; naming
                // a dead id is not.
                property var strip: null
                Component.onCompleted: tabMouse.strip = tabStrip

                // MEASURED IN THE STRIP, never in the tab. `m.x` is relative to
                // this MouseArea, and this MouseArea moves with the tab while
                // the tab follows the pointer — reading the pointer off a thing
                // that the pointer is moving is a feedback loop, and the tab
                // shivers. mapToItem asks the strip instead, which holds still.
                function stripX(m) {
                  return tabCell.mapToItem(tabStrip, m.x, 0).x;
                }

                onPressed: (m) => {
                  if (m.button !== Qt.LeftButton) return;
                  tabMouse.grabDx = tabMouse.stripX(m) - tabCell.x;
                  tabMouse.dragging = false;
                }

                onPositionChanged: (m) => {
                  if (!tabMouse.pressed || root.tabs.length < 2 || root.modal) return;
                  const at = tabMouse.stripX(m);
                  if (!tabMouse.dragging) {
                    // a threshold, so a click that wobbles two pixels is still
                    // a click and still switches tab
                    if (Math.abs(at - tabCell.x - tabMouse.grabDx) < 5) return;
                    tabMouse.dragging = true;
                    tabStrip.dragFrom = tabCell.index;
                    tabStrip.dragTo = tabCell.index;
                  }
                  const w = tabCell.width;
                  tabStrip.dragX = Math.max(0,
                    Math.min(tabStrip.width - w, at - tabMouse.grabDx));
                  // WHERE IT WOULD LAND: the slot its own left edge is nearest,
                  // which is what makes the gap open when the tab is more than
                  // half way past its neighbour rather than the moment it
                  // touches it.
                  tabStrip.dragTo = Math.max(0, Math.min(root.tabs.length - 1,
                    Math.round(tabStrip.dragX / w)));
                }

                // CLEARED WHETHER OR NOT THIS WAS A DRAG. An early return here
                // left `dragFrom` pointing at a tab whose gesture had ended — a
                // press that became a drag and then lost its release froze that
                // tab where it stood, and nothing afterwards put it back.
                onReleased: {
                  const was = tabMouse.dragging;
                  tabMouse.dragging = false;
                  // Through the held reference — see `strip` above. A drag
                  // that died with its component has nothing left to put back.
                  const st = tabMouse.strip;
                  if (!st) return;
                  if (was) root.moveTab(st.dragFrom, st.dragTo);
                  st.endDrag();
                }

                // A grab taken away mid-drag puts everything back rather than
                // committing a move nobody finished asking for.
                onCanceled: {
                  tabMouse.dragging = false;
                  // Through the held reference like the release above: a
                  // cancel is exactly what a torn-down delegate delivers.
                  if (tabMouse.strip) tabMouse.strip.endDrag();
                }

                onClicked: (m) => {
                  // a gesture that became a drag is not also a click — the same
                  // rule the listing's rows follow
                  if (tabMouse.dragging) return;
                  if (m.button === Qt.MiddleButton) {
                    // DEFERRED, because this handler is about to lose the
                    // ground it is standing on: closing a tab replaces
                    // `root.tabs`, which is this Repeater's model, so the
                    // delegate running this very line is destroyed inside the
                    // call and everything after it throws instead of running.
                    // Handing root an index and letting it do the work in its
                    // own scope — which nothing here can tear down — is the
                    // whole of the fix.
                    Qt.callLater(root.closeTabAt, tabCell.index);
                    return;
                  }
                  root.switchTab(tabCell.index);
                }
              }
            }
          }
        }

      }

      // ── the crumbs ────────────────────────────────────────────────
      Rectangle {
        id: crumbBar
        width: parent.width
        height: root.headH
        // BLACK WHILE THE SHEET IS UP. The send-to header is drawn on this
        // same strip, and the bar's translucent grey let the column behind it
        // read straight through a header that is answering a question — so
        // the strip goes solid for as long as the sheet is, and comes back
        // with it — see root.chromeBg, which the tab strip above wears too.
        color: root.chromeBg

        // HOW MUCH OF THE BAR'S OWN CONTENT IS SHOWING. The send-to header is
        // drawn on this bar (see sendToBarHead) and the two cannot share the
        // room, so everything that belongs to the path steps aside while the
        // sheet is up and comes back as it leaves. One number, because these
        // are half a dozen siblings rather than one container — crumbInner is
        // a geometry helper with nothing inside it, which is what made the
        // first attempt at this fade nothing at all.
        readonly property real chromeInk: 1 - root.sheetInk

        // AND THE PATH'S OWN SHARE OF IT. The trail stands down for the
        // send-to header like the rest of the chrome, and ALSO for the search
        // bar — which is anchored to the very same span, between the sidebar
        // toggle and the filter. With no rule of its own the trail was drawn
        // straight through the search field, two strings of text in one strip.
        readonly property real trailInk:
          crumbBar.chromeInk * (searchBar.open ? 0 : 1)

        // ── THE INSIDE OF THE BAR, WHICH IS NOT THE WHOLE OF IT ──────
        // The last pixel of this strip is the hairline along its bottom edge.
        // Everything on the bar used to be centred across the whole 34,
        // hairline included, and then nudged a pixel DOWN to compensate — the
        // note on crumbStatus says "up by the separator's own pixel", which is
        // what was meant and the opposite of what +1 does. Between the two,
        // every label on this bar sat a pixel and a half low.
        //
        // So the inside is named once, here, and everything is placed against
        // it: one answer to "where is the middle", and a divider that stands
        // the full height now starts on the bar's top edge and stops exactly
        // where the hairline starts instead of running under it.
        Item {
          id: crumbInner
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1
        }

        // the sidebar's switch, where the path begins — it is about what is to
        // the LEFT of the path, so it sits to the left of it
        Item {
          id: sideToggle
          opacity: crumbBar.chromeInk
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: crumbInner.verticalCenter
          width: 34
          height: crumbInner.height

          Text {
            anchors.centerIn: parent
            // Written as an escape, not as the character. Every literal nerd
            // glyph in this batch arrived empty — they do not survive the trip
            // through a shell heredoc — and an empty string renders as nothing
            // at all, which is exactly what the toggle did.
            text: "\uEC02"
            color: root.sidebar ? Zenon.cyan
              : (sideHov.hovered ? Zenon.white : Zenon.muted)
            font.family: Zenon.face
            font.pixelSize: 18
          }

          HoverHandler { id: sideHov }
          MouseArea {
            anchors.fill: parent
            onClicked: root.sidebar = !root.sidebar
          }
        }

        // ── the trail, as something that SCROLLS rather than gets cut ──
        // A path deeper than the bar is wide used to simply run off the
        // right-hand edge, and what went over the edge was the LAST step —
        // the directory you are actually standing in, and the one part of the
        // trail you cannot work out from the rest.
        Flickable {
          id: crumbFlick
          opacity: crumbBar.trailInk
          // Gone rather than merely transparent: an item at zero opacity
          // still takes the wheel and still lays out, and the search bar
          // needs both.
          visible: crumbBar.trailInk > 0.01
          anchors.left: sideToggle.right
          // Clear of the toggle rather than touching it. The glyph is a
          // control and the trail is text; at 4px the first step read as a
          // label ON the button instead of the beginning of a path.
          anchors.leftMargin: 12
          anchors.right: filterInline.left
          anchors.rightMargin: 12
          anchors.verticalCenter: crumbInner.verticalCenter
          height: crumbInner.height
          clip: true
          contentWidth: crumbTrail.width
          contentHeight: crumbFlick.height
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds

          // ── the trail does not END at the edge, it FADES there ────────
          // An ellipsis is a character: it has to be read, recognised as not
          // being part of any directory's name, and then discounted. A fade
          // says "there is more this way" without asking for a word.
          //
          // AN OPACITY MASK, not a wash of colour over the top. The obvious
          // trick — a rectangle ramping from the bar's own colour to
          // transparent — cannot work here, and it took a screenshot to see
          // why: headBg is #66282f36, four tenths opaque, so painting it over
          // the crumbs veils them by four tenths and stops. What is actually
          // behind this bar is the wallpaper, and there is no colour this
          // window can paint that matches that. So the pixels lose their own
          // alpha towards the edge instead, and it reads the same whatever
          // happens to be behind them.
          //
          // The layer is only enabled while there is something to fade: an
          // always-on layer would put the bar through an offscreen texture for
          // the whole session to buy an effect that only appears when the path
          // outgrows the bar.
          layer.enabled: crumbFlick.maxX > 0
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: crumbMask
            // The threshold is where the mask's alpha starts cutting and the
            // spread is how softly it does it. Both default to zero, which
            // means "cut nothing" — the mask was being read correctly and
            // changing precisely nothing. Half and full is the soft-edge
            // recipe: the ramp in the mask becomes a ramp in the alpha.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          readonly property bool overLeft: crumbFlick.contentX > 1
          readonly property bool overRight: crumbFlick.contentX < crumbFlick.maxX - 1
          // 64px of ramp, as a fraction, and never more than a third of the
          // bar — on a narrow pane a fixed 36 would be most of the trail.
          readonly property real fadeAt: crumbFlick.width > 0
            ? Math.min(0.33, 64 / crumbFlick.width) : 0

          // The WHEEL drives this; a drag does not. Every crumb is a click
          // target, and a Flickable that takes drags turns a slightly unsteady
          // click into a scroll instead of a step up the tree.
          interactive: false

          readonly property real maxX: Math.max(0, contentWidth - width)
          // A CHUNK, not a step. One crumb a notch means spinning the wheel
          // six times to get back to the root of a deep path, which is not
          // scrolling, it is winding. Most of the bar per notch covers the
          // trail in a couple of strokes and still leaves enough of the old
          // view on screen to keep your bearings.
          readonly property real chunk: Math.max(120, crumbFlick.width * 0.6)

          // PINNED TO THE END, so the step that falls off is the one nearest
          // the root — the part you can most afford to lose sight of, and the
          // part the wheel is there to bring back.
          function pinEnd() {
            crumbAnim.stop();
            crumbFlick.contentX = crumbFlick.maxX;
          }
          // The trail is rebuilt whenever the path changes, so this fires then
          // and not while you are reading it: scrolling back and standing
          // still does not yank you forward again.
          onContentWidthChanged: Qt.callLater(crumbFlick.pinEnd)
          onWidthChanged: Qt.callLater(crumbFlick.pinEnd)

          // Consecutive notches accumulate from where the animation is GOING,
          // for the reason wheelScroll spells out over the listing.
          function wheelBy(delta) {
            const from = crumbAnim.running ? crumbAnim.to : crumbFlick.contentX;
            const to = Math.max(0, Math.min(crumbFlick.maxX, from + delta));
            if (to === crumbFlick.contentX && !crumbAnim.running) return;
            crumbAnim.stop();
            crumbAnim.to = to;
            crumbAnim.start();
          }

        Row {
          id: crumbTrail
          height: crumbFlick.height
          spacing: 0

          Repeater {
            model: root.crumbList

            delegate: Row {
              id: crumbRow
              required property var modelData
              required property int index

              // FULL HEIGHT, and that is what levels the trail with the rest of
              // the bar. A Row lays its children out along x and leaves y alone,
              // so a delegate that sized itself to its label sat at the very top
              // of the strip with every other thing on the bar centred beside it
              // — measured at five pixels of air above the crumbs and eighteen
              // below. Standing the delegate the full height of the bar gives
              // the labels inside it a parent worth centring against, and it is
              // what lets the separator below be a rule rather than a character.
              height: crumbFlick.height

              // NO ENTRANCE. Each step used to fade and slide in as it was
              // created, which was written for the case of one step being
              // added to the end of the trail. The Repeater's model is the
              // whole path, so a path change destroys and rebuilds EVERY step,
              // and all of them ran it at once — the entire trail blinking on
              // each navigation. That is not movement, it is a flicker, and at
              // 140ms it is over before it reads as anything.
              //
              // What the trail actually does now is travel: the miller columns
              // slide and the trail simply is what it is when they arrive.

              // ── the separator ────────────────────────────────────────
              // A plain slash, which is what a path is written with. It was a
              // chevron, then a hairline, then a leaned rule cut to the bar's
              // exact height — and the leaned one was the wrong kind of exact:
              // a rule has ends, and ends have to be reasoned about every time
              // the bar's height or its border changes. A character has none of
              // that. It sits on the same baseline as the names either side of
              // it and moves with them.
              //
              // msgBorder, the hairline colour, so the separator stays chrome
              // and does not compete with the steps it is separating.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                // NONE AFTER THE FILESYSTEM ROOT, which is already a slash —
                // "/" then "home" reads as "/home" and a separator between
                // them would double it. Everything else gets one, `~`
                // included, which is why this asks what came BEFORE rather
                // than counting from the start.
                visible: index > 0 && root.crumbList[index - 1].path !== "/"
                text: " / "
                color: Zenon.msgBorder
                font.family: Zenon.face
                font.pixelSize: 15
              }

              Text {
                id: crumbLabel
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                // The last crumb is where you are; the rest are somewhere to
                // go. They stay muted under the pointer: a path is something
                // you READ, and lighting a segment up as the cursor crosses it
                // makes the whole bar twitch on the way to somewhere else.
                // They are still clickable — see below.
                color: index === root.crumbList.length - 1
                  ? root.crumbInk : Zenon.muted
                font.family: Zenon.face
                font.weight: Font.Medium
                font.pixelSize: 15

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.goTo(modelData.path)
                }
              }
            }
          }

          // ── what you are looking FOR, beside where you are looking ──────
          // The bar answers "where am I". During a search that is only half
          // the answer, and the other half was written in the search strip —
          // which closes the moment you press Return. So the results were a
          // directory of files from all over the tree with nothing on screen
          // saying what they had in common.
          //
          // It sits at the end of the path because that is what it qualifies:
          // this directory, these matches. The mode word stays over on the
          // right where it already was; repeating it here would be two labels
          // for one fact.
          Item {
            width: root.searchMode !== "" ? 10 : 0
            height: 1
          }

          Rectangle {
            id: searchChip
            anchors.verticalCenter: parent.verticalCenter
            visible: root.searchMode !== ""
            width: visible ? chipText.implicitWidth + 18 : 0
            height: 21
            radius: 5
            color: Qt.rgba(Zenon.sand.r, Zenon.sand.g, Zenon.sand.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(Zenon.sand.r, Zenon.sand.g, Zenon.sand.b, 0.32)

            Text {
              id: chipText
              anchors.centerIn: parent
              // the magnifier the search bar uses, so the two read as the same
              // thing seen twice rather than two different features
              text: "\uF002  " + root.searchQuery
              color: Zenon.sand
              font.family: Zenon.face
              font.pixelSize: 13
            }
          }
        }
        }

        // The ramp the trail is cut with: opaque through the middle, falling to
        // nothing at whichever end still has trail beyond it, so the fade
        // appears on the side there is more to see and only there.
        //
        // A REAL CHILD OF THE BAR, and that is the whole trick. Written inline
        // as the value of maskSource it never renders: a ShaderEffectSource
        // that is only referenced from a property is not in the scene, so its
        // texture comes back empty — and an empty mask does not mean "no mask",
        // it means every pixel has zero alpha, which took the entire trail with
        // it. hideSource keeps the gradient itself off the bar while it goes on
        // being rendered into the texture, which is exactly what it is for.
        Rectangle {
          id: crumbRamp
          width: Math.max(1, crumbFlick.width)
          height: Math.max(1, crumbFlick.height)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0
              color: crumbFlick.overLeft ? "#00000000" : "#ff000000" }
            GradientStop { position: crumbFlick.fadeAt; color: "#ff000000" }
            GradientStop { position: 1.0 - crumbFlick.fadeAt; color: "#ff000000" }
            GradientStop { position: 1.0
              color: crumbFlick.overRight ? "#00000000" : "#ff000000" }
          }
        }

        ShaderEffectSource {
          id: crumbMask
          width: crumbRamp.width
          height: crumbRamp.height
          sourceItem: crumbRamp
          hideSource: true
          visible: false
        }

        NumberAnimation {
          id: crumbAnim
          target: crumbFlick
          property: "contentX"
          duration: 130
          easing.type: Easing.OutCubic
        }

        // A MouseArea and NoButton, for both reasons the body's wheel overlay
        // gives: a WheelHandler is never offered these events, and a handler
        // that cannot take a press cannot come between a crumb and its click.
        MouseArea {
          anchors.fill: crumbFlick
          // Anchored to the trail but not inside it, so it outlives the
          // trail's own `visible` and would go on eating the wheel over a
          // search bar that wants it.
          enabled: crumbFlick.visible
          acceptedButtons: Qt.NoButton
          onWheel: (w) => {
            if (crumbFlick.maxX <= 0) { w.accepted = false; return; }
            // A horizontal wheel, or a trackpad's sideways swipe, says the
            // same thing as a vertical one here — there is only one axis to
            // travel — so either is taken and whichever moved is used.
            const d = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
            const notches = d / 120;
            if (notches === 0) { w.accepted = false; return; }
            w.accepted = true;
            crumbFlick.wheelBy(-notches * crumbFlick.chunk);
          }
        }

        // ── the search bar, IN PLACE OF THE BREADCRUMBS ───────────────
        // A STRIP, not a dialog. Searching is not a question with one answer to
        // give and then be done with — you type, you look, you narrow, you look
        // again — and a modal card over the listing hid the thing being searched
        // while asking about it.
        //
        // It used to be a strip of its OWN beneath the breadcrumbs, which pushed
        // the whole window down by a bar's height every time it opened and
        // pulled it back up when it closed. Two bars stacked is also two answers
        // to "where am I": the trail naming the directory, and the search naming
        // the same directory directly under it.
        //
        // So it takes the TRAIL'S place and nothing else's. The sidebar toggle
        // stays, the counts and the view name stay, and the one thing replaced
        // is the one thing the search is about to change the meaning of.
        Rectangle {
          id: searchBar
          anchors.left: sideToggle.right
          anchors.leftMargin: 12
          anchors.right: filterInline.left
          anchors.rightMargin: 12
          anchors.verticalCenter: crumbInner.verticalCenter
          height: crumbInner.height
          visible: searchBar.open
          clip: true
          // IN the bar rather than on top of it: the strip already has a colour
          // and painting a second one over it reads as a panel.
          color: "transparent"

          property bool open: false
          property string mode: "find"

          function begin(mode) {
            searchBar.mode = mode;
            searchBar.open = true;
            searchField.text = root.searchQuery;
            searchField.selectAll();
            searchField.forceActiveFocus();
          }

          function dismiss() {
            searchBar.open = false;
            content.forceActiveFocus();
          }

          function run() {
            const q = searchField.text.trim();
            if (q === "") { searchBar.dismiss(); return; }
            root.search(searchBar.mode, q);
            searchBar.dismiss();
          }

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            text: searchBar.mode === "grep" ? "\uF002" : "\uF002"
            color: Zenon.sand
            font.family: Zenon.face
            font.pixelSize: 15
          }

          // Which of the two searches this is, and where. `s` walks names and
          // `S` reads contents; they take the same field and produce very
          // different answers, so the bar says which one is armed.
          Text {
            id: searchLabel
            anchors.left: searchGlyph.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: (searchBar.mode === "grep" ? "contents" : "names") + " in"
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 14
          }

          Text {
            id: searchWhere
            anchors.left: searchLabel.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Terminus.basename(root.cwd) || "/"
            color: Zenon.keyInk
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 14
          }

          TextInput {
            id: searchField
            anchors.left: searchWhere.right
            anchors.leftMargin: 14
            anchors.right: searchKeys.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Zenon.white
            selectionColor: Zenon.selBg
            selectedTextColor: Zenon.white
            font.family: Zenon.face
            font.pixelSize: 16
            clip: true

            Keys.onReturnPressed: (e) => { e.accepted = true; searchBar.run(); }
            Keys.onEnterPressed: (e) => { e.accepted = true; searchBar.run(); }
            Keys.onEscapePressed: (e) => { e.accepted = true; searchBar.dismiss(); }
            // Tab flips between the two searches without retyping the query,
            // which is most of what the second one is for.
            Keys.onPressed: (e) => {
              if (e.key !== Qt.Key_Tab) return;
              e.accepted = true;
              searchBar.mode = searchBar.mode === "grep" ? "find" : "grep";
            }

            // ONE cursor, and the field's own.
            //
            // There were two: a hand-drawn bar placed at contentWidth, and
            // TextInput's built-in caret underneath it in the text colour. Two
            // cursors is one too many, and the drawn one was in the wrong place
            // the moment you moved the caret into the middle of a word — it
            // measures the whole string, not the position.
            //
            // A cursorDelegate REPLACES the built-in one, so there is exactly
            // one and the field itself decides where it goes. It breathes rather
            // than blinking: a hard on/off in a bar that is already asking for
            // your attention reads as a fault.
            cursorDelegate: Rectangle {
              width: 2
              color: Zenon.cyan
              SequentialAnimation on opacity {
                running: searchField.activeFocus
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
              }
            }
          }

          Text {
            id: searchHint
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            visible: false
          }

          // ── the same chips the keymap wears ─────────────────────────
          // This was one grey sentence in msgBorder — a HAIRLINE colour, three
          // tenths opaque, which is right for a line and far too quiet for
          // something you are meant to read. A key drawn as a key is legible at
          // that size in a way a word never is, and it matches what F1 shows for
          // the same two keys, so the bar is teaching the same alphabet.
          Row {
            id: searchKeys
            anchors.right: parent.right
            anchors.rightMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            visible: searchBar.open

            KeyChip {
              anchors.verticalCenter: parent.verticalCenter
              label: "tab"
              fontSize: 11
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "switches"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12
            }
            Item { width: 6; height: 1 }
            KeyChip {
              anchors.verticalCenter: parent.verticalCenter
              label: "esc"
              fontSize: 11
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "cancels"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12
            }
          }

        }


        // ── the filter, inline ──────────────────────────────────────
        // No card, no overlay. `/` or f puts the keyboard here and the list
        // narrows as you type; the query lives in the path bar beside the
        // counts, because that is where everything else about the current view
        // is already written. The field is only as wide as what is in it, so
        // an empty filter takes no room at all.
        Row {
          id: filterInline
          anchors.right: crumbStatus.left
          anchors.rightMargin: root.query !== "" || filterField.activeFocus ? 14 : 0
          anchors.verticalCenter: crumbInner.verticalCenter
          spacing: 6
          visible: root.query !== "" || filterField.activeFocus

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uF002"
            color: Zenon.cyan
            font.family: Zenon.face
            font.pixelSize: 15
          }

          TextInput {
            id: filterField
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(8, Math.min(260, contentWidth + 2))
            color: Zenon.cyan
            selectionColor: Zenon.cyan
            selectedTextColor: Zenon.black
            font.family: Zenon.face
            font.pixelSize: 17
            clip: true
            onTextChanged: { root.act.query = text; root.act.sel = 0; }
            Keys.onEscapePressed: (e) => {
              e.accepted = true;
              filterField.text = "";
              root.act.query = "";
              content.forceActiveFocus();
            }
            Keys.onReturnPressed: (e) => {
              e.accepted = true;
              content.forceActiveFocus();
            }
            Keys.onUpPressed: (e) => { e.accepted = true; root.moveSel(-1); }
            Keys.onDownPressed: (e) => { e.accepted = true; root.moveSel(1); }

            // The caret, since a bare TextInput on a bar has no frame to say
            // where the keyboard is — and the field's OWN, for the reason the
            // search bar's carries: a second one drawn at contentWidth is in
            // the wrong place as soon as the caret is not at the end.
            cursorDelegate: Rectangle {
              width: 2
              color: Zenon.cyan
              SequentialAnimation on opacity {
                running: filterField.activeFocus
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
              }
            }
          }
        }

        // ── the settings hatch ────────────────────────────────────────
        // The switches you flip WHILE you are working — hidden files, which
        // view, how much of the desktop shows through — at the far end of the
        // bar that already reports what the window is doing. Almost every one
        // of them has a key as well, and the panel is less a second way of
        // working than the place those keys are finally written down.
        Item {
          id: prefsToggle
          opacity: crumbBar.chromeInk
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: crumbInner.verticalCenter
          width: 30
          height: crumbInner.height

          Text {
            anchors.centerIn: parent
            // nf-fa-bars, as an escape — a literal nerd glyph does not survive
            // the trip through a shell heredoc, and arrives as nothing at all.
            text: "\uF0C9"
            color: prefs.open ? Zenon.cyan
              : (prefsHov.hovered ? Zenon.white : Zenon.muted)
            font.family: Zenon.face
            font.pixelSize: 16
          }

          HoverHandler { id: prefsHov }
          MouseArea {
            anchors.fill: parent
            onClicked: prefs.toggleFrom(prefsToggle)
          }
        }

        // ── what is running, in a drawer ──────────────────────────────
        // A browser's downloads button, and for the same reason: work that
        // takes time is not the thing you are doing, it is a thing that is
        // happening, and it belongs at the edge of the window rather than in
        // a card floating over the corner of it.
        //
        // The panel that used to sit in the bottom right could only ever show
        // ONE transfer, which was fine while transfers took turns. They no
        // longer do — see the note on `jobs` — so what is needed is a list,
        // and a list wants somewhere to hang from.
        //
        // IT IS NOT THERE WHEN THERE IS NOTHING TO SAY. An idle button that
        // reports nothing is a permanent invitation to check on nothing, and
        // the whole point of putting this in the bar is that the bar is
        // already where you look to find out what the window is doing.
        Item {
          id: jobsToggle
          opacity: crumbBar.chromeInk
          anchors.right: prefsToggle.left
          anchors.rightMargin: 2
          anchors.verticalCenter: crumbInner.verticalCenter
          readonly property bool live: jobsModel.count > 0
          // ONE COLOUR, READ BY EVERYTHING. The glyph, the count, the glow and
          // the burst all wear it, so "something went wrong" is a single fact
          // about the drawer rather than four things that have to be kept in
          // step. Red is reserved for exactly this — the same rule the confirm
          // card's verbInk follows.
          readonly property color tone: root.jobFaults > 0 ? Zenon.red : Zenon.cyan
          width: jobsToggle.live ? 32 : 0
          visible: width > 0.5
          height: crumbInner.height
          // Grows and collapses rather than appearing: it sits between the
          // status chip and the hamburger, and a button that pops into
          // existence shoves everything to its left across in one frame.
          Behavior on width {
            NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
          }

          // How lit the glow is, 0 to 1. Driven by the two animations below
          // rather than bound to anything: it has to BURST when a job starts
          // and then settle into a breath, and a binding can only ever say
          // one of those.
          property real glow: 0

          // ── the glow ────────────────────────────────────────────────
          // A blurred COPY of the glyph underneath the real one, not the
          // glyph itself blurred — blurring the thing you are meant to read
          // is how an icon becomes a smudge. The copy is what spreads; the
          // glyph on top of it stays sharp.
          Item {
            anchors.centerIn: parent
            width: parent.height
            height: parent.height
            opacity: jobsToggle.glow
            visible: opacity > 0.01
            // it swells with the burst, which is most of what makes a glow
            // read as an event rather than as a colour
            scale: 1.0 + 0.55 * jobsToggle.glow
            layer.enabled: true
            layer.effect: MultiEffect {
              blurEnabled: true
              // blurMax is the kernel, which is the actual softness knob —
              // `blur` alone is only the fraction of it that gets used. The
              // menu's shadow note spells this out at length.
              blurMax: 48
              blur: 1.0
              brightness: 0.5
              saturation: 0.4
              autoPaddingEnabled: true
            }

            Text {
              anchors.centerIn: parent
              text: jobsGlyph.text
              color: jobsToggle.tone
              font: jobsGlyph.font
            }
          }

          Text {
            id: jobsGlyph
            anchors.centerIn: parent
            // nf-fa-download, as an escape — a literal nerd glyph does not
            // survive the trip through a shell heredoc and arrives as
            // nothing at all. The browser's own sign for "things are coming
            // in", which is what this is.
            text: "\uF019"
            color: jobsHov.hovered && root.jobFaults === 0
              ? Zenon.white : jobsToggle.tone
            font.family: Zenon.face
            font.pixelSize: 15
          }

          // How many, when there is more than one — the same thing a browser
          // does, and the reason the glyph alone is not enough now that jobs
          // run together.
          Text {
            anchors.right: parent.right
            anchors.rightMargin: -1
            anchors.top: parent.top
            anchors.topMargin: 5
            visible: jobsModel.count > 1
            text: jobsModel.count
            color: Zenon.black
            style: Text.Outline
            styleColor: jobsToggle.tone
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 10
          }

          // ON HOVER, not on click. Checking what is running is a glance, and
          // a glance should not cost a click and then a second click to put
          // it away again.
          HoverHandler {
            id: jobsHov
            onHoveredChanged: {
              root.jobsOverGlyph = hovered;
              if (hovered) jobsDrawer.openFrom(jobsToggle);
              jobsDrawer.settle();
            }
          }

          // A BURST when a job starts, then a breath for as long as any is
          // running. Two animations rather than one, because they answer two
          // different questions — "something just began" and "something is
          // still going" — and one curve cannot say both.
          SequentialAnimation {
            id: jobsGlowBurst
            NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                              duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: jobsToggle; property: "glow"; to: 0.5;
                              duration: 460; easing.type: Easing.InQuad }
          }

          SequentialAnimation {
            id: jobsFaultBurst
            NumberAnimation { target: jobsToggle; property: "glow"; to: 1.0;
                              duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: jobsToggle; property: "glow"; to: 0.62;
                              duration: 320; easing.type: Easing.InQuad }
          }

          SequentialAnimation {
            id: jobsGlowPulse
            running: jobsToggle.live && !jobsGlowBurst.running
                     && !jobsFaultBurst.running
            loops: Animation.Infinite
            NumberAnimation { target: jobsToggle; property: "glow"
                              to: root.jobFaults > 0 ? 0.95 : 0.78
                              duration: 880; easing.type: Easing.InOutQuad }
            NumberAnimation { target: jobsToggle; property: "glow"
                              to: root.jobFaults > 0 ? 0.45 : 0.28
                              duration: 880; easing.type: Easing.InOutQuad }
          }

          // and out when the last one finishes, rather than freezing at
          // whatever the pulse was on
          NumberAnimation {
            id: jobsGlowOut
            target: jobsToggle
            property: "glow"
            to: 0
            duration: Zenon.normal
            easing.type: Zenon.ease
          }

          Connections {
            target: root
            function onJobStartedChanged() {
              jobsGlowOut.stop();
              jobsGlowBurst.restart();
            }
            // A failure bursts too, and harder: it settles to a brighter floor
            // than a start does, so a drawer with bad news in it is lit even
            // when nothing is running behind it.
            function onJobFaultedChanged() {
              jobsGlowOut.stop();
              jobsFaultBurst.restart();
            }
          }

          // The model's own count, rather than a second counter kept in step
          // with it by hand: the last job leaving IS the count reaching zero.
          Connections {
            target: jobsModel
            function onCountChanged() {
              if (jobsModel.count > 0) return;
              jobsGlowBurst.stop();
              jobsGlowOut.restart();
              jobsDrawer.open = false;
            }
          }
        }

        // What used to be a bar of its own along the bottom. Two full-width
        // strips to carry one line of text each was a strip too many, and the
        // right-hand end of the path bar was empty — so the count, the view
        // and whatever the last action had to say live here now.
        Row {
          id: crumbStatus
          opacity: crumbBar.chromeInk
          anchors.right: jobsToggle.left
          anchors.rightMargin: 10
          // up by the separator's own pixel: it is the bar's bottom EDGE, not
          // part of the inside, and centring across it sat everything low
          anchors.verticalCenter: crumbInner.verticalCenter
          spacing: 14

          // ── the status, as a chip ──────────────────────────────────
          // It was a bare line of red in a bar of greys: every note wore the
          // colour of an alarm, and none of them looked like they belonged to
          // the bar they sat in. Same rounded shape as the search chip and the
          // key caps, and the colour says which KIND of news it is rather than
          // only that there is some — red for refused or failed, sand for an
          // ordinary note.
          Rectangle {
            id: statusChip
            anchors.verticalCenter: parent.verticalCenter
            // THE COLOUR IS HELD THE SAME WAY THE WORDS ARE. Reading
            // root.statusBad live meant a failure turned sand the instant the
            // status cleared — because clearing resets the flag — and then
            // faded out yellow. It has to keep the tone it was shown in for as
            // long as it is still on screen.
            property bool shownBad: false
            readonly property color tone: statusChip.shownBad ? Zenon.red : Zenon.sand
            // It ARRIVES and it LEAVES, rather than blinking in and out. The
            // timeout above means the disappearance is something that happens
            // on its own while you are looking elsewhere, and a thing that
            // vanishes between frames reads as a glitch; a thing that fades
            // reads as finished. The width goes with it so the bar beside it
            // is not shoved sideways in one step.
            // IT KEEPS THE WORDS WHILE IT GOES. Binding the text straight to
            // root.status meant that clearing the status emptied the label in
            // the same frame, the width collapsed with it, and the opacity
            // animation then played out on something nought pixels wide — the
            // fade was running the whole time and there was nothing left to
            // see it on. `shown` holds the last message until the fade is
            // over, so there is something to fade.
            property string shown: ""
            onOpacityChanged: if (statusChip.opacity === 0) statusChip.shown = "";

            opacity: root.status !== "" ? 1 : 0
            visible: opacity > 0.01
            width: statusChip.shown !== "" ? statusInk.implicitWidth + 18 : 0
            height: 21
            radius: 5
            // Twice the slowest of the motion tokens, and deliberately outside
            // them: every other transition in this window answers something
            // you just did, so it should be over before you look for it. This
            // one happens on its own three seconds later, while you are
            // reading something else — the going IS the notice, and at 170ms
            // it is finished before it has been seen.
            Behavior on opacity {
              NumberAnimation { duration: Zenon.slow * 2; easing.type: Zenon.ease }
            }
            Behavior on width {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
            color: Qt.rgba(statusChip.tone.r, statusChip.tone.g,
                           statusChip.tone.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(statusChip.tone.r, statusChip.tone.g,
                                  statusChip.tone.b, 0.32)

            Text {
              id: statusInk
              anchors.centerIn: parent
              // ONLY the status. There used to be a fallback here that read
              // "1 copied · p to paste" for as long as something was on the
              // clipboard — which never emptied, so the chip could never fade
              // out and every message after it was a silent text swap. It was
              // also teaching a key on a permanent basis, which is what the
              // hint bar and F1 are for.
              text: statusChip.shown
              color: statusChip.tone
              font.family: Zenon.face
              font.pixelSize: 13
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
              const n = root.markedCount;
              // A MODE HAS TO BE VISIBLE. Everything else in this window is
              // one keystroke that does one thing; visual mode changes what
              // the arrow keys mean until it is turned off, so it says so.
              const mode = root.visualOn ? "VISUAL  \u00b7  " : "";
              // WHAT IT ADDS UP TO, not just how many. terminus.js has had
              // selectionSize since the status strip was written and nothing
              // ever called it — so "12 selected" told you nothing about
              // whether those twelve would fit on the stick you were copying
              // them to. Directories are left out of the total rather than
              // counted at their record size; the function's own note says why.
              if (n > 0) {
                const bytes = Terminus.selectionSize(root.markedRows());
                return bytes > 0
                  ? mode + n + " selected  \u00b7  " + Terminus.formatSize(bytes)
                  : mode + n + " selected";
              }
              if (mode !== "") return mode + "0 selected";
              const items = root.view.length
                + (root.view.length === 1 ? " item" : " items");
              // in the trash, how much it holds is what you are there to see
              return root.inTrash && root.trashSize !== ""
                ? items + " \u00b7 " + root.trashSize : items;
            }
            color: (root.markedCount > 0 || root.visualOn) ? Zenon.cyan : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 14
          }

          // WHAT THE ZOOM IS AT, as an instrument rather than as a number.
          // "140%" is a figure you have to read and then convert into "how
          // much room is left before it stops" — which is the only thing
          // anyone actually wants from it. A notched bar answers that at a
          // glance, and it is the same instrument the bar's own meters are,
          // so the shell has one way of drawing a level rather than two.
          //
          // Thumbs and the two list layouts scale independently, so this
          // follows whichever view you are in — one number would be reporting
          // the wrong one half the time.
          // AN INSTRUMENT YOU CAN ALSO TURN. It reported the zoom and
          // nothing more, which made it the only control-shaped thing in this
          // bar that did not answer to the pointer — you could see where the
          // zoom was and had to go to the keyboard to move it.
          //
          // The hit area is the wrapper, not the meter: the notches are 7px
          // tall and a 7px target is not a target. Twelve pixels of padding
          // top and bottom, taken inside the row's own height so nothing
          // moves.
          Item {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: zoomMeter.implicitWidth
            implicitHeight: zoomMeter.implicitHeight

            Meter {
              id: zoomMeter
              anchors.centerIn: parent
              vertical: false
              segCount: 8
              segLength: 3
              segGap: 2
              thickness: 7
              accent: zoomMa.containsMouse || zoomMa.pressed
                ? Zenon.white : Zenon.cyan
              Behavior on accent {
                ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }
              // Across the whole travel, not out of some absolute maximum:
              // the question is where this sits between as small as it goes
              // and as large, and that is what the wheel and the keys move it
              // through.
              value: (root.activeZoom - root.zoomMin)
                     / Math.max(0.0001, root.zoomMax - root.zoomMin)
              // The bottom notch is a real setting, not "off" — deadZone
              // would otherwise draw the smallest zoom as an unlit bar.
              deadZone: -1
            }

            MouseArea {
              id: zoomMa
              anchors.fill: parent
              anchors.topMargin: -12
              anchors.bottomMargin: -12
              anchors.leftMargin: -4
              anchors.rightMargin: -4
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton

              // the fraction of the METER the pointer is over, with the
              // padding taken back off
              function seek(x) {
                const w = zoomMeter.width;
                if (w <= 0) return;
                const f = Math.max(0, Math.min(1, (x - 4) / w));
                root.setZoom(root.zoomMin + f * (root.zoomMax - root.zoomMin));
              }

              onPressed: (m) => {
                // middle click is the reset every other meter-shaped thing
                // on this desktop uses
                if (m.button === Qt.MiddleButton) { root.zoomReset(); return; }
                zoomMa.seek(m.x);
              }
              onPositionChanged: (m) => { if (zoomMa.pressed) zoomMa.seek(m.x); }

              // the same 0.1 notch the keys and ctrl+wheel over the listing
              // step by, so the three ways of doing this agree
              onWheel: (w) => {
                root.zoomBy(w.angleDelta.y > 0 ? 0.1 : -0.1);
                w.accepted = true;
              }
            }
          }

          // WHAT IT IS SEARCHING, and nothing else. The view mode used to
          // share this slot as its fallback — a word that named what you were
          // already looking at, beside a menu that is one click away and says
          // the same thing. Nothing was read off it that the window was not
          // already showing.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.searchMode !== ""
            text: root.searchMode === "grep" ? "grep" : "find"
            color: Zenon.sand
            font.family: Zenon.face
            font.pixelSize: 14
          }

          // Which branch, while the mode is on and there is one to name. The
          // gutter says what changed; this says what it changed against, which
          // is the other half of the question and the only part a per-row mark
          // cannot carry. Silent outside a repository — the mode being on is
          // not a promise that there is a repository to report on.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.git && root.gitBranch !== ""
            text: "\uE725  " + root.gitBranch   // nf-dev-git_branch
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 14
          }
        }

        // ── WHAT THE SHEET IS DOING, SAID ON THE BAR ─────────────────
        // The send-to header lives HERE rather than inside the sheet, and
        // that is the whole of why it looks right: inside the sheet, anything
        // see-through reveals the file list, because the file list is what is
        // behind it. On the bar it sits over the window's own background with
        // the compositor's blur behind that, so its translucency shows what
        // the bar's translucency shows.
        //
        // The breadcrumb steps aside while it is up — you are choosing a
        // destination, not reading where you already are — and the two cross
        // fade on the sheet's own opacity, so the bar changes its mind at
        // exactly the speed the sheet arrives.
        //
        // Read as a sentence: this thing → that place. The verb and the arrow
        // are punctuation and stay muted; the nouns carry the colour.
        // THE DIALOG SHEETS' HEADER, in the same place and for the same
        // reason as the send picker's below. One Text rather than a row of
        // parts: these cards are about one thing and its name is the whole
        // of what there is to say.
        Row {
          id: sheetBarHead
          anchors.centerIn: crumbInner
          spacing: 7
          opacity: root.sheetHeadOn
          visible: sheetBarHead.opacity > 0.01

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.sheetGlyph !== ""
            text: root.sheetGlyph
            color: root.sheetGlyphInk
            font.family: Zenon.face
            font.pixelSize: 16
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, crumbInner.width - 160)
            elide: Text.ElideMiddle
            text: root.sheetTitle
            color: root.sheetTitleInk
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 16
          }
        }

        Row {
          id: sendToBarHead
          anchors.centerIn: crumbInner
          spacing: 6
          opacity: sendToCard.opacity
          visible: sendToBarHead.opacity > 0.01

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: sendTo.sending
            text: sendTo.op === "move" ? "\uDB80\uDD90" : "\uDB80\uDD8F"
            // crumbInk, the ink the step you are standing on uses. The header
            // takes the bar's place while it is up, so its punctuation is the
            // bar's punctuation — muted put it a shade below the chrome it had
            // replaced.
            color: root.crumbInk
            font.family: Zenon.face
            font.pixelSize: 15
          }

          // Air after the verb, so the glyph reads as a label on the line
          // rather than as the first character of the filename.
          // A Row skips an invisible child entirely, so the spacers go with
          // the nouns they were spacing and `go` reads as arrow, air, place.
          Item { width: 6; height: 1; visible: sendTo.sending }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sendTo.icon || ""
            // The Row's own 6 is the gap between PHRASES; a glyph and the
            // name it labels are one phrase and were reading as two things
            // jammed together.
            rightPadding: 3
            color: sendTo.iconInk
            font.family: Zenon.face
            font.pixelSize: 15
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // COUNTED OFF `names`, not off `paths`. They are the same length
            // for a copy and a move, and for `go` the subject is a name with
            // no path behind it — read from the path list it said "0 items".
            width: Math.min(implicitWidth, 300)
            elide: Text.ElideMiddle
            text: (sendTo.names.length === 1 ? sendTo.names[0]
                : sendTo.names.length + " items") || ""
            color: sendTo.iconInk
            font.family: Zenon.face
            font.pixelSize: 15
          }

          Item { width: 6; height: 1 }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!sendTo.current
            // A DIFFERENT ARROW FOR A DIFFERENT SENTENCE. Copy and move are
            // putting a thing somewhere, and the heavy arrow reads as
            // delivery; `go` is you travelling, so it gets the plain one.
            text: sendTo.op === "go" ? "\uF061" : "\uDB85\uDFB7"
            color: root.crumbInk
            font.family: Zenon.face
            font.pixelSize: 15
          }

          Item { width: 6; height: 1 }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!sendTo.current
            text: sendTo.glyphOf(sendTo.current) || ""
            rightPadding: 3
            color: sendTo.blocked ? Zenon.muted : Zenon.cyan
            font.family: Zenon.face
            font.pixelSize: 15
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!sendTo.current
            width: Math.min(implicitWidth, 260)
            elide: Text.ElideMiddle
            text: (sendTo.current ? sendTo.current.name : "") || ""
            color: sendTo.blocked ? Zenon.muted : Zenon.cyan
            font.family: Zenon.face
            font.pixelSize: 15
          }
        }

        // ── THE BAR'S BOTTOM EDGE, WITH A GAP WHERE THE SHEET HANGS ──
        // Two segments rather than one line with something drawn over it.
        // Covering was the first attempt and it could not work: headBg is
        // translucent, so a patch in the bar's own colour tinted the hairline
        // instead of hiding it. A rule with a hole in it has nothing to show
        // through.
        //
        // The sheet is spliced INTO the chrome, not hung under it — the bar's
        // edge stops where the sheet begins and picks up again on the far
        // side, so the two are one piece with a tongue coming out of it.
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          width: root.splicing ? root.spliceX : parent.width
          height: 1
          color: Zenon.msgBorder
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: root.splicing
            ? Math.max(0, parent.width - root.spliceX - root.spliceW) : 0
          height: 1
          color: Zenon.msgBorder
        }
      }


      // ── column headers ────────────────────────────────────────────
      // Only the list view has columns to name. The miller layout's panes are
      // one column each and the grid has none, so the strip collapses rather
      // than standing there labelling nothing.
      Rectangle {
        id: colHeads
        width: parent.width
        // ONE PANE ONLY. With two, each carries its own heading bar inside its
        // own half — because each has its own view, and a strip up here can be
        // only one height for both. A grid beside a list would have had a
        // 22px band of nothing over the grid, which is what it looked like:
        // a sort bar placeholder.
        height: root.colHeadsOn && root.viewMode === "list" && !root.dual
          ? 22 : 0
        visible: height > 0
        clip: true
        // TWO grounds, because this strip spans two things.
        //
        // Over the SIDEBAR it continues the sidebar's own tone — painting the
        // header colour the whole way across left a lighter band there that
        // read as a gap between the sidebar and the breadcrumb. Over the
        // listing it is transparent; see headArea.
        color: root.sidebarBg

        // Inset by the sidebar, because the columns name what is in the
        // LISTING and the sidebar is not the listing. Spanning the full width
        // put "NAME" above the bookmarks, labelling a column that is not
        // there — and the label moved out from over the rows it belongs to.
        //
        // Over the ACTIVE pane, wherever that is; only when that pane is a
        // list; and the SAME ColHeadBar the two-pane case draws inside each
        // half, so there is one definition of what a heading row is.
        ColHeadBar {
          x: side.width + root.activePaneX
          width: root.activePaneW
          height: parent.height
          visible: root.viewMode === "list"
        }

        // ── AND IT GOES DARK WITH THE SHEET ────────────────────────────
        // This strip sits between the path bar and the top of an open sheet,
        // and it is the one piece of chrome that was not following them: two
        // grounds, one of them transparent, so the blurred listing read
        // straight through a 22px band directly under a header that had gone
        // solid black. Which is exactly what "the header is not opaque" looks
        // like from the outside.
        //
        // OVER the heading bar, not behind it: headPlate covers the split
        // panes' headings for the same reason, and one layout showing NAME ·
        // SIZE · MODIFIED under an open sheet while the other shows a black
        // band is the same window disagreeing with itself.
        Rectangle {
          anchors.fill: parent
          color: Zenon.black
          opacity: root.sheetInk
          visible: opacity > 0.01
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.leftMargin: side.width
          anchors.right: parent.right
          height: 1
          color: Zenon.msgBorder
        }
      }

      // ── the body, with the sidebar beside it ──────────────────────
      // The row owns the leftover height; the sidebar and the body divide the
      // width of it. Reading it off bodyBox instead was a loop: bodyBox sizes
      // itself from its parent, and its parent is this.
      Row {
        id: bodyRow
        width: parent.width
        height: parent.height - tabStrip.height - crumbBar.height
          - colHeads.height - portalBar.height

        // ── SOFTENED BEHIND ANY CARD THAT TAKES THE WINDOW OVER ──────
        // zeus' confirm card does the same thing to its views, for the same
        // reason: what you are deciding about should recede rather than
        // compete, and it should still be THERE. An opaque black panel hid it
        // instead, which loses the sense of where you are.
        //
        // ON THE BODY, NOT ON THE CHROME. The blur was on the whole Column,
        // which took the bar with it — and the bar is where every sheet now
        // writes its title. A soft title over a soft path is a window with
        // nothing in focus at all. So the rule is simply: chrome stays sharp,
        // content recedes. The tab strip, the path bar and the sort strip are
        // chrome; the sidebar, the panes and the preview are what this holds.
        //
        // Only while a card is on screen. A layer left enabled would put the
        // body through an offscreen texture for the entire session to buy a
        // blur that shows for a couple of seconds.
        layer.enabled: root.cardSoft > 0.01
        layer.effect: MultiEffect {
          blurEnabled: true
          blurMax: 40
          // ramped by the card's own fade, so the body goes soft as the card
          // arrives instead of snapping out of focus underneath it
          blur: root.cardSoft

          // AND IT STAYS INSIDE THE BODY. MultiEffect pads its output so a
          // blur is not cut off at the item's edge — which means it DRAWS
          // OUTSIDE the item, and the item directly above this one is the
          // path bar. The listing's blur was spilling up across the hairline
          // onto the bar: a soft haze over the bottom of a strip that is
          // supposed to be solid black while a sheet is up, brightest under
          // the busiest half of the listing and absent over the empty one.
          //
          // Which is what "the header is not opaque" was the whole time. The
          // bar's colour was already #000000 at full ink and measured as
          // black in the middle of the strip; the bottom eight pixels of it
          // were carrying someone else's blur.
          autoPaddingEnabled: false
        }

        Rectangle {
          id: side
          width: root.sidebar ? root.sidebarWidth : 0
          height: parent.height
          visible: width > 0
          clip: true
          color: root.sidebarBg
          // Animated when it OPENS and CLOSES, not while it is being dragged:
          // easing every frame of a drag makes the edge lag the pointer, which
          // reads as the window resisting you.
          Behavior on width {
            enabled: !sideGrip.pressed
            NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
          }

          Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: sideGrip.pressed || sideGrip.containsMouse
              ? Zenon.cyan : Zenon.msgBorder
          }

          Flickable {
            anchors.fill: parent
            anchors.rightMargin: 1
            contentHeight: sideCol.implicitHeight
            clip: true

            // ── THE CURSOR, AS ONE BAR THAT MOVES ───────────────────
            // The list sheets get theirs from a view and the panes from an
            // index; this column has neither. Its rows come from two Repeaters
            // with headings between them and they are not all the same height,
            // so the bar is placed against the row itself — the settings
            // panel's answer, for the same reason.
            //
            // A SIBLING OF THE COLUMN, inside the same scroller: mapped into
            // this coordinate space the position already includes wherever the
            // list has been scrolled to, so nothing here has to watch contentY.
            Rectangle {
              id: sideBar
              readonly property var cur: root.sideAt
              visible: !!sideBar.cur && sideBar.cur.visible
              color: Zenon.selBg

              // mapToItem is a function call over geometry, not a property
              // read, so it is given the things that move to watch — the
              // column's own size, which settles when the rows are laid out
              // and changes again whenever a disk appears or the sidebar is
              // dragged wider.
              readonly property var spot: (sideBar.cur
                  && sideCol.height >= 0 && sideCol.width >= 0)
                ? sideBar.cur.mapToItem(sideBar.parent, 0, 0) : null
              x: sideBar.spot ? sideBar.spot.x : 0
              y: sideBar.spot ? sideBar.spot.y : 0
              width: sideBar.cur ? sideBar.cur.width : 0
              height: sideBar.cur ? sideBar.cur.height : 0

              // Only the travel eases. A bookmark row is 32 and a gauged disk
              // is 46, and easing fourteen pixels of height is a stretch
              // rather than a movement.
              Behavior on y {
                enabled: root.cursorSlide
                NumberAnimation {
                  duration: Zenon.fast; easing.type: Zenon.travelEase
                }
              }
            }

            Column {
              id: sideCol
              width: side.width - 1

              // The sidebar's top moves between views, and this makes up the
              // difference. colHeads spans the full width, so in LIST view its
              // 22px strip sits above the sidebar and gives the first heading
              // its breathing room; in grid and columns that strip collapses to
              // nothing and the heading ended up jammed against the breadcrumb.
              // Whatever colHeads is not supplying, this does.
              Item {
                width: 1
                height: Math.max(0, 22 - colHeads.height)
              }

              SideHead { label: "BOOKMARKS"; first: true }

              Repeater {
                model: root.bookmarks

                delegate: SideRow {
                  required property var modelData
                  required property int index
                  slot: index
                  width: sideCol.width
                  label: Terminus.basename(modelData)
                  // THE GLYPH THE FOLDER WEARS EVERYWHERE ELSE. Every row
                  // here used to be the same bookmark tag, which said "this
                  // is a bookmark" — a thing the panel it is sitting in had
                  // already said — and threw away the one piece of
                  // information the icon could have carried. Downloads,
                  // .config and a git checkout are told apart at a glance in
                  // the listing and in the send sheet; this is the third
                  // place they are drawn and it is the same table.
                  //
                  // Home by its own name rather than by the user's: the
                  // basename of ~ is "buck", which no rule claims, while the
                  // sheet's roots already label it "Home" for exactly this.
                  glyph: Icons.glyphFor({
                    name: modelData === Paths.home()
                      ? "home" : Terminus.basename(modelData),
                    isDir: true })
                  active: modelData === root.cwd
                  showRemove: true
                  onChosen: root.goTo(modelData)
                  // middle click removes it, the same gesture the tabs use
                  onRemoved: root.removeBookmark(modelData)
                }
              }

              Item {
                width: 1
                height: root.bookmarks.length === 0 ? 0 : 8
              }

              SideHead { label: "DISKS"; visible: root.disks.length > 0 }

              Repeater {
                model: root.disks

                delegate: SideRow {
                  required property var modelData
                  width: sideCol.width
                  label: modelData.name !== "" ? modelData.name
                    : Terminus.basename(modelData.path)
                  // Free space when it is mounted, total size when it is not.
                  // "412G free" is the number you actually want before copying
                  // to a disk; the capacity only matters when you cannot yet
                  // see inside it. lsblk supplies both, so neither costs a
                  // process.
                  detail: modelData.mount !== "" && modelData.avail !== ""
                    ? modelData.avail + " free" : modelData.size
                  used: Terminus.usedFraction(modelData.avail, modelData.fsSize)
                  glyph: modelData.removable ? "\uF0A0" : "\uF1C0"
                  active: modelData.mount !== "" && root.cwd.indexOf(modelData.mount) === 0
                  // a mounted disk is a place; an unmounted one is a button
                  mounted: modelData.mount !== ""
                  // no eject on the mounts the system is standing on
                  showMount: !Terminus.isSystemMount(modelData.mount)
                  onChosen: {
                    if (modelData.mount !== "") root.goTo(modelData.mount);
                    else root.mountDisk(modelData);
                  }
                  onToggledMount: root.mountDisk(modelData)
                }
              }
            }
          }
        }

        Item {
          id: bodyBox
          width: parent.width - side.width
          height: parent.height

          // The ACTIVE half's heading strip height, which is what the miller
          // frame and the hit tests mean by "the top of the listing". Each
          // half's own is asked for by side — see root.paneHeadH.
          readonly property real headH: root.paneHeadH(root.paneSide)
          readonly property real topH: bodyBox.headH

          // One strip per half, each following its own view and neither
          // moving. `live` marks the one the keyboard is in, the same way the
          // rows below it do.
          ColHeadBar {
            x: root.paneX(0)
            width: root.paneW(0)
            visible: root.paneHeadH(0) > 0
            live: paneL.active
            z: 3
          }

          ColHeadBar {
            x: root.paneX(1)
            width: root.paneW(1)
            visible: root.dual && root.paneHeadH(1) > 0
            live: paneR.active
            z: 3
          }

          // ── the divider, as something you can grab ────────────────
          // Not a child of the sidebar: `side` clips, so a handle inside it
          // could only ever be as wide as the 1px line it sits on. So it
          // overlays the seam from INSIDE the body instead.
          //
          // It used to sit in the Row between the sidebar and the body, which is
          // the one place it must not be: a Row lays out every visible child, so
          // the 9px handle was 9px of layout. The body was pushed 9px right of
          // the sidebar and, being sized as `parent.width - side.width`, ran 9px
          // off the right-hand edge of the window — which is why the preview
          // pane had 12px of padding down its left side and 3px down its right.
          // A child of bodyBox costs the Row nothing.
          MouseArea {
            id: sideGrip
            width: 9
            height: parent.height
            // z above the body so the cursor changes over the seam even where a
            // row is drawn right up to it
            z: 9
            visible: root.sidebar
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            preventStealing: true
            // Straddling the divider, half either side — and measured from
            // bodyBox's own left edge, which IS the divider, so this no longer
            // has to follow side.width at all.
            x: -4

            // Where in the grip it was taken hold of, so the seam stays under
            // the same part of the pointer for the whole drag.
            property real grab: 0

            // Measured in bodyRow's coordinates, never in the grip's own.
            //
            // The grip travels with the divider, so while you drag it slides
            // along underneath the pointer — and a delta taken from `m.x` is
            // measured against an origin that is itself moving. Each frame
            // overshot and the next corrected, which is what made the divider
            // jitter. bodyRow does not move, so a position mapped into it is
            // stable.
            onPressed: (m) => {
              sideGrip.grab = m.x;
            }
            onPositionChanged: (m) => {
              if (!sideGrip.pressed) return;
              const px = sideGrip.mapToItem(bodyRow, m.x, 0).x;
              root.sidebarWidth = Math.max(root.sidebarMin,
                Math.min(root.sidebarMax, px - sideGrip.grab + 4));
            }
            // Double click springs it back, so a width dragged somewhere silly is
            // one gesture to undo rather than a careful drag back.
            onDoubleClicked: root.sidebarWidth = 200
          }

        // Ctrl+wheel zooms — see the overlay at the bottom of this Item.
        // It cannot live here: a pointer handler on a parent is only offered
        // an event after every child has declined it, and all three views are
        // Flickables that handle the wheel themselves. So this container's own
        // handler was never reached and the gesture did nothing.

        // ── the two lists, one per half ─────────────────────────────
        // Neither ever moves. See PaneList, which is where the argument for
        // that lives; with one pane the right-hand one simply is not drawn.
        PaneList { id: listA; pane: paneL }
        PaneList { id: listB; pane: paneR }

        // ── AND THE CURSOR TRAVELS, HERE TOO ────────────────────────
        // The same bar the sheets wear. It was a fill on each row, which
        // cannot move between two of them — the mark blinked off one and on to
        // the next — and this is the list it matters most on, because it is
        // the one the cursor spends all day in.
        //
        // NOT WHILE THE ROW IS cursorOnly. With things ticked, or on the pane
        // the keyboard is not in, the cursor is drawn as an OUTLINE rather
        // than a fill so it cannot be mistaken for a selection; the bar stands
        // down for that and the row draws its own border, as before.
        SelectBar {
          view: listA
          index: paneL.sel
          rowH: root.rowH
          on: listA.on && !root.cursorOutline(paneL)
        }
        SelectBar {
          view: listB
          index: paneR.sel
          rowH: root.rowH
          on: listB.on && !root.cursorOutline(paneR)
        }

        // ── columns ─────────────────────────────────────────────────
        // Yazi's miller layout: where you came from, where you are, and what
        // you are about to open. The point is that moving the cursor changes
        // the right-hand pane rather than the whole window, so you can look
        // into a directory without entering it.
        // ── STEPPING THROUGH THE TREE, AS MOVEMENT ──────────────────
        // Miller's columns are a window onto the tree, and walking into a
        // directory slides that window one column along. Drawn as a cut — the
        // three columns simply becoming three different columns — there is
        // nothing for the eye to follow and no sense of which way you went;
        // out and back looked identical to going two levels down.
        //
        // A CLIPPING FRAME the columns move inside. The Row used to be placed
        // here directly, so shifting it would have shifted its own clip with
        // it and the columns would have drawn over the chrome either side.
        // The frame holds the pane's place; the Row travels within it.
        Item {
          id: millerBox
          x: root.activePaneX
          y: bodyBox.topH
          width: root.activePaneW
          height: parent.height - bodyBox.topH
          visible: root.viewMode === "columns"
          clip: true

          // AN ITEM, NOT A ROW. A Row lays its children out in declaration
          // order, and these three swap places — so they are placed by the
          // SLOT they are standing in instead. See millerOrder.
          Item {
            id: miller
            width: parent.width
            height: parent.height

            // ── TWO COLUMNS WHILE A FIND IS UP ────────────────────────
            // Results are not a directory — they come from all over the tree
            // — so the parent column has nothing true to say about them. It
            // was drawing the parent of the folder the search STARTED in,
            // which is a quarter of the pane spent on an answer to a question
            // nobody asked. With it gone the results and the preview split
            // the pane, which is what miller columns are for: the list, and
            // what the cursor is on.
            //
            // A find only. A grep already puts its own second column to work
            // — see showMeta — and its results are lines inside files rather
            // than places, so that layout is the one it wants.
            readonly property bool flat: root.searchMode === "find"

            readonly property real w0: miller.flat
              ? 0 : Math.round(miller.width * 0.24)
            // THE FREED QUARTER GOES TO THE RESULTS, all of it. The preview
            // keeps the 0.42 it has in the three-column layout — it is
            // showing one file and never wanted more — so the list takes the
            // parent column's room on top of its own and ends up the wider of
            // the two. Which is the right way round: a result is a PATH, and
            // a path is long.
            readonly property real w1: Math.round(
              miller.width * (miller.flat ? 0.58 : 0.34))
            // One seam instead of two when the parent is gone.
            readonly property int seams: miller.flat ? 1 : 2
            readonly property real w2:
              miller.width - miller.w0 - miller.w1 - miller.seams

            function slotX(sl) { return sl === 0 ? 0
              : (sl === 1 ? (miller.flat ? 0 : miller.w0 + 1)
                          : miller.w0 + miller.w1 + miller.seams); }
            function slotW(sl) { return sl === 0 ? miller.w0
              : (sl === 1 ? miller.w1 : miller.w2); }
            // Where the columns ARE, which is home except for the moment
            // after a step: millerStep drops them a third of a pane to one
            // side and the animator carries them back, so the motion reads as
            // the tree moving under a window that is standing still.
            //
            // A plain value, not a binding — see millerAnim, which writes it
            // from the render thread. Same for opacity and millerFade.
            x: 0
            opacity: 1

            MillerColumn {
              id: colA
              slot: root.millerOrder[0] === 0 ? 0
                  : (root.millerOrder[1] === 0 ? 1 : 2)
              x: miller.slotX(colA.drawnSlot)
              width: miller.slotW(colA.drawnSlot)
              height: parent.height
              // By SLOT, never by instance: rotating changes what this column
              // is about, and the binding follows it there.
              rows: colA.slot === 0 ? root.millerRowsParent
                  : (colA.slot === 1 ? root.millerRowsCurrent
                                   : root.millerRowsPreview)
            }

            MillerColumn {
              id: colB
              slot: root.millerOrder[0] === 1 ? 0
                  : (root.millerOrder[1] === 1 ? 1 : 2)
              x: miller.slotX(colB.drawnSlot)
              width: miller.slotW(colB.drawnSlot)
              height: parent.height
              // By SLOT, never by instance: rotating changes what this column
              // is about, and the binding follows it there.
              rows: colB.slot === 0 ? root.millerRowsParent
                  : (colB.slot === 1 ? root.millerRowsCurrent
                                   : root.millerRowsPreview)
            }

            MillerColumn {
              id: colC
              slot: root.millerOrder[0] === 2 ? 0
                  : (root.millerOrder[1] === 2 ? 1 : 2)
              x: miller.slotX(colC.drawnSlot)
              width: miller.slotW(colC.drawnSlot)
              height: parent.height
              // By SLOT, never by instance: rotating changes what this column
              // is about, and the binding follows it there.
              rows: colC.slot === 0 ? root.millerRowsParent
                  : (colC.slot === 1 ? root.millerRowsCurrent
                                   : root.millerRowsPreview)
            }

            // The two seams. They do not rotate — a divider is where one
            // column stops, not something a column owns.
            Rectangle {
              x: miller.w0; width: 1; height: parent.height
              visible: !miller.flat
              color: Zenon.msgBorder
            }
            Rectangle {
              x: miller.w0 + miller.w1 + miller.seams - 1
              width: 1; height: parent.height
              color: Zenon.msgBorder
            }

            // The media half of the third column — a picture, a film, a PDF,
            // an archive's tree. The DIRECTORY half is a rotating column like
            // the other two and sits above this; they are the same slot seen
            // two ways, which is why this takes slot 2's geometry.
            Item {
              id: previewPane
              x: miller.slotX(2)
              width: miller.slotW(2)
              height: parent.height
              clip: true

              // ── IT EASES IN, IT DOES NOT APPEAR ──────────────────────
              // The pane is filled once the columns have stopped, which is
              // deliberate: building a column of delegates syncs the scene
              // graph, and doing that mid-slide is the bump the transition
              // used to have. The cost is that the content then arrives on a
              // frame where nothing else is moving, and anything appearing at
              // full strength on a still frame POPS.
              //
              // So the pane carries its own short fade, reset by settlePreview
              // whenever the thing being shown actually changes. A plain
              // value, not a binding — previewFade writes it from the render
              // thread, like the slide and the columns' own fade.
              opacity: 1

              // ── THE WHOLE PANE IS THE DIRECTORY IT IS SHOWING ────────
              // Clicking a row in here already steps into the previewed folder.
              // The empty space below the rows did nothing, which made the pane
              // read as a picture OF a directory rather than as the directory —
              // and the gap below a short listing is most of the column.
              //
              // Declared FIRST, so it sits underneath: a row, a scrolling text
              // preview and an archive tree all take their own clicks before
              // this ever sees one. Only while a directory is what is being
              // shown; over a file this pane is a preview and not a door.
              MouseArea {
                anchors.fill: parent
                enabled: root.previewKind === "dir"
                acceptedButtons: Qt.LeftButton
                onClicked: {
                  const r = root.currentRow();
                  if (r && r.isDir) root.goTo(r.path);
                }
              }


              // ── a picture or a film, and what it IS ────────────────────
              // Anchored to the TOP of the pane rather than centred in it,
              // because the facts underneath are part of the preview now. A
              // frame floating in the middle with a block of text below it reads
              // as two unrelated things, and worse, both of them move: every
              // change of aspect ratio slid the metadata up or down the pane.
              //
              // Rounded the same 5px as the grid tiles, and for the same reason
              // the note over thumbClip gives — the corners belong on the frame,
              // never on the pane it is letterboxed inside.
              Column {
                id: media
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                // A touch tighter at the top than at the sides: the bar above is a hard
                // edge and the pane's own left divider is not, so an equal 16 read as
                // more air above than beside.
                anchors.topMargin: 12
                spacing: 10
                visible: root.previewKind === "image" || root.previewKind === "video"
                  || root.previewKind === "audio"

                // The frame gets at most this much of the pane and the rest
                // belongs to the facts. Uncapped, a tall photograph filled the
                // pane on its own and pushed every row of metadata off the
                // bottom of it.
                readonly property real boxW: media.width
                readonly property real boxH: Math.max(80, previewPane.height * 0.56)

                ClippingRectangle {
                  id: mediaClip
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: shot.status === Image.Ready
                  color: "transparent"
                  radius: 5

                  // The aspect ratio comes from the Image's IMPLICIT size, the
                  // decoded source, and never from paintedWidth/paintedHeight —
                  // the painted size follows the item's own, which is this
                  // rectangle's, and reading it here would be a binding loop.
                  readonly property real ar:
                    shot.implicitWidth > 0 && shot.implicitHeight > 0
                      ? shot.implicitWidth / shot.implicitHeight : 1
                  width: Math.max(1, Math.min(media.boxW, media.boxH * mediaClip.ar))
                  height: Math.max(1, Math.min(media.boxH, media.boxW / mediaClip.ar))

                  Image {
                    id: shot
                    anchors.fill: parent
                    // One Image for both kinds, because they differ only in
                    // where the pixels come from: a picture is shown as itself,
                    // a video as the frame ffmpeg pulled out of it for the grid.
                    //
                    // The row is re-checked here, not just previewKind. Moving
                    // the cursor changes the row a frame before loadPreview has
                    // decided what the new one is, so for that frame this
                    // binding asked for a DIRECTORY as an image and Qt logged
                    // "Cannot open: file:///home/buck/Desktop" every time the
                    // cursor passed one.
                    source: {
                      const r = root.currentRow();
                      if (!r || r.isDir) return "";
                      // a video's frame and an audio file's cover both live in
                      // the thumbnail cache; a picture is shown as itself
                      if (root.previewKind === "video"
                          || root.previewKind === "audio") {
                        return root.thumbFile[r.path]
                          ? "file://" + root.thumbFile[r.path] : "";
                      }
                      if (root.previewKind !== "image") return "";
                      return Terminus.isImage(r.name) ? "file://" + r.path : "";
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // capped rather than full-size: a 6000px wallpaper decoded
                    // at native resolution to fill a 300px pane is most of a
                    // second and a lot of memory for a picture nobody is
                    // looking at yet
                    sourceSize.width: 900
                    sourceSize.height: 900
                  }
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: {
                    const r = root.currentRow();
                    return r ? r.name : "";
                  }
                  elide: Text.ElideMiddle
                  color: Zenon.white
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: 17
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Zenon.msgBorder
                }

                Column {
                  width: parent.width
                  spacing: 3

                  Repeater {
                    // Every property this reads is named here on purpose: a
                    // binding re-evaluates when a PROPERTY it touched changes,
                    // and currentRow() is a function call, which is not one.
                    // Without `sel` and `view` in the expression the panel kept
                    // the first file's size and date for the whole folder.
                    model: {
                      const kind = root.previewKind;
                      const info = root.previewInfo;
                      const at = root.sel;
                      const all = root.view;
                      if (kind !== "image" && kind !== "video" && kind !== "audio")
                        return [];
                      const r = root.currentRow();
                      if (!r) return [];
                      const out = [];
                      const dot = "  \u00b7  ";
                      const add = (k, v) => { if (v) out.push([k, v]); };
                      if (info && info.dims) out.push(["dimensions", info.dims]);
                      if (kind === "video" && info) {
                        add("duration", info.duration);
                        add("codec", info.codec
                          + (info.container ? dot + info.container : ""));
                        add("frame rate", info.fps);
                        add("bitrate", info.bitrate);
                      } else if (kind === "audio" && info) {
                        // the tags first: on a track they are the answer, and
                        // the codec is the footnote
                        add("title", info.title);
                        add("artist", info.artist);
                        add("album", info.album
                          + (info.date ? dot + info.date : ""));
                        add("track", info.track);
                        add("duration", info.duration);
                        add("codec", info.codec
                          + (info.container ? dot + info.container : ""));
                        add("audio", [info.rate, info.channels]
                          .filter((x) => !!x).join(dot));
                        add("bitrate", info.bitrate);
                      } else if (info) {
                        add("format", info.format);
                        add("colour", [info.depth, info.colorspace]
                          .filter((x) => !!x).join(dot));
                      }
                      out.push(["size", Terminus.formatSize(r.size)]);
                      out.push(["modified", Terminus.formatTime(r.mtime)]);
                      return out;
                    }

                    delegate: Row {
                      required property var modelData
                      width: media.width
                      height: 24
                      spacing: 10

                      Text {
                        // wide enough for "frame rate", the longest label any of
                        // these rows carries, at this size
                        width: 102
                        height: parent.height
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        text: modelData[0]
                        color: Zenon.muted
                        font.family: Zenon.face
                        font.pixelSize: 16
                      }

                      Text {
                        width: media.width - 112
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: modelData[1]
                        elide: Text.ElideRight
                        color: Zenon.white
                        font.family: Zenon.face
                        font.pixelSize: 16
                      }
                    }
                  }
                }
              }

              // ── a typeface, in its own hand ────────────────────────────
              // Every other preview describes the file. This one IS it: Qt loads
              // the face and draws the specimen with it, which answers "what
              // does this look like" in a way no list of facts about a font ever
              // could.
              //
              // FontLoader reads the file on the fly and leaves nothing behind —
              // the family it registers lives only as long as the loader does,
              // so browsing a folder of fonts does not install any of them.
              Column {
                id: fontPane
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                // A touch tighter at the top than at the sides: the bar above is a hard
                // edge and the pane's own left divider is not, so an equal 16 read as
                // more air above than beside.
                anchors.topMargin: 12
                spacing: 12
                visible: root.previewKind === "font"

                FontLoader {
                  id: face
                  source: {
                    const r = root.currentRow();
                    if (!r || r.isDir || root.previewKind !== "font") return "";
                    return "file://" + r.path;
                  }
                }

                readonly property bool ready: face.status === FontLoader.Ready
                // The family NAME as the file declares it, which is very often
                // not what the file is called.
                readonly property string family: fontPane.ready ? face.font.family : ""

                Text {
                  width: parent.width
                  text: fontPane.ready ? fontPane.family : "could not read this font"
                  elide: Text.ElideRight
                  color: fontPane.ready ? Zenon.white : Zenon.muted
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: 17
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Zenon.msgBorder
                }

                Repeater {
                  // Sizes as well as letters, because a face that reads well at
                  // 28px can be mud at 13 and that is the thing worth knowing
                  // before choosing one.
                  model: fontPane.ready ? [
                    ["Sphinx of black quartz, judge my vow", 30],
                    ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", 20],
                    ["abcdefghijklmnopqrstuvwxyz", 20],
                    ["0123456789  &@#$%  .,;:!?  ()[]{}", 20],
                    ["The quick brown fox jumps over the lazy dog", 15],
                    ["The quick brown fox jumps over the lazy dog", 12]
                  ] : []

                  delegate: Text {
                    required property var modelData
                    width: fontPane.width
                    text: modelData[0]
                    wrapMode: Text.Wrap
                    color: Zenon.white
                    font.family: fontPane.family
                    font.pixelSize: modelData[1]
                  }
                }
              }

              // ── what is inside an archive ─────────────────────────────
              // A column of full paths was what the tool prints, not what the
              // question is: forty lines that all begin with the same three
              // directories say nothing about the SHAPE of the archive. Folded
              // back into the hierarchy it came out of, it reads the way yazi
              // draws a directory — which is what the pane beside it is already
              // showing you.
              //
              // Inert. There is nothing in here to open until it is extracted,
              // so unlike the directory preview above it takes no clicks.
              ListView {
                id: archiveList
                anchors.fill: parent
                anchors.margins: 16
                // level with the text preview beside it — see the note there
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                visible: root.previewKind === "archive"
                model: root.previewKind === "archive" ? root.previewTree : []
                clip: true
                interactive: true
                // drained with the model — see the note on the list, above
                reuseItems: root.previewKind === "archive"
                boundsBehavior: Flickable.StopAtBounds
                onVisibleChanged: if (!visible) contentY = 0;

                delegate: Item {
                  required property var modelData
                  width: archiveList.width
                  height: Math.round(21 * root.zoom)

                  // The guides are BOX-DRAWING characters and they have to stack
                  // exactly under the ones on the row above, which only a
                  // fixed-pitch face guarantees — the names beside them are set
                  // in the proportional one every other listing here uses.
                  Text {
                    id: treeGuide
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // `|| ""` on every field this delegate reads, and it is not
                    // defensive noise: reuseItems recycles a delegate by
                    // rebinding modelData, and on the frame the model swaps —
                    // one archive to the next, or an archive to nothing — the
                    // recycled row is briefly bound to a row of a different
                    // shape. Qt logged one "Unable to assign [undefined] to
                    // QString" per delegate per swap.
                    text: modelData.prefix || ""
                    // muted, not msgBorder: that is a hairline colour carrying
                    // 30% alpha and the guides came out as a suggestion of a
                    // tree. They are structure — meant to be seen at a glance
                    // and never read — which is exactly what muted is for.
                    color: Zenon.muted
                    font.family: Zenon.faceMono
                    font.pixelSize: Math.round(15 * root.zoom)
                  }

                  Text {
                    id: treeGlyph
                    anchors.left: treeGuide.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!modelData.glyph
                    width: visible ? Math.round(20 * root.zoom) : 0
                    text: modelData.glyph || ""
                    color: modelData.ink || Zenon.white
                    font.family: Zenon.faceMono
                    font.pixelSize: Math.round(15 * root.zoom)
                  }

                  Text {
                    anchors.left: treeGlyph.right
                    anchors.leftMargin: 4
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name || ""
                    elide: Text.ElideRight
                    color: modelData.ink || Zenon.white
                    font.family: Zenon.face
                    font.pixelSize: Math.round(15 * root.zoom)
                  }
                }
              }

              ScrollRail {
                target: archiveList
                on: archiveList.visible
                // Against the PANE rather than the view, for the reason the
                // text pane's rail gives below: the view is inset 16px and a
                // rail hung off that sits nowhere near where every other rail
                // in this window sits.
                anchors.top: previewPane.top
                anchors.topMargin: 2
                anchors.bottom: previewPane.bottom
                anchors.bottomMargin: 2
                anchors.right: previewPane.right
                anchors.rightMargin: 2
              }

              // SCROLLABLE, because a preview that only ever shows the first
              // screenful is a preview of the top of a file. bat is asked for a
              // capped number of lines either way, but forty lines in a pane
              // twenty deep is half an answer.
              //
              // Wheel and drag both work because it is a Flickable; the rail
              // beside it is the same one every other view here uses.
              Flickable {
                id: textScroll
                anchors.fill: parent
                anchors.margins: 16
                // NO VERTICAL PADDING AT ALL. The sides need it — the pane's own
                // divider is a hairline and text run up against it reads as
                // spilling out of the column. The top and bottom do not: the bar
                // above is a hard edge that already separates them, and the three
                // columns beside this one start their first row flush with it.
                // Inset, the preview began a line and a half lower than the
                // listing it is a preview OF, which reads as the pane sagging.
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                visible: root.previewKind === "text"
                clip: true
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, previewBody.implicitWidth)
                contentHeight: previewBody.implicitHeight
                // back to the top whenever the pane is showing something else
                onVisibleChanged: if (!visible) contentY = 0;

                Text {
                  id: previewBody
                  width: textScroll.width
                  text: root.previewText
                  // RichText, because bat's colours arrive as ANSI and are
                  // translated rather than thrown away — that is the syntax
                  // highlighting, and markdown comes through the same path
                  textFormat: Text.RichText
                  color: Zenon.white
                  wrapMode: Text.NoWrap
                  font.family: Zenon.faceMono
                  font.pixelSize: Math.round(17 * root.zoom)
                }
              }

              // A new file starts at the top of itself, not wherever the last
              // one was left. previewText changes for every row the cursor
              // lands on, so this is the moment to reset.
              Connections {
                target: root
                function onPreviewTextChanged() { textScroll.contentY = 0; }
                // and the same for the tree, which stays visible from one
                // archive to the next and would otherwise open the second one
                // partway down
                function onPreviewRowsChanged() { archiveList.contentY = 0; }
              }

              ScrollRail {
                target: textScroll
                on: textScroll.visible
                // Placed against the PANE, not against textScroll — the
                // flickable is inset 16px so that its text does not run into
                // the edges, and hanging the rail off that put it 18px in from
                // the pane while every other rail here sits 2px from its view.
                anchors.top: previewPane.top
                anchors.topMargin: 2
                anchors.bottom: previewPane.bottom
                anchors.bottomMargin: 2
                anchors.right: previewPane.right
                anchors.rightMargin: 2
              }

              Image {
                anchors.fill: parent
                anchors.margins: 16
                // A touch tighter at the top than at the sides: the bar above is a hard
                // edge and the pane's own left divider is not, so an equal 16 read as
                // more air above than beside.
                anchors.topMargin: 12
                visible: root.previewKind === "pdf"
                source: root.previewKind === "pdf" && root.previewStamp > 0
                  ? "file://" + root.pdfStem + ".png?v=" + root.previewStamp : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                sourceSize.width: 900
                sourceSize.height: 1200
              }

              Text {
                anchors.centerIn: parent
                visible: root.previewKind === "binary" || root.previewKind === "none"
                text: root.previewKind === "binary" ? "binary" : ""
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 13
              }
            }
          }
        }

        // ── grid ────────────────────────────────────────────────────
        // Qt decodes the picture itself. There is no thumbnail cache and no
        // thumbnailer process behind this: sourceSize makes the loader scale
        // while decoding, so what lands in memory is already tile-sized, and
        // asynchronous keeps that off the render thread.
        // ── the two grids, one per half ─────────────────────────────
        PaneGrid { id: gridA; pane: paneL }
        PaneGrid { id: gridB; pane: paneR }

        // The listing's cursor, on the grid's two axes. Stands down for the
        // same case the lists do: with things ticked, or on the half the
        // keyboard is not in, the cursor is an outline rather than a fill.
        SelectCell {
          view: gridA
          index: paneL.sel
          on: gridA.on && !root.cursorOutline(paneL)
        }
        SelectCell {
          view: gridB
          index: paneR.sel
          on: gridB.on && !root.cursorOutline(paneR)
        }

        // One rail per view that scrolls, each riding its own flickable —
        // four of them now, because there are four views and each belongs to
        // a half rather than to a role. Declared here, after the views, so
        // they draw over the tiles rather than under them.
        ScrollRail {
          target: gridA
          on: gridA.on
          anchors.right: gridA.right
          anchors.rightMargin: 2
          anchors.top: gridA.top
          anchors.topMargin: 2
          anchors.bottom: gridA.bottom
          anchors.bottomMargin: 2
        }

        ScrollRail {
          target: gridB
          on: gridB.on
          anchors.right: gridB.right
          anchors.rightMargin: 2
          anchors.top: gridB.top
          anchors.topMargin: 2
          anchors.bottom: gridB.bottom
          anchors.bottomMargin: 2
        }

        ScrollRail {
          target: listA
          on: listA.on
          anchors.right: listA.right
          anchors.rightMargin: 2
          anchors.top: listA.top
          anchors.topMargin: 2
          anchors.bottom: listA.bottom
          anchors.bottomMargin: 2
        }

        ScrollRail {
          target: listB
          on: listB.on
          anchors.right: listB.right
          anchors.rightMargin: 2
          anchors.top: listB.top
          anchors.topMargin: 2
          anchors.bottom: listB.bottom
          anchors.bottomMargin: 2
        }

        // In miller columns only the FOCUSED column gets one. The parent
        // column is context you glance at, and a second bar beside it would
        // be two scrollbars for one cursor.
        //
        // Positioned rather than anchored to its target: root.midCol is a child of
        // the `miller` Row, so a rail anchored to it would have to live in that
        // Row too — and a Row lays its children out side by side, so the bar
        // would take a slice of width from the columns instead of floating over
        // the one it belongs to. `miller` fills this parent, so root.midCol's own x
        // is already the offset needed here.

        ScrollRail {
          target: root.midCol.view
          on: root.viewMode === "columns"
          anchors.top: millerBox.top
          anchors.topMargin: 2
          anchors.bottom: millerBox.bottom
          anchors.bottomMargin: 2
          // The frame's coordinates, not the travelling Row's: a scrollbar
          // belongs to the pane, so it holds still while the columns move.
          x: millerBox.x + root.midCol.x + root.midCol.width - width - 2
        }

        // ── the second pane ─────────────────────────────────────────
        // Deliberately plain. It shows a directory, a cursor and its columns,
        // and nothing else: no filter, no marks, no preview, no view modes.
        // Everything a pane can DO belongs to the active one, and Tab, `o` or
        // a click in here is how this side becomes that.
        // The same neutral border every other seam in this window uses. A cyan
        // one was tried and read as decoration rather than structure — cyan
        // here means "chosen", and a line that is always there is not making a
        // choice. The CHEVRON on it is cyan, which is the one thing that is.
        //
        // UNDER THE POINTER IT IS CYAN, which is the sidebar's grip exactly:
        // the seam is neutral while it is only a seam, and says so the moment
        // it is a thing you can take hold of. That is not decoration — it is
        // the line answering the cursor that has just changed shape over it.
        Rectangle {
          width: 1
          height: parent.height
          x: root.paneSplit
          visible: root.dual
          color: splitGrip.pressed || splitGrip.containsMouse
            ? Zenon.cyan : Zenon.msgBorder
        }

        // The divider, as something you can take hold of. The sidebar's grip in
        // every respect — 9px straddling a 1px line, z above the body so the
        // cursor changes over the seam, and measured in a frame that does NOT
        // move: bodyBox's own width is fixed while the split is dragged, and
        // reading the delta off the grip would be reading it against an origin
        // sliding under the pointer.
        MouseArea {
          id: splitGrip
          width: 9
          height: parent.height
          x: root.paneSplit - 4
          z: 9
          visible: root.dual
          hoverEnabled: true
          cursorShape: Qt.SizeHorCursor
          preventStealing: true

          property real grab: 0
          onPressed: (m) => { splitGrip.grab = m.x; }
          onPositionChanged: (m) => {
            if (!splitGrip.pressed || bodyBox.width <= 0) return;
            const px = splitGrip.mapToItem(bodyBox, m.x, 0).x - splitGrip.grab + 4;
            root.paneFrac = Math.max(root.paneMinFrac,
              Math.min(root.paneMaxFrac, px / bodyBox.width));
            viewSave.restart();
          }
          // back to even, the way the sidebar's grip springs back to 200
          onDoubleClicked: { root.paneFrac = 0.5; viewSave.restart(); }
        }

        // Which side the keyboard is in, as a chevron ON the divider.
        //
        // It was a hairline around the whole active half, which is a lot of
        // line for one bit of information and put a cyan rectangle around a
        // grid of pictures. The divider is already the boundary between the
        // two, so the mark belongs on it: `❮|` the left side has the keyboard,
        // `|❯` the right one does.
        //
        // Both panes still say it a second way — the inactive one's cursor is
        // an outline rather than a fill — so the chevron is the confirmation,
        // not the only clue.
        Text {
          id: paneMark
          visible: root.dual
          text: root.paneSide === 1 ? "\u276F" : "\u276E"
          color: Zenon.cyan
          font.family: Zenon.face
          font.pixelSize: 13
          y: (parent.height - height) / 2
          x: root.paneSide === 1
            ? root.paneSplit + 4 : root.paneSplit - width - 3
          z: 4
        }

        // ── the second half's chrome ────────────────────────────────
        // Its listing and its grid are PaneList/PaneGrid now, declared
        // alongside the first half's and never moved. What is left here is
        // the part that is about the half rather than about the listing: a
        // click on its empty space is still "I want to be over here", and a
        // half with nothing in it still has to say so.
        Item {
          id: otherPane
          x: root.paneX(1)
          width: root.paneW(1)
          height: parent.height
          visible: root.dual && !root.pas.active
          // Clicks only. The views underneath draw the rows; this is the
          // space between and below them.
          //
          // Above the views rather than under them, because a Flickable takes
          // the left button for its own flick and never gives it back. Gated
          // on the hover hit test so a press that IS on a row reaches the row
          // and steps across once, not twice.
          property bool overRow: false

          HoverHandler {
            id: otherWatch
            onPointChanged: {
              const v = root.otherViewMode === "grid"
                ? root.gridOf(root.pas.side) : root.listOf(root.pas.side);
              otherPane.overRow = v.indexAt(
                otherWatch.point.position.x + v.contentX,
                otherWatch.point.position.y - v.y + v.contentY) >= 0;
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: root.dual && !otherPane.overRow
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.stepOver()
          }

          // The same word at the same size as the active pane's — see the
          // note there. Two panes saying the same thing two different ways
          // reads as two different states.
          Text {
            anchors.centerIn: parent
            visible: root.dual && root.otherRows.length === 0
            text: "Empty"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 15
          }
        }

        // ── dropping onto this directory ────────────────────────────
        // ONE DropArea, and that is the fix.
        //
        // There were two, stacked on the same rectangle with the same keys: the
        // real one, and a second declared later that existed only to light up
        // the border. Later means on top, and the top DropArea is the one Qt
        // delivers to — so every drop landed on the decorative one, which had
        // no onDropped and quietly dropped it on the floor. Dragging a file
        // from artemis into terminus did nothing for exactly this reason.
        //
        // No `keys` filter either. Keys are matched against the SOURCE's
        // Drag.keys, which an application outside quickshell has no reason to
        // set — the honest test is whether what arrived carries file URLs, and
        // dropUris already checks that and ignores anything else.
        //
        // The high z keeps it above the click and wheel overlays.
        DropArea {
          id: dropHint
          anchors.fill: parent
          z: 7
          // WHERE it was dropped decides where it goes. With one pane that is
          // always here; with two, dropping on the right-hand side means the
          // right-hand side, which is most of what a second pane is for.
          // Tracked as the pointer moves so the row under it can light up:
          // a drop that is about to go INTO something has to say which thing,
          // or the only honest reading is "somewhere in this pane".
          onPositionChanged: (d) => root.dropDir = root.dropDirAt(d.x, d.y)
          onExited: root.dropDir = ""

          onDropped: (d) => {
            const pane = root.dual && (d.x < root.activePaneX
                                       || d.x > root.activePaneX + root.activePaneW)
              ? root.otherCwd : root.cwd;
            const into = root.dropDir !== "" ? root.dropDir : pane;
            root.dropDir = "";
            root.dropUris(root.urlsFrom(d), d.proposedAction, into,
                          dropHint, d.x, d.y);
          }
        }

        Rectangle {
          anchors.fill: parent
          // Not while a directory is the target: two things lit at once says
          // the drop is going to both.
          visible: dropHint.containsDrag && root.dropDir === ""
          color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.07)
          border.width: 2
          border.color: Zenon.cyan
          z: 8
        }

        // ── the drag box ────────────────────────────────────────────
        // A DragHandler, not a MouseArea. Every row already has a MouseArea
        // for its click, and a MouseArea laid over them would either swallow
        // those clicks or never see the press; a pointer handler can sit above
        // the lot and only TAKE the grab once the pointer has actually moved,
        // which is exactly the difference between a click and a drag.
        DragHandler {
          id: band
          target: null
          acceptedButtons: Qt.LeftButton
          // Off while the pointer is on an item, because then a drag is that
          // item being dragged. Anywhere else — the gap under the last row, the
          // empty half of a grid — the band is what a drag means, and it has to
          // outrank the ListView's own flick to get the gesture.
          //
          // `band.active ||` is what makes it survive the drag. hoverRow is a
          // live property, so the moment the pointer crossed onto a tile this
          // went false and the handler was disabled mid-gesture — in the grid
          // that is the very first row, which is why the box could not be
          // dragged past it. Once the band has the grab it keeps it.
          //
          // `overBandZone` is the third condition, and it is about COLUMNS
          // view: of its three panes only the middle one holds rows this
          // window can select. A press in the preview started a band that
          // could never select anything and drew a box over a picture to say
          // so; the left-hand pane is the parent directory and is no better.
          // railHOVER, not only railDragging. The rail disarms the band by
          // saying it has the pointer, and the row and tile handlers both read
          // that — this one only read the drag half. railDragging is set on
          // PRESS, and a DragHandler declaring CanTakeOverFromAnything has
          // already taken the gesture by then, so the guard arrived too late
          // to stop anything. Below the last tile in a grid there is no row
          // under the pointer, so the band was armed right where the scrollbar
          // lives — and grabbing the bar at the bottom drew a selection box
          // instead of scrolling.
          enabled: band.active
            || (!root.hoverRow && root.overBandZone
                && !root.railHover && !root.railDragging
                && !root.modal)
          grabPermissions: PointerHandler.CanTakeOverFromAnything

          // Where a band is allowed to be drawn: the whole body in list and
          // grid view, the middle column alone in columns view.
          readonly property real zoneL: root.activePaneX
            + (root.viewMode === "columns" ? root.midCol.x : 0)
          readonly property real zoneR: root.activePaneX
            + (root.viewMode === "columns"
              ? root.midCol.x + root.midCol.width : root.activePaneW)

          // Clamped to that zone. bodyBox does not clip, so a drag carried
          // past its left edge drew the selection box out over the sidebar —
          // the rectangle was honest about the pointer and wrong about what it
          // was selecting from, since there is nothing selectable over there.
          readonly property real x1: Math.max(band.zoneL,
            Math.min(centroid.pressPosition.x, centroid.position.x))
          readonly property real y1: Math.max(0,
            Math.min(centroid.pressPosition.y, centroid.position.y))
          readonly property real x2: Math.min(band.zoneR,
            Math.max(centroid.pressPosition.x, centroid.position.x))
          readonly property real y2: Math.min(bodyBox.height,
            Math.max(centroid.pressPosition.y, centroid.position.y))

          // What was already ticked when the drag began, so dragging ADDS to a
          // selection instead of replacing it — and so releasing without
          // having moved cannot wipe what you had.
          property var base: ({})

          // The rectangle as last drawn. Kept because the centroid collapses
          // the instant the button comes up, and the box has to still have a
          // shape to fade out from.
          property rect held: Qt.rect(0, 0, 0, 0)

          onActiveChanged: {
            if (active) {
              band.base = Object.assign({}, root.marked);
              band.lastLo = -1;
              band.lastHi = -1;
              // COLLAPSE THE OLD RECTANGLE FIRST.
              //
              // `held` survives a release on purpose, so the box has a shape
              // to fade out from — but it also survived into the NEXT gesture,
              // and opacity goes to 1 the instant the band activates. So a
              // band that activated and had not yet been dragged anywhere drew
              // the PREVIOUS box, at the previous place, for a frame.
              //
              // That is the ghost: press on a selected row and move fast, and
              // hoverRow has not caught up, so this handler — which may take
              // the grab from anything — wins the gesture for a moment before
              // the row drag claims it, just long enough to flash the last
              // rectangle back onto the screen.
              band.held = Qt.rect(band.x1, band.y1, 0, 0);
            }
            // nothing to apply on release: the last centroid already did, and
            // the collapsed one would select a single row
          }
          // The last row range applied, so a move that stays inside the same
          // rows does not rebuild the selection. Dragging across a tall list
                    // fires a centroid change per pixel and only a fraction of
          // them cross a row boundary.
          property int lastLo: -1
          property int lastHi: -1

          onCentroidChanged: {
            if (!band.active) return;
            // (see the TapHandler below for the click, as opposed to the drag)
            const w = band.x2 - band.x1, h = band.y2 - band.y1;
            // Only remember a rectangle with a shape. On release the centroid
            // collapses to a point while `active` is still true for one more
            // event, and letting that through overwrote the held rect with a
            // 0x0 one — so the fade ran on something invisible, which looked
            // exactly like no fade at all.
            if (w > 2 && h > 2)
              band.held = Qt.rect(band.x1, band.y1, w, h);
            root.applyBand(band.x1, band.y1, band.x2, band.y2, band.base);
          }
        }

        Rectangle {
          // Drawn from the HELD rectangle, not the live centroid, so releasing
          // leaves it where it was and it fades from there rather than
          // collapsing to a point on the way out.
          // A rectangle with no shape is not drawn at all, so a stale one can
          // never appear and the fade only ever runs on something real.
          visible: opacity > 0.01 && band.held.width > 2 && band.held.height > 2
          opacity: band.active ? 1 : 0
          // Slower on the way out than a normal transition: the box is being
          // dismissed rather than moved, and a 140ms disappearance reads as a
          // cut rather than a fade.
          Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }
          x: band.held.x
          y: band.held.y
          width: band.held.width
          height: band.held.height
          radius: 5
          color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
          border.width: 1
          border.color: Zenon.cyan
          z: 5
        }

        // Ctrl+wheel zooms.
        //
        // A MouseArea, not a WheelHandler, and that is not a preference: a
        // WheelHandler receives NOTHING here. Verified with a logging handler
        // placed inside the very ListView those same wheel events were visibly
        // scrolling, and again on an overlay above all three views — zero
        // events in both, while a console.log elsewhere in this file logged
        // fine. MouseArea.onWheel does get them.
        //
        // NoButton is what makes it safe to lay over everything: it never takes
        // a press, so clicks, drags and the rubber band are untouched. A wheel
        // without ctrl is declined and falls through to the view underneath,
        // which goes on scrolling exactly as before.
        MouseArea {
          anchors.fill: parent
          z: 6
          acceptedButtons: Qt.NoButton
          onWheel: (w) => {
            if (w.modifiers & Qt.ControlModifier) {
              w.accepted = true;
              root.zoomBy(w.angleDelta.y > 0 ? 0.1 : -0.1);
              return;
            }
            // A PLAIN WHEEL, HANDLED RATHER THAN DECLINED.
            //
            // Flickable's own wheel step is not settable from QML — it comes
            // from the platform's scroll-lines setting — and three rows a
            // notch is a lot of wheel for a long directory. Taking the event
            // and moving the view is the only place the distance can be
            // decided, so it is decided here.
            const v = root.wheelTarget(w.x, w.y);
            if (!v) { w.accepted = false; return; }
            const notches = w.angleDelta.y / 120;
            if (notches === 0) { w.accepted = false; return; }
            w.accepted = true;
            root.wheelScroll(v, -notches * root.wheelStep);
          }
        }

        // Whether the pointer is over empty space, tracked by something that
        // can never steal a press.
        //
        // A HoverHandler only ever handles hover, so unlike a MouseArea it
        // cannot take the press that a row's DragHandler needs — and taking
        // that press is exactly what the overlay below was doing, which is why
        // dragging a file out of terminus produced no drag at all. Declining the
        // press with `accepted = false` was not enough: by then the overlay had
        // already won the gesture.
        //
        // It asks the view's own indexAt rather than reading hoverRow, for the
        // reason rowUnder exists.
        //
        // AND IT ASKS ONLY WHEN THE ANSWER COULD HAVE CHANGED. This fires on
        // every motion event — on a 180Hz panel that is a hit test against a
        // view, per frame, for a boolean that changes when you cross a row
        // boundary and at no other time. The last point is remembered and a
        // move of less than a pixel in both axes is not worth asking about.
        HoverHandler {
          id: emptyWatch
          property real lastX: -1
          property real lastY: -1
          //
          // The throttle remembers an answer, so anything else that could
          // change it has to say so. A pane switch is the one: the pointer has
          // not moved, but which half is active has, and in column view that
          // decides whether it is over anything at all.
          readonly property int activeSide: root.act.side
          onActiveSideChanged: {
            emptyWatch.lastX = -1;
            emptyWatch.lastY = -1;
            if (emptyWatch.hovered) emptyWatch.settle();
          }

          function settle() {
            const px = emptyWatch.point.position.x;
            const py = emptyWatch.point.position.y;
            if (Math.abs(px - emptyWatch.lastX) < 1
             && Math.abs(py - emptyWatch.lastY) < 1) return;
            emptyWatch.lastX = px;
            emptyWatch.lastY = py;
            root.overEmpty = root.rowUnder(px, py) < 0;
            // The rubber band cannot ask where the pointer is — a DragHandler
            // has a position only once it is already dragging — so the hover
            // that is watching anyway answers for it.
            root.overBandZone = px >= band.zoneL && px <= band.zoneR;
          }
          onPointChanged: emptyWatch.settle()
        }

        // A click on nothing: right opens the menu, left means "none of them".
        //
        // ABOVE the views, not below them, and that one word was the whole bug.
        // At z:-1 this sat underneath three Flickables, and a Flickable takes
        // the left button for its own flick and never gives it back — so the
        // deselect could not fire. RIGHT clicks did arrive, because a Flickable
        // ignores those, which is why the paste-here menu worked all along and
        // hid the fact that its other half never did.
        //
        // Two things stop it swallowing what it should not: `enabled` turns it
        // off whenever the pointer is on a row, so rows get their own clicks;
        // and the rubber band is a DragHandler declaring CanTakeOverFromAnything,
        // so it still steals the press the moment a click becomes a drag.
        MouseArea {
          anchors.fill: parent
          z: 5
          // Not present at all over a row, so a row keeps every press it is
          // entitled to — including the one that becomes a drag out of terminus.
          enabled: root.overEmpty
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => {
            // FIRST, so both of the lines below are about the half that was
            // clicked rather than the half that had the keyboard.
            root.comeOverAt(m.x);
            if (m.button === Qt.RightButton) { menu.openHere(bodyBox, m); return; }
            if (Object.keys(root.marked).length > 0) root.act.marked = {};
            content.forceActiveFocus();
          }
        }

        // Centred in the ACTIVE PANE, not in the body. With two panes open the
        // body is both of them, so an empty directory on one side put its
        // label in the middle of the window — half of it hanging over the
        // other pane's rows, saying "Empty" about a listing that was not.
        // CENTRED ON THE LISTING, WHICH IS NOT ALWAYS THE PANE.
        //
        // In list and grid the listing IS the pane, so the middle of one is
        // the middle of the other. Miller is three columns and only the middle
        // one holds these rows — so "Empty" sat in the centre of all three,
        // which puts it over the preview of a directory that is not the empty
        // one and a third of a pane away from the column it is about.
        //
        // It travels with the columns too: miller.x is the step animation, so
        // the label slides in with the column it belongs to rather than
        // sitting still while that column moves out from under it.
        Text {
          id: emptyLabel
          x: root.viewMode === "columns"
            // NOT miller.x. That is written by an XAnimator on the render
            // thread, which does not notify QML bindings as it goes — so this
            // read it frozen at the step's STARTING offset, a quarter of a
            // pane to one side, and then snapped when the animation ended.
            // The label appeared over the third column and jumped to the
            // second. Measured from the column's resting place instead, and
            // the fade below carries the change.
            ? millerBox.x + root.midCol.x + (root.midCol.width - width) / 2
            : root.activePaneX + (root.activePaneW - width) / 2
          y: (parent.height - height) / 2
          // IT WAITS FOR THE COLUMNS, THEN ARRIVES ON ITS OWN.
          //
          // Riding miller's fade was close but not it: the label came in
          // WITH the tree, while the tree was still travelling, and its x is
          // measured off the middle column's resting place — so it sat still
          // in the middle of a pane that had not stopped moving yet.
          //
          // Held at nothing for the whole step and eased in once the columns
          // are down. "Empty" is an answer about where you have arrived, and
          // it can wait until you have.
          //
          // Not a child of miller either, because miller SLIDES: this belongs
          // at the column's resting place rather than wherever it is mid-step.
          //
          // AND NOT WHILE A DIRECTORY IS ARRIVING. `view.length === 0` is a
          // complete answer to "is this empty" and a wrong one for the window
          // between asking for a directory and its rows landing: enter() holds
          // `arriving` across exactly that gap, for exactly this reason, and
          // the label was not asking. Caught on a step BACK out of a folder —
          // the columns had already rotated and stopped, the new listing had
          // not arrived, and "Empty" flashed over a column that was about to
          // be full. Frame-accurate from a 60fps capture: two rows drawn in
          // the middle column with the label underneath them.
          readonly property bool wanted: root.view.length === 0
            && !millerAnim.running && !root.arriving
          // ── IT FADES IN, IT DOES NOT FADE OUT ──────────────────────
          // The rows of the directory you step back into land in a single
          // frame; a fade spent the next seven dissolving this ON TOP of them.
          // Measured with the label temporarily drawn in red: still visible
          // over a populated column a frame after the step, which is the
          // flicker — an animation playing inside a directory it is not about.
          //
          // A STATE AND A ONE-WAY TRANSITION, not a Behavior that switches
          // itself off. `enabled: wanted` on a Behavior is a race: the opacity
          // binding and the enabled binding both fall off `wanted`, and
          // nothing says which is re-evaluated first. A transition with `to`
          // simply has no rule for the other direction, so leaving is instant
          // by construction rather than by winning an ordering.
          opacity: 0
          visible: emptyLabel.opacity > 0.01

          states: State {
            name: "shown"
            when: emptyLabel.wanted
            PropertyChanges { emptyLabel.opacity: 1 }
          }
          transitions: Transition {
            to: "shown"
            NumberAnimation {
              property: "opacity"
              duration: Zenon.fast
              easing.type: Zenon.travelEase
            }
          }
          text: root.query !== "" ? "No matches" : "Empty"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 15
        }
        }
      }


      // ── the picker's own footer ───────────────────────────────────
      // Only while a portal request is open. It is deliberately the widest
      // thing on screen and sits directly above the hints: an application is
      // blocked waiting on this, so what terminus is being asked for has to be
      // impossible to miss.
      Rectangle {
        id: portalBar
        width: parent.width
        height: root.picking ? 44 : 0
        visible: height > 0
        clip: true
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)

        // The neutral seam every other strip in this window uses. A cyan rule
        // here was the loudest line on the surface, for a bar that is already
        // tinted and already says what it is.
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.msgBorder
        }

        Text {
          id: portalLabel
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: root.portalTitle
          color: Zenon.cyan
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 15
        }

        // save requests need a name, and it is the only thing being chosen
        Rectangle {
          id: saveBox
          anchors.left: portalLabel.right
          anchors.leftMargin: 14
          anchors.right: portalButtons.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          height: 26
          radius: 4
          visible: !!root.portal && root.portal.save
          color: Zenon.selBg
          border.width: 1
          border.color: Terminus.nameError(saveField.text) === ""
            ? Zenon.msgBorder : Zenon.red

          TextInput {
            id: saveField
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Zenon.white
            selectionColor: Zenon.cyan
            font.family: Zenon.face
            font.pixelSize: 14
            clip: true
            Keys.onReturnPressed: (e) => { e.accepted = true; root.portalConfirm(); }
            Keys.onEscapePressed: (e) => { e.accepted = true; root.portalCancel(); }
            // Tab goes back to the listing, so the two halves of the dialog
            // are one ring rather than a field you can get into and not out of.
            Keys.onPressed: (e) => {
              if (e.key !== Qt.Key_Tab && e.key !== Qt.Key_Backtab) return;
              e.accepted = true;
              content.forceActiveFocus();
            }
          }
        }

        // what a confirm would actually hand over, spelled out, because the
        // difference between "this directory" and "the directory under the cursor"
        // is invisible otherwise
        Text {
          anchors.left: portalLabel.right
          anchors.leftMargin: 14
          anchors.right: portalButtons.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          visible: !!root.portal && !root.portal.save
          elide: Text.ElideMiddle
          text: {
            const c = root.portalChoice;
            if (c.length === 0) return "nothing selected";
            if (c.length === 1) return c[0];
            return c.length + " selected";
          }
          color: root.portalChoice.length === 0 ? Zenon.muted : Zenon.white
          font.family: Zenon.face
          font.pixelSize: 13
        }

        Row {
          id: portalButtons
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          DialogButton {
            label: "Cancel"
            ink: Zenon.muted
            onClicked: root.portalCancel()
          }

          DialogButton {
            label: (!!root.portal && root.portal.save) ? "Save" : "Choose"
            ink: Zenon.cyan
            ready: root.portalChoice.length > 0
            primary: root.portalChoice.length > 0
            onClicked: root.portalConfirm()
          }
        }
      }

    }

    // ── THE HEADING STRIP, PAINTED OVER THE BODY RATHER THAN IN IT ────────
    // With the window split, colHeads collapses to nothing and each half draws
    // its own heading bar INSIDE the body — and the body is the layer that goes
    // soft behind a sheet. A black ground painted in there is blurred together
    // with the rows underneath and comes out a grey band: a lighter strip
    // between a black bar and a black card, which is the whole of what "the
    // header is not opaque" looks like from the outside. Measured at (4,5,5)
    // with the ground in the pane and (0,0,0) with it here.
    //
    // A SIBLING OF THE CHROME, not a child of it: the Column would lay it out
    // as another strip and push the body down by its height. It is positioned
    // against the same three heights the Column stacks, so it lands exactly on
    // the heading bars it is covering and moves with them.
    //
    // ONE PER HALF rather than one across the window, because only a half that
    // is showing a LIST has a heading bar — a single strip would have laid a
    // black band across the top row of a grid beside it.
    Repeater {
      model: 2

      delegate: Rectangle {
        required property int index

        // The sidebar's width, because paneX is measured from the body's left
        // edge and the body begins where the sidebar ends.
        x: side.width + root.paneX(index)
        width: root.paneW(index)
        y: tabStrip.height + crumbBar.height + colHeads.height
        height: root.paneHeadH(index)
        color: Zenon.black
        opacity: root.sheetInk
        visible: height > 0 && opacity > 0.01
      }
    }


    // ── properties ────────────────────────────────────────────────────
    // What the listing cannot fit: the whole path, the owner, the exact byte
    // count, and for a selection the total. `stat` is asked once for the set,
    // the same way the search results are — one process, not one per file.
    Rectangle {
      id: props
      anchors.fill: parent
      z: 13
      visible: opacity > 0.01
      opacity: props.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: props.open ? propsSheet.slideIn : propsSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      property var rows: []
      property string owner: ""
      // -1 while du is still walking, so the row can say so rather than
      // showing a zero that looks like an answer
      property real walked: -1
      // -1 until the walk answers, the same sentinel `walked` uses
      property int files: -1
      property int dirs: -1
      // "" = never asked, "…" = running, otherwise the digest or an error
      property string checksum: ""
      // dimensions and format, for an image; null for anything else
      property var imageInfo: null

      readonly property bool many: props.rows.length > 1
      readonly property int total: {
        let n = 0;
        for (const r of props.rows) if (!r.isDir) n += r.size;
        return n;
      }

      function ask() {
        const sel = root.acting();
        if (sel.length === 0) return;
        props.show(sel);
      }

      // Properties of THE DIRECTORY YOU ARE IN, which is what a right click on
      // empty space is asking about — there is no row selected and the one the
      // cursor happens to be on is not the answer.
      //
      // It needs a row object and the listing has none: the listing is of this
      // directory's CHILDREN. So one is made the same way a search result's
      // is, out of `stat` — the same command, parser and enrich the results
      // path already uses, so the card gets a row indistinguishable from one
      // that came out of a listing.
      function askPath(path) {
        if (path === "" || hereProc.running) return;
        props.wantPath = path;
        hereProc.command = Terminus.statArgv([path]);
        hereProc.running = true;
      }

      property string wantPath: ""

      // One string, because "0 files · 0 directories" and "counting…" are
      // the same row in two states, and deciding which at each call site is how
      // the two shapes of this card drift apart.
      function countText() {
        if (props.files < 0 || props.dirs < 0) return "counting\u2026";
        const f = props.files + (props.files === 1 ? " file" : " files");
        const d = props.dirs + (props.dirs === 1 ? " directory" : " directories");
        return f + "  ·  " + d;
      }

      function show(sel) {
        props.rows = sel;
        props.owner = "";
        props.walked = -1;
        props.files = -1;
        props.dirs = -1;
        props.open = true;
        // only when there is a directory in the set: for plain files the size
        // is already known and du would be a process for nothing
        if (sel.some((r) => r.isDir)) {
          sizeProc.command = ["sh", "-c",
            Terminus.sizeCommand(sel.map((r) => r.path))];
          sizeProc.running = true;
          countProc.command = ["sh", "-c",
            Terminus.countCommand(sel.map((r) => r.path))];
          countProc.running = true;
        }
        ownerProc.command = ["sh", "-c",
          "stat -c '%U:%G' -- " + Strings.shellQuote(sel[0].path) + " 2>/dev/null"];
        ownerProc.running = true;

        // Dimensions come for free — identify reads a header, not a file — so
        // an image simply has them. A CHECKSUM does not: sha256 over a few
        // gigabytes takes real time, so it is a button, and only the digest you
        // asked for is ever computed.
        props.checksum = "";
        props.imageInfo = null;
        // The thumbnail panel above shows a video's frame or a track's cover
        // from the same cache the grid uses — which may not have been asked
        // for yet if you have only ever seen this directory as a list.
        const one = props.many ? null : sel[0];
        if (one && !one.isDir && !root.thumbFile[one.path]
            && (Terminus.isVideo(one.name) || Terminus.isAudio(one.name))
            && !thumbProc.running) {
          root.thumbJobs = [{ src: one.path,
                              kind: Terminus.isVideo(one.name) ? "v" : "a" }];
          thumbProc.command = ["sh", "-c", Thumbs.generate(root.thumbJobs)];
          thumbProc.running = true;
        }
        if (!props.many && !sel[0].isDir && Terminus.isImage(sel[0].name)) {
          imageProc.command = ["sh", "-c", Terminus.imageInfoCommand(sel[0].path)];
          imageProc.running = true;
        }
      }

      Process {
        id: hereProc
        stdout: StdioCollector {
          id: hereOut
          waitForEnd: true
          onStreamFinished: {
            const rows = root.enrich(Terminus.parseStat(hereOut.text));
            if (rows.length === 0) {
              root.warn("could not read " + Terminus.basename(props.wantPath));
              return;
            }
            props.show(rows);
          }
        }
      }

      function computeChecksum() {
        const r = props.rows[0];
        if (!r || r.isDir || sumProc.running) return;
        props.checksum = "\u2026";
        sumProc.command = ["sh", "-c", Terminus.checksumCommand(r.path)];
        sumProc.running = true;
      }

      InputShield {
        onClicked: { props.open = false; content.forceActiveFocus(); }
      }

      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      // ── WHAT THE PANEL SAYS, AS A LIST ────────────────────────────────
      // Hoisted off the Repeater so the CARD can measure it. A panel that is
      // as wide as its longest value has to know what its values are before it
      // has drawn any of them, and a model written inline in the view is not
      // available to anything else.
      // 16, which is what a value is drawn at — a measurement taken at the
      // wrong size is a card that fits nothing.
      FontMetrics {
        id: propFm
        font.family: Zenon.face
        font.pixelSize: 16
      }

      readonly property var facts: {
                  const r = props.rows[0];
                  if (!r) return [];
                  if (props.many) {
                    let dirs = 0;
                    for (const x of props.rows) if (x.isDir) dirs++;
                    return [
                      ["items", props.rows.length + " (" + dirs + " directories)"],
                      ["total size", props.walked < 0
                        ? (dirs > 0 ? "measuring\u2026"
                            : Terminus.formatSize(props.total) + "  ·  " + props.total + " bytes")
                        : Terminus.formatSize(props.walked) + "  ·  " + props.walked + " bytes"],
                      ["location", Terminus.dirname(r.path)]
                    ].concat(dirs > 0 ? [["contains", props.countText()]] : []);
                  }
                  // no "name" row: it is the card's own title now
                  return [
                    ["location", Terminus.dirname(r.path)],
                    ["type", r.isDir ? "directory"
                      : (r.isLink ? "symbolic link"
                        : (Terminus.categoryOf(r.name) || (r.isExec ? "executable" : "file")))],
                    ["size", r.isDir
                      ? (props.walked < 0 ? "measuring\u2026"
                          : Terminus.formatSize(props.walked) + "  ·  " + props.walked + " bytes")
                      : Terminus.formatSize(r.size) + "  ·  " + r.size + " bytes"],
                    ["modified", Terminus.formatTime(r.mtime)],
                    ["owner", props.owner === "" ? "…" : props.owner],
                    ["permissions", ("000" + (r.mode & 511).toString(8)).slice(-3)
                      + "  " + Terminus.modeString(r.mode)]
                  ].concat(
                    // What is inside it, for a directory — the natural companion
                    // to the size two rows up, and the one thing this card could
                    // not tell you about a folder.
                    r.isDir ? [["contains", props.countText()]] : [],
                    props.imageInfo
                      ? [["image", props.imageInfo.dims + "  \u00b7  "
                          + props.imageInfo.format + "  \u00b7  "
                          + props.imageInfo.depth + "  \u00b7  "
                          + props.imageInfo.colorspace]]
                      : [],
                    r.isDir ? []
                      : [["sha256", props.checksum === "" ? "click to compute"
                          : props.checksum]]);
      }

      Sheet {
        id: propsSheet
        shown: props.open
        fromTop: tabStrip.height + crumbBar.height
        // ── AS WIDE AS WHAT IT IS SAYING ──────────────────────────────
        // A fixed 760 was right for a photograph with a long path beside it
        // and wrong for everything else: a directory has no picture and six
        // short facts, and sat in a card with a third of it empty.
        //
        // MEASURED, not guessed. FontMetrics.advanceWidth is a method a
        // binding can CALL — TextMetrics is an object you set and then read,
        // which is no use inside a loop over the rows — so the widest value is
        // asked for directly. The same approach the send picker uses to size
        // itself around the deepest path it is offering.
        //
        // The floor stops a one-line panel from being a slot; the ceiling
        // stops a 4000-character path from being the whole screen, and elide
        // takes over there, which is what elide is for.
        readonly property real factsW: {
          let w = 0;
          const rows = props.facts;
          for (let i = 0; i < rows.length; i++) {
            const t = propFm.advanceWidth(String(rows[i][1]));
            if (t > w) w = t;
          }
          // the row's own layout: 18 of padding, the 118 label column, 12 of
          // spacing, the value, and 18 of padding again
          return 18 + 118 + 12 + w + 18;
        }

        cardW: Math.max(420, Math.min(760,
          propShotBox.width + (props.many ? 0 : 10) + propsSheet.factsW))
        cardH: propsCol.implicitHeight

        Column {
          id: propsCol
          width: parent.width

          // The caption band stood here. It is drawn on the bar now — see
          // sheetBarHead — because a sheet says what it is where it hangs from.
          // Its own air stays: the sheet adds none, so a card whose first row
          // does not carry any has to say so.
          Item { width: 1; height: 10 }

          // picture on the left, facts on the right
          Item {
            id: propBody
            width: parent.width
            height: Math.max(props.many ? 0 : propShotBox.height + 4,
                             propFacts.implicitHeight)

            // What it LOOKS like, beside what it is.
            //
            // A picture or a video shows itself; a font shows its own A; anything
            // else shows the glyph the listing gives it, which is at least the
            // mark you picked the row out by. A multi-selection shows nothing at
            // all — there is no single thing to be a picture of, and the first
            // item's thumbnail standing in for eleven files would be a small lie
            // at the top of a panel of facts.
            //
            // Down the LEFT rather than across the top: the rows beside it are a
            // label column and a value column, and a picture over them pushed
            // every fact half a panel further down for no reason. On the left it
            // sits in the margin the labels already leave.
              Item {
                id: propShotBox
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter

                // ── A PICTURE IS NOT A GLYPH, AND NEED NOT BE ITS SIZE ──
                // Both stand here, so both were 96 — the size a 56px glyph
                // wants to sit in with air around it, and a photograph shown at
                // 88 on its long edge is a stamp. They answer different
                // questions: the glyph is a MARK, the one you picked the row
                // out by, and only has to be recognisable; the thumbnail is the
                // thing itself, and this is the one panel where you look AT it.
                //
                // AS TALL AS THE FACTS BESIDE IT, which is the one measurement
                // in this panel that means anything — the picture and the
                // column of figures are the two halves of the answer, so they
                // are the same height and the panel is a rectangle rather than
                // a picture with a column hanging off it.
                //
                // Safe to measure against: propFacts' rows are a fixed 28 each,
                // so its implicitHeight is a row count and does not depend on
                // the width this box leaves it. Bound the other way round it
                // would be a loop.
                readonly property int glyphBox: 96
                readonly property real shotH: Math.max(88,
                  propFacts.implicitHeight)
                // A ceiling for panoramas: 2560x1080 as tall as the facts
                // would still be half the card wide and crowd the figures.
                readonly property real maxW: 320

                // The box IS the picture, so the facts start right beside it
                // whatever shape it turned out to be.
                width: props.many ? 0
                  : (propShotClip.visible ? propShotClip.width
                                          : propShotBox.glyphBox)
                height: propShotClip.visible ? propShotClip.height
                                             : propShotBox.glyphBox
                visible: !props.many

              ClippingRectangle {
                id: propShotClip
                anchors.centerIn: parent
                visible: propShot.status === Image.Ready
                color: "transparent"
                radius: 5

                // sized from the decoded source, never from paintedWidth — the
                // note over the preview pane's thumbClip has the reason
                readonly property real ar:
                  propShot.implicitWidth > 0 && propShot.implicitHeight > 0
                    ? propShot.implicitWidth / propShot.implicitHeight : 1
                // The facts' height, unless that would make it wider than
                // the ceiling — then the width decides and the height follows.
                readonly property real fitH: Math.min(propShotBox.shotH,
                  propShotBox.maxW / Math.max(0.01, propShotClip.ar))
                width: Math.max(1, propShotClip.fitH * propShotClip.ar)
                height: Math.max(1, propShotClip.fitH)

                Image {
                  id: propShot
                  anchors.fill: parent
                  source: {
                    if (props.many || !props.open) return "";
                    const r = props.rows[0];
                    if (!r || r.isDir) return "";
                    if (Terminus.isVideo(r.name) || Terminus.isAudio(r.name)) {
                      return root.thumbFile[r.path]
                        ? "file://" + root.thumbFile[r.path] : "";
                    }
                    return Terminus.isImage(r.name) ? "file://" + r.path : "";
                  }
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  // Decoded at twice the drawn size, so the panel is sharp on
                  // a scaled display and has something to work with if the box
                  // grows again.
                  sourceSize.width: 384
                  sourceSize.height: 384
                }
              }

              FontLoader {
                id: propFace
                source: {
                  if (props.many || !props.open) return "";
                  const r = props.rows[0];
                  return r && !r.isDir && Terminus.isFont(r.name) ? "file://" + r.path : "";
                }
              }

              Text {
                anchors.centerIn: parent
                visible: !propShotClip.visible
                readonly property bool specimen: propFace.status === FontLoader.Ready
                text: {
                  const r = props.rows[0];
                  if (!r) return "";
                  return specimen ? "Ag" : r.glyph;
                }
                color: {
                  const r = props.rows[0];
                  return r ? root.inkFor(r) : Zenon.muted;
                }
                font.family: specimen ? propFace.font.family
                  : Zenon.face
                font.pixelSize: 56
              }
          }


            Column {
              id: propFacts
              anchors.left: props.many ? parent.left : propShotBox.right
              anchors.leftMargin: props.many ? 0 : 10
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: props.facts

              delegate: Row {
                required property var modelData
                width: propFacts.width
                height: 28
                leftPadding: 18
                rightPadding: 18
                spacing: 12

                Text {
                  width: 118
                  height: parent.height
                  horizontalAlignment: Text.AlignRight
                  verticalAlignment: Text.AlignVCenter
                  text: modelData[0]
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 16
                }

                Text {
                  id: propValue
                  width: propFacts.width - 118 - 48
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  text: modelData[1]
                  elide: Text.ElideMiddle
                  // The one row you can act on says so by looking like a link
                  // until it has an answer.
                  readonly property bool askable:
                    modelData[0] === "sha256" && props.checksum === ""
                  color: propValue.askable
                    ? (sumHov.hovered ? Zenon.cyan : Zenon.keyInk) : Zenon.white
                  font.family: Zenon.face
                  font.pixelSize: 16

                  HoverHandler { id: sumHov; enabled: propValue.askable }

                  MouseArea {
                    anchors.fill: parent
                    enabled: propValue.askable
                    onClicked: props.computeChecksum()
                  }
                }
              }
            }

            }
          }

          Item { width: 1; height: 10 }

          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.msgBorder
          }

          Item {
            width: parent.width
            height: 46

            DialogButton {
              anchors.centerIn: parent
              label: "Close"
              ink: Zenon.cyan
              primary: true
              onClicked: { props.open = false; content.forceActiveFocus(); }
            }
          }
        }
      }
    }

    // ── what the prefix key is waiting for ────────────────────────────
    // Yazi shows the continuations of a half-typed sequence along the bottom,
    // which is the difference between a sequence you remember and one you
    // have to look up. Same list, same place. It appears with the prefix and
    // goes the moment the next key lands or the timeout gives up.
    Rectangle {
      id: which
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: content.pending === "" ? 0 : whichFlow.implicitHeight + 20
      // one line, so the bar is a fixed depth whichever prefix is pending
      visible: height > 0
      clip: true
      z: 7
      // THE SHELL'S HINT-BAR GROUND, which every popup with a row of keys
      // along its bottom wears. This strip had its own answer — 86% black with
      // headBg over it — and 86% is not opaque: at a `g` pressed over a file
      // of Lua the code behind it read straight through the hints, which is
      // the exact thing the alpha was there to stop.
      color: Zenon.hintBg
      Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        // the divider every other strip in this window is separated by
        color: Zenon.msgBorder
      }

      readonly property var entries:
        content.pending === "" ? [] : (content.sequences[content.pending] || [])

      // ── laid out by hand, so it can WRAP AND STILL BE CENTRED ────────
      //
      // This was a single Row that clipped at both ends when the set was wider
      // than the window — the reasoning being that a Flow can wrap but cannot
      // centre the lines it wraps, so a narrow window would trade a clipped
      // strip for a ragged block. Both halves of that are true, and clipping
      // is still the worse of the two: a hint you cannot see is not a hint.
      //
      // So the break points are worked out here rather than left to a Flow,
      // and each line is its own centred Row. FontMetrics measures the same
      // two fonts the delegates draw with, so the widths it adds up are the
      // widths that get drawn — the chip's padding is the one constant that
      // has to agree with KeyChip, and it is written down in both places.
      readonly property real chipPad: Math.round(13 * 1.15)
      readonly property real gap: 22
      readonly property real entryGap: 8

      FontMetrics {
        id: chipFm
        font.family: Zenon.face
        font.pixelSize: 13
      }
      FontMetrics {
        id: labelFm
        font.family: Zenon.face
        font.pixelSize: 15
      }

      function entryText(e) {
        return (typeof e[1] === "function") ? e[1]() : e[1];
      }
      function keyText(e) { return e[0] === " " ? "space" : e[0]; }

      function entryWidth(e) {
        return chipFm.advanceWidth(which.keyText(e)) + which.chipPad
          + which.entryGap + labelFm.advanceWidth(which.entryText(e));
      }

      // The entries grouped into the lines they will be drawn on. Greedy, which
      // is what you want here: the order is the order the keys are listed in,
      // so a line break must never reorder them to pack better.
      readonly property var lines: {
        const avail = which.width - 32;
        const out = [];
        let cur = [];
        let w = 0;
        for (const e of which.entries) {
          const ew = which.entryWidth(e);
          if (cur.length > 0 && w + which.gap + ew > avail) {
            out.push(cur);
            cur = [];
            w = 0;
          }
          w += (cur.length > 0 ? which.gap : 0) + ew;
          cur.push(e);
        }
        if (cur.length > 0) out.push(cur);
        return out;
      }

      Column {
        id: whichFlow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10
        spacing: 6

        Repeater {
          model: which.lines

          delegate: Row {
            required property var modelData
            anchors.horizontalCenter: parent.horizontalCenter
            // wider apart than the two halves of one entry, so a line reads as
            // separate hints rather than one long sentence
            spacing: which.gap

            Repeater {
              model: parent.modelData

              delegate: Row {
                required property var modelData
                spacing: which.entryGap

                KeyChip {
                  anchors.verticalCenter: parent.verticalCenter
                  fontSize: 13
                  // The KEY as something you can read, which is not always the
                  // key itself: the entry that opens the path bar is bound to a
                  // space, and a space drawn in the key column is a gap with a
                  // label floating after it. The binding stays a space — this
                  // is the name of it, not the match.
                  label: which.keyText(modelData)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // Static for nearly every entry, and worked out on the spot
                  // for the ones whose meaning depends on what the cursor is on.
                  text: which.entryText(modelData)
                  // same ink and the same weight as the path bar's current
                  // segment, because they are the same kind of statement
                  color: root.crumbInk
                  font.family: Zenon.face
                  font.weight: Font.Medium
                  font.pixelSize: 15
                }
              }
            }
          }
        }
      }
    }

    // ── clicking away from a pending chord cancels it ─────────────────
    // The hint bar waits for the second key and only Escape ever called it
    // off, so a `g` pressed by mistake sat there holding the keyboard — and
    // the thing you actually do when you have changed your mind is click
    // somewhere, which did nothing to it and then fed it the next keystroke.
    //
    // The click is SWALLOWED rather than passed on, the way dismissing a menu
    // is: the gesture that cancels something should not also do the next
    // thing. Above the bar as well as the rows, so clicking the hints
    // themselves cancels too — they are a reminder, not a set of buttons.
    MouseArea {
      anchors.fill: parent
      z: 8
      enabled: content.pending !== ""
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: (m) => { m.accepted = true; content.done(); }
    }

    // ── the keymap, on F1 ─────────────────────────────────────────────
    // The hint strip is gone. A permanent one row of keys could only ever show
    // a fraction of them and cost a strip of the window for the privilege;
    // yazi puts the whole list behind a key, and so does this. ESCAPE closes
    // it, and nothing else does — it is a page you read while you work out
    // which key you wanted, so it has to survive you pressing keys.



    // ── the drawer's list ─────────────────────────────────────────────
    // Hangs off the glyph in the breadcrumb bar and shows every job at once,
    // live. No focus is taken and no shield is laid down: it is a glance, not
    // a dialog, and the listing behind it stays as usable as it was.
    Item {
      id: jobsDrawer
      anchors.fill: parent
      z: 14
      visible: opacity > 0.01
      opacity: jobsDrawer.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      property bool open: false
      // where the card's TOP RIGHT corner goes, in this item's coordinates —
      // the same arithmetic the prefs panel does from the hamburger
      property real px: 0
      property real py: 0

      function openFrom(item) {
        const p = item.mapToItem(jobsDrawer, item.width, item.height);
        jobsDrawer.px = p.x;
        jobsDrawer.py = p.y + 6;
        jobsDrawer.open = true;
      }

      // ONE DECISION, ASKED FROM BOTH SIDES. The glyph and the card each
      // report whether the pointer is on them; this is the only thing that
      // acts on the answer, so the two cannot disagree about whether the
      // drawer should still be up.
      function settle() {
        if (root.jobsOverGlyph || root.jobsOverCard) {
          jobsLinger.stop();
          jobsDrawer.open = true;
          return;
        }
        jobsLinger.restart();
      }

      // The gap between the glyph and the card is a few pixels of bar, and
      // for those few pixels the pointer is over neither. Closing on the
      // frame that happens would make the drawer impossible to reach.
      Timer {
        id: jobsLinger
        interval: 220
        onTriggered: {
          if (root.jobsOverGlyph || root.jobsOverCard) return;
          jobsDrawer.open = false;
          // You opened it and moved away, so you have read whatever went
          // wrong: the red goes with the pointer rather than sitting there
          // until a timer decides you are done.
          root.clearJobFaults();
        }
      }

      // the same shadow the menu and the prefs panel carry
      MenuShadow {
        panel: jobsCard
        cornerRadius: 8
        transformOrigin: Item.TopRight
        scale: jobsCard.scale
      }

      Rectangle {
        id: jobsCard
        x: Math.round(Math.max(4,
             Math.min(jobsDrawer.px - jobsCard.width, jobsDrawer.width - jobsCard.width - 4)))
        y: Math.round(Math.max(4,
             Math.min(jobsDrawer.py, jobsDrawer.height - jobsCard.height - 4)))
        width: 352
        height: jobsCol.implicitHeight
        color: Zenon.black
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: 8
        transformOrigin: Item.TopRight
        scale: 0.96 + 0.04 * jobsDrawer.opacity

        HoverHandler {
          onHoveredChanged: {
            root.jobsOverCard = hovered;
            jobsDrawer.settle();
          }
        }

        Column {
          id: jobsCol
          width: parent.width
          topPadding: 4
          bottomPadding: 6

          Item {
            width: parent.width
            height: 26

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: {
                const bad = root.jobFaults;
                const live = jobsModel.count - bad;
                const runs = live === 1 ? "1 operation" : live + " operations";
                if (bad === 0) return runs;
                const said = bad === 1 ? "1 did not finish"
                                       : bad + " did not finish";
                return live === 0 ? said : runs + "  \u00b7  " + said;
              }
              color: root.jobFaults > 0 ? Zenon.red : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12
            }

            // Only once there are two. With one job the row's own × is right
            // there and a second way to press it is just another thing to
            // read past.
            Text {
              id: stopAll
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              visible: jobsModel.count - root.jobFaults > 1
              text: "stop all"
              color: stopAllHov.hovered ? Zenon.red : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12

              HoverHandler { id: stopAllHov }
              MouseArea {
                anchors.fill: parent
                onClicked: root.cancelAllJobs()
              }
            }
          }

          Repeater {
            model: jobsModel

            // `model` rather than named roles: the row carries nine of them
            // and declaring each one as a required property is nine lines
            // that say nothing the ListModel has not already said.
            delegate: Item {
              id: jobRow
              required property var model
              width: jobsCol.width
              height: 50

              // Present tense while it runs, past tense once it has not. A row
              // that still says "Copying" about a copy that died five seconds
              // ago is the drawer lying about the present.
              readonly property bool ended: jobRow.model.state !== "running"
              readonly property string verb: jobRow.ended
                ? (jobRow.model.op === "copy" ? "Copy"
                  : jobRow.model.op === "move" ? "Move"
                  : jobRow.model.op === "archive" ? "Archive" : "Extract")
                : (jobRow.model.op === "copy" ? "Copying"
                  : jobRow.model.op === "move" ? "Moving"
                  : jobRow.model.op === "archive" ? "Archiving" : "Extracting")
              readonly property color ink: jobRow.model.state === "failed"
                ? Zenon.red
                : (jobRow.ended || jobRow.model.cancelled ? Zenon.muted : Zenon.white)

              // icarus' menu highlight, which the context menu and its submenu
              // already wear. A drawer that lit its rows a different colour
              // from every other list in this window read as a different piece
              // of software — the same argument the context menu's own note
              // makes about matching the desktop menu.
              Rectangle {
                anchors.fill: parent
                color: rowHov.hovered ? Zenon.headBg : "transparent"
              }
              HoverHandler { id: rowHov }

              Text {
                id: jobRowLabel
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.right: jobRowPct.left
                anchors.rightMargin: 8
                text: {
                  // "3/7" only when the job actually goes item by item; the
                  // single rsync modes report one true percentage across the
                  // whole set, and a counter beside that would be two
                  // different progresses at once.
                  const at = jobRow.model.entries > 0
                    ? "  " + jobRow.model.seen + "/" + jobRow.model.entries
                    : (jobRow.model.index > 0
                        ? "  " + jobRow.model.index + "/" + jobRow.model.total
                        : "");
                  if (jobRow.ended)
                    return jobRow.verb + " " + jobRow.model.what
                      + (jobRow.model.state === "failed" ? "  failed"
                                                         : "  stopped");
                  return jobRow.verb + " " + jobRow.model.what + at;
                }
                elide: Text.ElideMiddle
                color: jobRow.ink
                font.family: Zenon.face
                font.pixelSize: 14
              }

              Text {
                id: jobRowPct
                anchors.right: jobRowStop.left
                anchors.rightMargin: 8
                anchors.verticalCenter: jobRowLabel.verticalCenter
                text: jobRow.ended ? ""
                  : (jobRow.model.cancelled ? "stopping" : jobRow.model.pct + "%")
                color: jobRow.model.cancelled ? Zenon.muted : Zenon.cyan
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 14
              }

              // Stopping it has to be possible from here. A list that reports
              // percentages and offers no way out is a set of progress bars
              // you have to wait for whatever they turn out to be doing — a
              // mistyped destination, a directory far bigger than you thought.
              Item {
                id: jobRowStop
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: jobRowLabel.verticalCenter
                width: 18
                height: 18

                Text {
                  anchors.centerIn: parent
                  text: "\uF00D"   // nf-fa-times
                  color: jobStopHov.hovered ? Zenon.red : Zenon.muted
                  font.family: Zenon.faceMono
                  font.pixelSize: 14
                }

                HoverHandler { id: jobStopHov }
                MouseArea {
                  anchors.fill: parent
                  // The same glyph does both jobs because it is the same
                  // gesture: make this row go away. On one that is running
                  // that means stop it; on one that already stopped there is
                  // nothing left to stop, only to dismiss.
                  onClicked: {
                    if (!jobRow.ended) { root.cancelJob(jobRow.model.id); return; }
                    const i = root.jobRowAt(jobRow.model.id);
                    if (i < 0) return;
                    jobsModel.remove(i);
                    root.jobFaults = Math.max(0, root.jobFaults - 1);
                  }
                }
              }

              Rectangle {
                id: jobBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 9
                height: 6
                radius: 3
                clip: true
                color: Zenon.trough(Zenon.cyan)

                // NOT EVERY JOB CAN SAY HOW FAR ALONG IT IS.
                //
                // The percentage is counted out of entries, and an archive of
                // ONE file has exactly one entry: it sits at 0 for the whole
                // run and then jumps to 100 as it exits. An empty trough for
                // twenty seconds is indistinguishable from a bar that does not
                // work — which is what it was taken for.
                //
                // So a job with nothing to report says so by MOVING: a sweep
                // across the trough, which is what every progress bar that
                // cannot count does. The moment a real percentage arrives the
                // sweep stops and the fill takes over.
                readonly property bool counting: jobRow.ended
                  || jobRow.model.pct > 0 || jobRow.model.entries > 1
                  || jobRow.model.index > 0

                Rectangle {
                  id: jobSweep
                  height: parent.height
                  width: parent.width * 0.32
                  radius: 3
                  visible: !jobBar.counting && !jobRow.model.cancelled
                  color: Zenon.cyan
                  opacity: 0.55
                  XAnimator on x {
                    running: jobSweep.visible
                    loops: Animation.Infinite
                    from: -jobSweep.width
                    to: jobBar.width
                    duration: 1150
                    easing.type: Easing.InOutQuad
                  }
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  visible: jobBar.counting || jobRow.model.cancelled
                  width: parent.width * (jobRow.model.pct / 100)
                  radius: 3
                  color: jobRow.model.state === "failed" ? Zenon.red
                    : (jobRow.ended || jobRow.model.cancelled ? Zenon.muted
                                                              : Zenon.cyan)
                  // The row is edited in place rather than rebuilt — see the
                  // note on jobsModel — which is what lets this animate at
                  // all.
                  Behavior on width {
                    NumberAnimation { duration: 300; easing.type: Zenon.ease }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ── the dialogs' keyboard ─────────────────────────────────────────
    // ONE ITEM THAT ACTUALLY HAS FOCUS.
    //
    // The confirm card used to carry `focus: confirm.open` on an item of its
    // own, which makes that item focused within ITS scope and nothing more —
    // `content` holds the window's active focus, so the card's Return never
    // arrived. The card appeared, showed you two buttons and would not take an
    // answer from the keyboard: "delete doesn't work".
    //
    // Putting the dispatch in content's own handler is not enough either,
    // because that only works while content is the thing with focus. So this
    // ASKS for the keyboard when a dialog opens, keeps asking until it has it
    // the way the window's focusClaim does, and hands it back on the way out.
    //
    // prompt is excluded: it holds a TextInput that takes focus for itself and
    // needs the letters.
    Item {
      id: dialogKeys
      anchors.fill: parent
      z: 20
      readonly property bool anyOpen:
        confirm.open || perms.open || props.open || prefs.open || sendTo.open
        || cmdPalette.open || marks.open || root.looking
      enabled: dialogKeys.anyOpen

      onAnyOpenChanged: {
        if (dialogKeys.anyOpen) { dialogClaim.tries = 0; dialogClaim.restart(); }
        else content.forceActiveFocus();
      }

      Timer {
        id: dialogClaim
        interval: 30
        repeat: true
        property int tries: 0
        onTriggered: {
          if (!dialogKeys.anyOpen || dialogKeys.activeFocus
              || dialogClaim.tries++ > 20) {
            dialogClaim.stop();
            return;
          }
          dialogKeys.forceActiveFocus();
        }
      }

      Keys.onPressed: (event) => {
        event.accepted = true;

        // Before confirm, because choosing a destination can raise the
        // overwrite question on top of this one and the answer belongs to
        // whichever card is in front.
        // Before confirm for the same reason the palette is: a sheet that can
        // raise another question belongs to whichever card is in front.
        if (marks.open && !confirm.open) {
          // Escape backs out one step at a time, the palette's rule: the
          // filter first, then the sheet.
          if (event.key === Qt.Key_Escape) {
            if (marks.query !== "") { marks.query = ""; return; }
            marks.dismiss(); return;
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // SHIFT OPENS IT IN A TAB, the same modifier the listing uses on
            // a directory and the go sheet uses on a destination.
            marks.go((event.modifiers & Qt.ShiftModifier) !== 0);
            return;
          }
          // Alt first: the bare arrows walk, the held ones carry.
          if (event.modifiers & Qt.AltModifier) {
            if (event.key === Qt.Key_Down) { marks.shift(1); return; }
            if (event.key === Qt.Key_Up) { marks.shift(-1); return; }
          }
          if (event.key === Qt.Key_Down) { marks.step(1); return; }
          if (event.key === Qt.Key_Up) { marks.step(-1); return; }
          // ctrl a, not a letter — every letter belongs to the filter.
          if ((event.modifiers & Qt.ControlModifier)
              && event.key === Qt.Key_A) {
            marks.addHere(); return;
          }
          // DELETE, and not a letter. Every letter belongs to the filter now —
          // `d` would have taken a bookmark away in the middle of typing
          // "downloads", which is the one mistake this sheet must not make
          // easy. There is no confirmation and there does not need to be: a
          // bookmark is a pointer, not a file, and b a puts it back.
          if (event.key === Qt.Key_Delete) { marks.drop(); return; }
          if (event.key === Qt.Key_Backspace) {
            marks.query = marks.query.slice(0, -1); return;
          }
          if (event.key !== Qt.Key_Tab && event.text
              && event.text.length === 1 && event.text >= " ") {
            marks.query += event.text;
          }
          return;
        }

        if (cmdPalette.open && !confirm.open) {
          if (event.key === Qt.Key_Escape) {
            if (cmdPalette.query !== "") { cmdPalette.query = ""; return; }
            cmdPalette.dismiss(); return;
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            cmdPalette.run(); return;
          }
          if (event.key === Qt.Key_Down) { cmdPalette.step(1); return; }
          if (event.key === Qt.Key_Up) { cmdPalette.step(-1); return; }
          if (event.key === Qt.Key_Backspace) {
            cmdPalette.query = cmdPalette.query.slice(0, -1); return;
          }
          if (event.key !== Qt.Key_Tab && event.text
              && event.text.length === 1 && event.text >= " ") {
            cmdPalette.query += event.text;
          }
          return;
        }

        // ── LOOKING ──────────────────────────────────────────────────
        // One key in and one key out, and the arrows walk the listing
        // underneath so a folder of photographs can be flicked through
        // without closing and reopening on each one.
        if (root.looking && !confirm.open) {
          // ESCAPE AND i LEAVE. Return does NOT any more: it is the key that
          // means "do the thing", and over a file being looked at the thing is
          // to open it — which is the one verb this overlay existed to save
          // you from needing, and then could not do.
          if (event.key === Qt.Key_Escape || event.text === "i") {
            root.looking = false;
            return;
          }
          // ── ACTING ON IT WITHOUT CLOSING IT FIRST ───────────────────
          // Looking at a folder of photographs is exactly when you know which
          // ones you want gone, and every one of these used to need the
          // overlay shut and reopened. The cursor stays where it is, so the
          // next picture is already up by the time the status line answers.
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.looking = false;
            root.activate();
            return;
          }
          if (event.text === "d") { root.trash(); return; }
          if (event.text === "y") { content.seq("y"); return; }
          if (event.text === "r") {
            root.looking = false; root.beginRename(); return;
          }
          if (event.key === Qt.Key_Space) {
            root.toggleMark(); root.moveSel(1); return;
          }
          // ── FOUR WAYS TO SAY "THE NEXT ONE" ─────────────────────────
          // j/k and the vertical arrows because that is how the listing under
          // it moves, and h/l and the horizontal arrows because this is a
          // PICTURE VIEWER and left-right is what a hand reaches for in one.
          //
          // h and l do NOT walk the trail here, which they do everywhere else.
          // The trail is about directories and there is no directory on screen
          // — closing the overlay to jump somewhere else is not a thing anyone
          // reaches for mid-flick through a folder of photographs.
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Right
              || event.text === "j" || event.text === "l") {
            root.moveSel(1); return;
          }
          if (event.key === Qt.Key_Up || event.key === Qt.Key_Left
              || event.text === "k" || event.text === "h") {
            root.moveSel(-1); return;
          }
          return;
        }

        if (sendTo.open && !confirm.open) {
          // Escape backs out of the filter before it backs out of the sheet:
          // a narrowed tree is a state you can be in by accident, and losing
          // the whole picker for it would be losing the branches you opened
          // to get there.
          if (event.key === Qt.Key_Escape) {
            if (sendTo.query !== "") { sendTo.query = ""; return; }
            sendTo.dismiss(); return;
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // SHIFT GOES THERE WITHOUT LEAVING HERE — the same shift the
            // listing's own open honours, and only for `go`: a copy has
            // nowhere to arrive that a tab could show.
            sendTo.choose((event.modifiers & Qt.ShiftModifier) !== 0);
            return;
          }
          if (event.key === Qt.Key_Down) { sendTo.step(1); return; }
          if (event.key === Qt.Key_Up) { sendTo.step(-1); return; }
          if (event.key === Qt.Key_Right) { sendTo.expandCurrent(); return; }
          if (event.key === Qt.Key_Left) { sendTo.outward(); return; }
          if (event.key === Qt.Key_Backspace) {
            sendTo.query = sendTo.query.slice(0, -1); return;
          }
          // EVERYTHING ELSE PRINTABLE NARROWS THE TREE. Arrows and the four
          // keys above are the whole of the navigation, deliberately — see
          // the note on `query`.
          if (event.key !== Qt.Key_Tab && event.text
              && event.text.length === 1 && event.text >= " ") {
            sendTo.query += event.text;
            return;
          }
          return;
        }

        if (confirm.open) {
          if (event.key === Qt.Key_Escape) { confirm.dismiss(); return; }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            confirm.choose(confirm.pick);
            return;
          }
          const n = Math.max(1, confirm.choices.length);
          if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            confirm.pick = (confirm.pick + n - 1) % n;
            return;
          }
          if (event.key === Qt.Key_Right || event.key === Qt.Key_L
              || event.key === Qt.Key_Tab) {
            confirm.pick = (confirm.pick + 1) % n;
            return;
          }
          // A number picks one outright: "2" on a three-way overwrite prompt
          // is faster than two arrows and a Return.
          if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            const i = event.key - Qt.Key_1;
            if (i < confirm.choices.length) confirm.choose(i);
            return;
          }
          return;
        }

        if (event.key === Qt.Key_Escape) {
          props.open = false;
          perms.open = false;
          prefs.open = false;
          content.forceActiveFocus();
          return;
        }

        // ── THE SETTINGS PANEL, FROM THE KEYBOARD ──────────────────
        // Tab and the arrows walk the rows; space or return works the one
        // under the cursor; left and right move a slider or a segment along.
        // Everything else is swallowed, which is why this branch was here in
        // the first place: `d` behind an open panel was a file in the trash
        // you never asked to send there.
        if (prefs.open) {
          const cur = root.prefAt();
          switch (event.key) {
          // Shift+Tab does not arrive as Tab with a modifier — it is its own
          // key, and testing Tab with ShiftModifier finds nothing.
          case Qt.Key_Tab:
          case Qt.Key_Down:     root.prefStep(1); return;
          case Qt.Key_Backtab:
          case Qt.Key_Up:       root.prefStep(-1); return;
          case Qt.Key_Right:    if (cur) cur.nudge(1); return;
          case Qt.Key_Left:     if (cur) cur.nudge(-1); return;
          case Qt.Key_Space:
          case Qt.Key_Return:
          case Qt.Key_Enter:    if (cur) cur.activate(); return;
          }
          return;
        }

        if (perms.open) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            perms.apply();
          } else if (event.key === Qt.Key_Left) {
            perms.cursor = (perms.cursor + 8) % 9;
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            perms.cursor = (perms.cursor + 1) % 9;
          } else if (event.key === Qt.Key_Up) {
            perms.cursor = (perms.cursor + 6) % 9;
          } else if (event.key === Qt.Key_Down) {
            perms.cursor = (perms.cursor + 3) % 9;
          } else if (event.key === Qt.Key_Space) {
            perms.toggleCursor();
          }
          return;
        }

        // properties: Return closes it, and the one thing in it you can ask
        // for is the checksum
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          props.open = false;
          content.forceActiveFocus();
        } else if (event.key === Qt.Key_S) {
          props.computeChecksum();
        }
      }
    }

    // ── what the pointer carries while dragging ───────────────────────
    //
    // A platform drag has no picture unless one is given to it: Drag.imageSource
    // takes a URL, and grabToImage renders a live item into one. So the card
    // below is drawn for real — off to one side and fully transparent, but in
    // the scene, because grabToImage renders an item's subtree and an item
    // that is `visible: false` is not in the graph to render.
    //
    // It is grabbed at the moment a drag begins rather than kept up to date,
    // because what it says depends on what is being dragged and that is not
    // known until then. The result object has to be held onto: its url stays
    // valid only as long as it is alive, and a collected one leaves the drag
    // carrying a broken image.
    Item {
      id: dragCard
      opacity: 0
      z: -100
      x: -4000
      height: 38

      // SIZED FROM THE TEXT, NOT FROM A ROW'S LAID-OUT WIDTH.
      //
      // This is what made the FIRST drag of a session carry a squashed card.
      // grabToImage sizes its target from the item's width at the moment it is
      // CALLED, and dragPicture calls it in the same tick that it fills the
      // labels in. A Row sets its own width during polish, at the end of the
      // frame — so the width read back was the one the card had before the
      // labels existed, a few pixels, and the picture was cut to it. Every
      // drag after that inherited the previous drag's width, which is exactly
      // why only the first one looked wrong.
      //
      // implicitWidth on a Text is an ordinary property: changing `text`
      // re-evaluates the bindings that read it, synchronously, in the tick
      // that changed it. So by the time grabToImage looks, the width is right.
      // Which is also why the children below are anchored rather than
      // positioned — a Row here would put the polish step back.
      readonly property real pad: 12
      width: dragCard.pad * 2 + dragGlyphText.implicitWidth
        + (root.dragGlyph !== "" ? 8 : 0) + dragLabelText.implicitWidth
        + (root.dragCount > 1 ? 8 + dragBadge.width : 0)

      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Zenon.layerBg
        border.width: 1
        border.color: Zenon.cyan
      }

      Text {
        id: dragGlyphText
        anchors.left: parent.left
        anchors.leftMargin: dragCard.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragGlyph
        color: root.dragInk
        font.family: Zenon.faceFixed
        font.pixelSize: 16
      }

      Text {
        id: dragLabelText
        anchors.left: dragGlyphText.right
        anchors.leftMargin: root.dragGlyph !== "" ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragLabel
        color: Zenon.white
        font.family: Zenon.face
        font.pixelSize: 15
      }

      // the count rides along only when there is more than one, because
      // "1" beside a filename is noise
      Rectangle {
        id: dragBadge
        anchors.left: dragLabelText.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: root.dragCount > 1
        width: countText.implicitWidth + 12
        height: 20
        radius: 10
        color: Zenon.cyan

        Text {
          id: countText
          anchors.centerIn: parent
          text: root.dragCount
          color: Zenon.black
          font.family: Zenon.face
          font.pixelSize: 13
          font.weight: Font.Medium
        }
      }
    }

    // ── the settings panel ────────────────────────────────────────────
    // What the hamburger at the end of the breadcrumb bar opens. Built like
    // the right-click menu — one `shade` driving the whole arrival, a full-
    // window catcher behind it so anywhere else dismisses it — because they
    // are the same object with different contents, and a second set of
    // animation numbers to keep in step would drift from the first.
    Item {
      id: prefs
      anchors.fill: parent
      z: 14
      // THE SHEET'S OWN ARRIVAL DECIDES THIS. It used to carry a `shade` that
      // faded the whole overlay on the menu's timing — which would now cut
      // the sheet off partway out, because a sheet leaves more slowly than a
      // menu card ever did. The sheet fades and slides itself; this only has
      // to still be there while it does.
      visible: prefsSheet.cardInk > 0.01

      property bool open: false

      // The corner it used to hang from. A sheet hangs from the bar instead,
      // so the item is no longer measured against — but the hamburger still
      // calls this, and a caller should not have to change because the thing
      // it opens changed shape.
      function openFrom(item) {
        prefs.open = true;
      }
      function toggleFrom(item) {
        if (prefs.open) { prefs.open = false; content.forceActiveFocus(); }
        else prefs.openFrom(item);
      }

      // ── ON THE PROPERTY, NOT IN THE OPENER ──────────────────────────
      // openFrom is the hamburger's way in and it is not the only one: the
      // palette's `settings` verb sets prefs.open outright, so anything hung
      // off the function is skipped for the door most people use. Whatever
      // sets the property gets this.
      //
      // Sorted here rather than once at startup because the two columns are as
      // wide as the sheet lets them be: a row's x is not settled until there
      // is a sheet to measure it against.
      onOpenChanged: {
        if (prefs.open) {
          root.prefOrder();
          // AT THE TOP, not wherever it was left. The panel is short enough to
          // read in one glance, so there is no place in it you were.
          root.prefCursor = 0;
        } else {
          root.prefCursor = -1;
        }
      }

      InputShield {
        onClicked: { prefs.open = false; content.forceActiveFocus(); }
      }

      // ── A SHEET, LIKE EVERY OTHER CARD IN THIS WINDOW ────────────────
      // It hung off the hamburger as a menu card, 292 pixels of settings in
      // one tall strip, positioned by arithmetic against the corner it came
      // out of and clamped to the window so it did not fall off the bottom.
      // It is a panel of settings, not a menu of verbs — and the sheet gives
      // it the width to be laid out rather than listed.
      //
      // The arrival, the title on the bar, the gap it opens in the bar's own
      // edge and the blur behind it all come with the shape.
      Sheet {
        id: prefsSheet
        shown: prefs.open
        fromTop: tabStrip.height + crumbBar.height
        // 700, not 620: the two columns each hold a slider with a label and a
        // readout, and a PrefText whose field is whatever is left after its
        // label — the narrower the sheet, the less of a terminal command you
        // can see at once. The well caps it against the window either way, so
        // this is a ceiling rather than a width.
        cardW: 700
        cardH: prefsCol.implicitHeight

        // The card eats its own clicks. Without this, the gaps between rows
        // fall through to the catcher behind and dismiss the panel you were
        // reaching into.
        InputShield {}

        // ── THE SELECTION, AS ONE BAR THAT MOVES ──────────────────────
        // The list sheets get theirs beside a view; this panel is two Columns
        // and has no view, so it carries its own. DECLARED BEFORE THE ROWS so
        // it draws beneath them, and a sibling of the Column rather than a
        // child, because a Column lays out what it holds and this is not a row.
        Rectangle {
          id: prefBar
          readonly property var cur: root.prefAt()
          visible: !!prefBar.cur
          color: Zenon.selBg

          // mapToItem rather than the row's own x and y: the rows live in two
          // different Columns inside a Row, so their coordinates are each
          // relative to a different parent and mean nothing here until they
          // are brought into this one.
          //
          // AND IT IS NOT A BINDING ON ITS OWN. mapToItem is a function call
          // over geometry, not a property read, so nothing tells it to run
          // again when the geometry moves — and the panel is still sliding in
          // when the cursor is first set. The bar came up one slot high and
          // snapped into place on the first Tab, because THAT changed `cur`.
          // So it is given the two things that do move to watch: the sheet's
          // arrival, which ramps 0 to 1 while the card travels, and the
          // column's height, which settles when the rows are laid out.
          readonly property var spot: (prefBar.cur
              && prefsSheet.cardInk >= 0 && prefsCol.height >= 0)
            ? prefBar.cur.mapToItem(prefsCol.parent, 0, 0) : null
          x: prefBar.spot ? prefBar.spot.x : 0
          y: prefBar.spot ? prefBar.spot.y : 0
          width: prefBar.cur ? prefBar.cur.width : 0
          height: prefBar.cur ? prefBar.cur.height : 0

          // Only the travel is animated. The size changes when the cursor
          // crosses between a 32px switch and a 34px slider, and easing two
          // pixels of height is a wobble rather than a movement.
          //
          // AND IT ANSWERS THE SAME SWITCH. This panel's cursor is not a
          // SelectBar — it is placed by mapToItem rather than by an index, so
          // it cannot be one — which meant the setting reached every sliding
          // cursor in the window except the one on the panel the setting is
          // ON. Gated here by hand for the same reason it exists there.
          Behavior on x {
            enabled: root.cursorSlide
            NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
          }
          Behavior on y {
            enabled: root.cursorSlide
            NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
          }
        }

        Column {
          id: prefsCol
          width: parent.width
          topPadding: 4
          bottomPadding: 10

          // ── TWO COLUMNS, BECAUSE THERE IS ROOM FOR TWO ──────────────
          // As a menu card hanging off the hamburger this was 292 pixels
          // wide and thirteen rows tall — a strip you scrolled your eye
          // down. A sheet is as wide as the window lets it be, so the
          // sections sit beside each other and the whole of it is one
          // glance. Split by SECTION rather than by row count: a heading
          // and the switches under it are one thing and do not get to be
          // in two places.
          Row {
            width: parent.width
            spacing: 26

            Column {
              width: (parent.width - parent.spacing) / 2

            SideHead { label: "VIEW"; first: true }

            // The three views as three buttons rather than as `v` pressed until
            // the right one comes round. While the window is split, columns is
            // not in the ring — six columns of listing in half a window each —
            // so it is shown refusing rather than quietly doing nothing.
            PrefSeg {
              options: ["columns", "list", "grid"]
              current: root.viewMode
              allowed: root.viewRing
              onChose: (v) => root.setView(v)
            }

            // The two zooms are deliberately independent — the grid scales its
            // pictures and everything else scales its text — so the row says
            // which one it is holding rather than reading "zoom" and meaning
            // something different in each view.
            // The grid's own switch, named for what it turns off rather than for
            // the view it belongs to — there is nowhere else thumbnails are drawn.
            PrefRow {
              label: "Thumbnails"
              on: root.thumbsOn
              onToggled: root.thumbsOn = !root.thumbsOn
            }

            PrefRow {
              label: "Preview pane"
              on: root.previewOn
              onToggled: root.previewOn = !root.previewOn
            }

            PrefSlider {
              label: root.viewMode === "grid" ? "Thumbnails" : "Text size"
              value: root.activeZoom
              from: root.zoomMin
              to: root.zoomMax
              neutral: 1.0
              // the same notch ctrl+wheel over the listing uses, and the same
              // one ctrl+plus steps by
              wheelStep: 0.1
              readout: Math.round(root.activeZoom * 100) + "%"
              onMoved: (v) => root.setZoom(v)
            }

            SideHead { label: "LISTING" }

            PrefRow {
              label: "Hidden files"
              hint: "."
              on: root.showHidden
              onToggled: root.showHidden = !root.showHidden
            }

            PrefRow {
              label: "Disk usage"
              hint: ", u"
              on: root.usage
              onToggled: root.toggleUsage()
            }

            PrefRow {
              label: "Confirm trash"
              on: root.confirmTrash
              onToggled: root.confirmTrash = !root.confirmTrash
            }

            PrefRow {
              label: "Git status"
              hint: ", g"
              on: root.git
              onToggled: root.toggleGit()
            }

            // ACTION, not a switch. PrefRow draws a toggle because every other
            // row in this panel is one; this is a thing you DO once, so it wears
            // its verb where the switch would be and nothing is left lit
            // afterwards to suggest a state.
            PrefAction {
              label: "Reset remembered views"
              verb: root.dirViewOrder.length > 0
                ? root.dirViewOrder.length + " kept" : "none"
              enabled: root.dirViewOrder.length > 0
              onTriggered: root.forgetDirViews()
            }

            // Beside the button that forgets them, because it is the same
            // fact said as a number: how many are kept at all.
            PrefSlider {
              label: "Remember"
              value: root.dirViewCap
              from: 50
              to: 1000
              readout: root.dirViewCap + " dirs"
              onMoved: (v) => {
                root.dirViewCap = Math.round(v);
                root.trimDirViews();
              }
            }

            PrefRow {
              label: "Remember per directory"
              on: root.perDirView
              onToggled: {
                root.perDirView = !root.perDirView;
                // Recorded on the way ON, so the folder you are standing in is
                // remembered from here rather than from the next one you walk
                // into — and applied at once, so turning it back on returns the
                // view this folder had rather than waiting for you to leave.
                if (root.perDirView) { root.rememberView(); root.applyDirView(); }
                viewSave.restart();
              }
            }

            }

            Column {
              width: (parent.width - parent.spacing) / 2

            SideHead { label: "SORT"; first: true }

            // The column headings do this too, by clicking them — but only in
            // list view, and the grid and columns had no way to reach the order
            // at all except by learning `,` sequences.
            //
            // USAGE joins the ring only while the disk-usage mode is on, which
            // is the only time it means anything. Without it, turning the mode
            // on left all four buttons unlit and the panel looking broken.
            PrefSeg {
              options: root.usage
                ? ["name", "kind", "size", "time", "usage"]
                : ["name", "kind", "size", "time"]
              current: root.sortKey
              onChose: (v) => {
                // a second press on the key already in force turns it round,
                // exactly as clicking the heading twice does
                if (root.sortKey === v) root.sortDesc = !root.sortDesc;
                else { root.sortKey = v; root.sortDesc = false; }
              }
            }

            PrefRow {
              label: "Natural order"
              on: root.naturalSort
              onToggled: root.naturalSort = !root.naturalSort
            }

            PrefRow {
              label: "Folders first"
              on: root.dirsFirst
              // No re-sort to ask for: the pane's `view` reads this, so
              // both halves rearrange themselves — see the note on Pane.raw.
              onToggled: root.dirsFirst = !root.dirsFirst
            }

            PrefRow {
              label: "Descending"
              on: root.sortDesc
              onToggled: root.sortDesc = !root.sortDesc
            }

            SideHead { label: "WINDOW" }

            PrefRow {
              label: "Sidebar"
              on: root.sidebar
              onToggled: root.sidebar = !root.sidebar
            }

            PrefRow {
              label: "Always show tabs"
              on: root.alwaysTabs
              onToggled: root.alwaysTabs = !root.alwaysTabs
            }

            PrefRow {
              label: "Column headers"
              on: root.colHeadsOn
              onToggled: root.colHeadsOn = !root.colHeadsOn
            }

            PrefRow {
              label: "Sliding cursor"
              on: root.cursorSlide
              onToggled: root.cursorSlide = !root.cursorSlide
            }

            PrefRow {
              label: "Restore session"
              on: root.sessionReplay
              onToggled: {
                root.sessionReplay = !root.sessionReplay;
                viewSave.restart();
              }
            }

            PrefRow {
              label: "Split view"
              hint: "\\"
              on: root.dual
              onToggled: root.toggleDual()
            }

            // Empty is the default and says so: xdg-terminal-exec is what
            // runs when nothing is typed here.
            PrefText {
              label: "Terminal"
              value: root.termCmd
              ghost: "xdg-terminal-exec"
              onCommitted: (v) => {
                root.termCmd = v.trim();
                viewSave.restart();
              }
            }

            PrefSlider {
              label: "Opacity"
              value: root.winAlpha
              from: root.winAlphaMin
              to: 1.0
              neutral: 1.0
              readout: Math.round(root.winAlpha * 100) + "%"
              onMoved: (v) => root.setAlpha(v)
            }
            }
          }
        }
      }
    }

    // ── the right-click menu ──────────────────────────────────────────
    // What you can do to the thing under the pointer. Everything here has a
    // key as well; this is the half of the interface for the hand that is
    // already on the mouse.
    Item {
      id: menu
      anchors.fill: parent
      z: 9
      // Kept alive through the fade OUT, which is the whole reason a menu
      // needs an opacity rather than just a visible: a card that vanishes on
      // the frame you click it never shows you which row you clicked.
      visible: menu.shade > 0.01
      opacity: menu.shade

      // 0 closed, 1 open. Everything about the card's arrival — its opacity,
      // its scale, the shade behind it — is a function of this one number, so
      // there is one animation to tune rather than four to keep in step.
      property real shade: 0
      Behavior on shade {
        NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
      }
      onOpenChanged: menu.shade = menu.open ? 1 : 0
      // Once the card is actually gone, and not before. Guarded on `open` as
      // well as on the shade so that a menu reopened mid-fade keeps the list
      // it was just given.
      onShadeChanged: if (!menu.open && menu.shade <= 0.01) {
        menu.customItems = null;
        menu.centered = false;
      }

      property bool open: false
      property real mx: 0
      property real my: 0

      readonly property var target: root.currentRow()
      readonly property bool isImage:
        !!menu.target && !menu.target.isDir && Terminus.isImage(menu.target.name)

      // on a row: everything applies to it
      function openAt(item, mouse) {
        const p = item.mapToItem(menu, mouse.x, mouse.y);
        menu.mx = p.x;
        menu.my = p.y;
        menu.here = false;
        // Said outright rather than left to the last close(), which may still
        // be fading and no longer clears these on the way out.
        menu.customItems = null;
        menu.centered = false;
        menu.subAt = -1;
        menu.subSel = -1;
        menu.open = true;
        // after `open`, so `items` has been rebuilt for this target
        menu.at = menu.step(menu.items, -1, 1);
        // asked now rather than on every selection change: it is a process,
        // and almost every right-click is not about opening with something
        const t = menu.target;
        root.findApps(t && !t.isDir ? t.path : "");
      }

      // on empty space: only the things that are about the DIRECTORY, because
      // there is no row under the pointer to be about
      function openHere(item, mouse) {
        const p = item.mapToItem(menu, mouse.x, mouse.y);
        menu.mx = p.x;
        menu.my = p.y;
        menu.here = true;
        // Said outright rather than left to the last close(), which may still
        // be fading and no longer clears these on the way out.
        menu.customItems = null;
        menu.centered = false;
        menu.subAt = -1;
        menu.subSel = -1;
        menu.open = true;
        menu.at = menu.step(menu.items, -1, 1);
      }

      property bool here: false

      // The sort options, as the submenu the `,` sequence already spells out.
      // One list feeding both would be ideal; these are three lines and the
      // sequence table's entries carry hint text this menu has no room for.
      // One row per format, described rather than just named: ".tar.zst" is
      // not self-explanatory to anyone who has not met zstd.
      readonly property var formatItems: {
        const out = [];
        for (const f of root.archiveFormats) {
          const ext = f[0];
          out.push({ label: ext, hint: f[1],
                     act: () => root.beginArchive(ext) });
        }
        return out;
      }

      readonly property var sortItems: [
        { label: "Name", act: () => root.setSort("name") },
        { label: "Size", act: () => root.setSort("size") },
        { label: "Modified", act: () => root.setSort("time") },
        { label: "Kind", act: () => root.setSort("kind") },
        { sep: true },
        // A mode rather than an order, which is why it says what it will do
        // rather than naming a column.
        { label: root.usage ? "Leave disk usage" : "Disk usage",
          key: ", u", act: () => root.toggleUsage() },
        { label: root.git ? "Leave git status" : "Git status",
          key: ", g", act: () => root.toggleGit() },
        { sep: true },
        { label: root.sortDesc ? "Ascending" : "Descending",
          act: () => root.sortDesc = !root.sortDesc }
      ]

      // Filled by the process findApps starts when the menu opens. Empty until
      // it answers, which is why it says so rather than showing nothing.
      // Only entries that can actually be launched. It used to fall back to a
      // "(no applications)" row, which is a submenu whose one item is an
      // apology — you opened a card, walked into a second card, and were told
      // there was nothing there. The parent row says it instead, by being dim.
      readonly property var appItems: {
        const t = menu.target;
        if (!t) return [];
        const apps = root.openWithApps;
        const out = [];
        for (let i = 0; i < apps.length; ++i) {
          // the ID, captured per iteration. Not the scanned file: that is the
          // first one found, which may be a stale user override — see
          // openWithCommand. An entry the scan could not locate at all still
          // has nothing to run.
          const id = apps[i].id;
          if (!id || !apps[i].file) continue;
          out.push({ label: apps[i].name, act: () => root.openWith(id, t.path) });
        }
        return out;
      }

      // The submenu itself: what already handles this file, and then a way out
      // of that list.
      //
      // A type CAN have a handler and still not have the one you want — a
      // .conf that opens in the wrong editor, an image that opens in a viewer
      // when you meant to edit it — and the picker was only reachable from a
      // file nothing claimed at all. So the same card hangs off the bottom of
      // the populated submenu, behind a rule: everything above it is one
      // click, this one opens something.
      readonly property var appMenu: {
        const t = menu.target;
        if (!t) return [];
        const out = menu.appItems.slice();
        if (out.length > 0) out.push({ sep: true });
        out.push({ label: "Choose Program",
                   act: () => root.beginOpenWith(t.path) });
        return out;
      }

      // which item's submenu is showing, or -1
      property int subAt: -1

      // ── as wide as its longest entry ────────────────────────────────
      // 240 was a guess, and the entries that outgrew it were elided — so the
      // menu hid the ends of exactly the labels that needed the room, and
      // "Paste as hard link" or a long "Open with" name became a shrug. The
      // card measures its own contents instead, with the same fonts the rows
      // draw with and the same paddings they are laid out by. Still bounded:
      // a menu the width of the window would be its own problem.
      FontMetrics {
        id: menuLabelFm
        font.family: Zenon.face
        font.pixelSize: 16
      }
      FontMetrics {
        id: menuKeyFm
        font.family: Zenon.face
        font.pixelSize: 12
      }

      function rowWidth(it, labelFm, keyFm) {
        if (it.sep) return 0;
        // 12 in from the left, then the label, then the gap before the key —
        // the same 22 the row is laid out with, or the card measures itself
        // narrower than it draws and the labels elide again.
        let w = 12 + Math.ceil(labelFm.advanceWidth(String(it.label || ""))) + 22;
        // the chip's own text plus the padding KeyChip adds around it
        if (it.key) w += Math.ceil(keyFm.advanceWidth(String(it.key))) + 14;
        // the chevron needs more room on the right than a plain row does
        w += it.sub ? 26 : 12;
        // AND A COUPLE OF PIXELS OF SLACK. advanceWidth is the sum of the
        // glyph advances; Text lays the same string out with shaping and its
        // own rounding and comes out a little wider, which is the difference
        // between a label that fits and "Propertie…".
        return w + 6;
      }

      readonly property real cardWidth: {
        let w = 0;
        for (const it of menu.items)
          w = Math.max(w, menu.rowWidth(it, menuLabelFm, menuKeyFm));
        return Math.round(Math.max(200, Math.min(460, w)));
      }

      // ── the keyboard's place in the card ────────────────────────────
      // The menu was mouse-only: every key but Escape was dropped while it was
      // up, so the Menu key could open a card you then had to reach for the
      // mouse to use. `at` is the cursor in the parent card and `subSel` the
      // one in the submenu, with -1 meaning "the keyboard is not in there".
      property int at: -1
      property int subSel: -1

      // The next selectable row in a direction, wrapping, skipping separators
      // — a separator is a line, not a place you can be. Returns -1 for a list
      // with nothing selectable in it at all.
      function step(list, from, dir) {
        const n = list ? list.length : 0;
        if (n === 0) return -1;
        let i = from;
        for (let k = 0; k < n; ++k) {
          i = (i + dir + n) % n;
          if (!list[i].sep) return i;
        }
        return -1;
      }

      readonly property var subItems: {
        if (menu.subAt < 0) return [];
        const it = menu.items[menu.subAt];
        return (it && it.sub) ? it.sub : [];
      }

      // THE ACTION IS READ BEFORE THE MENU CLOSES, for the reason spelled out
      // on the rows themselves: close() empties the Repeater's model, an
      // emptied Repeater destroys its delegates, and modelData goes with them.
      function run(act) {
        menu.close();
        if (act) act();
      }

      function activateAt() {
        const it = menu.items[menu.at];
        if (!it || it.sep) return;
        // a parent row opens its children rather than doing anything
        if (it.sub) { menu.subAt = menu.at; menu.subSel = menu.step(it.sub, -1, 1); return; }
        menu.run(it.act);
      }

      function activateSub() {
        const it = menu.subItems[menu.subSel];
        if (!it || it.sep) return;
        menu.run(it.act);
      }

      // Down and up, in whichever card the keyboard is actually in.
      function move(dir) {
        if (menu.subSel >= 0) menu.subSel = menu.step(menu.subItems, menu.subSel, dir);
        else menu.at = menu.step(menu.items, menu.at, dir);
      }

      function close() {
        menu.open = false;
        // customItems is NOT cleared here, and that is the whole fix for the
        // flash: the card is deliberately kept alive through its fade out, so
        // clearing the handed-in list on the closing frame let `items` fall
        // back to the row menu — and the last thing you saw of the drop menu
        // was the full context menu wearing its shape for 150ms. It is
        // cleared when the fade has finished instead, below.
        menu.subAt = -1;
        menu.at = -1;
        menu.subSel = -1;
        content.forceActiveFocus();
      }

      // anything that misses the card puts it away
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: menu.close()
      }

      // ── a list handed in from outside ───────────────────────────────
      // For the questions that are about a PLACE rather than about a row:
      // what to do with something just dropped. Answering those in a dialog
      // put the choice in the middle of the screen, a long way from the
      // pointer that had just arrived somewhere specific — so the menu takes
      // an explicit list and opens where the drop happened.
      property var customItems: null
      // Centred entries, for the handed-in menus only. A row menu is a column
      // of verbs you read down the left edge, and it has keys along the right
      // to line up against; the drop menu is three short answers to one
      // question with nothing in the right-hand column, and left-aligning
      // those leaves them hanging off the side of a card sized for them.
      property bool centered: false

      function openCustom(item, mouse, list) {
        const p = item.mapToItem(menu, mouse.x, mouse.y);
        menu.mx = p.x;
        menu.my = p.y;
        menu.here = false;
        menu.subAt = -1;
        menu.subSel = -1;
        menu.customItems = list;
        menu.centered = true;
        menu.open = true;
        menu.at = menu.step(menu.items, -1, 1);
      }

      readonly property var items: {
        if (menu.customItems) return menu.customItems;
        if (menu.here) {
          const out = [];
          if (root.pending) {
            out.push({ label: "Paste here", key: "p", act: () => root.paste() });
            out.push({ label: "Paste as symlink", act: () => root.pasteLink(true) });
            out.push({ label: "Paste as hard link", act: () => root.pasteLink(false) });
            out.push({ sep: true });
          }
          out.push({ label: "New directory", key: "a /", act: () => root.beginMkdir() });
          out.push({ label: "New file", key: "a", act: () => root.beginCreate() });
          out.push({ sep: true });
          out.push({ label: "Sort by", key: ",", sub: menu.sortItems });
          if (root.undoStack.length > 0)
            out.push({ label: root.undoLabel, key: "u", act: () => root.undo() });
          out.push({ sep: true });
          out.push({ label: root.isBookmarked(root.cwd)
              ? "Remove bookmark" : "Bookmark this directory",
            key: "b a",
            act: () => root.toggleBookmark() });
          if (root.inTrash)
            out.push({ label: "Empty the trash", danger: true,
                       act: () => root.emptyTrash() });
          out.push({ label: "Open shell here", key: ";", act: () => root.openShell() });
          out.push({ label: root.dual ? "Close second pane" : "Second pane",
                     key: "\\", act: () => root.toggleDual() });
          out.push({ label: root.sidebar ? "Hide sidebar" : "Sidebar",
                     key: "|", act: () => { root.sidebar = !root.sidebar; } });
          // Braced. Both of these are about the SECOND PANE and both were
          // meant to be behind `root.dual` — but only the first was, so a
          // one-pane window offered to swap sides with a pane that was not
          // there. The indentation had said what was intended all along.
          if (root.dual) {
            out.push({ label: "Step into other pane", key: "tab", act: () => root.stepOver() });
            out.push({ label: "Swap sides", act: () => root.swapSides() });
          }
          out.push({ label: "Select all", key: "ctrl a", act: () => root.selectAll() });
          out.push({ sep: true });
          // THIS directory, not whatever the cursor is resting on. Last, where
          // every other file manager puts it.
          out.push({ label: "Properties",
                     act: () => props.askPath(root.cwd) });
          return out;
        }
        const t = menu.target;
        if (!t) return [];
        // the cheap counter, so labels stay right without depending on the
        // whole selection array
        const n = root.markedCount > 0 ? root.markedCount : 1;
        const many = n > 1 ? " (" + n + ")" : "";
        const out = [
          { label: t.isDir ? "Open directory" : "Open", key: "return", act: () => root.activate() }
        ];
        // Directly under Open, because it is the other way to open this — and
        // only for a directory, which is the only thing with a listing to give
        // a tab. The same gesture is on the middle mouse button.
        if (t.isDir)
          out.push({ label: "Open in new tab", key: "shift return",
                     act: () => root.openInNewTab(t.path) });
        // Opening is one kind of thing and moving is another; the rule below
        // holds them apart. Cut first: the pair is ordered by how much of a
        // commitment it is, and the one that takes the file away is the one
        // you want to have to read past to reach.
        out.push({ sep: true });
        out.push(
          { label: "Cut" + many, key: "x x", act: () => root.yank("move") },
          { label: "Copy" + many, key: "y y", act: () => root.yank("copy") },
          // The path is another thing you can take from the row, so it belongs
          // with the two above rather than down among the dialogs.
          { label: "Copy path", key: "c c", act: () => root.copyPath() });
        // The other half of cut-and-paste, for when you know where it is
        // going and do not want to go there first — see sendTo.
        out.push(
          { label: "Copy to" + many + "…", key: "y s",
            act: () => sendTo.ask("copy") },
          { label: "Move to" + many + "…", key: "x s",
            act: () => sendTo.ask("move") },
          { label: "Duplicate" + many, key: "y d",
            act: () => root.duplicate() });
        out.push({ sep: true });
        if (root.pending)
          out.push({ label: "Paste here", key: "p", act: () => root.paste() });
        if (root.pending) {
          out.push({ label: "Paste as symlink", act: () => root.pasteLink(true) });
          out.push({ label: "Paste as hard link", act: () => root.pasteLink(false) });
          // Closing the block rather than opening one: the paste entries are
          // about what is on the clipboard, everything under them is about the
          // row, and with nothing between them the menu grew by three rows in
          // the middle and read as one long list of unrelated verbs.
          out.push({ sep: true });
        }
        // Only where it can do something: an Extract on a text file and a
        // Restore outside the trash are entries that exist to be greyed out.
        if (t.isDir)
          out.push({ label: "Calculate size" + many, key: "z",
                     act: () => root.measureDirs() });
        if (root.dual && root.otherCwd !== "" && root.otherCwd !== root.cwd) {
          out.push({ label: "Copy to other pane" + many, key: "f5",
                     act: () => root.sendToOther("copy") });
          out.push({ label: "Move to other pane" + many, key: "f6",
                     act: () => root.sendToOther("move") });
        }
        if (Terminus.isArchive(t.name) && !t.isDir)
          out.push({ label: "Extract here" + many, act: () => root.extractSelected() });
        out.push({ label: "Archive" + many, key: "c a", sub: menu.formatItems });
        if (root.inTrash) {
          out.push({ label: "Restore" + many, act: () => root.restoreSelected() });
          out.push({ label: "Empty the trash", danger: true,
                     act: () => root.emptyTrash() });
        }
        if (!t.isDir) {
          // A submenu when something already handles this type, and a CARD
          // when nothing does.
          //
          // The old fallback was a submenu holding one row that said "(no
          // applications)" — you opened a card, walked right into a second
          // card, and were told there was nothing in it. Worse, it was a dead
          // end: the answer to "nothing opens this" is to pick something, and
          // the menu had nowhere to do that from.
          //
          // So the entry becomes an action instead, and the card it opens
          // lists everything installed. What you choose is REGISTERED for the
          // type on its way to running it, which is what turns this row back
          // into a submenu the next time you open it — see adoptAppCommand.
          // The same card is reachable from the bottom of the populated
          // submenu, because "it has a handler" and "it has the one you want"
          // are not the same claim — see appMenu.
          //
          // Only once the scan has actually answered. While it is still out
          // there is no news yet, and flipping the row from one shape to the
          // other under the pointer would be inventing some.
          if (menu.appItems.length === 0 && root.appsScanned)
            out.push({ label: "Open with",
                       act: () => root.beginOpenWith(t.path) });
          else
            out.push({ label: "Open with", sub: menu.appMenu });
          // Beside the two verbs that open things, because it is the one that
          // opens nothing — see root.quickLook.
          out.push({ label: "Quick look", key: "i",
                     act: () => root.quickLook() });
        }
        out.push({ label: "Sort by", key: ",", sub: menu.sortItems });
        // Renaming sits under the sort, not up among cut and copy: those act
        // on the row and hand you straight back to it, and this one opens a
        // field and waits. It is the first of the verbs that ask a question.
        // Whichever one the selection means, and only that one. Offering both
        // asked you to choose between renaming the row under the cursor and
        // renaming the nine you had ticked — which is not a choice anybody
        // wants to make on a menu, and the first answer is almost never it.
        // JUST "Rename", with the count saying how many. "Bulk rename (9)"
        // named a mechanism; the row above it already says Rename for one,
        // and the only thing that changes with nine is the number.
        if (n > 1)
          out.push({ label: "Rename" + many, key: "r",
                     act: () => root.beginBulkRename() });
        else
          out.push({ label: "Rename", key: "r", act: () => root.beginRename() });
        if (t.isDir)
          out.push({ label: root.isBookmarked(t.path)
              ? "Remove bookmark" : "Bookmark",
            key: "b b",
            act: () => root.toggleBookmarkFor(t.path) });
        // The two that open a card of their own, together at the bottom behind
        // a rule — everything above acts on the row and returns you to it.
        out.push({ sep: true });
        out.push({ label: "Permissions", key: "c m", act: () => perms.ask() });
        out.push({ label: "Properties", key: "alt return", act: () => props.ask() });
        if (menu.isImage) {
          out.push({ sep: true });
          out.push({ label: "Set as background",
                     act: () => root.setWallpaper(null) });
          const screens = Quickshell.screens;
          if (screens.length > 1) {
            for (let i = 0; i < screens.length; ++i) {
              const nm = screens[i].name;
              out.push({ label: "Background on " + nm,
                         act: () => root.setWallpaper(nm) });
            }
          }
        }
        out.push({ sep: true });
        out.push({ label: "Trash" + many, key: "d", danger: true, act: () => root.trash() });
        return out;
      }

      // icarus' shadow, worn here. The menu this window opens and the menu
      // the desktop opens are the same gesture, and the one that cast a
      // different shadow read as a different piece of software.
      //
      // It rides the card's own arrival — same scale, same origin — so it
      // grows out of the pointer with it rather than sitting at full size
      // under a card that is still unfolding.
      MenuShadow {
        panel: menuCard
        cornerRadius: Zenon.menuRadius
        transformOrigin: Item.TopLeft
        scale: menuCard.scale
      }

      ClippingRectangle {
        id: menuCard
        // Grows out of the pointer rather than appearing at full size. The
        // origin is the corner the pointer is at, so the card unfolds FROM the
        // click instead of expanding around its own middle.
        transformOrigin: Item.TopLeft
        scale: Zenon.menuScale(menu.shade)

        // kept inside the window: a menu opened near the right edge that
        // hangs off it is a menu with items you cannot reach
        // Rounded. The position comes from a pointer, which lands on
        // fractions of a pixel, and an item on a half pixel renders its text
        // through a filter — which is what "blurry" was.
        x: Math.round(Math.max(4, Math.min(menu.mx, menu.width - width - 4)))
        y: Math.round(Math.max(4, Math.min(menu.my, menu.height - height - 4)))
        width: menu.cardWidth
        // EXACTLY the column, which already carries 4px of padding at each
        // end. The extra 8 here was a second bottom padding — the column sits
        // at the card's top, so every pixel of it landed underneath the last
        // row and nowhere else.
        height: menuCol.implicitHeight
        // Solid. A backdrop blur here was fighting the card rather than
        // helping it: ShaderEffectSource copies the rectangle behind the card,
        // and a menu that opens over three columns of text ends up smearing
        // three different backgrounds under one small surface. Opaque black is
        // what a menu wants — it is meant to sit ON the window, not in it.
        color: Zenon.menuBgSolid
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: Zenon.menuRadius
        // and the parent gives up the side the child is standing on
        topLeftRadius: subCard.visible && !subCard.onRight ? 0 : Zenon.menuRadius
        bottomLeftRadius: subCard.visible && !subCard.onRight ? 0 : Zenon.menuRadius
        topRightRadius: subCard.visible && subCard.onRight ? 0 : Zenon.menuRadius
        bottomRightRadius: subCard.visible && subCard.onRight ? 0 : Zenon.menuRadius

        Column {
          id: menuCol
          width: parent.width
          topPadding: Zenon.menuCardPad
          bottomPadding: Zenon.menuCardPad

          Repeater {
            model: menu.items

            delegate: Item {
              id: menuRow
              required property var modelData
              width: menuCol.width
              height: modelData.sep ? Zenon.menuSepHeight : Zenon.menuRowHeight

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 1
                visible: !!modelData.sep
                color: Zenon.msgBorder
              }

              required property int index

              Rectangle {
                anchors.fill: parent
                visible: !modelData.sep
                // icarus' menu highlight, worn here too — the two are the same
                // gesture on the same desktop, and a context menu that lit its
                // rows a different colour from the desktop menu read as a
                // different piece of software.
                // The keyboard's row counts as highlighted only while the
                // keyboard is in THIS card — with a submenu open the cursor
                // has moved into it and the parent row keeps its subAt tint
                color: itemHov.hovered || menu.subAt === index
                       || (menu.subSel < 0 && menu.at === index)
                  ? Zenon.headBg : "transparent"
              }
              HoverHandler {
                id: itemHov
                enabled: !modelData.sep
                // Hovering a row with children opens them and hovering one
                // without closes whatever was open — so moving down the card
                // never leaves an orphaned second card beside an unrelated row.
                onHoveredChanged: if (hovered) {
                  menu.subAt = modelData.sub ? index : -1;
                  // so a keystroke after a hover carries on from the row under
                  // the pointer rather than from wherever the keyboard was
                  menu.at = index;
                  menu.subSel = -1;
                }
              }

              // BOUNDED ON THE RIGHT by whatever is over there, which is what
              // it was missing: a left-anchored Text with no right edge is as
              // wide as its string, so "Open in new tab" simply drew straight
              // through the "middle click" beside it and the two were printed
              // on top of each other. Now it stops short and elides.
              Text {
                id: menuLabel
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: menuKey.visible ? menuKey.left
                             : (menuChev.visible ? menuChev.left : parent.right)
                // The label and its key are two different statements — what
                // this does, and what performs it — and at 10px they read as
                // one run of text with a box at the end of it. Centred, the
                // gap has to match the left inset or the middle is not the
                // middle.
                anchors.rightMargin: menu.centered ? 12 : 22
                horizontalAlignment: menu.centered ? Text.AlignHCenter
                                                   : Text.AlignLeft
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                visible: !modelData.sep
                text: modelData.label || ""
                color: modelData.danger ? Zenon.red : Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }

              // The key that does the same thing, so the menu teaches the
              // keyboard rather than competing with it. A footnote to the
              // entry, not a second label — but it was drawn in msgBorder,
              // which is a BORDER colour carrying 30% alpha, so it came out
              // barely there. keyInk is the palette's name for exactly this:
              // dimmer than the label, still meant to be read.
              KeyChip {
                id: menuKey
                anchors.right: menuChev.visible ? menuChev.left : parent.right
                anchors.rightMargin: modelData.sub ? 8 : 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !modelData.sep && !!modelData.key
                label: modelData.key || ""
              }

              // the chevron that says there is more to the right
              Text {
                id: menuChev
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: !!modelData.sub
                text: "\uf105"   // nf-fa-angle_right
                color: Zenon.muted
                font.family: Zenon.faceMono
                font.pixelSize: 15
              }

              // The row FLASHES, then the card closes, then the thing happens.
              //
              // A menu that disappears on mouse-down leaves you unsure which
              // row you hit — and for the destructive entries that is a bad
              // moment to be unsure in. The delay is long enough to see and
              // short enough that it is not a wait.
              property real chosen: 0
              SequentialAnimation {
                id: chosenAnim
                NumberAnimation { target: menuRow; property: "chosen"; to: 1;
                                  duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: menuRow; property: "chosen"; to: 0;
                                  duration: 130; easing.type: Easing.InQuad }
                ScriptAction {
                  script: {
                    const act = menuRow.pending;
                    menuRow.pending = null;
                    menu.close();
                    if (act) act();
                  }
                }
              }
              property var pending: null

              Rectangle {
                anchors.fill: parent
                visible: menuRow.chosen > 0
                color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                               0.55 * menuRow.chosen)
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData.sep && !chosenAnim.running
              // No hand cursor. This is a file manager, not a page of links:
              // a row you can click is the normal state of everything here, so
              // pointing at one is not news and the pointer should not change
              // to say so.
                onClicked: {
                  // a parent row opens its children rather than doing anything
                  if (modelData.sub) { menu.subAt = index; return; }
                  menuRow.pending = modelData.act;
                  chosenAnim.restart();
                }
              }
            }
          }
        }
      }

      // ── the submenu ───────────────────────────────────────────────
      // A second card beside the first, for the entries that are a CHOICE
      // rather than an action — how to sort, which application to open with.
      // Those would each be four or five more rows on a menu that is already
      // long, and they are all answers to one question, which is what a
      // submenu is for.
      //
      // Its y is computed from the rows above it rather than measured off the
      // delegate: the rows are a fixed 30 and separators 7, so the arithmetic
      // is exact and nothing has to be mapped between items.
      MenuShadow {
        panel: subCard
        cornerRadius: Zenon.menuRadius
        visible: subCard.visible
        opacity: subCard.shade
        transformOrigin: Item.TopLeft
        scale: subCard.scale
      }

      ClippingRectangle {
        id: subCard
        // The same arrival the card it hangs off has, and every other menu on
        // this desktop. It used to simply appear, which next to a parent that
        // unfolds read as two different pieces of software.
        readonly property bool wanted: menu.subAt >= 0 && subCard.items.length > 0
        property real shade: 0
        onWantedChanged: subCard.shade = subCard.wanted ? 1 : 0
        Behavior on shade {
          NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
        }
        visible: subCard.wanted || subCard.shade > 0.01
        transformOrigin: Item.TopLeft
        scale: Zenon.menuScale(subCard.shade)
        opacity: subCard.shade

        readonly property var items: menu.subItems

        readonly property real rowTop: {
          let y = Zenon.menuCardPad;   // menuCol's top padding
          for (let i = 0; i < menu.subAt && i < menu.items.length; ++i) {
            y += menu.items[i].sep ? Zenon.menuSepHeight : Zenon.menuRowHeight;
          }
          return y;
        }

        // the same measurement, plus the description column those rows carry
        width: {
          let w = 0;
          for (const it of subCard.items) {
            let x = menu.rowWidth(it, menuLabelFm, menuKeyFm);
            if (it.hint) x += 16 + menuKeyFm.advanceWidth(String(it.hint));
            w = Math.max(w, x);
          }
          return Math.round(Math.max(200, Math.min(460, w)));
        }
        height: subCol.implicitHeight
        // Flipped to the left of the parent card when there is no room on the
        // right, for the same reason the parent card is clamped to the window.
        // Asked ONCE, as a property, because the corners below have to agree
        // with the placement — a card that squares the wrong edge is worse
        // than one that squares neither.
        readonly property bool onRight:
          menuCard.x + menuCard.width + subCard.width < menu.width - 4

        // Flush against the parent, with the gap taken out. The two cards are
        // one surface with a rule down it, the way icarus' menus read, and two
        // pixels of window showing between them is what stopped them being it.
        x: Math.round(subCard.onRight
          ? menuCard.x + menuCard.width
          : Math.max(4, menuCard.x - subCard.width))
        y: Math.round(Math.max(4,
          Math.min(menuCard.y + subCard.rowTop, menu.height - height - 4)))
        color: Zenon.menuBgSolid
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: Zenon.menuRadius
        // Square where it meets the parent, round everywhere else.
        topLeftRadius: subCard.onRight ? 0 : Zenon.menuRadius
        bottomLeftRadius: subCard.onRight ? 0 : Zenon.menuRadius
        topRightRadius: subCard.onRight ? Zenon.menuRadius : 0
        bottomRightRadius: subCard.onRight ? Zenon.menuRadius : 0

        Column {
          id: subCol
          width: parent.width
          topPadding: Zenon.menuCardPad
          bottomPadding: Zenon.menuCardPad

          Repeater {
            model: subCard.items

            delegate: Item {
              id: subRow
              required property var modelData
              // needed by the keyboard cursor's highlight below; the parent
              // card's rows have always declared it
              required property int index
              width: subCol.width
              height: modelData.sep ? Zenon.menuSepHeight : Zenon.menuRowHeight

              // The action is READ BEFORE THE MENU CLOSES, and that ordering is
              // the whole reason these rows do anything at all.
              //
              // close() sets subAt back to -1, which makes subCard.items answer
              // with an empty list, which empties this Repeater's model — and an
              // emptied Repeater destroys its delegates. `modelData` belongs to
              // the delegate, so calling modelData.act() after close() is a call
              // on something that no longer exists. Every entry under Archive,
              // Open with and Sort by was silently dead for exactly that reason.
              //
              // Holding it in `pending` also buys the same flash the parent
              // card's rows get, so a choice in a submenu confirms itself the
              // same way a choice in the menu does.
              property real chosen: 0
              property var pending: null
              SequentialAnimation {
                id: subChosenAnim
                NumberAnimation { target: subRow; property: "chosen"; to: 1;
                                  duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: subRow; property: "chosen"; to: 0;
                                  duration: 130; easing.type: Easing.InQuad }
                ScriptAction {
                  script: {
                    const act = subRow.pending;
                    subRow.pending = null;
                    menu.close();
                    if (act) act();
                  }
                }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 1
                visible: !!modelData.sep
                color: Zenon.msgBorder
              }

              Rectangle {
                anchors.fill: parent
                visible: !modelData.sep
                // the same highlight the parent card wears, from icarus
                color: subHov.hovered || menu.subSel === subRow.index
                  ? Zenon.headBg : "transparent"
              }
              HoverHandler { id: subHov; enabled: !modelData.sep }

              Text {
                id: subLabel
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !modelData.sep
                text: modelData.label || ""
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }

              // what the format actually is, for the rows that carry one
              Text {
                anchors.left: subLabel.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: !!modelData.hint
                text: modelData.hint || ""
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 13
              }

              Rectangle {
                anchors.fill: parent
                visible: subRow.chosen > 0
                color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                               0.55 * subRow.chosen)
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData.sep && !subChosenAnim.running
              // No hand cursor. This is a file manager, not a page of links:
              // a row you can click is the normal state of everything here, so
              // pointing at one is not news and the pointer should not change
              // to say so.
                onClicked: {
                  if (!modelData.act) return;
                  subRow.pending = modelData.act;
                  subChosenAnim.restart();
                }
              }
            }
          }
        }
      }

    }

    // ── bulk rename ───────────────────────────────────────────────────
    // Forty names, edited where the forty files are.
    //
    // Two columns and nothing else: what a thing is called now, and what it
    // would be called. The pattern field above them is the reason this exists
    // at all — "replace .JPEG with .jpg across all of them" is one gesture,
    // and the per-row fields are there for the handful the pattern got wrong.
    //
    // NOTHING IS APPLIED UNTIL THE BUTTON. The rules are checked live and
    // written on the offending row, so an empty name or two files that would
    // end up with the same name is something you see before you commit rather
    // than a refusal afterwards.
    Rectangle {
      id: bulk
      anchors.fill: parent
      z: 15
      visible: opacity > 0.01
      opacity: bulk.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: bulk.open ? bulkSheet.slideIn : bulkSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      // Which row has the keyboard. A delegate cannot be told to take focus
      // from outside, so it watches this and claims it for itself.
      property int at: 0
      // Bumped to ask row `at` to take the keyboard AGAIN even when `at` did
      // not change — tabbing out of the pattern fields and back into the row
      // it was already on has nothing to change but still has to move the
      // caret. A counter, for the reason openPulse is one.
      property int atPulse: 0

      function focusRow(i) {
        const n = root.bulkNames.length;
        if (n === 0) return;
        bulk.at = Math.max(0, Math.min(n - 1, i));
        bulk.atPulse++;
      }

      // Tab walks the whole card and wraps: find, replace, every row, back to
      // find. One ring rather than two halves that cannot reach each other,
      // which is what the pattern fields and the rows were before.
      function tabFromRow(i) {
        if (i < root.bulkNames.length - 1) bulk.focusRow(i + 1);
        else findField.claim();
      }
      function backTabFromRow(i) {
        if (i > 0) bulk.focusRow(i - 1);
        else replField.claim();
      }

      // What is wrong with each proposed name, from the same function the
      // commit gate reads — see Terminus.bulkIssues.
      readonly property var issues:
        Terminus.bulkIssues(root.bulkNames, root.bulkEdits)
      readonly property bool sound: {
        for (let i = 0; i < bulk.issues.length; ++i)
          if (bulk.issues[i] !== "") return false;
        return true;
      }
      readonly property int changes: {
        let n = 0;
        for (let i = 0; i < root.bulkNames.length; ++i)
          if (root.bulkEdits[i] !== root.bulkNames[i]) n++;
        return n;
      }

      function dismiss() {
        bulk.open = false;
        content.forceActiveFocus();
      }

      onOpenChanged: {
        if (!bulk.open) return;
        bulk.at = 0;
        findField.text = "";
        replField.text = "";
        bulkClaim.tries = 0;
        bulkClaim.restart();
      }

      // ASK UNTIL IT HAS IT. The card is animating in from opacity 0 when the
      // first request goes out, and forceActiveFocus() on an item the scene
      // has not placed yet is silently dropped — the same trap the rename
      // field and the create prompt both carry a retry for.
      Timer {
        id: bulkClaim
        interval: 40
        repeat: true
        property int tries: 0
        onTriggered: {
          if (!bulk.open || findField.focused || bulkClaim.tries++ > 12) {
            bulkClaim.stop();
            return;
          }
          bulkKeys.forceActiveFocus();
          // AND THE FIND FIELD WITHIN IT. It used to be the first name row,
          // on the reasoning that a row is where you would start typing —
          // but the card's own verb is the pattern at the top, and landing in
          // row one meant reaching for the mouse or tabbing backwards to use
          // it. Editing a single name by hand is what the in-place rename is
          // for; this card is open because the pattern is what you wanted.
          findField.claim();
        }
      }

      InputShield { onClicked: bulk.dismiss() }

      // Escape from anywhere in the card, including from inside a field that
      // has not handled it — so there is always one key that gets you out.
      FocusScope {
        id: bulkKeys
        anchors.fill: parent
        // Escape from anywhere in the card, and nothing else out of it.
        //
        // The fields are deeper than this, so they see their own keys first
        // and this only ever gets what they did not want — which must not
        // travel on to the listing's key handler. Before this, a key the
        // pattern fields ignored acted on the rows behind the card.
        Keys.onPressed: (e) => {
          e.accepted = true;
          if (e.key === Qt.Key_Escape) bulk.dismiss();
        }

        Sheet {
          id: bulkSheet
          shown: bulk.open
          fromTop: tabStrip.height + crumbBar.height
          cardW: 760
          cardH: bulkCol.implicitHeight

          Column {
            id: bulkCol
            width: parent.width

            // The caption band stood here. It is drawn on the bar now — see
            // sheetBarHead — because a sheet says what it is where it hangs from.

            // ── the pattern ───────────────────────────────────────
            // Return in either field applies it. A BUTTON rather than a live
            // binding: the replace runs from the original names, so making it
            // live would wipe a hand edit every time the caret moved through
            // the pattern.
            Item {
              id: patRow
              width: parent.width
              height: 46
              // Anchored rather than laid out in a Row: the button sizes
              // itself to its own label, so the two fields are whatever is
              // left over after it — and a Row would have to be told that
              // number twice.
              readonly property real cell:
                Math.max(60, (patRow.width - 72 - replBtn.width) / 2)

              BulkField {
                id: findField
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: patRow.cell
                ghost: "find"
                onAccepted: root.applyBulkReplace(findField.text, replField.text)
                onTabbed: replField.claim()
                onBackTabbed: bulk.focusRow(root.bulkNames.length - 1)
              }

              Text {
                id: patArrow
                anchors.left: findField.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                horizontalAlignment: Text.AlignHCenter
                text: "\u2192"
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }

              BulkField {
                id: replField
                anchors.left: patArrow.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: patRow.cell
                ghost: "replace with"
                onAccepted: root.applyBulkReplace(findField.text, replField.text)
                onTabbed: bulk.focusRow(0)
                onBackTabbed: findField.claim()
              }

              DialogButton {
                id: replBtn
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                label: "Replace"
                ink: Zenon.cyan
                ready: findField.text !== ""
                onClicked: root.applyBulkReplace(findField.text, replField.text)
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Zenon.msgBorder
            }

            // ── the verbs ─────────────────────────────────────────
            // A find and a replace answer "change this into that", which is
            // one of the things batch renaming is for and not the common one.
            // The rest — put these in order, make the case consistent, get the
            // underscores out — are not patterns at all, they are the same
            // edit applied to every row, and doing them through find/replace
            // means writing a regular expression to say "lowercase".
            //
            // They stack: each reads the rows as they stand, so numbering and
            // then tidying is two presses. Reset goes back to the names the
            // card opened with, because a stack of verbs needs a bottom.
            Item {
              width: parent.width
              height: 42

              Row {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                BulkVerb { label: "abc";  onClicked: root.applyBulkCase("lower") }
                BulkVerb { label: "ABC";  onClicked: root.applyBulkCase("upper") }
                BulkVerb { label: "Abc";  onClicked: root.applyBulkCase("title") }
                BulkVerb { label: "tidy"; onClicked: root.applyBulkTidy() }
                BulkVerb { label: "1 ·";  onClicked: root.applyBulkNumber("prefix") }
                BulkVerb { label: "· 1";  onClicked: root.applyBulkNumber("suffix") }
              }

              Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Two switches rather than two more verbs: they change what
                // every button above MEANS rather than doing anything
                // themselves, and a thing that stays on has to look like it.
                // Written out rather than symbolised. There is room, and
                // ".*" meaning "regular expression" is a thing you either
                // already know or cannot guess.
                BulkVerb {
                  label: "keep .ext"
                  on: root.bulkStemOnly
                  onClicked: root.bulkStemOnly = !root.bulkStemOnly
                }
                BulkVerb {
                  label: "regex"
                  on: root.bulkRegex
                  onClicked: root.bulkRegex = !root.bulkRegex
                }
                BulkVerb {
                  label: "undo"
                  // Dimmed rather than hidden when there is nothing to undo:
                  // a button that comes and goes moves the two beside it.
                  dim: root.bulkHistory.length === 0
                  onClicked: root.undoBulkEdit()
                }
                BulkVerb {
                  label: "reset"
                  dim: root.bulkEdits.join("\u0000") === root.bulkNames.join("\u0000")
                  onClicked: root.resetBulkEdits()
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Zenon.msgBorder
            }

            // ── the two columns ───────────────────────────────────
            Rectangle {
              width: parent.width
              height: 22
              color: Zenon.headBg

              Text {
                x: 46
                width: (parent.width - 60) * 0.42
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "NOW"
                color: Zenon.muted
                font.family: Zenon.faceFixed
                font.pixelSize: 12
              }

              Text {
                x: 46 + (parent.width - 60) * 0.42 + 12
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "TO"
                color: Zenon.muted
                font.family: Zenon.faceFixed
                font.pixelSize: 12
              }

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Zenon.msgBorder
              }
            }

            Item {
              width: parent.width
              // Sized to what it holds, up to the room the card has left. A
              // fixed height left a band of empty card under three names and
              // could not show thirty.
              height: Math.max(34, Math.min(bulkList.contentHeight,
                bulk.height - 100 - 26 - 46 - 1 - 22 - 52))

              SelectBar {
                view: bulkList
                index: bulk.at
                rowH: 30
                on: root.bulkNames.length > 0
              }

              ListView {
                id: bulkList
                anchors.fill: parent
                clip: true
                model: root.bulkNames.length
                // The fields are live TextInputs holding unsaved text, and a
                // recycled delegate would carry one row's caret into another.
                reuseItems: false

                delegate: Item {
                  id: bulkRow
                  required property int index
                  width: bulkList.width
                  height: 30

                  readonly property string issue:
                    bulk.issues[bulkRow.index] === undefined
                      ? "" : bulk.issues[bulkRow.index]
                  readonly property bool moved:
                    root.bulkEdits[bulkRow.index] !== root.bulkNames[bulkRow.index]

                  // No cursor fill: that is the SelectBar beside the view.
                  // The issue tint stays — it is about the ROW's text being
                  // wrong, not about where the cursor is, and it has to be
                  // visible on rows the cursor is nowhere near.
                  Rectangle {
                    anchors.fill: parent
                    color: bulkRow.issue !== ""
                      ? Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.10)
                      : "transparent"
                  }

                  // The row number, because the duplicate warning names one.
                  Text {
                    x: 0
                    width: 40
                    height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: bulkRow.index + 1
                    color: Zenon.muted
                    font.family: Zenon.face
                    font.pixelSize: 12
                  }

                  Text {
                    id: wasName
                    x: 46
                    width: (parent.width - 60) * 0.42
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.bulkNames[bulkRow.index] || ""
                    elide: Text.ElideMiddle
                    // Dimmed once the row is going to change: the old name is
                    // then history, and the eye should be on the new one.
                    color: bulkRow.moved ? Zenon.muted : Zenon.keyInk
                    font.family: Zenon.face
                    font.pixelSize: 14
                  }

                  TextInput {
                    id: toName
                    x: wasName.x + wasName.width + 12
                    width: parent.width - x - 14 - (issueText.visible ? issueText.width + 10 : 0)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.bulkEdits[bulkRow.index] || ""
                    color: bulkRow.issue !== "" ? Zenon.red
                      : (bulkRow.moved ? Zenon.cyan : Zenon.white)
                    selectionColor: Zenon.selBg
                    selectedTextColor: Zenon.white
                    font.family: Zenon.face
                    font.weight: bulkRow.moved ? Font.Bold : Font.Medium
                    font.pixelSize: 14
                    clip: true

                    onTextEdited: root.setBulkEdit(bulkRow.index, toName.text)
                    onActiveFocusChanged: if (activeFocus) bulk.at = bulkRow.index

                    // Down and up walk the list, which is what a column of
                    // fields is for; Tab walks the whole card, pattern fields
                    // included. Return commits the batch from any of them, so
                    // the common case never needs the pointer.
                    Keys.onPressed: (e) => {
                      if (e.key === Qt.Key_Tab) {
                        e.accepted = true; bulk.tabFromRow(bulkRow.index); return;
                      }
                      if (e.key === Qt.Key_Backtab) {
                        e.accepted = true; bulk.backTabFromRow(bulkRow.index); return;
                      }
                    }
                    Keys.onDownPressed: (e) => {
                      e.accepted = true;
                      bulk.focusRow(bulkRow.index + 1);
                    }
                    Keys.onUpPressed: (e) => {
                      e.accepted = true;
                      bulk.focusRow(bulkRow.index - 1);
                    }
                    Keys.onReturnPressed: (e) => {
                      e.accepted = true;
                      if (bulk.sound) root.commitBulkRename();
                    }
                    Keys.onEnterPressed: (e) => {
                      e.accepted = true;
                      if (bulk.sound) root.commitBulkRename();
                    }

                    // A delegate cannot be handed focus from outside, so it
                    // takes it when the card says this row is the one. The
                    // STEM is selected and the extension is not, for the same
                    // reason the in-place rename does it: a bulk rename is
                    // almost never about the type.
                    Connections {
                      target: bulk
                      function onAtPulseChanged() {
                        if (bulk.at !== bulkRow.index) return;
                        toName.forceActiveFocus();
                        const st = Terminus.stem(toName.text);
                        toName.select(0, st.length > 0 ? st.length : toName.text.length);
                      }
                    }
                    Component.onCompleted: {
                      if (bulk.at !== bulkRow.index) return;
                      toName.forceActiveFocus();
                      const st = Terminus.stem(toName.text);
                      toName.select(0, st.length > 0 ? st.length : toName.text.length);
                    }
                  }

                  // WHY the row is red, on the row. A card that only greyed
                  // out its own button left you comparing thirty names by eye
                  // to find the two that collided.
                  Text {
                    id: issueText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bulkRow.issue !== ""
                    text: bulkRow.issue
                    color: Zenon.red
                    font.family: Zenon.face
                    font.pixelSize: 12
                  }
                }
              }

              ScrollRail {
                target: bulkList
                anchors.top: bulkList.top
                anchors.bottom: bulkList.bottom
                x: bulkList.x + bulkList.width - width - 2
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Zenon.msgBorder
            }

            // ── what it will do, and the two answers ──────────────
            Item {
              width: parent.width
              height: 52

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: !bulk.sound ? "fix the marked names"
                  : (bulk.changes === 0 ? "nothing changed"
                    : bulk.changes + (bulk.changes === 1
                        ? " name will change" : " names will change"))
                color: !bulk.sound ? Zenon.red
                  : (bulk.changes === 0 ? Zenon.muted : Zenon.cyan)
                font.family: Zenon.face
                font.pixelSize: 14
              }

              Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                DialogButton {
                  label: "Cancel"
                  ink: Zenon.muted
                  onClicked: bulk.dismiss()
                }

                DialogButton {
                  label: "Rename"
                  ink: Zenon.cyan
                  primary: true
                  ready: bulk.sound && bulk.changes > 0
                  onClicked: root.commitBulkRename()
                }
              }
            }
          }
        }
      }
    }

    // ── permissions ───────────────────────────────────────────────────
    // Nine bits, shown as the grid they are. The octal and the rwxrwxrwx
    // string are both on screen because those are the two forms every other
    // tool speaks, and reading one off the other in your head is exactly the
    // step that gets a mode wrong.
    Rectangle {
      id: perms
      anchors.fill: parent
      z: 12
      visible: opacity > 0.01
      opacity: perms.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: perms.open ? permsSheet.slideIn : permsSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      property int mode: 0
      property var paths: []
      // WHAT IT LOOKED LIKE IN THE LISTING, captured with the paths rather
      // than looked up afterwards — the card maps rows down to paths and the
      // glyph would be gone by the time the bar asked for it. Only meaningful
      // for one item; a mixed set has no single glyph, the same way it has no
      // single mode.
      property string icon: ""
      property color iconInk: Zenon.cyan
      // Which of the nine boxes the keyboard is on, read across then down:
      // owner r w x, group r w x, other r w x — the order chmod writes them
      // and the order they are drawn in. The dialog was mouse-only.
      property int cursor: 0
      readonly property int cursorBit:
        [4, 2, 1][perms.cursor % 3] << (6 - Math.floor(perms.cursor / 3) * 3)
      function toggleCursor() { perms.mode = perms.mode ^ perms.cursorBit; }

      function ask() {
        const rows = root.acting();
        if (rows.length === 0) return;
        perms.paths = rows.map((r) => r.path);
        perms.icon = rows.length === 1 && rows[0].glyph !== undefined
          ? rows[0].glyph : "";
        perms.iconInk = rows.length === 1 ? root.inkFor(rows[0]) : Zenon.cyan;
        // the cursor's mode is the starting point even for a multi-select:
        // there is no single answer for a mixed set, and picking one of them
        // is more honest than showing zero
        perms.mode = rows[0].mode || 0;
        perms.cursor = 0;
        perms.open = true;
      }

      function apply() {
        root.run(Terminus.chmodCommand(perms.paths, perms.mode));
        perms.open = false;
        content.forceActiveFocus();
      }

      InputShield {
        onClicked: { perms.open = false; content.forceActiveFocus(); }
      }

      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      Sheet {
        id: permsSheet
        shown: perms.open
        fromTop: tabStrip.height + crumbBar.height
        // Sized to the grid it holds: 78 label + 3x62 boxes + 40 for the
        // row's octal digit is 304, and 40 either side of that is the margin
        // everything else in the card lines up to.
        cardW: 384
        // Sized to what is in it, like every other dialog here. It was a fixed
        // 208 that happened to fit the type it had; enlarging the type left a
        // band of empty card under the buttons, and the next change to its
        // contents would have done the same thing again.
        cardH: permsCol.implicitHeight

        Column {
          id: permsCol
          width: parent.width

          // ONE RHYTHM. Everything below the title is 12px apart and the grid
          // is centred rather than left-padded — it used to start 40px in and
          // end 146px short of the right edge, which is what made the card
          // look like it was leaning.
          readonly property int gap: 12
          readonly property int labelW: 78
          readonly property int cellW: 62
          readonly property int octW: 40

          // The caption band stood here. It is drawn on the bar now — see
          // sheetBarHead — because a sheet says what it is where it hangs from.
          // The rhythm's own gap stays: the sheet adds no air, so the first
          // row has to bring it like every other row does.
          Item { width: 1; height: permsCol.gap }

          // The answer in both spellings on one line — the octal you would
          // type at chmod and the rwx string ls prints. They are the same
          // number said twice, so they belong side by side rather than stacked.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ("000" + (perms.mode & 511).toString(8)).slice(-3)
              color: Zenon.cyan
              font.family: Zenon.faceMono
              font.weight: Font.Bold
              font.pixelSize: 30
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: 24
              color: Zenon.msgBorder
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Terminus.modeString(perms.mode)
              color: Zenon.sand
              font.family: Zenon.faceMono
              font.weight: Font.Bold
              font.pixelSize: 21
            }
          }

          Item { width: 1; height: permsCol.gap }

          // The four modes anyone actually types. A permissions dialog whose
          // quickest route to 755 is nine clicks is a dialog that has not
          // finished the job.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
              model: [
                ["644", 420], ["755", 493], ["600", 384], ["700", 448]
              ]

              delegate: Rectangle {
                required property var modelData
                readonly property bool on: (perms.mode & 511) === modelData[1]
                width: 62
                height: 24
                radius: 4
                color: on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
                  : (presetHov.hovered ? Zenon.hoverTint : "transparent")
                border.width: 1
                border.color: on ? Zenon.cyan : Zenon.msgBorder
                Behavior on color {
                  ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData[0]
                  color: parent.on ? Zenon.cyan : Zenon.muted
                  font.family: Zenon.faceMono
                  font.pixelSize: 14
                }

                HoverHandler { id: presetHov }
                MouseArea {
                  anchors.fill: parent
                  // the high bits — setuid and friends — are left alone: this
                  // is a shortcut for the nine, not a reset of the whole mode
                  onClicked: perms.mode = (perms.mode & ~511) | modelData[1]
                }
              }
            }
          }

          Item { width: 1; height: permsCol.gap + 2 }

          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.msgBorder
          }

          Item { width: 1; height: permsCol.gap }

          // A GRID with its columns named, rather than three unlabelled rows
          // of three: r, w and x are not obvious from the boxes alone, and the
          // heading costs one row of small type.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18

            Item { width: permsCol.labelW; height: 1 }
            Repeater {
              model: ["read", "write", "exec"]
              delegate: Text {
                required property var modelData
                width: permsCol.cellW
                height: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Zenon.msgBorder
                font.family: Zenon.face
                font.pixelSize: 12
              }
            }
            Item { width: permsCol.octW; height: 1 }
          }

          // three rows of three, in the order chmod writes them
          Repeater {
            model: [["owner", 6], ["group", 3], ["other", 0]]

            delegate: Row {
              id: permRow
              required property var modelData
              required property int index
              readonly property int shift: modelData[1]
              anchors.horizontalCenter: parent.horizontalCenter
              height: 34

              Text {
                width: permsCol.labelW
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: modelData[0]
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }

              Repeater {
                model: [["r", 4], ["w", 2], ["x", 1]]

                delegate: Item {
                  required property var modelData
                  required property int index
                  width: permsCol.cellW
                  height: parent.height

                  readonly property int bit: modelData[1] << permRow.shift
                  readonly property bool on: (perms.mode & bit) !== 0
                  readonly property bool here:
                    perms.cursor === permRow.index * 3 + index

                  Rectangle {
                    anchors.centerIn: parent
                    width: 50
                    height: 26
                    radius: 4
                    color: parent.on
                      ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
                      : (bitHov.hovered ? Zenon.hoverTint : "transparent")
                    border.width: parent.here ? 2 : 1
                    border.color: parent.here ? Zenon.sand
                      : (parent.on ? Zenon.cyan : Zenon.msgBorder)
                    Behavior on color {
                      ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                    }

                    Text {
                      anchors.centerIn: parent
                      text: modelData[0]
                      color: parent.parent.on ? Zenon.cyan : Zenon.muted
                      font.family: Zenon.faceMono
                      font.weight: Font.Bold
                      font.pixelSize: 16
                    }
                  }

                  HoverHandler { id: bitHov }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      perms.cursor = permRow.index * 3 + parent.index;
                      perms.mode = perms.mode ^ parent.bit;
                    }
                  }
                }
              }

              // This row's own octal digit, so the three boxes and the number
              // at the top are visibly the same statement.
              Text {
                width: permsCol.octW
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: String((perms.mode >> permRow.shift) & 7)
                color: Zenon.muted
                font.family: Zenon.faceMono
                font.pixelSize: 15
              }
            }
          }

          Item { width: 1; height: permsCol.gap + 2 }

          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.msgBorder
          }

          Item {
            width: parent.width
            height: 54

            Row {
              anchors.centerIn: parent
              spacing: 12

              DialogButton {
                label: "Cancel"
                ink: Zenon.muted
                onClicked: { perms.open = false; content.forceActiveFocus(); }
              }

              DialogButton {
                label: "Apply"
                ink: Zenon.cyan
                primary: true
                onClicked: perms.apply()
              }
            }
          }
        }
      }
    }

    // ── the confirmation ──────────────────────────────────────────────
    // Everything that overwrites or deletes comes through here. Same shape as
    // zeus' kill card, and for the same reason: the thing you are about to act
    // on stays on screen behind the question, dimmed, so you can still read
    // what you picked while you answer for it.
    Rectangle {
      id: confirm
      anchors.fill: parent
      z: 10
      visible: opacity > 0.01
      opacity: confirm.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: confirm.open ? confirmSheet.slideIn : confirmSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      property string heading: ""
      property string detail: ""
      // Which choice the keyboard is on. Starts at 0 — the verb, listed first
      // — so Return still means what it always meant.
      property int pick: 0
      // Every button on the card, Cancel included: { label, ink, act }. A LIST
      // rather than a fixed yes/no pair, because a paste onto a name that is
      // already taken has three real answers and cramming a third one into a
      // second dialog would have been two cards that drift apart.
      property var choices: []

      // Red is reserved for what cannot be undone. Trash is recoverable, so it
      // is a warning colour and not an alarm.
      function verbInk(verb) {
        if (verb === "Delete") return Zenon.red;
        if (verb === "Trash") return Zenon.yellow;
        return Zenon.sand;
      }

      // AND ITS MARK, off the same word, so the two cannot come to disagree
      // about which question is being asked. A bin for the one that can be
      // undone and a cross for the one that cannot — the same split verbInk
      // already draws in yellow and red, and it inks this too. Every other
      // question gets none: a picture makes none of them clearer.
      function verbGlyph(verb) {
        if (verb === "Delete") return "\uF00D";
        if (verb === "Trash") return "\uF014";
        return "";
      }

      // The two-button case, which is most of them, in the shape every existing
      // caller already uses.
      function ask(heading, detail, verb, onYes) {
        confirm.askMany(heading, detail,
          [{ label: verb, ink: confirm.verbInk(verb), act: onYes }]);
      }

      // Cancel is appended here rather than passed in: every one of these can
      // be backed out of, and a caller that forgot to offer the way out would
      // be a dialog with no way out.
      function askMany(heading, detail, choices) {
        const all = choices.slice();
        all.push({ label: "Cancel", ink: Zenon.muted, act: null });
        confirm.pick = 0;
        confirm.heading = heading;
        confirm.detail = detail;
        confirm.choices = all;
        // focus is not claimed here: the item that reads these keys is
        // dialogKeys, which watches `open` on all three dialogs and takes
        // focus itself, with a retry — a delegate that the scene has not
        // finished placing silently drops forceActiveFocus().
        confirm.open = true;
      }

      function choose(i) {
        const c = confirm.choices[i];
        confirm.open = false;
        confirm.choices = [];
        content.forceActiveFocus();
        if (c && c.act) c.act();
      }

      // Enter takes the FIRST choice — the primary one, listed first for that
      // reason — and escape takes none of them.
      function accept() { confirm.choose(0); }

      function dismiss() {
        confirm.open = false;
        confirm.choices = [];
        content.forceActiveFocus();
      }

      InputShield { onClicked: confirm.dismiss() }


      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      Sheet {
        id: confirmSheet
        shown: confirm.open
        fromTop: tabStrip.height + crumbBar.height
        // wider once there are more than two answers, so "Keep both" is not
        // squeezed into a column narrower than its own label
        cardW: confirm.choices.length > 2 ? 700 : 560
        cardH: confirmCol.implicitHeight

        Column {
          id: confirmCol
          width: parent.width

          // The caption band stood here. It is drawn on the bar now — see
          // sheetBarHead — because a sheet says what it is where it hangs from.

          Item {
            width: parent.width
            height: 44

            Text {
              anchors.fill: parent
              anchors.margins: 12
              text: confirm.detail
              color: Zenon.white
              elide: Text.ElideRight
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              font.family: Zenon.face
              font.pixelSize: 16
            }
          }

          // 32 was the button's own 28 plus two pixels a side, which put the
          // border of a Delete you are being asked to think about hard against
          // the card's rounded corner — the row read as clipped rather than
          // laid out. 46 gives it the same 9px of air underneath that every
          // other card here gives its buttons.
          Row {
            width: parent.width
            height: 46

            Repeater {
              model: confirm.choices

              delegate: Item {
                required property var modelData
                required property int index
                width: parent.width / Math.max(1, confirm.choices.length)
                height: parent.height

                DialogButton {
                  anchors.centerIn: parent
                  width: parent.width - 16
                  label: modelData.label
                  ink: modelData.ink
                  onHovered: confirm.pick = index
                  // The one Return takes, which the arrow keys move.
                  primary: index === confirm.pick
                  // one definition of what choosing means — Return goes
                  // through choose(0) and so does a click
                  onClicked: confirm.choose(index)
                }
              }
            }
          }
        }
      }
    }

    // ── THE PALETTE ───────────────────────────────────────────────────────
    // NOT `palette`, and that is not a style choice. Every Item in Qt 6 has a
    // `palette` property of its own, and an item's own property is found
    // before an id declared outside it — so inside the delegate `palette.sel`
    // read a QQuickPalette and came back undefined, which made `on` false on
    // every row forever. The rows were the right size and the colours were
    // right; the comparison was against nothing. Measured: sel=undefined,
    // size=558x30, selBg=#4d45505c.
    // A sheet over root.commands. It borrows the send picker's shape wholesale
    // — type to filter with no field, arrows to move, Return to commit — for
    // the reason that picker states in its own note: the sheet has the
    // keyboard and there is nothing else in it a letter could mean.
    Rectangle {
      id: cmdPalette
      anchors.fill: parent
      z: 13
      visible: opacity > 0.01
      opacity: cmdPalette.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity {
        NumberAnimation {
          duration: cmdPalette.open ? paletteSheet.slideIn : paletteSheet.slideOut
          easing.type: Zenon.ease
        }
      }

      property bool open: false
      property string query: ""
      property int sel: 0

      // Ranked, not merely filtered — the same scorer the file filter uses, so
      // "dup" puts duplicate first rather than somewhere among everything
      // containing those letters in that order.
      // THE SECTION IS MATCHED AGAINST BUT NEVER DRAWN. The groups decide the
      // order, so related rows still sit together, and the name of the group
      // is a word the query can find — "new" and "all" and "top" are each a
      // single word that only means something in company, and typing "tab"
      // has to reach the one that means a tab. It is not a heading, though:
      // headings were a row you had to step past to get anywhere, for a label
      // nobody reads twice.
      readonly property var shown: {
        const q = cmdPalette.query.trim().toLowerCase();
        const all = root.commands;
        if (q === "") return all;
        const hit = [];
        for (let i = 0; i < all.length; i++) {
          const sc = Terminus.fuzzyScore(
            String(all[i].section) + " " + String(all[i].label).toLowerCase()
              + " " + String(all[i].alias).toLowerCase()
              + " " + String(all[i].key), q);
          if (sc >= 0) hit.push({ c: all[i], sc: sc, i: i });
        }
        // ── THE ONES THAT DO SOMETHING FIRST, HERE TOO ──────────────
        // The unfiltered list is partitioned that way and a query used to
        // throw it out: a reference key that scored a shade better than a verb
        // sat above it, so "co" led with `copy path` on some queries and with
        // the copy GROUP HEADING's keys on others. Which half a row is in is
        // not a matter of degree, so it is not left to a score.
        //
        // The score still decides everything inside each half, and the
        // original index still breaks ties inside that.
        hit.sort((a, b) => {
          const ar = a.c.act ? 0 : 1;
          const br = b.c.act ? 0 : 1;
          if (ar !== br) return ar - br;
          return (b.sc - a.sc) || (a.i - b.i);
        });
        const out = [];
        for (let i = 0; i < hit.length; i++) out.push(hit[i].c);
        return out;
      }

      onQueryChanged: cmdPalette.sel = 0

      function ask() {
        cmdPalette.query = "";
        cmdPalette.sel = 0;
        cmdPalette.open = true;
      }

      // Held rather than read back at the end: the flash is long enough for a
      // second keystroke to move the cursor, and what runs is what was lit up.
      property var pending: null

      RowFlash { id: cmdFlash; onDone: () => cmdPalette.fire() }

      function dismiss() {
        cmdFlash.cancel();
        cmdPalette.pending = null;
        cmdPalette.open = false;
        content.forceActiveFocus();
      }

      function step(d) {
        const n = cmdPalette.shown.length;
        if (n === 0) return;
        cmdPalette.sel = (cmdPalette.sel + d + n) % n;
        paletteList.positionViewAtIndex(cmdPalette.sel, ListView.Contain);
      }

      // CLOSED BEFORE THE VERB RUNS, never after. Half of these open another
      // sheet, and a palette still on screen underneath one would be a card
      // over a card — and the two would fight for the keyboard.
      // WHAT THE CURSOR IS ON, and whether it is a thing that can be done.
      // Most of the keymap is not: j is the cursor, escape means four
      // different things, and the mouse gestures are not keys.
      readonly property var atSel: cmdPalette.shown[cmdPalette.sel]
      readonly property bool runnable:
        !!cmdPalette.atSel && !!cmdPalette.atSel.act

      // NOTHING HAPPENS ON A ROW THAT ONLY TELLS YOU SOMETHING, and the sheet
      // stays up — you are reading it. Closing on return would have made the
      // keymap half of this dismiss itself every time a hand finished a
      // thought. The footer says which kind of row you are on.
      function run() {
        if (!cmdPalette.runnable) return;
        if (!cmdFlash.fire(cmdPalette.sel)) return;
        cmdPalette.pending = cmdPalette.atSel;
      }

      // CLOSED BEFORE THE VERB RUNS, never after. Half of these open another
      // sheet, and a palette still on screen underneath one would be a card
      // over a card — and the two would fight for the keyboard.
      function fire() {
        const c = cmdPalette.pending;
        cmdPalette.pending = null;
        cmdPalette.dismiss();
        if (c && c.act) c.act();
      }

      InputShield { onClicked: cmdPalette.dismiss() }

      Sheet {
        id: paletteSheet
        shown: cmdPalette.open
        fromTop: tabStrip.height + crumbBar.height
        // Wider and taller than it was, because it is the keymap now as well
        // as the verbs — ninety-odd rows rather than fifty, read as a page.
        cardW: 620
        readonly property int rowH: 30
        // FOURTEEN, the go and send sheets' page. They are the same shape
        // hanging off the same bar and a page that is one row deeper on this
        // one is a sheet that does not quite match the others.
        readonly property int pageRows: 14
        // THE ROWS AND WHAT HOLDS THEM, AND NOTHING ELSE. The list runs from
        // 6 below the top of the card to 6 above the footer, so those twelve
        // and the footer's own height are the whole of what is not rows. A
        // spare 14 on the end here was 14 pixels the list had and the rows did
        // not — which is exactly one sliver of a fifteenth row, showing under
        // a page that says it holds fourteen.
        cardH: 12 + Math.max(1, Math.min(paletteSheet.pageRows,
                                         cmdPalette.shown.length))
                    * paletteSheet.rowH + paletteFoot.height

        SelectBar {
          view: paletteList
          index: cmdPalette.sel
          rowH: paletteSheet.rowH
        }

        ListView {
          id: paletteList
          anchors.top: parent.top
          anchors.topMargin: 6
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: paletteFoot.top
          anchors.bottomMargin: 6
          clip: true
          model: cmdPalette.shown
          currentIndex: cmdPalette.sel
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged:
            paletteList.positionViewAtIndex(paletteList.currentIndex,
                                            ListView.Contain)

          delegate: Item {
            id: cmdRow
            required property var modelData
            required property int index
            width: paletteList.width
            height: paletteSheet.rowH

            readonly property bool on: cmdRow.index === cmdPalette.sel

            // NO HOVER, and no fill of its own — see the bar above the view.
            // Sweeping the pointer across the list used to drag the cursor
            // with it, which is a second thing moving the selection while the
            // arrow keys are moving it too: reach for the mouse on the way to
            // something else and the row you had picked was gone. A click
            // still picks, because a click is a decision.
            MouseArea {
              anchors.fill: parent
              enabled: !cmdFlash.running
              onClicked: { cmdPalette.sel = cmdRow.index; cmdPalette.run(); }
            }

            FlashOver { flash: cmdFlash; index: cmdRow.index }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.right: cmdKey.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: cmdRow.modelData.label
              elide: Text.ElideRight
              // ── TWO KINDS OF ROW, TWO INKS ──────────────────────────
              // A row that RUNS and a row that only tells you something are
              // different in kind, not in degree: one is a verb you can press
              // return on, the other is a key the window already answers to.
              // Yellow for the verbs, so the half of this list you can act on
              // reads as a list of things to do with a keymap around it.
              //
              // The cursor is not in this: the bar under the row says where it
              // is, and inking the cursor's row as well said the same fact
              // twice and hid which kind of row it was.
              color: cmdRow.modelData.act ? Zenon.yellow : Zenon.white
              font.family: Zenon.face
              font.pixelSize: 16
            }

            // The key it already had, so the palette teaches as well as does.
            KeyChip {
              id: cmdKey
              visible: cmdRow.modelData.key !== ""
              anchors.right: parent.right
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              label: cmdRow.modelData.key
              fontSize: 12
            }
          }
        }

        // ── A LIST THIS LONG NEEDS TO SAY HOW LONG ───────────────────
        // Ninety-odd rows through a fourteen-row window, and the only thing
        // saying so was that the rows kept coming. The shared rail, placed the
        // way every other rail in this window is placed — 2px in from the
        // view it reports on, hidden outright when everything already fits,
        // which is what it does the moment a filter cuts the list to a page.
        //
        // It clears the key chips: they stop 16px from the card's edge and the
        // rail is 10 wide from 2, so the two never meet.
        ScrollRail {
          target: paletteList
          anchors.right: paletteList.right
          anchors.rightMargin: 2
          anchors.top: paletteList.top
          anchors.topMargin: 2
          anchors.bottom: paletteList.bottom
          anchors.bottomMargin: 2
        }

        Rectangle {
          anchors.bottom: paletteFoot.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.msgBorder
        }

        Item {
          id: paletteFoot
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 34

          Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: 2
              text: cmdPalette.query !== "" ? cmdPalette.query
                : (cmdPalette.shown.length === 0 ? "nothing matches"
                                              : "type to filter")
              color: cmdPalette.query !== "" ? Zenon.sand : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 13
            }

            // THE RUN CHIP ONLY WHEN THERE IS SOMETHING TO RUN. This list is
            // half keymap now, and a return chip standing over a row that is
            // the cursor key would have been an offer the palette cannot keep.
            Repeater {
              model: cmdPalette.runnable
                ? [["\u2191\u2193", "move"], ["\u21b5", "run"],
                   ["esc", "close"]]
                : [["\u2191\u2193", "move"], ["esc", "close"]]

              delegate: Row {
                id: pfPair
                required property var modelData
                spacing: 5

                KeyChip {
                  anchors.verticalCenter: parent.verticalCenter
                  label: pfPair.modelData[0]
                  fontSize: 11
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: pfPair.modelData[1]
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 13
                }
              }
            }
          }
        }
      }
    }


    // ── THE BOOKMARKS, ON g b ─────────────────────────────────────────────
    // They are in the sidebar and they are among the go sheet's roots, and
    // neither is the same thing as asking for them: the sidebar is a panel you
    // keep open or you do not, and the go sheet answers "where to?" with every
    // root it has. This answers "which bookmark?" and nothing else.
    //
    // The palette's shape, because it is the palette's problem — a short list
    // you filter with the keyboard and commit with return.
    Rectangle {
      id: marks
      anchors.fill: parent
      z: 13
      visible: opacity > 0.01
      opacity: marks.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity {
        NumberAnimation {
          duration: marks.open ? marksSheet.slideIn : marksSheet.slideOut
          easing.type: Zenon.ease
        }
      }

      property bool open: false
      property int sel: 0
      property string query: ""

      // THE SIDEBAR'S OWN LIST, read straight off root.bookmarks so the two
      // can never disagree about what is bookmarked. Home wears its own name
      // rather than the user's — the basename of ~ is "buck", which no rule
      // claims — the same substitution the sidebar and the go sheet make.
      readonly property var all: {
        const out = [];
        const bs = root.bookmarks;
        for (let i = 0; i < bs.length; i++) {
          const p = bs[i];
          out.push({
            path: p,
            name: p === Paths.home() ? "Home" : Terminus.basename(p),
            glyph: Icons.glyphFor({
              name: p === Paths.home() ? "home" : Terminus.basename(p),
              isDir: true })
          });
        }
        return out;
      }

      // RANKED, not merely filtered — the same scorer the file filter and the
      // palette use. Matched against the PATH as well as the name, because a
      // bookmark two levels inside Steam is found by "steam" more often than
      // by what its own folder happens to be called.
      readonly property var rows: {
        const q = marks.query.trim().toLowerCase();
        const all = marks.all;
        if (q === "") return all;
        const hit = [];
        for (let i = 0; i < all.length; i++) {
          const sc = Terminus.fuzzyScore(
            all[i].name.toLowerCase() + " " + all[i].path.toLowerCase(), q);
          if (sc >= 0) hit.push({ c: all[i], sc: sc, i: i });
        }
        hit.sort((a, b) => (b.sc - a.sc) || (a.i - b.i));
        const out = [];
        for (let i = 0; i < hit.length; i++) out.push(hit[i].c);
        return out;
      }

      onQueryChanged: marks.sel = 0

      function ask() {
        marks.query = "";
        marks.sel = 0;
        marks.open = true;
      }

      // Held rather than read back at the end: the flash is long enough for a
      // second keystroke to move the cursor, and where you go is where it lit.
      property string pendingPath: ""
      property bool pendingTab: false

      RowFlash { id: marksFlash; onDone: () => marks.travel() }

      function dismiss() {
        marksFlash.cancel();
        marks.pendingPath = "";
        marks.open = false;
        content.forceActiveFocus();
      }

      function step(d) {
        const n = marks.rows.length;
        if (n === 0) return;
        marks.sel = (marks.sel + d + n) % n;
        marksList.positionViewAtIndex(marks.sel, ListView.Contain);
      }

      // ── AND IT MANAGES THEM, not just lists them ──────────────────
      // The sheet STAYS OPEN. Removing one is housekeeping and housekeeping
      // comes in runs — a card that closed after each would make tidying four
      // of them four trips through g b.
      //
      // The cursor holds its place rather than its index: with the last row
      // gone there is no row there any more, so it steps back onto the one
      // above instead of off the end of the list.
      // ── REORDER ───────────────────────────────────────────────────
      // The order is the file's order and the sidebar reads the same file, so
      // moving one here moves it there. Alt, because the bare arrows walk the
      // list and a manager that reordered on them could not be scrolled.
      //
      // ONLY WITH NOTHING TYPED. Under a filter the rows on screen are a
      // ranked subset and the one "above" a row is not the one above it in the
      // file — swapping by what you can see would shuffle what you cannot.
      function shift(d) {
        if (marks.query !== "") {
          root.warn("clear the filter to reorder");
          return;
        }
        const from = marks.sel;
        const to = from + d;
        if (from < 0 || to < 0 || to >= marks.rows.length) return;
        root.moveBookmark(from, to);
        marks.sel = to;
      }

      // The other half of a manager: b a is still the way in from the listing,
      // but a panel about bookmarks that cannot make one is a viewer.
      function addHere() {
        const at = root.cwd;
        if (root.bookmarks.indexOf(at) >= 0) {
          root.warn("already bookmarked");
          return;
        }
        root.editBookmarks((list) => list.push(at));
        root.status = "bookmarked " + Terminus.basename(at);
        marks.query = "";
        marks.sel = Math.max(0, marks.rows.length - 1);
      }

      function drop() {
        const r = marks.rows[marks.sel];
        if (!r) return;
        const n = marks.rows.length;
        root.removeBookmark(r.path);
        if (marks.sel >= n - 1) marks.sel = Math.max(0, n - 2);
      }

      function go(inTab) {
        const r = marks.rows[marks.sel];
        if (!r) return;
        if (!marksFlash.fire(marks.sel)) return;
        marks.pendingPath = r.path;
        marks.pendingTab = inTab === true;
      }

      // Closed before it travels, for the reason the palette gives: the sheet
      // is answering a question and the answer is somewhere else.
      function travel() {
        const path = marks.pendingPath;
        const inTab = marks.pendingTab;
        marks.dismiss();
        if (path === "") return;
        if (inTab) root.openInNewTab(path);
        else root.goTo(path);
      }

      InputShield { onClicked: marks.dismiss() }

      Sheet {
        id: marksSheet
        shown: marks.open
        fromTop: tabStrip.height + crumbBar.height
        // SIZED BY THE FOOTER, not by the rows. A bookmark's name and path are
        // short and would sit happily in 520; the hint row is SEVEN pairs long
        // — move, go, tab, order, add, remove, close, with the filter echoed
        // ahead of them — and it is the footer that decides how wide a sheet
        // full of short names has to be.
        cardW: 880
        // A point taller than the palette's, because the rows are: a 17px name
        // in a 30px row leaves four pixels above and below it.
        readonly property int rowH: 32
        readonly property int pageRows: 14
        cardH: 12 + Math.max(1, Math.min(marksSheet.pageRows,
                                         marks.rows.length))
                    * marksSheet.rowH + marksFoot.height

        SelectBar {
          view: marksList
          index: marks.sel
          rowH: marksSheet.rowH
          on: marks.rows.length > 0
        }

        ListView {
          id: marksList
          anchors.top: parent.top
          anchors.topMargin: 6
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: marksFoot.top
          anchors.bottomMargin: 6
          clip: true
          model: marks.rows
          currentIndex: marks.sel
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: markRow
            required property var modelData
            required property int index
            width: marksList.width
            height: marksSheet.rowH

            FlashOver { flash: marksFlash; index: markRow.index }

            MouseArea {
              anchors.fill: parent
              enabled: !marksFlash.running
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              onClicked: (m) => {
                marks.sel = markRow.index;
                // Middle click removes it, the gesture the sidebar's rows and
                // the tab strip already use for "take this away".
                if (m.button === Qt.MiddleButton)
                  root.removeBookmark(markRow.modelData.path);
                else marks.go(false);
              }
            }

            // A FIXED COLUMN for the glyph, not its own width: the nerd font
            // is proportional, so a wide icon ended further right than a
            // narrow one and ran into a name pinned at a constant x. The
            // listing and the go sheet both do this, for the same reason.
            Text {
              id: markGlyph
              x: 16
              width: 22
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: markRow.modelData.glyph
              color: Zenon.cyan
              font.family: Zenon.face
              font.pixelSize: 16
            }

            Text {
              anchors.left: markGlyph.right
              anchors.leftMargin: 8
              anchors.right: markPath.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: markRow.modelData.name
              elide: Text.ElideRight
              color: Zenon.white
              font.family: Zenon.face
              font.pixelSize: 17
            }

            // ── THE WAY OUT, ON THE ROW THE CURSOR IS ON ──────────────
            // Shown for the cursor's row only, so the list is a list until you
            // are standing on something — twelve little crosses down the side
            // is a panel about deleting rather than a panel of places.
            //
            // It sits where the path ends rather than beside it: the path is
            // the quiet half of the row and the cross would have read as part
            // of it.
            Text {
              id: markDrop
              anchors.right: parent.right
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              visible: markRow.index === marks.sel
              text: "\uEA76"
              color: dropHov.hovered ? Zenon.red : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 14

              HoverHandler { id: dropHov }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: {
                  marks.sel = markRow.index;
                  marks.drop();
                }
              }
            }

            // Where it actually is, quietly. Two bookmarks can share a
            // basename and the name alone would be the sheet refusing to say
            // which is which.
            Text {
              id: markPath
              anchors.right: markDrop.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, marksList.width * 0.45)
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
              // ~ for home, the way the breadcrumb writes it: the full path
              // of a bookmark under home is mostly the same eleven characters
              // on every row, and elide would have eaten the useful end of it
              // to keep them.
              text: {
                const h = Paths.home();
                const p = markRow.modelData.path;
                return p === h ? "~"
                  : (p.indexOf(h + "/") === 0 ? "~" + p.slice(h.length) : p);
              }
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 13
            }
          }
        }

        // Nothing bookmarked yet, said where the rows would be rather than as
        // an empty card that looks like something failed to load.
        Text {
          anchors.centerIn: marksList
          visible: marks.all.length === 0
          text: "nothing bookmarked yet \u2014 b a adds this directory"
          color: Zenon.muted
          font.family: Zenon.face
          font.pixelSize: 14
        }

        Rectangle {
          anchors.bottom: marksFoot.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.msgBorder
        }

        Item {
          id: marksFoot
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 34

          Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: 2
              text: marks.query !== "" ? marks.query
                : (marks.rows.length === 0 ? "nothing matches"
                                           : "type to filter")
              color: marks.query !== "" ? Zenon.sand : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 14
            }

            Repeater {
              // SHORT WORDS, because there are seven of them now. The chip
              // carries the key and the word only has to disambiguate it —
              // "tab" after a return glyph cannot mean anything but a new one,
              // and "order" after alt-arrows cannot mean sorting.
              model: [["\u2191\u2193", "move"], ["\u21b5", "go"],
                      ["\u21e7\u21b5", "tab"], ["alt \u2191\u2193", "order"],
                      ["ctrl a", "add"], ["del", "remove"],
                      ["esc", "close"]]

              delegate: Row {
                id: mfPair
                required property var modelData
                spacing: 5

                KeyChip {
                  anchors.verticalCenter: parent.verticalCenter
                  label: mfPair.modelData[0]
                  fontSize: 12
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: mfPair.modelData[1]
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 14
                }
              }
            }
          }
        }
      }
    }

    // ── QUICK LOOK ────────────────────────────────────────────────────────
    // The preview the pane already worked out, at the size of the window. It
    // starts nothing and asks for nothing: previewKind, previewText and the
    // cached frame are all standing answers about the row under the cursor by
    // the time this opens.
    Rectangle {
      id: look
      anchors.fill: parent
      z: 15
      visible: look.opacity > 0.01
      opacity: root.looking ? 1 : 0
      // Darker than a card's scrim. This is the one overlay whose whole job
      // is the thing in the middle of it, so everything else gets out of the
      // way rather than merely standing back.
      color: Qt.rgba(0, 0, 0, 0.82)
      // Asymmetric, the rule every card in this window follows: arriving takes
      // the full normal, leaving takes the fast. One duration for both made
      // opening and dismissing the same event played twice.
      Behavior on opacity {
        NumberAnimation {
          duration: root.looking ? Zenon.normal : Zenon.fast
          easing.type: Zenon.ease
        }
      }

      readonly property var row: root.currentRow()

      // The caption bar's height, named on the OVERLAY rather than on the bar:
      // the picture's height subtracts it and the panel's height adds it, and
      // the bar is anchored inside the panel, so asking the bar itself puts
      // the panel's own geometry in the middle of both sums.
      readonly property real capH: 34

      // ── HOW BIG THE PICTURE IS, ASKED OF SOMETHING THAT IS NOT DRAWN ──
      // PreserveAspectFit keeps an Image's IMPLICIT size in step with its
      // explicit one — set a width and the implicit height follows it. So
      // asking the picture that is being drawn how big it naturally is, in
      // order to decide how big to draw it, is a circle, and Qt says so.
      //
      // This one is never sized, so its implicit size is the decoded size and
      // nothing else. Same source and same sourceSize as the real one, which
      // means Qt serves both out of one decode — it costs a QML item, not a
      // second copy of the picture.
      Image {
        id: lookNat
        visible: false
        asynchronous: true
        sourceSize.width: Math.round(look.width * 0.9)
        sourceSize.height: Math.round(look.height * 0.86)
        source: look.src
      }

      // Capped at 1, because a small picture blown up to fill the window is
      // not a preview of it.
      readonly property real fitScale: {
        const iw = lookNat.implicitWidth;
        const ih = lookNat.implicitHeight;
        if (iw <= 0 || ih <= 0) return 0;
        return Math.min(1, look.width * 0.9 / iw,
                        (look.height * 0.86 - look.capH) / ih);
      }
      readonly property real shotW:
        Math.round(lookNat.implicitWidth * look.fitScale)
      readonly property real shotH:
        Math.round(lookNat.implicitHeight * look.fitScale)

      // ── THE SHAPE IT HAD WHILE THE NEXT ONE IS DECODING ───────────────
      // Stepping to the next picture clears the old one instantly and the new
      // one arrives a frame or two later. In between, shotW is 0, the panel
      // has nothing to be the size of, and it fell back to the size of a card
      // with no picture in it — so every step went small, then big. With the
      // resize eased that was a shrink and a grow; without it, a flash. Either
      // way it reads as the panel closing and reopening, which is the one
      // thing it is not doing.
      //
      // So the last good size is kept and worn through the gap. The panel
      // changes size once, when there is something to change it for.
      property real heldW: 0
      property real heldH: 0
      function holdSize() {
        if (look.shotW > 0 && look.shotH > 0) {
          look.heldW = look.shotW;
          look.heldH = look.shotH;
        }
      }
      onShotWChanged: look.holdSize()
      onShotHChanged: look.holdSize()

      // The row WANTS a picture and has not got one yet — as against a text
      // file, which never will and should collapse to its own size at once.
      readonly property bool pending: look.src !== ""
        && lookShot.status !== Image.Ready && lookShot.status !== Image.Error

      // ── ASKED OF THE FILE, NOT OF THE PREVIEW PANE ───────────────────
      // This read root.previewKind, which is the miller column's state — and
      // the miller column only exists in the columns view. In a list or a
      // grid nothing had computed it, so previewKind was "none" and every
      // picture opened as "nothing to show for this one".
      //
      // The row itself always knows, in every view, by the same functions the
      // grid's tiles use.
      readonly property bool pic:
        look.row ? Terminus.isImage(look.row.name) : false
      readonly property bool framed: look.row
        && (Terminus.isVideo(look.row.name) || Terminus.isAudio(look.row.name))

      // The file itself for a picture; the cached frame for a film or a cover,
      // which is the only image either of those has.
      readonly property string src: {
        const r = look.row;
        if (!r) return "";
        if (look.pic) return "file://" + r.path;
        if (look.framed)
          return root.thumbFile[r.path] ? "file://" + root.thumbFile[r.path] : "";
        return "";
      }

      InputShield { onClicked: root.looking = false }

      // ── THE PREVIEW AND ITS NAME, AS ONE PANEL ───────────────────────
      // The name used to float against the scrim along the bottom of the
      // WINDOW, which on a picture half the window tall left it stranded an
      // inch under the thing it was naming. A caption belongs to what it
      // captions, so it is a bar across the bottom of the panel now and the
      // panel is whatever there is to show — a picture, or the text preview.
      //
      // THE FRAME IS SIZED TO THE CONTENT, not the content to the frame.
      // lookShot takes its bounds from the window and the panel then takes the
      // picture's PAINTED size, which is the only number that knows where the
      // picture actually ends after PreserveAspectFit has had it. The other
      // way round is a binding loop: the painted size is what the frame would
      // be asking for.
      ClippingRectangle {
        id: lookFrame
        anchors.centerIn: parent
        color: Zenon.black
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: Zenon.dialogRadius

        readonly property real textW: Math.min(900, look.width * 0.8)

        // NOTHING TO READ IS NOT A SHORT DOCUMENT. With no preview text the
        // column is empty and the card collapsed onto its own caption bar —
        // a sentence saying there is nothing to show needs somewhere to be
        // shown, so the card keeps a fixed, modest height for that case.
        readonly property real emptyH: 120

        // Held through the decode — see look.heldW — so a step between two
        // pictures is one change of size rather than a collapse and a recovery.
        readonly property bool holding: look.pending && look.heldW > 0

        width: lookShot.visible ? look.shotW
          : (lookFrame.holding ? look.heldW : lookFrame.textW)
        height: look.capH + (lookShot.visible ? look.shotH
          : (lookFrame.holding ? look.heldH
             : (root.previewText !== ""
                ? Math.min(lookCol.implicitHeight + 32, look.height * 0.8)
                : lookFrame.emptyH)))

        // ── NO EASING ON THE SIZE ─────────────────────────────────────
        // The panel used to ease between sizes, on the reasoning that stepping
        // files should be one panel changing shape rather than two panels.
        // With the size now HELD across the decode there is nothing to ease:
        // the change happens once, when the new picture is already in hand,
        // and easing it only delays the picture you asked for.
        //
        // Which leaves this overlay animating on exactly two events — opening
        // and closing. Everything in between is instant, which is what a
        // viewer you flick through should be.

        // THE ARRIVAL EVERY OTHER CARD HAS AND THIS ONE DID NOT. It appeared
        // at full size the instant the scrim began to fade, which reads as a
        // cut rather than as something being opened. CardRise and CardGrow are
        // the shared pair — rise and grow on travelEase, asymmetric in and
        // out — so quick look opens the way the menus and the cards do.
        transform: [
          CardGrow { shown: root.looking; card: lookFrame },
          CardRise { shown: root.looking }
        ]

        Image {
          id: lookShot
          // PLACED, NOT ANCHORED. The panel is sized to this picture, so a
          // horizontalCenter anchor is a loop: the picture's x would come from
          // the panel's width and the panel's width comes from the picture.
          // The panel IS the picture's size, so the corner is 0, 0 — and the
          // border draws over the edge, which is what a frame is.
          x: 0
          y: 0
          // Ninety per cent of the window, less the caption bar, which is
          // part of the panel now and has to fit in the same room. The
          // arithmetic is look.fitScale; this is the result of it, which is
          // already aspect-correct and therefore exactly what is drawn.
          width: look.shotW
          height: look.shotH
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: look.src !== "" && look.shotW > 0
            && lookShot.status === Image.Ready
          // Decoded at the size it is drawn, which for this is most of a
          // monitor — the grid's 480px cache would be a blur at that size.
          sourceSize.width: Math.round(look.width * 0.9)
          sourceSize.height: Math.round(look.height * 0.86)
          source: look.src
        }

        // Everything that is not a picture: the text preview the pane already
        // read, or the name and the reason there is nothing to show.
        Flickable {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: lookCap.top
          anchors.margins: 16
          visible: !lookShot.visible && root.previewText !== ""
          clip: true
          contentWidth: width
          contentHeight: lookCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: lookCol
            width: parent.width
            spacing: 10

            Text {
              width: parent.width
              text: root.previewText
              textFormat: Text.RichText
              wrapMode: Text.Wrap
              color: Zenon.white
              font.family: Zenon.faceMono
              font.pixelSize: 14
            }
          }
        }

        // ── AND WHEN THERE IS NOTHING ───────────────────────────────
        // Its own item rather than a third state of the text above: that one
        // is a document — left-aligned, monospaced, scrollable, starting at
        // the top because that is where a file starts. This is a SENTENCE
        // ABOUT the file, and it belongs in the middle of the space it is
        // explaining rather than in the corner of it.
        //
        // Yellow, the ink this window gives a thing that can be acted on and
        // an answer that is not a failure: the file is fine, terminus simply
        // has no way to show it. Muted read as though something had gone
        // wrong and been swallowed.
        Text {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: lookCap.top
          // NOT WHILE ONE IS ON ITS WAY. "no preview available" is an answer
          // about the file, and during a decode there is no answer yet.
          visible: !lookShot.visible && !look.pending
                   && root.previewText === ""
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: "no preview available"
          color: Zenon.yellow
          font.family: Zenon.face
          font.pixelSize: 15
        }

        // ── THE NAME, AS A BAR RATHER THAN A CAPTION ─────────────────
        // headBg over the panel's black, which is the same pairing the path
        // bar has with the window: a strip that is part of the surface and a
        // shade off it, rather than a separate thing laid on top.
        Rectangle {
          id: lookCap
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: look.capH
          color: Zenon.headBg

          // The seam every strip in this window uses. Without it the bar and
          // a dark picture above it ran together into one shape.
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.msgBorder
          }

          // ── THE NAME LEFT, THE KEYS RIGHT ─────────────────────────
          // Centred, the name moved every time you stepped to a file with a
          // longer one — a title that shifts under the eye on every keypress,
          // in the one place you are pressing a key repeatedly. Pinned left it
          // starts in the same spot whatever it says, and the room it is not
          // using is where the keys go.
          Text {
            id: lookName
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: lookKeys.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideMiddle
            text: look.row ? look.row.name : ""
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 15
          }

          // WHAT MOVES YOU, said on the bar rather than left to be discovered.
          // Quick look has no footer of its own — the caption bar IS the
          // chrome — so the hint lives beside the name it is about.
          Row {
            id: lookKeys
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            KeyChip {
              anchors.verticalCenter: parent.verticalCenter
              label: "h / l"
              fontSize: 11
            }
            KeyChip {
              anchors.verticalCenter: parent.verticalCenter
              label: "\u2190 / \u2192"
              fontSize: 11
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: 3
              text: "prev / next"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 12
            }
          }
        }
      }
    }

    // ── SEND TO: copy or move without going there ─────────────────────────
    // "Copy to…" and "Move to…" on the row menu. The point is not having to
    // navigate to the destination first — pick it out of a tree and the
    // transfer starts from where you are standing.
    //
    // IT DOES NO FILE WORK OF ITS OWN, and that is the whole design. pasteDest
    // already exists for the one gesture that pastes somewhere other than the
    // cwd, so this sets the same property and calls the same paste(). Conflict
    // resolution, the undo record a move leaves, the job queue, the status
    // line and the refresh of the destination all behave exactly as they do
    // for an ordinary paste, because they ARE the ordinary paste.
    Rectangle {
      id: sendTo
      anchors.fill: parent
      z: 11
      // NO DIM. A sheet is a picker, not a warning — and the listing behind
      // it is what the choice is ABOUT, so darkening it hid the thing you
      // were looking at to decide. The card has the menus' shadow to sit
      // against the window on, which is separation enough.
      //
      // The overlay stays, because it is what catches every click that misses
      // the card — see the MouseArea below. It simply paints nothing now.
      color: "transparent"
      opacity: 1
      // Held up by the sheet rather than by a fade of its own: with nothing
      // to dim there is nothing here to animate, and the card's own fade is
      // what says when the sheet has gone.
      visible: sendTo.open || sendToCard.opacity > 0.01

      // ── HOW WIDE THE WIDEST ROW WANTS TO BE ──────────────────────────
      // The crawl answers with PATHS, and a path is as long as it is — at a
      // fixed width the useful half of every deep hit sat behind an ellipsis,
      // which is the one thing a list of destinations cannot afford. So the
      // sheet measures what it is holding and takes the room.
      //
      // FontMetrics, because advanceWidth is a method a binding can CALL —
      // TextMetrics is an object you set and then read, which is no use
      // inside a loop over a hundred rows.
      //
      // The sum is the delegate's own layout: the indent for its depth, the
      // twisty and the glyph ahead of the name, and the room kept clear at
      // the end for the bookmark mark.
      FontMetrics {
        id: sendToFm
        font.family: Zenon.face
        font.pixelSize: 15
      }

      readonly property real wantWidth: {
        let w = 0;
        const rows = sendTo.shown;
        for (let i = 0; i < rows.length; i++) {
          // 18 to the glyph column, 22 across it, 8 to the name — the
          // delegate's own layout, which is why it is spelled out rather than
          // rounded to one number.
          const t = 10 + rows[i].depth * 14 + 18 + 22 + 8
                  + sendToFm.advanceWidth(rows[i].name) + 34;
          if (t > w) w = t;
        }
        return w;
      }

      // WHAT THE BAR ASKS THE SHEET. Read from crumbBar's two rule segments
      // so its bottom edge can open a gap exactly where this hangs from it.
      readonly property bool splicing: sendToCard.opacity > 0.01
      readonly property real spliceX: sendToCard.x
      readonly property real spliceW: sendToCard.width

      property bool open: false
      property string op: "copy"
      // CAPTURED WHEN THE MENU ENTRY IS CHOSEN, not read back when you pick a
      // destination. commitPaste clears the marks, and a picker that asked
      // "which rows?" afterwards would answer with none of them.
      property var paths: []
      property var names: []
      // WHAT IS MOVING, AS THE LISTING DRAWS IT. Taken from the enriched rows
      // at the moment they are captured — the same glyph and the same ink the
      // file wears on its own line — so the header names the thing in the
      // vocabulary you were just reading it in. Several at once have no single
      // icon, so they get Material's file-multiple (U+F12F7).
      property string icon: ""
      property color iconInk: Zenon.white
      // The tree, flattened: every row on screen in order, each carrying the
      // depth it is drawn at. Children are spliced in under their parent and
      // spliced out again when it closes.
      property var nodes: []
      property int sel: 0
      // The one directory being read. One at a time: a tree you are walking
      // fast would otherwise have four reads in flight for branches you have
      // already left, and the answers arrive in whatever order they finish.
      property string loadFor: ""

      // WHETHER THERE IS A VERB TO NAME. Copy and move have to say which
      // they are; `go` has nothing to disambiguate, so it drops the leading
      // glyph and lets the sentence start with the place you are leaving.
      readonly property bool sending: sendTo.op !== "go"

      readonly property string verb: sendTo.op === "go" ? "Go to"
        : sendTo.op === "copy" ? "Copy" : "Move"
      // ── WHAT CANNOT BE A DESTINATION ─────────────────────────────────
      // A directory cannot go inside itself, or inside anything it contains.
      // Pasting could always be asked to do it too, but you had to walk into
      // the folder first and nobody does that by accident — here the child is
      // sitting on screen one keystroke below its own parent, and rsync will
      // copy a folder into its own subdirectory for as long as the disk holds
      // out. Refused at the point of choosing rather than filtered out of the
      // tree: a branch you cannot land on is still a branch you walk THROUGH.
      //
      // Written out rather than calling bans() so the binding actually
      // depends on what it reads — a binding does not re-evaluate on a
      // function call, which this file has paid for more than once.
      readonly property bool blocked: {
        const n = sendTo.current;
        if (!n) return true;
        for (let i = 0; i < sendTo.paths.length; i++) {
          const p = sendTo.paths[i];
          if (n.path === p || n.path.indexOf(p + "/") === 0) return true;
        }
        return false;
      }

      function bans(path) {
        for (let i = 0; i < sendTo.paths.length; i++) {
          const p = sendTo.paths[i];
          if (path === p || path.indexOf(p + "/") === 0) return true;
        }
        return false;
      }

      // ── TYPE AND IT NARROWS ──────────────────────────────────────────
      // No field, no prompt, no slash to start it: the sheet has the keyboard
      // and there is nothing else in it a letter could mean, so a letter
      // filters. Which is exactly why the vim keys are not bound in here —
      // `j` and `l` are letters first in a box you can type into, and a
      // picker that sometimes moved and sometimes typed would be neither.
      // Arrows move; everything printable filters.
      property string query: ""

      // ── A SPACE IS AND ─────────────────────────────────────────────
      // Typing narrows; typing a second word narrows what the first one
      // left. "config" finds every config directory on the disk, and
      // "config buck" keeps the ones under /home/buck — which is how you
      // actually arrive at a destination: you remember the name first and
      // where it lives second.
      //
      // Held as a property rather than split inside the sift, because a
      // binding tracks the properties it READS and this file has paid more
      // than once for dependencies hidden behind a function call.
      readonly property var terms: {
        const out = [];
        const parts = sendTo.query.toLowerCase().split(/\s+/);
        for (let i = 0; i < parts.length; i++)
          if (parts[i] !== "") out.push(parts[i]);
        return out;
      }

      onQueryChanged: {
        sendTo.sel = 0;
        sendTo.hits = [];
        // One letter matches most of a filesystem, so the crawl waits for a
        // second one; the local sift runs from the first keystroke either way.
        if (sendTo.terms.join("").length >= 2) sendToCrawl.restart();
        else { sendToCrawl.stop(); sendToFind.running = false; sendTo.crawling = false; }
      }

      // ── AND IT LOOKS PAST WHAT IS OPEN ───────────────────────────────
      // The sift above can only answer about branches you have already
      // expanded, which makes the filter a way of re-reading the tree rather
      // than a way of finding somewhere. So typing also sends out one search
      // for directories under the places that are worth searching, and what
      // comes back is listed underneath the local matches as flat rows.
      //
      // FLAT, DELIBERATELY. A hit six levels down would otherwise need its
      // whole ancestry synthesised into the tree to be drawn in place, and
      // the result is harder to read than the path itself: the answer to
      // "where?" is the path, so the row is the path.
      property var hits: []
      property bool crawling: false

      // ── THE GLYPH A NODE WEARS ───────────────────────────────────────
      // OFF THE PATH, NEVER OFF THE NAME. A row found by the crawl is drawn
      // as its path — "~/.config/quickshell" is the answer to "where?", which
      // a bare basename is not — and that name went to the icon table, which
      // has no rule for a whole path and handed back the plain folder. So
      // every hit in both sheets was a generic folder while the identical
      // directory two rows up in the tree wore its own glyph.
      //
      // Home by its own name rather than by the user's: the basename of ~ is
      // "buck", which no rule claims, and the tree's root row for it is
      // labelled "Home" for the same reason.
      function glyphOf(n) {
        if (!n) return "";
        return Icons.glyphFor({
          name: n.path === Paths.home() ? "home" : Terminus.basename(n.path),
          isDir: true });
      }

      function pretty(p) {
        const h = Paths.home();
        if (p === h) return "~";
        return p.indexOf(h + "/") === 0 ? "~" + p.slice(h.length) : p;
      }

      Timer {
        id: sendToCrawl
        interval: 220
        onTriggered: {
          if (!sendTo.open || sendTo.query.length < 2) return;
          sendTo.crawling = true;
          sendToFind.running = false;
          sendToFind.command = ["sh", "-c",
            Terminus.dirFindCommand(sendTo.query)];
          sendToFind.running = true;
        }
      }

      Process {
        id: sendToFind
        stdout: StdioCollector {
          id: sendToFound
          waitForEnd: true
          onStreamFinished: {
            sendTo.crawling = false;
            if (!sendTo.open) return;
            const out = [];
            const parts = sendToFound.text.split("\u0000");
            for (let i = 0; i < parts.length; i++) {
              // fd ends a directory with a slash — see dirFindCommand.
              let p = parts[i];
              if (p.length > 1 && p.charAt(p.length - 1) === "/")
                p = p.slice(0, -1);
              if (p !== "") out.push(p);
            }
            sendTo.hits = out;
          }
        }
      }

      // WHAT IS ON SCREEN, which is the whole tree until you type. A match
      // keeps its ANCESTORS too — a hit six levels down with its parents
      // stripped out is a name with no answer to "where?", and the depth
      // indents would be measuring nothing.
      //
      // Only over what has been loaded — the crawl below is what looks
      // further than the branches you have opened.
      readonly property var shown: {
        const t = sendTo.terms;
        if (t.length === 0) return sendTo.nodes;
        const n = sendTo.nodes;
        const keep = [];
        // AGAINST THE PATH, for the same reason the crawl is — a word like
        // "buck" is never in the folder's own name, it is in where the
        // folder lives. Inlined rather than called: see the note on `terms`.
        for (let i = 0; i < n.length; i++) {
          const hay = n[i].path.toLowerCase();
          let all = true;
          for (let k = 0; k < t.length; k++)
            if (hay.indexOf(t[k]) < 0) { all = false; break; }
          keep.push(all);
        }
        // Backwards, so a kept row can mark the parents above it and those
        // parents are themselves passed over later in the same sweep.
        for (let i = n.length - 1; i >= 0; i--) {
          if (!keep[i]) continue;
          let d = n[i].depth;
          for (let j = i - 1; j >= 0 && d > 0; j--) {
            if (n[j].depth < d) { keep[j] = true; d = n[j].depth; }
          }
        }
        const out = [];
        const have = ({});
        for (let i = 0; i < n.length; i++)
          if (keep[i]) { out.push(n[i]); have[n[i].path] = true; }
        // Then whatever the crawl found that the tree has not already shown.
        for (let i = 0; i < sendTo.hits.length; i++) {
          const p = sendTo.hits[i];
          if (have[p] === true) continue;
          have[p] = true;
          out.push({ path: p, name: sendTo.pretty(p), depth: 0, hit: true,
                     open: false, loaded: false, kids: null });
        }
        return out;
      }

      // The cursor indexes what is VISIBLE, not the tree — so filtering does
      // not leave it pointing at a row that has been sifted out. Everything
      // that acts on a row goes back to the tree through its path.
      readonly property var current:
        (sendTo.sel >= 0 && sendTo.sel < sendTo.shown.length)
          ? sendTo.shown[sendTo.sel] : null

      function nodeIndex(path) {
        for (let i = 0; i < sendTo.nodes.length; i++)
          if (sendTo.nodes[i].path === path) return i;
        return -1;
      }

      function ask(op) {
        sendTo.op = op;
        if (op === "go") {
          // PATHS STAYS EMPTY, and that is not an oversight — it is what
          // makes `blocked` answer false for every row, since nothing can be
          // put inside itself when nothing is being put. The header's subject
          // is filled in from `names` alone, which is why it reads that and
          // not the path list.
          sendTo.paths = [];
          // WHERE YOU ARE STANDING, said in the same slot the cargo uses. The
          // header is a sentence — this → that — and the half a journey needs
          // is the half you are leaving. Without it the sheet named a
          // destination with nothing to be a destination FROM.
          sendTo.names = [sendTo.pretty(root.cwd)];
          sendTo.icon = Icons.glyphFor({ name: Terminus.basename(root.cwd),
                                         isDir: true });
          sendTo.iconInk = Zenon.cyan;
        } else {
          const rows = root.acting();
          if (rows.length === 0) return;
          sendTo.paths = rows.map((r) => r.path);
          sendTo.names = rows.map((r) => r.name);
          if (rows.length === 1) {
            sendTo.icon = rows[0].glyph !== undefined ? rows[0].glyph : "";
            sendTo.iconInk = rows[0].ink !== undefined ? rows[0].ink : Zenon.white;
          } else {
            sendTo.icon = "\uDB84\uDEF7";
            sendTo.iconInk = Zenon.white;
          }
        }
        sendTo.nodes = sendTo.roots();
        sendTo.query = "";
        sendTo.hits = [];
        sendTo.sel = 0;
        sendTo.loadFor = "";
        sendTo.open = true;
      }

      function dismiss() {
        sendToFlash.cancel();
        sendTo.pendingDest = "";
        sendTo.pendingTab = false;
        sendTo.open = false;
        sendTo.nodes = [];
        sendTo.query = "";
        sendTo.hits = [];
        sendToCrawl.stop();
        sendToFind.running = false;
        sendTo.crawling = false;
        sendTo.loadFor = "";
      }

      // WHERE A TREE CAN START. The places you already told terminus you care
      // about — bookmarks and disks — plus home, the root, and the other
      // pane's directory, which is the destination often enough to be worth a
      // row of its own. Deduplicated, because a bookmarked home is one place
      // and two entries for it would be two answers to the same question.
      function roots() {
        const out = [];
        const seen = ({});
        function add(p, label) {
          if (!p || p === "" || seen[p] === true) return;
          seen[p] = true;
          out.push({ path: p,
                     name: label !== undefined && label !== ""
                       ? label : Terminus.basename(p),
                     depth: 0, open: false, loaded: false, kids: null });
        }
        // WHAT YOU CHOSE, PLUS THE TWO WAYS IN. Home, the other pane when
        // there is one, your bookmarks, and the root.
        //
        // Not the current directory: you are already in it, its subfolders
        // are one keystroke away in the tree and one letter away in the
        // filter, and as a root it only ever restated the window behind it.
        // Not the mounted disks either — /boot and the partition under /home
        // were two more rows saying the same thing the root already says, and
        // the useful part of a disk is a folder ON it, which the filter finds
        // without a shortcut of its own.
        add(Paths.home(), "Home");
        if (root.dual && root.pas) add(root.pas.cwd);
        for (let i = 0; i < root.bookmarks.length; i++) add(root.bookmarks[i]);
        add("/", "/");
        return out;
      }

      // Children are kept on the node once read, so closing a branch and
      // opening it again is free. A directory that changed under you is the
      // price, and it is the same price the preview cache pays.
      function expand(i) {
        const n = sendTo.nodes[i];
        if (!n || n.open) return;
        if (n.kids !== null) { sendTo.insert(i, n.kids); return; }
        if (sendTo.loadFor !== "") return;
        sendTo.loadFor = n.path;
        sendToProc.running = false;
        sendToProc.command = ["sh", "-c", Terminus.peekCommand(n.path)];
        sendToProc.running = true;
      }

      function insert(i, kids) {
        const n = sendTo.nodes[i];
        if (!n) return;
        const made = [];
        for (let k = 0; k < kids.length; k++)
          made.push({ path: kids[k].path, name: kids[k].name,
                      depth: n.depth + 1, open: false, loaded: false, kids: null });
        const a = sendTo.nodes.slice();
        a[i] = { path: n.path, name: n.name, depth: n.depth,
                 open: true, loaded: true, kids: kids };
        sendTo.nodes = a.slice(0, i + 1).concat(made, a.slice(i + 1));
      }

      function collapse(i) {
        const n = sendTo.nodes[i];
        if (!n || !n.open) return;
        const a = sendTo.nodes.slice();
        let j = i + 1;
        while (j < a.length && a[j].depth > n.depth) j++;
        a[i] = { path: n.path, name: n.name, depth: n.depth,
                 open: false, loaded: n.loaded, kids: n.kids };
        sendTo.nodes = a.slice(0, i + 1).concat(a.slice(j));
      }

      function toggle(i) {
        const n = sendTo.nodes[i];
        if (!n) return;
        if (n.open) sendTo.collapse(i); else sendTo.expand(i);
      }

      // The three the keyboard and the mouse actually call: they are handed a
      // row that is on screen and find it in the tree themselves.
      function expandCurrent() {
        const n = sendTo.current;
        if (n) sendTo.expand(sendTo.nodeIndex(n.path));
      }

      function toggleShown(i) {
        const n = sendTo.shown[i];
        if (n) sendTo.toggle(sendTo.nodeIndex(n.path));
      }

      function clamp() {
        sendTo.sel = Math.max(0,
          Math.min(sendTo.sel, sendTo.shown.length - 1));
      }

      // Left on an open branch closes it; left on a closed one goes out to
      // the branch it is in. The same thing `h` does in the listing.
      function outward() {
        const n = sendTo.current;
        if (!n) return;
        if (n.open) {
          sendTo.collapse(sendTo.nodeIndex(n.path));
          sendTo.clamp();
          return;
        }
        // Walked over what is VISIBLE: with a filter on, the parent two rows
        // up in the tree may not be on screen, and the one that is, is the
        // one the indent is drawn against.
        for (let i = sendTo.sel - 1; i >= 0; i--)
          if (sendTo.shown[i].depth < n.depth) { sendTo.sel = i; return; }
      }

      function step(d) {
        if (sendTo.shown.length === 0) return;
        sendTo.sel = Math.max(0,
          Math.min(sendTo.shown.length - 1, sendTo.sel + d));
      }

      // ── THE ROW FLASHES, THEN THE SHEET GOES, THEN IT HAPPENS ────────
      // The same three beats a menu row gives when you click it, and the same
      // numbers — 60ms up, 130ms down, cyan at 0.55 — because it is the same
      // gesture: you have picked a thing and the card is answering before it
      // acts. Return used to send with the sheet vanishing on the keystroke,
      // which leaves you unsure which row you were on at the moment it went.
      property string pendingDest: ""

      RowFlash { id: sendToFlash; onDone: () => sendTo.commit() }

      // Held beside pendingDest and for the same reason: the flash is long
      // enough for a second keystroke, and what was asked for is what was
      // asked for at the moment the key went down.
      property bool pendingTab: false

      function choose(inTab) {
        const n = sendTo.current;
        if (!n || sendToFlash.running) return;
        sendTo.pendingTab = (inTab === true) && sendTo.op === "go";
        if (sendTo.blocked) {
          root.warn(n.path === sendTo.paths[0]
            ? "that is where it already is"
            : "cannot put a folder inside itself");
          return;
        }
        // Held on the sheet rather than read back at the end: the flash is
        // long enough for a second keystroke to move the cursor, and the
        // destination is the one that was lit up.
        if (!sendToFlash.fire(sendTo.sel)) return;
        sendTo.pendingDest = n.path;
      }

      function commit() {
        const dest = sendTo.pendingDest;
        sendTo.pendingDest = "";
        if (dest === "") return;
        sendTo.open = false;
        if (sendTo.op === "go") {
          const tab = sendTo.pendingTab;
          sendTo.pendingTab = false;
          sendTo.nodes = [];
          if (tab) root.openInNewTab(dest);
          else root.goTo(dest);
          return;
        }
        root.setPending({ op: sendTo.op, paths: sendTo.paths,
                          names: sendTo.names });
        root.pasteDest = dest;
        root.paste();
        sendTo.nodes = [];
      }

      Process {
        id: sendToProc
        stdout: StdioCollector {
          id: sendToOut
          waitForEnd: true
          onStreamFinished: {
            const p = sendTo.loadFor;
            sendTo.loadFor = "";
            if (p === "" || !sendTo.open) return;
            // Found by PATH, not by the index that asked: the tree can have
            // been collapsed or rebuilt while the read was out.
            let at = -1;
            for (let i = 0; i < sendTo.nodes.length; i++)
              if (sendTo.nodes[i].path === p) { at = i; break; }
            if (at < 0) return;
            // Directories only — this is a destination picker, and the same
            // parse the listing and the preview use, so hidden folders and
            // the sort order match what the window is already showing.
            const all = root.rowsFromListing(sendToOut.text, p);
            const dirs = [];
            for (let i = 0; i < all.length; i++)
              if (all[i].isDir) dirs.push(all[i]);
            sendTo.insert(at, dirs);
          }
        }
      }

      // Clicking off cancels, the way the other cards behave. Under the card,
      // which is declared after it and so takes its own clicks first.
      MouseArea {
        anchors.fill: parent
        onClicked: sendTo.dismiss()
      }

      // ── IT COMES OUT FROM UNDER THE BAR ──────────────────────────────
      // A sheet, the way macOS drops one: it belongs to this window, it hangs
      // off the chrome, and the way in and the way out are the same movement
      // reversed. A card that simply appeared in the corner said nothing
      // about where it came from or what it is attached to.
      //
      // The well is everything BELOW the chrome and it clips, so the sheet is
      // genuinely hidden behind the bar rather than fading out on top of it.
      // The band is the tab strip plus the path bar — chrome is a Column, so
      // those two heights are exactly where the body begins.
      Item {
        id: sendToWell
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: tabStrip.height + crumbBar.height
        anchors.bottom: parent.bottom
        clip: true

      // The one every menu on this desktop wears. A sibling, never a child —
      // the card clips, and a card that clips clips its own shadow away.
      // Inside the well, so the part that would fall across the bar is cut
      // off with it: a sheet hanging from the chrome does not cast upwards.
      MenuShadow {
        panel: sendToCard
        cornerRadius: Zenon.dialogRadius
        opacity: sendToCard.opacity
      }

      Rectangle {
        id: sendToCard
        anchors.horizontalCenter: parent.horizontalCenter
        // AS WIDE AS IT NEEDS, AND NEVER WIDER THAN THE WINDOW. The well is
        // the window's width, so the sheet may reach the frame on either side
        // and stops exactly there. 560 is the floor rather than the size: a
        // tree of short names should not rattle around in a wide card.
        //
        // Animated for the reason the height is — the width changes as you
        // type, and a card that jumped on every keystroke would be the filter
        // shouting rather than answering.
        width: Math.max(Math.min(560, sendToWell.width),
                        Math.min(sendToWell.width, sendTo.wantWidth))
        Behavior on width {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }
        // Grown to what it holds, capped at the well. A picker sized for the
        // deepest tree you might open is mostly empty space when all it has
        // is six bookmarks; one that grows as you open branches is the same
        // gesture continuing. Animated, or the sheet would jump every time a
        // branch loaded.
        // ADDED UP FROM THE PARTS RATHER THAN WRITTEN AS A NUMBER. A guessed
        // constant was seven pixels short and sliced the last row with the
        // bottom rule, on a sheet that had room for it — which reads as a
        // scroll that is not there. This one cannot drift when a font size
        // or a margin changes, because it is made of them.
        //
        // dialogRadius is in it because the card's top is that far above the
        // clip — see the note on `y`. Those pixels are cut away, so the sheet
        // has to be that much taller to hold the same contents.
        // No header any more — it is drawn on the bar, see sendToBarHead — so
        // the sheet is a list, a rule and a footer.
        // EVERY PIXEL THAT IS NOT A ROW, EACH ONE NAMED. dialogRadius is the
        // list's top margin, and the height the card's top sits above the clip
        // — the same number for the same reason. 12 is the list's bottom
        // margin. The footer is the footer. And 14 is the footer's OWN margin
        // against the bottom of the card, which is written on sendToFoot as
        // `anchors.margins`.
        //
        // That last one reads as slack and is not: taken out, the card came up
        // 14 short and the bottom row was sliced by the frame. Measured, with
        // four roots in the sheet — 106 pixels of list for 120 pixels of rows.
        // The whole point of adding it up from the parts is that every term
        // has to be one of them.
        readonly property real chromeH:
          Zenon.dialogRadius + 12 + sendToFoot.height + 14
        readonly property int rowH: 30
        // WHAT IS VISIBLE, not what is loaded. Bound to the tree instead, a
        // sheet that had been opened out stayed at full height when a filter
        // cut it to three rows, and the answer sat in the top inch of a lot
        // of empty card.
        // FOURTEEN ROWS TO A PAGE, and the well's height after that. A crawl
        // can answer with a hundred and twenty; a sheet grown to hold them
        // would be the window with a border round it, and everything past the
        // first dozen is something you scroll to rather than read.
        readonly property int pageRows: 14
        height: Math.min(sendToWell.height - 40,
          sendToCard.chromeH
            + Math.max(2, Math.min(sendToCard.pageRows, sendTo.shown.length))
              * sendToCard.rowH)
        Behavior on height {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }

        // AT REST ITS TOP SITS ABOVE THE CLIP by exactly the corner radius,
        // so the rounded top corners are cut away and the sheet reads as
        // hanging FROM the bar rather than floating below it. Rounded at the
        // bottom, square at the top — which is the shape of the thing being
        // imitated.
        y: sendTo.open ? -Zenon.dialogRadius : -sendToCard.height - 2
        // A SHEET IS SLOWER THAN A MENU. It is a bigger object and it travels
        // further, so the shared durations — sized for a card that appears
        // where the pointer already is — read as a snap here rather than as a
        // slide. Taken as a multiple of the token rather than written as a
        // number, so turning the desktop's motion down still turns this down.
        readonly property int slideIn: Math.round(Zenon.slow * 2.0)
        readonly property int slideOut: Math.round(Zenon.slow * 1.3)

        // Down on a curve that settles, up on one that accelerates away: a
        // sheet arrives and is dismissed, it does not do the same thing twice.
        Behavior on y {
          NumberAnimation {
            duration: sendTo.open ? sendToCard.slideIn : sendToCard.slideOut
            easing.type: sendTo.open ? Easing.OutCubic : Easing.InCubic
          }
        }

        // AND IT FADES AS IT TRAVELS. The well clips, so a sheet that only
        // slid would be a hard edge crossing the listing; fading the same
        // distance makes it arrive rather than pass by. Same two durations as
        // the slide, so the two halves of one movement cannot drift apart.
        opacity: sendTo.open ? 1 : 0
        Behavior on opacity {
          NumberAnimation {
            duration: sendTo.open ? sendToCard.slideIn : sendToCard.slideOut
            easing.type: sendTo.open ? Easing.OutCubic : Easing.InCubic
          }
        }

        color: Zenon.black
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: Zenon.dialogRadius
        clip: true

        // Hairlines, the same ink the menu separates with. The list scrolls
        // under both of them, so a row cut in half at the bottom reads as
        // more to come rather than as a row drawn wrong.
        Rectangle {
          anchors.bottom: sendToFoot.top
          anchors.bottomMargin: 10
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.menuSepInk
        }

        SelectBar {
          view: sendToList
          index: sendTo.sel
          rowH: sendToCard.rowH
        }

        ListView {
          id: sendToList
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: sendToFoot.top
          // THE CORNER RADIUS, which is how far the card's top sits above the
          // clip — see the note on `y`. Below that the first row is flush
          // with the bar's own bottom edge, which is where the sheet begins
          // as far as the eye is concerned.
          anchors.topMargin: Zenon.dialogRadius
          anchors.bottomMargin: 12
          clip: true
          model: sendTo.shown
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: sendTo.sel
          highlightMoveDuration: 0
          // Keeps the cursor on screen without the view chasing it: the same
          // Contain the listing uses.
          onCurrentIndexChanged: sendToList.positionViewAtIndex(
            sendToList.currentIndex, ListView.Contain)

          delegate: Item {
            id: sendToRow
            required property var modelData
            required property int index
            width: sendToList.width
            height: sendToCard.rowH

            readonly property bool on: sendToRow.index === sendTo.sel
            readonly property bool banned: sendTo.bans(sendToRow.modelData.path)
            readonly property real indent: 10 + sendToRow.modelData.depth * 14

            // No fill here: the bar above the view carries the cursor. This
            // was headBg, a BACKGROUND colour that says "this is chrome", and
            // it read a shade quieter than the same cursor does everywhere
            // else — (16,19,22) against selBg's (21,24,28).

            // The twisty. Its own click target, so a click on the NAME picks
            // the directory and a click here opens it — one row, two verbs,
            // and no guessing which one a single click meant.
            Text {
              id: sendToTwist
              x: sendToRow.indent
              width: 14
              anchors.verticalCenter: parent.verticalCenter
              // A crawl result is a leaf here: it is somewhere to send to, not
              // a branch, and it has no place in the tree to open into.
              visible: sendToRow.modelData.hit !== true
              text: sendToRow.modelData.open ? "" : ""
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 13
            }

            Text {
              id: sendToGlyph
              x: sendToRow.indent + 18
              // A FIXED COLUMN, not the glyph's own width — the same fix the
              // listing's glyphs got, for the same reason. The nerd font is
              // proportional, so a wide icon ended further right than a
              // narrow one and ran into a name that was pinned at a constant
              // x: some rows had a gap, some had none, and the wide ones
              // touched. A column of constant width puts every icon on one
              // centre line and starts every name at the same place.
              width: 22
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: sendTo.glyphOf(sendToRow.modelData)
              // CYAN, WHICH IS WHAT inkOf GIVES A DIRECTORY. Every row in
              // this tree is one, so the whole list wears the colour the
              // listing wears — the glyph and the name together, the way a
              // row is inked everywhere else in the window. The cursor is the
              // highlight behind it, not a different colour on top of it.
              color: sendToRow.banned ? Zenon.muted : Zenon.cyan
              font.family: Zenon.face
              font.pixelSize: 15
            }

            Text {
              // OFF THE COLUMN'S EDGE, not off a number that has to be kept
              // equal to it. The listing puts 12 between its 24-wide column
              // and the name; this tree is a size down, so it is 8 against 22.
              anchors.left: sendToGlyph.right
              anchors.leftMargin: 8
              // Room kept for the bookmark mark, whether or not this row has
              // one: a name that elided differently depending on a mark at
              // the far end would make the column look ragged.
              anchors.right: parent.right
              anchors.rightMargin: 34
              anchors.verticalCenter: parent.verticalCenter
              text: sendToRow.modelData.name
              elide: Text.ElideRight
              color: sendToRow.banned ? Zenon.muted : Zenon.cyan
              font.family: Zenon.face
              font.pixelSize: 15
            }

            // THE SAME MARK A ROW IN THE LISTING WEARS, in the same place and
            // the same sand — see entryBookmark. A bookmark keeps its own
            // directory glyph on the left, because what it is and the fact
            // that you kept it are two different things and the row has room
            // to say both. Asked of the path rather than stored on the node,
            // so a bookmarked folder deep inside the tree is marked too and
            // not only the ones that opened it.
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              visible: root.isBookmarked(sendToRow.modelData.path)
              text: "\uF02E"
              color: Zenon.sand
              font.family: Zenon.face
              font.pixelSize: 14
            }

            FlashOver { flash: sendToFlash; index: sendToRow.index }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              enabled: !sendToFlash.running
              onClicked: (m) => {
                sendTo.sel = sendToRow.index;
                if (m.x < sendToRow.indent + 16) sendTo.toggleShown(sendToRow.index);
              }
              onDoubleClicked: sendTo.choose()
            }
          }
        }

        // THE SAME RAIL THE VIEWS USE, so "there is more below" looks here
        // exactly as it looks in the listing. It shows itself only when the
        // results overrun the page — which, with fourteen rows and a crawl
        // that can answer with a hundred and twenty, is most of a filter.
        //
        // After the list, so it draws over the rows rather than under them.
        ScrollRail {
          target: sendToList
          anchors.right: sendToList.right
          anchors.rightMargin: 2
          anchors.top: sendToList.top
          anchors.topMargin: 2
          anchors.bottom: sendToList.bottom
          anchors.bottomMargin: 2
        }

        Column {
          id: sendToFoot
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 14
          spacing: 4

          // NO PATH ROW. It was here because a tree shows you a leaf and the
          // question is about the whole path — but a crawl result IS its
          // path, so under a filter the line restated the row above it, and
          // the filter is how most destinations get found.
          //
          // THE HINT IS THE FIELD. "type to filter" is an instruction you need
          // once, and the moment you follow it the same line can show what you
          // typed instead — so the sheet gets a filter field without carrying
          // a box for one, in the place your eyes already are while the
          // results move. The second half stays the keys, and says "searching"
          // there while the crawl is out rather than taking the line over: a
          // query that disappeared for a tenth of a second every time you
          // stopped typing would be the one thing you wanted to read.
          // ── THE KEYS ARE DRAWN AS KEYS ────────────────────────────
          // They were one run of text with the glyphs spaced into it, which
          // made this the only list of keys in the window not wearing the
          // chip every other one wears — the context menu and F1 are both
          // KeyChip, and this is the third list. Spelt out as chip-and-word
          // pairs so a key and what it does stay together.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Text {
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: 2
              text: sendTo.blocked && sendTo.current ? "cannot go there"
                  : (sendTo.query !== "" ? sendTo.query : "type to filter")
              color: sendTo.query !== "" && !sendTo.blocked
                ? Zenon.sand : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 13
            }

            // While the crawl is out this takes the KEYS' place and not the
            // query's: a query that disappeared for a tenth of a second every
            // time you stopped typing would be the one thing you wanted to
            // read.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: sendTo.crawling && !(sendTo.blocked && sendTo.current)
              text: "searching\u2026"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 13
            }

            Repeater {
              model: {
                if (sendTo.crawling) return [];
                if (sendTo.blocked && sendTo.current) return [];
                const out = [["\u2191\u2193", "move"], ["\u2192", "open"]];
                // The verb is the op's own, and `go` has a second one.
                out.push(["\u21b5", sendTo.op === "go" ? "go" : "send"]);
                if (sendTo.op === "go") out.push(["\u21e7\u21b5", "new tab"]);
                out.push(["esc", "close"]);
                return out;
              }

              delegate: Row {
                id: hintPair
                required property var modelData
                spacing: 5

                KeyChip {
                  anchors.verticalCenter: parent.verticalCenter
                  label: hintPair.modelData[0]
                  fontSize: 11
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: hintPair.modelData[1]
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 13
                }
              }
            }
          }
        }
      }
      }

    }


    // ── the one-line prompt ───────────────────────────────────────────
    // Rename and new-folder both want a name and nothing else, so they share
    // one card rather than growing two nearly identical ones.
    Rectangle {
      id: prompt
      anchors.fill: parent
      z: 11
      visible: opacity > 0.01
      opacity: prompt.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: prompt.open ? promptSheet.slideIn : promptSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      property string heading: ""
      property var onDone: null
      readonly property string error: Terminus.nameError(promptField.text)

      // whatever the field did not take stops here
      Keys.onPressed: (event) => { event.accepted = true; }

      function ask(heading, initial, onDone) {
        prompt.heading = heading;
        prompt.onDone = onDone;
        prompt.open = true;
        promptField.text = initial;
        // the stem, not the extension — renaming almost never means retyping
        // ".tar.gz", and selecting the lot means you have to click to avoid it
        // The stem, and for an archive that means BOTH halves of the
        // extension. lastIndexOf(".") alone selected "name.tar" out of
        // "name.tar.zst" and left ".zst" behind, so typing a new name gave you
        // a bare zstd file rather than the tarball the menu just promised —
        // the one thing the format menu exists to get right.
        const bare = Terminus.stripArchiveExt(initial);
        const dot = initial.lastIndexOf(".");
        prompt.selectTo = bare.length < initial.length ? bare.length
                        : (dot > 0 ? dot : initial.length);
        promptField.select(0, prompt.selectTo);
        promptClaim.tries = 0;
        promptClaim.restart();
      }

      // The card is INVISIBLE at the moment ask() runs.
      //
      // `visible` follows opacity, opacity is animated, and the animation has
      // not started yet on the frame that opens the prompt — so opacity is
      // still 0, visible is still false, and an invisible item silently
      // refuses active focus. The prompt appeared, took no keystrokes, and
      // ignored Return, which is what "compress does not work" looked like
      // from the outside. Retrying until the card is really on screen is the
      // same fix the confirm dialog and the inline rename field both needed.
      property int selectTo: 0
      Timer {
        id: promptClaim
        interval: 30
        repeat: true
        property int tries: 0
        onTriggered: {
          if (!prompt.open || promptClaim.tries++ > 20) { promptClaim.stop(); return; }
          if (promptField.activeFocus) { promptClaim.stop(); return; }
          promptField.forceActiveFocus();
          // the selection is re-applied with the focus: taking focus moves the
          // cursor, and a name you have to re-select is a name you retype
          promptField.select(0, prompt.selectTo);
        }
      }

      function accept() {
        if (prompt.error !== "") return;
        const fn = prompt.onDone;
        const name = promptField.text;
        prompt.open = false;
        prompt.onDone = null;
        content.forceActiveFocus();
        if (fn) fn(name);
      }

      function dismiss() {
        prompt.open = false;
        prompt.onDone = null;
        content.forceActiveFocus();
      }

      InputShield { onClicked: prompt.dismiss() }

      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      Sheet {
        id: promptSheet
        shown: prompt.open
        fromTop: tabStrip.height + crumbBar.height
        cardW: 460
        // As tall as it needs: the error line appears and disappears under the
        // field, and a fixed 104 clipped it off the bottom when it did.
        cardH: promptCol.implicitHeight

        Column {
          id: promptCol
          width: parent.width

          // The caption band stood here. It is drawn on the bar now — see
          // sheetBarHead — because a sheet says what it is where it hangs from.

          // BARE, the way the path bar and the application picker are. It was
          // a filled, bordered box inside a card that is already a filled,
          // bordered box — two frames around one line of text, and the inner
          // one had no edge to define that the card was not defining already.
          // What says "this takes typing" is the caret and the colour of the
          // text, not a rectangle drawn around them.
          Item {
            width: parent.width
            height: 46

            TextInput {
              id: promptField
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              // Red while the name is one the filesystem will refuse. The
              // border used to carry that and the border is gone, so the text
              // carries it — which is the better place for it anyway: what is
              // wrong is what you typed.
              color: prompt.error !== "" ? Zenon.red : Zenon.cyan
              selectionColor: Zenon.selBg
              selectedTextColor: Zenon.white
              font.family: Zenon.face
              font.pixelSize: 18
              clip: true

              // The same breathing caret the search bar, the path bar, the
              // keymap search and the picker all wear. A cursorDelegate
              // REPLACES the built-in one, so there is exactly one and it is
              // this; a hard blink in a field that is already asking for your
              // attention reads as a fault.
              cursorDelegate: Rectangle {
                width: 2
                color: prompt.error !== "" ? Zenon.red : Zenon.cyan
                SequentialAnimation on opacity {
                  running: promptField.activeFocus
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
                  NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
                }
              }

              Keys.onReturnPressed: (e) => { e.accepted = true; prompt.accept(); }
              Keys.onEscapePressed: (e) => { e.accepted = true; prompt.dismiss(); }
            }
          }

          // No hint bar. Return and escape are what every card in this window
          // already does, and a line under each one repeating them is a line
          // nobody reads twice.
          //
          // The ERROR is not a hint, though — it is the answer to what you
          // just typed, and without it a name the window will not accept looks
          // like a card that has stopped taking Return.
          Item {
            width: parent.width
            height: prompt.error !== "" ? 26 : 0
            visible: height > 0

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              text: prompt.error
              elide: Text.ElideRight
              color: Zenon.red
              font.family: Zenon.face
              font.pixelSize: 14
            }
          }

          // the card's own bottom padding, which the hint bar was standing in for
          Item { width: 1; height: 8 }
        }
      }
    }

    // ── choosing an application by hand ───────────────────────────────
    // Reached from the menu's "Open with…" — the shape that row takes when
    // NOTHING already handles the file's type. Everything installed is in
    // here, because the whole reason this card is open is that the short list
    // was empty.
    //
    // What you choose is registered against the TYPE on its way to opening
    // the file, so this is a card you visit once per kind of file rather than
    // once per file. See adoptAppCommand.
    Rectangle {
      id: appPick
      anchors.fill: parent
      z: 16
      visible: opacity > 0.01
      opacity: appPick.open ? 1 : 0
      color: root.cardScrim
      Behavior on opacity { NumberAnimation { duration: appPick.open ? appSheet.slideIn : appSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      // what is being opened, and what it IS — the second is what gets the
      // association, and it can be empty for a file xdg-mime could not name
      property string path: ""
      // EVERYTHING IT WILL OPEN. The card took one path — the row under the
      // pointer — and opened that alone with three files selected, which is
      // the one entry on the menu that did not act on the selection the way
      // copy, move and rename all do. `path` stays the first of them, because
      // the type being adopted has to be one type and that is the one xdg-mime
      // was asked about.
      property var paths: []
      property string mime: ""
      // As permissions does: what the row looked like in the listing, kept
      // beside the paths. Only for one file — several at once have no single
      // glyph, and the title says so.
      property string icon: ""
      property color iconInk: Zenon.white
      property int pick: 0

      // Snapshotted when the card opens rather than read live. It is a few
      // hundred entries, the filter runs over it on every keystroke, and
      // DesktopEntries.applications is a model rather than an array — walking
      // it per keystroke is work that answers the same thing every time.
      property var installed: []

      // ── TYPE AND IT NARROWS ─────────────────────────────────────────
      // No field, the way the send picker has none: the card has the keyboard
      // and there is nothing else in it a letter could mean, so a letter
      // filters. A box drawn around that only said "this takes typing", which
      // the caret and the footer say without spending a row on it.
      property string query: ""

      readonly property var hits:
        Terminus.filterApps(appPick.installed, appPick.query)

      // Back to the top on every keystroke: the ranking has changed underneath
      // the cursor, so where it was means nothing.
      onQueryChanged: {
        appPick.pick = 0;
        appList.positionViewAtBeginning();
      }

      Keys.onPressed: (event) => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
          // Escape clears the filter before it closes the card: a narrowed
          // list is a state you can be in by accident.
          if (appPick.query !== "") { appPick.query = ""; return; }
          appPick.dismiss(); return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          appPick.accept(); return;
        }
        if (event.key === Qt.Key_Down) { appPick.step(1); return; }
        if (event.key === Qt.Key_Up) { appPick.step(-1); return; }
        if (event.key === Qt.Key_Backspace) {
          appPick.query = appPick.query.slice(0, -1); return;
        }
        if (event.key !== Qt.Key_Tab && event.text
            && event.text.length === 1 && event.text >= " ") {
          appPick.query += event.text;
        }
      }

      function snapshot() {
        const vals = DesktopEntries.applications.values;
        const out = [];
        for (let i = 0; i < vals.length; ++i) {
          const e = vals[i];
          if (!e) continue;
          const nm = String(e.name || "").trim();
          const id = String(e.id || "").trim();
          // An entry with no name is a row you cannot read and one with no id
          // is a row that cannot be launched OR registered — neither belongs
          // in a list whose only job is to be chosen from.
          if (nm === "" || id === "") continue;
          out.push({ name: nm, id: id });
        }
        // By name, once, here — filterApps breaks every tie by the order it
        // was handed, so this is the order the unfiltered list appears in and
        // the order equally good matches keep.
        out.sort((a, b) => {
          const x = a.name.toLowerCase(), y = b.name.toLowerCase();
          return x < y ? -1 : (x > y ? 1 : 0);
        });
        return out;
      }

      function ask(paths, mime) {
        const list = (paths && paths.length !== undefined)
          ? paths : [String(paths || "")];
        appPick.paths = list;
        appPick.path = list.length > 0 ? list[0] : "";
        appPick.mime = mime;
        const lead = list.length === 1 ? root.rowFor(list[0]) : null;
        appPick.icon = lead && lead.glyph !== undefined ? lead.glyph : "";
        appPick.iconInk = lead ? root.inkFor(lead) : Zenon.white;
        appPick.installed = appPick.snapshot();
        appPick.pick = 0;
        appPick.query = "";
        appPick.open = true;
        // the same retry the prompt needs, and for the same reason: the card
        // is still invisible on the frame that opens it, and an invisible item
        // refuses active focus without saying so
        appClaim.tries = 0;
        appClaim.restart();
      }

      Timer {
        id: appClaim
        interval: 30
        repeat: true
        property int tries: 0
        onTriggered: {
          if (!appPick.open || appClaim.tries++ > 20) { appClaim.stop(); return; }
          // THE CARD ITSELF, now that there is no field in it to hold the
          // keyboard — and it is the card that reads the keys.
          if (appPick.activeFocus) { appClaim.stop(); return; }
          appPick.forceActiveFocus();
        }
      }

      function step(d) {
        const n = appPick.hits.length;
        if (n === 0) return;
        appPick.pick = (appPick.pick + d + n) % n;
        appList.positionViewAtIndex(appPick.pick, ListView.Contain);
      }

      function accept() {
        const a = appPick.hits[appPick.pick];
        if (!a) return;
        appPick.choose(a);
      }

      // Run it, and remember it. The status line says which of the two
      // happened: a file whose type xdg-mime could not name is opened and
      // nothing is learned from it, and claiming otherwise would be a lie
      // about what the next right-click will show.
      property var pendingApp: null

      RowFlash { id: appFlash; onDone: () => appPick.launch() }

      function choose(app) {
        if (!appFlash.fire(appPick.pick)) return;
        appPick.pendingApp = app;
      }

      function launch() {
        const app = appPick.pendingApp;
        appPick.pendingApp = null;
        if (!app) return;
        appPick.run(app);
      }

      function run(app) {
        const mime = appPick.mime;
        const paths = appPick.paths.slice();
        const n = paths.length;
        appPick.dismiss();
        // The type is adopted ONCE, on the row the menu opened on, and the
        // rest are launched. Registering per file would be the same statement
        // made three times.
        root.run(Terminus.adoptAppCommand(app.id, mime, paths[0]));
        for (let i = 1; i < n; ++i)
          root.run(Terminus.openWithCommand(app.id, paths[i]));
        root.status = mime !== ""
          ? mime + " now opens with " + app.name
          : (n > 1 ? n + " opened with " + app.name
                   : "opened with " + app.name);
        // the scan behind the menu is stale the moment that lands
        root.openWithApps = [];
        root.appsScanned = false;
      }

      function dismiss() {
        // Harmless when dismiss is called BY the flash: the animation has
        // already finished by the time its own script action runs.
        appFlash.cancel();
        appPick.pendingApp = null;
        appPick.open = false;
        content.forceActiveFocus();
      }

      // The snapshot is NOT dropped on the way out, and that is deliberate:
      // the card is kept alive through its fade, so emptying the list here
      // would collapse the rows out from under it and the last thing you saw
      // of it would be an empty box. It is replaced wholesale by the next
      // ask(), which is the only place its contents can be stale.

      InputShield { onClicked: appPick.dismiss() }

      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      Sheet {
        id: appSheet
        shown: appPick.open
        fromTop: tabStrip.height + crumbBar.height
        cardW: 560
        // As tall as it needs and no taller: a filter over four hundred
        // entries usually leaves three, and a card that stayed full height
        // around them would be mostly empty box.
        cardH: appCol.implicitHeight

        Column {
          id: appCol
          width: parent.width

          // The caption band stood here. It is drawn on the bar now — see
          // sheetBarHead — because a sheet says what it is where it hangs from.

          // NO FIELD. Typing filters — see the key handler — the way it
          // does in the send picker, so the card opens straight onto the list
          // it is asking you to choose from instead of onto a box.
          Item { width: 1; height: 12 }

          Rectangle {
            width: parent.width
            height: appPick.hits.length > 0 ? 1 : 0
            color: Zenon.msgBorder
          }

          SelectBar {
            view: appList
            index: appPick.pick
            rowH: 30
            on: appPick.hits.length > 0
          }

          ListView {
            id: appList
            width: parent.width
            // Ten rows of room, and fewer when there are fewer — the card
            // shrinks around a filter that has narrowed to two.
            height: Math.min(appPick.hits.length, 10) * 30
            model: appPick.hits
            clip: true
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: appRow
              required property var modelData
              required property int index
              width: appList.width
              height: 30

              readonly property bool target: index === appPick.pick

              // No fill: the card carries one bar and slides it. Hover keeps
              // its own tint, because the pointer moves the cursor here — see
              // the HoverHandler below.
              Rectangle {
                anchors.fill: parent
                color: !appRow.target && appHov.hovered
                  ? Zenon.hoverTint : "transparent"
              }

              FlashOver { flash: appFlash; index: appRow.index }
              // Hovering moves the cursor, so Return after a hover takes what
              // is under the pointer rather than what the arrows last left
              // behind — the context menu's rows do the same.
              HoverHandler {
                id: appHov
                onHoveredChanged: if (hovered) appPick.pick = appRow.index
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                visible: appRow.target
                text: "\u276F"
                color: Zenon.cyan
                font.family: Zenon.face
                font.pixelSize: 13
              }

              Text {
                id: appName
                anchors.left: parent.left
                anchors.leftMargin: 43
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, appRow.width - 43 - 14)
                text: modelData.name
                elide: Text.ElideRight
                color: appRow.target ? Zenon.white : Zenon.keyInk
                font.family: Zenon.face
                font.pixelSize: 16
              }

              // The id, dimmed, because two entries can call themselves the
              // same thing and the id is what tells them apart — and it is
              // what you typed if you typed "evince".
              Text {
                anchors.left: appName.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.id
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignRight
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 13
              }

              MouseArea {
                anchors.fill: parent
                onClicked: appPick.choose(modelData)
              }
            }
          }

          // No hint bar. Return, escape and the arrows are what every card in
          // this window already does, and a line repeating them under every
          // one of them is a line nobody reads twice.
          //
          // "nothing matches" is not a hint, though — it is the answer to what
          // you just typed, and without it a filter that matches nothing is
          // indistinguishable from a card that has stopped working.
          Item {
            width: parent.width
            height: appPick.hits.length === 0 ? 30 : 0
            visible: height > 0

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 43
              anchors.verticalCenter: parent.verticalCenter
              text: "nothing matches"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 16
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.msgBorder
          }

          // ── THE HINT IS THE FIELD ────────────────────────────────────
          // The send picker's footer, verbatim in shape: what you typed on
          // the left where the instruction was, and the keys as chips on the
          // right. "type to filter" is something you need told once, and the
          // moment you follow it the same line shows what you typed — so the
          // card gets a filter without carrying a box for one.
          Item {
            width: parent.width
            height: 34

            Row {
              anchors.centerIn: parent
              spacing: 12

              Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 2
                text: appPick.query !== "" ? appPick.query : "type to filter"
                color: appPick.query !== "" ? Zenon.sand : Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 13
              }

              Repeater {
                model: [["\u2191\u2193", "move"], ["\u21b5", "open"],
                        ["esc", "close"]]

                delegate: Row {
                  id: appHintPair
                  required property var modelData
                  spacing: 5

                  KeyChip {
                    anchors.verticalCenter: parent.verticalCenter
                    label: appHintPair.modelData[0]
                    fontSize: 11
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: appHintPair.modelData[1]
                    color: Zenon.muted
                    font.family: Zenon.face
                    font.pixelSize: 13
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // One row of a directory, drawn the same way in all three places it appears.
  //
  // The list view wants size and date beside the name; the miller columns are
  // a third of the width and want the name alone; the preview pane wants the
  // name and no interaction at all. Those are the same row with two switches
  // on it, not three delegates — and three delegates is how the glyph, the
  // colour rules and the tick end up drifting apart.
  // ── one tile of a thumbnail view ────────────────────────────────────────
  // Lifted out of the grid's delegate so the SECOND PANE can be a grid too.
  // Both panes draw the same tile; what differs is which state it is bound to
  // and, for the inactive one, that its cursor is an outline rather than a
  // fill — see EntryRow.passive, which is the same rule for rows.
  // ── A PANE, AS A THING THAT OWNS ITS OWN LISTING ───────────────────────
  // This window used to have one directory and a spare. The active side held
  // `cwd`, `rows`, `sel` and the view mode; the other side held `otherCwd`
  // and `otherRaw` and could do nothing until you stepped into it — and
  // stepping into it EXCHANGED the two, so the state crossed the divider one
  // way while the side it was drawn on crossed the other. On screen nothing
  // moved, which was the point; underneath, every delegate in both halves was
  // destroyed and rebuilt, because the item drawing a directory before the
  // step was not the item drawing it after.
  //
  // The cost was thumbnails. The set of pictures on screen is identical
  // either side of a Tab, but for an instant one pane's worth is referenced
  // by nothing, and Qt frees unreferenced pixmaps the moment its cache is
  // over budget — so they decode again. Around eleven of forty-eight, per
  // press, at default zoom.
  //
  // So a pane owns its half of the window and everything in it, permanently,
  // and `paneSide` decides only which of the two the keyboard is in. Tab
  // moves a flag. Nothing is handed over, nothing is rebuilt, and the
  // question "which item draws this directory" has one answer for as long as
  // the directory is on screen.
  component Pane: QtObject {
    id: pane

    // 0 left, 1 right. Fixed for the life of the object — a pane IS a half of
    // the window, which is the whole reason this type exists.
    property int side: 0
    readonly property bool active: root.act === pane

    property string cwd: ""
    // Raw, as the listing came back. The sort and the hidden-file setting are
    // applied below rather than baked in, so changing either rearranges both
    // panes at once instead of only the one you are standing in.
    property var raw: []

    // ── WHERE THIS PANE HAS BEEN ────────────────────────────────────────
    // On the pane, not on the window: two panes navigate independently, and
    // "back" in one is not a question about the other. Carried in and out of
    // tab state with everything else a pane is, so stepping between tabs does
    // not hand one tab's history to another.
    //
    // `trailAt` is where in it you are standing. Everything after that index
    // is the forward direction — and a fresh navigation throws it away, which
    // is what every browser does and what makes the pair of keys make sense.
    property var trail: []
    property int trailAt: -1
    // Where the cursor was in each directory this pane has left. goUp already
    // does this for one step — it arms wantSel with the folder you came out
    // of — and walking the trail is the same promise over any distance: the
    // row you were on when you left is the row you come back to.
    property var trailSel: ({})

    property int sel: 0
    property string viewMode: "list"
    property real zoom: 1.0
    Behavior on zoom {
      NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
    }
    property string query: ""
    // path -> true. A map rather than a list so a row can ask about itself in
    // constant time while the list is being drawn.
    property var marked: ({})
    // null, never "", is the "nothing loaded yet" sentinel: an empty
    // directory prints nothing, so "" is a perfectly real listing.
    property var lastListing: null

    // ── the listing, arranged ────────────────────────────────────────────
    // Deliberately free of anything that changes when the keyboard moves. A
    // dependency on `active` here would re-derive both panes' arrays on every
    // Tab — the diff below would absorb it without touching a delegate, but
    // it is a full pass over the directory for a keystroke that changed
    // nothing, and on four thousand rows that is felt.
    readonly property var sorted: {
      const kept = Terminus.filterEntries(pane.raw, "", root.showHidden);
      if (root.searchMode !== "") return kept;
      if (root.usage) {
        const m = root.dirSizes;
        for (let i = 0; i < kept.length; ++i) {
          const r = kept[i];
          r.du = r.isDir ? m[r.path] : r.size;
        }
      }
      return Terminus.sortEntries(kept, root.sortKey, root.sortDesc,
                                  root.dirsFirst, root.naturalSort);
    }

    readonly property var view: Terminus.filterQuery(pane.sorted, pane.query)

    // The model the views are TOLD ABOUT rather than handed. One role, the
    // path: identity only. Everything a row draws with is looked up from
    // `viewIndex` by that path, so a file whose size or mtime changed
    // re-evaluates one binding in its delegate instead of being destroyed and
    // built again.
    readonly property ListModel vm: ListModel {}

    // path -> row, rebuilt with the listing. NOT a binding: a binding is
    // evaluated when it is first read, and the model is synced before
    // anything reads this — so a delegate created for a path that had only
    // just been appended would look it up as the map was BEFORE the listing
    // changed, and get nothing.
    property var viewIndex: ({})

    function rowFor(path) {
      return pane.viewIndex["k:" + String(path)] || null;
    }

    onViewChanged: {
      const m = ({});
      const v = pane.view;
      for (let i = 0; i < v.length; ++i) m["k:" + v[i].path] = v[i];
      pane.viewIndex = m;
      pane.syncView();
      // The rows under the cursor are new ones, so what the preview is OF has
      // changed even when the cursor itself has not moved.
      if (pane.active && pane.viewMode === "columns") root.refreshPreview();
    }

    // The diff. Removals first so the forward walk never has to step over a
    // row that is on its way out, then one pass placing what is left.
    function syncView() {
      const next = pane.view;
      const m = pane.vm;

      // A WHOLESALE CHANGE IS CHEAPER TO REBUILD than to walk into place, and
      // there are two of them: arriving in a different directory, and
      // re-sorting the one you are in. Both move nearly every row, and the
      // walk below is quadratic when nearly every row has moved.
      // Nothing to nothing. The passive pane hits this on every navigation
      // in the other half — its model is empty and its listing is empty —
      // and the branch below would rewind two views and walk a clear for it.
      if (m.count === 0 && next.length === 0) return;

      const n = Math.min(next.length, m.count);
      let same = 0;
      for (let i = 0; i < n; ++i)
        if (m.get(i).path === next[i].path) ++same;
      if (m.count === 0 || same < n * 0.5) {
        // BEFORE the rows change, never after — see rewindPane.
        //
        // AND NOT AT ALL WHEN A ROW IS ALREADY SPOKEN FOR. Rewinding puts the
        // view at the top; positionSel then moves it to the row that was
        // asked for. Two scroll positions in two frames, and walking back UP
        // a tree hits it every time — the cursor is headed for the directory
        // you just came out of, which is usually below the fold, so the
        // column snapped to the top and then jumped down it. That is most of
        // what "it redraws a list it had already drawn" looks like: not the
        // rows being rebuilt, the view being scrolled twice.
        //
        // `wantSel` is read rather than landWanted() called: that one is not
        // a predicate — it consumes the request and moves the cursor.
        let spokenFor = false;
        if (pane.active && root.wantSel !== "") {
          for (let i = 0; i < next.length; ++i)
            if (next[i].path === root.wantSel) { spokenFor = true; break; }
        }
        if (!spokenFor) root.rewindPane(pane.side);
        // REPLACED IN PLACE, not cleared and refilled.
        //
        // `clear()` destroys every delegate and leaves the view empty for a
        // frame; the rows then arrive one append at a time, each its own
        // model change. Walking back UP a tree is where that shows, because
        // the directory landing in this column was on screen a moment ago in
        // the one beside it: the column blanks and redraws a list you were
        // already looking at.
        //
        // `set` rebinds the delegate that is already standing there. Same
        // count of rows either way, and none of them stop existing — which
        // also means reuseItems never has to hand anything back.
        const keep = Math.min(m.count, next.length);
        for (let i = 0; i < keep; ++i) m.set(i, { path: next[i].path });
        for (let i = keep; i < next.length; ++i) m.append({ path: next[i].path });
        if (m.count > next.length) m.remove(next.length, m.count - next.length);
        return;
      }

      const want = ({});
      for (let i = 0; i < next.length; ++i) want["k:" + next[i].path] = true;
      for (let i = m.count - 1; i >= 0; --i)
        if (want["k:" + m.get(i).path] !== true) m.remove(i);

      for (let i = 0; i < next.length; ++i) {
        const p = next[i].path;
        if (i < m.count && m.get(i).path === p) continue;
        let at = -1;
        for (let j = i + 1; j < m.count; ++j)
          if (m.get(j).path === p) { at = j; break; }
        if (at >= 0) m.move(at, i, 1);
        else m.insert(i, { path: p });
      }
      while (m.count > next.length) m.remove(m.count - 1);
    }
  }

  // ── A HALF OF THE WINDOW, AS A LIST ────────────────────────────────────
  // One definition, instantiated once per side and never moved, which is the
  // whole of the refactor as far as the screen is concerned: the item drawing
  // a directory is decided when the window is built rather than when the
  // keyboard moves, so Tab destroys nothing.
  //
  // There used to be two of these written out in full — the active pane's and
  // a deliberately plainer one for the other side — and stepping across swapped
  // which of them held which directory. Whether a half is ACTIVE now changes
  // how it BEHAVES and never which item it is: a passive row draws its cursor
  // as an outline rather than a fill, takes no marks, opens no menu, and a
  // click in it is a request to come over.
  component PaneList: ListView {
    id: plist
    property Pane pane: null
    readonly property bool act: !!plist.pane && plist.pane.active
    readonly property bool on: !!plist.pane
      && (root.dual || plist.pane.side === 0)
      && plist.pane.viewMode === "list"
    readonly property int side: plist.pane ? plist.pane.side : 0

    x: root.paneX(plist.side)
    y: root.paneHeadH(plist.side)
    width: root.paneW(plist.side)
    height: parent.height - plist.y
    visible: plist.on
    clip: true
    // Only the view that is ON SCREEN holds delegates. An invisible ListView
    // still builds every one of them. null rather than an empty list, so a
    // hidden view holds none at all.
    model: plist.on ? plist.pane.vm : null
    boundsBehavior: Flickable.StopAtBounds
    // RECYCLING IS TURNED OFF WITH THE MODEL, not left running across it. A
    // view whose model goes null releases its delegates into the reuse pool,
    // and the pool survives the detach — coming back it hands those items out
    // again WITHOUT re-injecting the model's roles, so a recycled delegate
    // keeps the `path` it was holding before the view was hidden and draws as
    // an empty row you can still click. Binding it to the model's own gate
    // drains the pool the moment the model is detached.
    reuseItems: plist.on

    // ── THE VIEW MUST NOT WALK WHILE A NAME IS BEING TYPED ──────────────
    // The listing's own handler already refuses every key during an inline
    // rename, and that was not enough here: an item view has key navigation of
    // its own, and it is an ANCESTOR of the field. A Right the TextInput could
    // not use — the caret already at the end of the text, which is exactly
    // where you are when you reach for an extension — bubbled into the view,
    // moved currentIndex, destroyed the delegate being edited and took the
    // rename with it. It never got as far as the handler that would have
    // stopped it.
    //
    // Swallowed here, before the view sees it. Return and Escape never arrive:
    // the field consumes both.
    Keys.onPressed: (event) => { if (root.renaming) event.accepted = true; }


    delegate: EntryRow {
      // The model carries identity; the row comes from the pane's index. A
      // file whose size or date changed re-evaluates this one binding instead
      // of being destroyed and built again.
      required property string path
      required property int index
      readonly property var row: plist.pane.rowFor(path)
      width: plist.width
      entry: row
      current: index === plist.pane.sel
      // Marks are the active half's business — two sets of ticks on screen
      // at once read as terminus having chosen things on its own.
      ticked: plist.act && !!plist.pane.marked[path]
      dim: !!root.cutSet[path]
      live: plist.act
      passive: !plist.act
      // Not `plist.act`: by the time EntryRow asks, the click above has
      // already brought this pane over, so the menu is about a row in the
      // active listing either way.
      actionable: true
      showMeta: plist.width >= root.metaMinWidth
      onChosen: (right, shift, ctrl) => {
        // A click in the half the keyboard is not in comes over FIRST and
        // then does what it came to do. Stopping at the hand-over meant a
        // right click over there only ever switched panes — you had to click
        // once to arrive and again to ask, and the first click looked like it
        // had done nothing but move the focus.
        if (!plist.act) root.focusPane(plist.pane, index);
        root.clickRow(index, right, shift, ctrl);
      }
      onOpened: {
        if (plist.act) plist.pane.sel = index;
        else root.focusPane(plist.pane, index);
        root.activate();
      }
      onTabbed: if (row && row.isDir) root.openInNewTab(path)
    }
  }

  // ── and as a grid ──────────────────────────────────────────────────────
  // The same argument, and the one the refactor was actually for: a tile
  // holds a decoded image, and the old exchange left a whole pane's worth of
  // them referenced by nothing for an instant — which is all it takes for Qt
  // to free them and decode them again on the next frame.
  component PaneGrid: GridView {
    id: pgrid
    property Pane pane: null
    readonly property bool act: !!pgrid.pane && pgrid.pane.active
    readonly property bool on: !!pgrid.pane
      && (root.dual || pgrid.pane.side === 0)
      && pgrid.pane.viewMode === "grid"
    readonly property int side: pgrid.pane ? pgrid.pane.side : 0
    readonly property real zoom: pgrid.pane ? pgrid.pane.zoom : 1.0

    x: root.paneX(pgrid.side)
    y: root.paneHeadH(pgrid.side)
    width: root.paneW(pgrid.side)
    height: parent.height - pgrid.y
    visible: pgrid.on
    clip: true
    model: pgrid.on ? pgrid.pane.vm : null
    boundsBehavior: Flickable.StopAtBounds
    // drained with the model — see the note on PaneList
    reuseItems: pgrid.on

    // ── THE VIEW MUST NOT WALK WHILE A NAME IS BEING TYPED ──────────────
    // The listing's own handler already refuses every key during an inline
    // rename, and that was not enough here: an item view has key navigation of
    // its own, and it is an ANCESTOR of the field. A Right the TextInput could
    // not use — the caret already at the end of the text, which is exactly
    // where you are when you reach for an extension — bubbled into the view,
    // moved currentIndex, destroyed the delegate being edited and took the
    // rename with it. It never got as far as the handler that would have
    // stopped it.
    //
    // Swallowed here, before the view sees it. Return and Escape never arrive:
    // the field consumes both.
    Keys.onPressed: (event) => { if (root.renaming) event.accepted = true; }


    // A target width rather than a fixed one: the cells divide the pane
    // exactly, so there is never a ragged strip of dead space down the
    // right-hand edge, and they land near enough to the target that a
    // thumbnail is worth looking at.
    readonly property int targetCell: Math.round(190 * pgrid.zoom)
    cellWidth: Math.floor(pgrid.width
      / Math.max(1, Math.round(pgrid.width / pgrid.targetCell)))
    cellHeight: Math.round(168 * pgrid.zoom)

    delegate: Tile {
      id: tileItem
      required property string path
      required property int index
      readonly property var row: pgrid.pane.rowFor(path)
      width: pgrid.cellWidth
      height: pgrid.cellHeight
      entry: row
      current: index === pgrid.pane.sel
      dim: !!root.cutSet[path]
      ticked: pgrid.act && !!pgrid.pane.marked[path]
      live: pgrid.act
      passive: !pgrid.act
      tileZoom: pgrid.zoom
      onChosen: (right, shift, ctrl, mx, my) => {
        // Come over, then act — see the list's note.
        if (!pgrid.act) root.focusPane(pgrid.pane, index);
        root.clickRow(index, right, shift, ctrl);
        if (right) root.openMenuAt(tileItem, { x: mx, y: my });
      }
      onOpened: {
        if (pgrid.act) pgrid.pane.sel = index;
        else root.focusPane(pgrid.pane, index);
        root.activate();
      }
      onTabbed: if (row && row.isDir) root.openInNewTab(path)
    }
  }

  component Tile: Item {
    id: tile
    property var entry: null
    // Resolved once per tile rather than three times inside the label's own
    // binding — see the note there. "" whenever the mode is off, so a grid
    // outside a repository builds the same string it always did.
    readonly property string gitState: (root.git && tile.entry)
      ? (root.gitMarks[tile.entry.path] || "") : ""
    property bool current: false
    property bool ticked: false
    property bool passive: false
    // A pending CUT, faded to say so — the same signal EntryRow gives a row.
    property bool dim: false
    // Whether this tile is in the grid the cursor moves through — the second
    // pane's grid draws tiles the rename verb was never about. Same property,
    // same meaning, as EntryRow.live.
    property bool live: false
    readonly property bool editing:
      root.renaming && tile.live && !!tile.entry
      && tile.entry.path === root.renamePath
    // the zoom this tile's pane is at, so two grids can be at two zooms
    property real tileZoom: root.thumbZoom

    // The POSITION rides along with the click, because the actions menu opens
    // where the pointer is and a signal that dropped it left right-click in
    // the grid doing nothing at all.
    signal chosen(bool right, bool shift, bool ctrl, real mx, real my)
    // middle click: this entry, in a tab of its own
    signal tabbed()
    signal opened()

    // true while a drag hovers THIS directory — see root.dropDirAt
    readonly property bool dropTarget: root.dropDir !== "" && !!tile.entry
      && tile.entry.isDir && root.dropDir === tile.entry.path

    // ── dragging this tile out ──────────────────────────────────────
    // The same shape as EntryRow's, and for the same reasons written there:
    // the attached Drag group belongs on the DELEGATE, and a DragHandler with
    // no target decides WHEN while the group decides WHAT. The grid had none
    // of this, so nothing in it could be dragged anywhere at all.
    Drag.active: false
    Drag.source: tile
    Drag.keys: ["text/uri-list"]
    Drag.mimeData: ({ "text/uri-list": tile.entry ? root.dragUris(tile.entry) : "" })
    Drag.supportedActions: Qt.CopyAction
    Drag.dragType: Drag.Automatic
    Drag.hotSpot.x: tile.width / 2
    Drag.hotSpot.y: tile.height / 2
    Drag.onDragFinished: (dropAction) => {
      tile.Drag.active = false;
      root.draggingRow = false;
    }

    DragHandler {
      id: tileDrag
      target: null
      enabled: !!tile.entry && !tile.editing && !root.modal
               && !root.railHover && !root.railDragging
      onActiveChanged: {
        if (!tileDrag.active) return;
        root.draggingRow = true;
        root.dragPicture(tile.entry, (url) => {
          tile.Drag.imageSource = url;
          tile.Drag.active = true;
        });
      }
    }

    readonly property bool cursorOnly:
      tile.current
        && (tile.passive || (!tile.ticked && root.markedCount > 0))

    // A cyan flare on the tile that was just opened.
    //
    // Opening from a grid gives no feedback of its own — the window that comes
    // up is somewhere else, and if it takes a moment there is nothing to say
    // the keypress landed. This says it, on the tile it landed on, and is gone
    // before it can become clutter.
    property real glow: 0
    Connections {
      target: root
      function onOpenPulseChanged() { if (tile.current && !tile.passive) flare.restart(); }
    }
    SequentialAnimation {
      id: flare
      NumberAnimation { target: tile; property: "glow"; to: 1; duration: 90;
                        easing.type: Easing.OutQuad }
      NumberAnimation { target: tile; property: "glow"; to: 0; duration: 420;
                        easing.type: Easing.InQuad }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 4
      radius: 6
      // NO CURSOR FILL: that is SelectCell, one rectangle the view slides
      // between tiles. The tick stays, because a tick is a property of the
      // FILE rather than of where the cursor happens to be — and the border
      // below stays too, because a tile has always carried one.
      color: tile.ticked && !tile.cursorOnly
        ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)
        : "transparent"
      // ── THE OUTLINE MOVED TO THE CURSOR ITSELF ────────────────
      // The sliding bar is BEHIND the tiles, which is right for a
      // glyph — it shows around it — and useless under a photograph,
      // which covers the cell. So on a thumbnail the only mark left
      // was this border, and a border drawn per tile cannot travel:
      // the cursor slid invisibly and the outline teleported.
      //
      // SelectCell carries the cyan outline now, so the thing you can
      // actually see on a grid of pictures is the thing that moves.
      // What stays here is the outline for the case the bar stands
      // down for — passive pane, or anything ticked — and the flare,
      // which is about the tile that was OPENED rather than the one
      // under the cursor.
      border.width: (tile.current && tile.cursorOnly) || tile.glow > 0
        ? 1 + tile.glow * 2 : 0
      border.color: tile.glow > 0 ? Zenon.cyan : Zenon.msgBorder

      // the flare itself, over the tile's own fill
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: tile.glow > 0
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.22 * tile.glow)
      }
    }
    HoverHandler {
      id: tileHov
      onHoveredChanged: {
        if (hovered) root.hoverRow = true;
        else if (root.hoverRow) root.hoverRow = false;
      }
    }

    Item {
      id: thumbBox
      anchors.top: parent.top
      anchors.topMargin: 12
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - 24
      // 68, not 62. The reserve has to hold the 8px gap, two lines of
      // label and the 4px the highlight is inset by — and the label
      // went from 15px to 16px, which is exactly enough for a name
      // long enough to wrap to overrun the bottom of its own tile.
      height: parent.height - 68

      // Rounded corners, and they belong to the PICTURE rather than
      // to the box holding it. The image is letterboxed inside
      // thumbBox — a portrait photo leaves a bar down each side — so
      // rounding the box would have curved empty space and left the
      // picture's own corners square.
      //
      // ClippingRectangle rather than `clip: true`: an item's clip is
      // a rectangle, always, and never follows a radius.
      //
      // The aspect ratio is taken from the Image's IMPLICIT size, the
      // decoded source, and NOT from paintedWidth/paintedHeight. The
      // painted size is derived from the item's own size, which is now
      // this rectangle's — reading it here would be a binding loop.
      ClippingRectangle {
        id: thumbClip
        anchors.centerIn: parent
        visible: thumb.status === Image.Ready
        color: "transparent"
        radius: 5

        readonly property real ar:
          thumb.implicitWidth > 0 && thumb.implicitHeight > 0
            ? thumb.implicitWidth / thumb.implicitHeight : 1
        width: Math.max(1, Math.min(thumbBox.width,
          thumbBox.height * thumbClip.ar))
        height: Math.max(1, Math.min(thumbBox.height,
          thumbBox.width / thumbClip.ar))

        Image {
          id: thumb
          anchors.fill: parent
          opacity: tile.dim ? 0.45 : 1
          // the cached 256px PNG if the batch has made it, the original
          // otherwise — so a folder is never blank while it renders, it
          // just gets cheaper a moment later
          // A video has no thumbnail until ffmpeg has pulled a frame
          // out of it, so unlike a picture there is nothing to fall back
          // to — it shows its glyph until the batch lands.
          // Zoomed past the cache, a PICTURE goes back to the original.
          //
          // The cached thumbnails are 480px, which is generous at the
          // default tile size and not enough at the top of the zoom
          // range — a 600px tile showing a 480px PNG is visibly soft,
          // and zooming in is precisely when you are looking closely. So
          // above the cache's own resolution the original file is decoded
          // instead, at the size actually needed. A VIDEO has no such
          // fallback: its thumbnail is a frame ffmpeg had to pull out of
          // it, so it keeps the cached one at any zoom.
          readonly property bool big: thumbBox.width > 480
          source: {
            // `entry` is declared null and, until the listing became a model
            // the views are told about rather than handed, could never be one.
            // A delegate now outlives a single listing, so it can be asked to
            // draw in the instant between a row leaving and the view being
            // told — guarded here rather than left to throw.
            if (!tile.entry) return "";
            // Switched off, a tile shows the glyph it shows before anything
            // has decoded — see root.thumbsOn.
            if (!root.thumbsOn) return "";
            const pic = Terminus.isImage(tile.entry.name);
            // a video's frame and an audio file's cover are both
            // CACHE-ONLY: there is no original to fall back to
            const cached = Terminus.isVideo(tile.entry.name)
              || Terminus.isAudio(tile.entry.name);
            if (!pic && !cached) return "";
            const ready = root.thumbFile[tile.entry.path];
            if (ready && !(thumb.big && pic))
              return "file://" + ready;
            return pic ? "file://" + tile.entry.path : "";
          }
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          // Decode at the size drawn, not at a fixed 320: below that it
          // was decoding more than it showed, above it, less.
          //
          // ROUNDED UP TO A STEP, because the decode size is half of the
          // cache key and the two panes are NEVER the same width. The split
          // gives the left half floor(body * frac) and the right half what is
          // left after the divider — one pixel apart — so above the 320 floor
          // the same file was asked for at 376 and at 375. Qt treats those as
          // two different images: it decoded both, held both, and every step
          // across the divider was a guaranteed miss on the one it needed.
          //
          // A step of 64 puts both panes, and every zoom inside the step, on
          // ONE key. It only ever rounds UP, so nothing is decoded smaller
          // than it is drawn and no tile loses resolution — it just stops
          // asking for a resolution nobody can tell apart from its neighbour.
          sourceSize.width: Math.max(320, Math.ceil(thumbBox.width / 64) * 64)
          sourceSize.height: Math.max(320, Math.ceil(thumbBox.height / 64) * 64)
        }
      }

      // the glyph is the fallback AND the placeholder: it is what a
      // non-image shows, and what an image shows until it has decoded
      Text {
        anchors.centerIn: parent
        visible: thumb.status !== Image.Ready
        opacity: tile.dim ? 0.45 : 1
        text: tile.entry ? tile.entry.glyph : ""
        color: root.inkFor(tile.entry)
        font.family: Zenon.face
        font.pixelSize: Math.round(40 * tile.tileZoom)
      }
    }

    Text {
      anchors.top: thumbBox.bottom
      anchors.topMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 8
      horizontalAlignment: Text.AlignHCenter
      id: tileName
      visible: !tile.editing
      // THE BADGE READS WITH THE NAME. It used to sit in the corner of the
      // thumbnail, which put it over the picture and a long way from the thing
      // it qualifies. Inline it has to survive centring, wrapping to two lines
      // and eliding — which a Row beside the label would not — so it is part
      // of the same string, coloured with StyledText. The name is escaped
      // because it is now markup: an ampersand in a filename would otherwise
      // eat the rest of the label.
      textFormat: Text.StyledText
      // The git mark leads, because it is about the file rather than about
      // your relationship to it, and because a row of tiles reads left to
      // right. Same inline treatment as the bookmark below and for the same
      // reason: a badge in the corner of the thumbnail sits over the picture
      // and a long way from the thing it qualifies.
      text: (tile.gitState !== ""
              ? "<font color=\"" + Zenon.hex(root.gitInk(tile.gitState)) + "\">"
                + Terminus.gitMark(tile.gitState) + "</font>&#160;&#160;" : "")
            + (tile.entry && root.isBookmarked(tile.entry.path)
              // NON-BREAKING spaces: this is markup now, and StyledText
              // collapses a run of ordinary ones to a single space, so the gap
              // asked for was never the gap drawn.
              ? "<font color=\"" + Zenon.hex(Zenon.sand) + "\">\uF02E</font>&#160;&#160;" : "")
            + Strings.escapeHtml(tile.entry ? tile.entry.name : "")
      opacity: tile.dim ? 0.5 : 1
      elide: Text.ElideMiddle
      maximumLineCount: 2
      wrapMode: Text.Wrap
      color: root.inkFor(tile.entry)
      font.family: Zenon.face
      font.weight: tile.current ? Font.Bold : Font.Medium
      // NOT scaled by zoom, unlike the tile and the glyph above it.
      // Zoom in a thumbnail view is about how big the PICTURES are;
      // scaling the filenames with them meant zooming out to fit more
      // on screen also shrank the labels towards unreadable, and
      // zooming in to inspect an image blew its name up to a headline.
      // The 62px the tile reserves for this text is a constant too, so
      // two lines always fit at every zoom.
      font.pixelSize: 16
    }

    // ── renaming, on the tile ───────────────────────────────────────
    // The grid needs its own field: EntryRow's lives in a row and this is not
    // one. Without it `a` in a thumbnail view made the file and left you with
    // no way to name it, and `r` did nothing at all — the two views disagreed
    // about whether renaming existed.
    // Behind a Loader, for the reason EntryRow's is — a grid of thumbnails
    // keeps a lot of tiles alive and only one of them is ever being renamed.
    Loader {
      id: tileEditBox
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      anchors.top: tileName.top
      height: tileName.height
      active: tile.editing
      sourceComponent: tileEditField
    }

    Component {
      id: tileEditField

      TextInput {
      id: tileEdit
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      color: Zenon.white
      selectionColor: Zenon.selBg
      selectedTextColor: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 16
      clip: true

      cursorDelegate: Rectangle {
        width: 2
        color: Zenon.cyan
        SequentialAnimation on opacity {
          running: tileEdit.activeFocus
          loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
        }
      }

      property bool hadFocus: false

      Component.onCompleted: {
        tileEdit.hadFocus = false;
        // A CREATION STARTS BLANK. A rename starts with the name it is
        // about — you are editing something that exists, and the old name is
        // the thing you are editing. A creation is not editing anything: the
        // generic name is a placeholder the window picked, and presenting it
        // selected means the first thing you do is throw it away. Blank is the
        // same gesture with nothing to delete first.
        //
        // Return on a blank field keeps the generic name — commitRename
        // already reads an empty answer as "the one it arrived with", which is
        // the whole point of it arriving with one.
        const madeNow = root.freshPath !== "" && tile.entry
          && tile.entry.path === root.freshPath;
        tileEdit.text = madeNow ? "" : (tile.entry ? tile.entry.name : "");
        if (!madeNow) {
          const stem = Terminus.stem(tileEdit.text);
          tileEdit.select(0, stem.length > 0 ? stem.length : tileEdit.text.length);
        }
        tileEdit.forceActiveFocus();
        tileClaim.tries = 0;
        tileClaim.restart();
      }

      // asks until it has the keyboard — see EntryRow's editClaim
      Timer {
        id: tileClaim
        interval: 40
        repeat: true
        property int tries: 0
        onTriggered: {
          if (!tile.editing || tileEdit.activeFocus || tileClaim.tries++ > 12) {
            tileClaim.stop();
            return;
          }
          tileEdit.forceActiveFocus();
        }
      }

      Keys.onReturnPressed: (e) => {
        e.accepted = true; root.commitRename(tile.entry, tileEdit.text);
      }
      Keys.onEnterPressed: (e) => {
        e.accepted = true; root.commitRename(tile.entry, tileEdit.text);
      }
      Keys.onEscapePressed: (e) => { e.accepted = true; root.endRename(true); }
      onActiveFocusChanged: {
        if (activeFocus) { tileEdit.hadFocus = true; return; }
        // see EntryRow's note: still claiming is not yet finished
        if (tile.editing && tileEdit.hadFocus && !tileClaim.running)
          root.endRename(false);
      }
      }
    }

    // Lit while a drag is over this directory — the grid's answer to the same
    // question the list row answers with its own outline.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 4
      z: 6
      visible: tile.dropTarget
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
      border.width: 2
      border.color: Zenon.cyan
      radius: 6
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      enabled: !tile.editing
      // ALL FIVE arguments, always. The signal is typed, and emitting it with
      // three left QML raising "Insufficient arguments" before the handler
      // ran — so every click in the grid did nothing at all while hovering
      // still worked, which is a very quiet way to break a view.
      //
      // Middle click is its own signal rather than a sixth argument: adding
      // one to a typed signal means every emit has to grow with it, and that
      // is exactly the mistake the note above is about.
      onClicked: (m) => {
        if (m.button === Qt.MiddleButton) { tile.tabbed(); return; }
        tile.chosen(m.button === Qt.RightButton,
                    (m.modifiers & Qt.ShiftModifier) !== 0,
                    (m.modifiers & Qt.ControlModifier) !== 0,
                    m.x, m.y);
      }
      onDoubleClicked: tile.opened()
    }
  }

  // ── ONE COLUMN OF THE MILLER VIEW ─────────────────────────────────────
  // Three of these stand side by side: the directory above, the one you are
  // in, and the one under the cursor. They were three separate ListViews with
  // three different model shapes — an array, the pane's ListModel, another
  // array — which is why a directory moving from one to the next was a
  // rebuild rather than a hand-off: no two of them could ever hold the same
  // thing, so every step destroyed a column's worth of delegates and built
  // them again from data it already had.
  //
  // Interchangeable now, and each owns a ListModel it syncs IN PLACE. What a
  // column is depends only on its `slot`, and nothing about the delegate is
  // conditional on it at the top level — role changes rebind properties,
  // which is cheap; a conditional `delegate` would rebuild the view, which is
  // the thing being removed.
  //
  //   slot 0  the parent directory   inert, click walks up
  //   slot 1  the one you are in     live: cursor, marks, rename, menu
  //   slot 2  the one under the cursor   inert, click walks in
  component MillerColumn: Item {
    id: col

    required property int slot
    // The rows this column is showing. A plain array, assigned; the model
    // below follows it without ever being cleared.
    property var rows: []

    // ── THE PREVIEW COLUMN ARRIVES, IT DOES NOT APPEAR ──────────────────
    // MEASURED, off a 60fps capture of a step in and a step out:
    //
    //   out  7.3 → 7.4 → 9.8 → 11.7 → 11.85   eased in over three frames
    //   in   7.8 → 7.6 → 7.5 → 7.4 → 7.3 → 13.66   one frame, full strength
    //
    // Walking out, the preview is the listing you just left — it is in hand,
    // settlePreview runs, and previewPane's fade covers it. Walking in, it is
    // a cold read that comes back through previewOut and never touches
    // settlePreview, so the column sat empty for a tenth of a second and then
    // cut in at full strength on a still frame. That single frame is the
    // flicker in the third column on the way in.
    //
    // DRIVEN FROM sync(), not from the preview pipeline. Rows reach this
    // column by several routes — a cache hit, a cold read, a rotation — and
    // hanging the fade off any one of them misses the others. sync() is the
    // only place colModel can change, whoever asked for it.
    property real ink: 1
    opacity: col.ink

    NumberAnimation {
      id: inkFade
      target: col
      property: "ink"
      to: 1
      duration: Zenon.fast
      easing.type: Zenon.travelEase
    }

    // ── THE SLOT THIS COLUMN IS DRAWN IN ────────────────────────────────
    // Not always the slot it IS. `slot` moves the instant millerOrder
    // rotates; the model behind it does not, because onRowsChanged defers
    // sync to the end of the tick — and has to, since at the moment of the
    // rotation the sources for the new slots still describe the old position.
    //
    // Geometry bound to `slot` therefore moved a frame ahead of its own
    // contents. CAUGHT ON A 60fps CAPTURE of a step into ~/.config/btop: for
    // exactly one frame the column that had been the parent was drawn in the
    // preview seat, shifted by the travel offset, still holding the whole of
    // ~ — .cache, .cargo, .claude — at full brightness down the right-hand
    // edge. One frame at 60Hz, three at 180. That is the flash of a directory
    // in the third column on the way in.
    //
    // So the geometry waits for the model rather than racing it: sync() moves
    // this at the end of its own call, and the seat and the rows in it change
    // on the same frame. Everything the eye or the mouse can tell apart reads
    // this — position, width, which column is live, which row is current.
    // `rows` is the exception and must stay on `slot`: it is what drives sync.
    property int drawnSlot: -1
    Component.onCompleted: col.drawnSlot = col.slot
    // Queued here as well as on rows, so a rotation into a slot whose source
    // is the array this column already holds still catches up — callLater
    // coalesces the two into the single sync it would have done anyway.
    onSlotChanged: Qt.callLater(col.sync)

    readonly property bool isLive: col.drawnSlot === 1
    readonly property alias view: colView

    // path -> row, rebuilt with the model. The delegate holds a path so that
    // replacing a row rebinds the item standing there instead of rebuilding
    // it, and something has to turn that path back into an entry — scanning
    // the array per delegate would be quadratic on a big directory.
    property var index: ({})
    function rowAt(p) { const r = col.index["k:" + p]; return r === undefined ? null : r; }

    // COALESCED TO THE END OF THE TICK, and that is not an optimisation.
    //
    // A step changes two things: which slot this column stands in, and what
    // each slot is about. QML re-evaluates a binding the instant one of its
    // dependencies moves, so between those two writes there is a moment when
    // a column has its NEW slot and the OLD rows for it — the column rotating
    // into the preview slot sees the child directory it was showing a moment
    // ago. Syncing there rebuilds to rows nobody asked for, and then rebuilds
    // again when the real ones land: two rebuilds where the answer was
    // already in the column all along.
    //
    // callLater coalesces repeats, so however many times `rows` moves within
    // one step, the model is synced once, against the value it settled on. It
    // runs before the next frame, so nothing is drawn a tick late.
    onRowsChanged: Qt.callLater(col.sync)

    function sync() {
      const next = col.rows || [];
      const wasEmpty = colModel.count === 0;
      const ix = ({});
      for (let i = 0; i < next.length; ++i)
        if (next[i]) ix["k:" + next[i].path] = next[i];
      col.index = ix;

      const m = colModel;
      const keep = Math.min(m.count, next.length);
      for (let i = 0; i < keep; ++i)
        if (m.get(i).path !== next[i].path) m.set(i, { path: next[i].path });
      for (let i = keep; i < next.length; ++i) m.append({ path: next[i].path });
      if (m.count > next.length) m.remove(next.length, m.count - next.length);

      // LAST, with the rows above and in the same call. This is the line that
      // keeps a column's seat and its contents on the same frame.
      col.drawnSlot = col.slot;

      // Rows landing in an empty PREVIEW column are an arrival and ease in.
      // Anywhere else is full strength: the parent and the middle are where
      // you already are, and a column caught mid-fade by the next step must
      // not carry a part-opacity into its new seat.
      if (col.slot === 2 && wasEmpty && next.length > 0) {
        inkFade.stop();
        col.ink = 0;
        inkFade.start();
      } else if (col.slot !== 2) {
        inkFade.stop();
        col.ink = 1;
      }
    }

    ListModel { id: colModel }

    // The listing's bar, in the columns too. `current` here is not one number
    // — the leftmost column marks where you came FROM and the live one marks
    // where you are — so the bar asks the same question the delegate does and
    // stands down on the column that has no cursor of its own.
    SelectBar {
      view: colView
      index: col.drawnSlot === 0 ? root.parentIndex : root.sel
      rowH: root.rowH
      on: (col.drawnSlot === 0 || col.isLive)
          && !root.cursorOutline(root.act)
      // Only the live column has a cursor that MOVES. The left-hand one marks
      // where you came from — it changes because the columns rotated, not
      // because anything travelled — and during the rotation itself the live
      // one is being handed a new directory, so neither should ease.
      animate: col.isLive && !millerAnim.running
    }

    ListView {
      id: colView
      anchors.fill: parent
      clip: true
      model: colModel
      reuseItems: true
      boundsBehavior: Flickable.StopAtBounds
      // Only the live column scrolls under the hand; the other two are what
      // is around you, not what you are working in.
      interactive: col.isLive

      delegate: EntryRow {
        id: colRow
        required property string path
        required property int index
        readonly property var row: col.rowAt(path)

        width: col.width
        entry: colRow.row
        current: col.drawnSlot === 0 ? (colRow.index === root.parentIndex)
               : (col.isLive ? (colRow.index === root.sel) : false)
        live: col.isLive
        // ONLY THE LIVE COLUMN OPENS A MENU. EntryRow opens one itself on a
        // right click when `actionable`, and that menu acts on
        // root.currentRow() — never on a hit test. The live column gets away
        // with it because its rows call clickRow() first, which moves the
        // cursor to the row you clicked; the other two navigate instead, so
        // the cursor never moves and the menu came up about whatever was
        // under it in the middle column. Right-clicking a parent directory
        // offered you actions on a completely different file.
        actionable: col.isLive
        dim: col.isLive && !!root.cutSet[colRow.path]
        ticked: col.isLive && !!root.marked[colRow.path]
        // No metadata this narrow, where the name says everything there is
        // room to say — but results are not a directory, and two of them can
        // share a name. See colFoundNarrow.
        showMeta: col.isLive && root.searchMode !== ""
        whereOnly: col.isLive

        onChosen: (right, shift, ctrl) => {
          if (col.isLive) { root.clickRow(colRow.index, right, shift, ctrl); return; }
          // The two inert columns are places you can SEE, and clicking a thing
          // you can see should get you there. Slot 2 enters the previewed
          // directory rather than the row clicked, so a click there can never
          // act on the wrong file.
          if (col.drawnSlot === 0) { if (colRow.row && colRow.row.isDir) root.goTo(colRow.path); return; }
          const r = root.currentRow();
          if (r && r.isDir) root.goTo(r.path);
        }
        onOpened: {
          if (col.isLive) { root.act.sel = colRow.index; root.activate(); return; }
          if (col.drawnSlot === 0) { if (colRow.row && colRow.row.isDir) root.goTo(colRow.path); return; }
          const r = root.currentRow();
          if (r && r.isDir) root.goTo(r.path);
        }
        onTabbed: {
          if (col.drawnSlot === 2) {
            const r = root.currentRow();
            if (r && r.isDir) root.openInNewTab(r.path);
            return;
          }
          if (colRow.row && colRow.row.isDir) root.openInNewTab(colRow.path);
        }
      }
    }
  }

  component EntryRow: Item {
    id: entryRow

    property var entry: null
    property bool current: false
    property bool ticked: false
    // size and modified, which only the full-width list has room for
    property bool showMeta: true
    // A row a pending CUT will take away, faded to say so. It was written for
    // the parent and preview columns, which turned out to read worse at 65%
    // than at full strength, and then sat unused — this is the question it was
    // the right answer to all along.
    property bool dim: false
    property bool clickable: true
    // Whether this row is in THE LISTING THE CURSOR MOVES THROUGH.
    //
    // False in the parent column, in the preview, and in the second pane —
    // all of which draw an EntryRow with a `current` row of their own that the
    // cursor has nothing to do with. Two things hang off it: renaming in place
    // is only ever about the active listing, and so is the sweep. Without it
    // every cursor move animated the parent column's highlighted row as well,
    // which is why the parent directory kept flashing at you.
    property bool live: false
    readonly property bool editable: entryRow.live
    readonly property bool editing:
      root.renaming && entryRow.editable && !!entryRow.entry
      && entryRow.entry.path === root.renamePath
    // Whether a right-click on this row opens the actions menu. False in the
    // panes that are not the active listing — the second pane, and the parent
    // and preview columns — because the menu acts on the ACTIVE selection, so
    // opening it from over there offers a set of verbs aimed at rows you are
    // not pointing at.
    property bool actionable: true

    // The column widths, from the same two sets the headings read — so a cell
    // is under the heading that names it by construction rather than by two
    // lists of numbers being kept in step by hand. Only the LIVE listing grows
    // a WHERE column: results replace the active pane and nothing else.
    // Set on a pane that has room for the WHERE column but not for the
    // numbers beside it — the miller middle column, and nothing else so far.
    property bool whereOnly: false
    readonly property var frac:
      (root.searchMode !== "" && entryRow.live)
        ? (entryRow.whereOnly ? root.colFoundNarrow : root.colFound)
        : root.colPlain

    // What was held down when it was clicked. The row does not decide what
    // that means — clickRow does — because the same three modifiers have to
    // mean the same three things in all three views.
    signal chosen(bool right, bool shift, bool ctrl)
    signal opened()
    // middle click: a directory in a tab of its own, the way a browser opens
    // a link. Files have nothing sensible to do with it and ignore it.
    signal tabbed()

    // true while a drag hovers THIS directory — see root.dropDirAt
    readonly property bool dropTarget: root.dropDir !== "" && !!entryRow.entry
      && entryRow.entry.isDir && root.dropDir === entryRow.entry.path

    height: root.rowH


    // ── dragging this row out ───────────────────────────────────────
    // Copied from artemis, which drags into other applications successfully;
    // terminus' own version did not, and the differences were all here.
    //
    // The attached Drag group is on the DELEGATE, not on a child Item that
    // fills it — terminus had it on a child, and a child that merely fills its
    // parent is not the same thing to Qt's drag machinery. `Drag.source` and
    // `Drag.keys` were both missing entirely, and startDrag() returned false
    // with no warning: the drag began and nothing anywhere would accept it.
    //
    // CopyAction only, like artemis. A move offered over the wayland data-device
    // means the source has to delete the file when the target says it took it,
    // and nothing here implements that half — so offering it would be a
    // promise terminus cannot keep. Moving between terminus windows is `x` then `p`.
    Drag.active: false
    Drag.source: entryRow
    Drag.keys: ["text/uri-list"]
    Drag.mimeData: ({ "text/uri-list": entryRow.entry ? root.dragUris(entryRow.entry) : "" })
    Drag.supportedActions: Qt.CopyAction
    Drag.dragType: Drag.Automatic
    Drag.hotSpot.x: 16
    Drag.hotSpot.y: entryRow.height / 2
    Drag.onDragFinished: (dropAction) => {
      entryRow.Drag.active = false;
      root.draggingRow = false;
    }

    // Resolved once per delegate. It was inkFor(entry) in two bindings — the
    // glyph's colour and the name's — and a function call in a binding cannot
    // be compiled, so every row paid for two interpreted calls on every
    // repaint. The value is already on the row; this just reads it.
    readonly property color rowInk: (entryRow.entry && entryRow.entry.ink !== undefined)
      ? entryRow.entry.ink : Zenon.muted

    // The CURSOR and a SELECTION are two different things, and they only need
    // to look different once both are on screen.
    //
    // They shared one fill, so opening a directory — where the cursor rests on
    // the first row by default — and then marking files elsewhere left that
    // first row looking selected when it was not in the selection at all.
    //
    // With nothing marked the cursor keeps its filled highlight, because then
    // there is nothing for it to be confused with. The moment a selection
    // exists, a cursor that is not part of it drops to an outline: still
    // plainly where you are, no longer claiming to be one of the chosen.
    // The cursor of a pane the keyboard is NOT in. Still plainly where that
    // side's cursor is; no longer claiming to be a selection. Two filled
    // highlights on screen at once, one of them in a pane no key reaches, read
    // as terminus having chosen something on its own — which is exactly what it
    // was reported as.
    property bool passive: false

    readonly property bool cursorOnly:
      entryRow.current
        && (entryRow.passive || (!entryRow.ticked && root.markedCount > 0))

    // A light passing across the bar as the row is OPENED — Return, or a
    // double click. The same acknowledgement the grid's tiles have always
    // flared with, so a directory opened from a list and the same directory
    // opened from thumbnails answer the same way.
    //
    // NOT when the cursor arrives on it. That was the first version, and it
    // fired on every j, every k, every click and every pointer drift across
    // the list — a light washing over rows you were only passing through,
    // which reads as the window flashing at the pointer rather than as an
    // answer to anything.
    //
    // Driven by a COUNTER the window bumps, not by `current` changing. The
    // list recycles its delegates, so `current` goes true again whenever a row
    // is reused for the cursor's index — which would replay the sweep on every
    // scroll and every return to a tab.
    Connections {
      target: root
      // A fuller flash for a row that has just been MADE, so `a` shows you
      // where the new thing went before you have typed a character of its
      // name. That is the only pulse this row answers now — see the note on
      // the sweep that used to sit beside it.
      function onMadePulseChanged() {
        if (entryRow.live && entryRow.current) rowBorn.restart();
      }
    }

    property real bornGlow: 0
    SequentialAnimation {
      id: rowBorn
      NumberAnimation { target: entryRow; property: "bornGlow"; to: 1;
                        duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: entryRow; property: "bornGlow"; to: 0;
                        duration: 520; easing.type: Easing.InQuad }
    }

    Rectangle {
      anchors.fill: parent
      clip: true
      // No hover tint. The cursor is already marked and a selection is already
      // marked; a third highlight that follows the pointer just made the list
      // twitch as it crossed.
      // NO CURSOR FILL. The cursor is the SelectBar beside the view, one
      // rectangle that slides between rows; a fill here is a mark that can
      // only blink. What is left is the tick, which is a property of the ROW
      // rather than of where the cursor happens to be, so it stays with it.
      color: entryRow.ticked && !entryRow.cursorOnly
        ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)
        : "transparent"

      Rectangle {
        anchors.fill: parent
        visible: entryRow.bornGlow > 0
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                       0.30 * entryRow.bornGlow)
      }

      // NO SWEEP. A cyan band used to travel across the row when it was
      // opened — 340ms of light passing over the highlight — as an
      // acknowledgement that Return had landed. It is not needed: opening a
      // directory replaces the entire listing, which is the loudest
      // acknowledgement this window can give, and on a file the status line
      // says so. What was left was a flourish playing over the one bar the eye
      // is locked to, every single time.
      //
      // The born flash stays: that answers a question the window cannot
      // otherwise answer — where did the thing I just made go.

      // the outline that replaces the fill
      border.width: entryRow.cursorOnly ? 1 : 0
      border.color: Zenon.msgBorder
    }

    // Still tracked, for the drag box: whether the pointer is ON a row is what
    // decides whether a drag moves that row or draws a selection rectangle.
    HoverHandler {
      id: entryHov
      enabled: entryRow.clickable
      onHoveredChanged: {
        if (hovered) root.hoverRow = true;
        else if (root.hoverRow) root.hoverRow = false;
      }
    }

    // The gesture that starts a drag. Artemis' shape: a DragHandler with no
    // target, which sets Drag.active imperatively once it activates — the
    // handler decides WHEN, the attached group above decides WHAT.
    DragHandler {
      id: rowDrag
      target: null
      enabled: entryRow.clickable && !!entryRow.entry && !root.modal
               && !root.railHover && !root.railDragging
      onActiveChanged: {
        if (!rowDrag.active) return;
        root.draggingRow = true;
        // The picture first, then the drag: Drag.imageSource has to be set
        // before active goes true, or the platform has already taken the
        // gesture and started carrying nothing.
        root.dragPicture(entryRow.entry, (url) => {
          entryRow.Drag.imageSource = url;
          entryRow.Drag.active = true;
        });
      }
    }

    // The row's clicks.
    //
    // The drag used to be a DragHandler, and it never once activated — proved
    // with a logging handler across drags of every length and speed, in every
    // view, with and without permission to take the grab from anything. The
    // row lives inside a Flickable, and whatever the arbitration was doing, the
    // handler was not winning it.
    //
    // This MouseArea, on the other hand, demonstrably receives the press: row
    // clicks and ctrl-clicks have always worked. So the drag is started from
    // here instead, by setting Drag.active once the pointer has moved far
    // enough to mean it — with Drag.Automatic that is what hands the gesture to
    // the platform, and no startDrag() call is needed (calling it as well is
    // what once logged "startDrag() drag must be active").
    //
    // preventStealing keeps the ListView from claiming the gesture as a flick
    // half way through. Nothing is lost by it: the rubber band is already
    // disabled while the pointer is on a row.
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: entryRow.clickable
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

      property bool dragging: rowDrag.active

      onClicked: (m) => {
        // a gesture that became a drag is not also a click
        if (rowMouse.dragging) return;
        if (m.button === Qt.MiddleButton) { entryRow.tabbed(); return; }
        const right = m.button === Qt.RightButton;
        entryRow.chosen(right,
                        (m.modifiers & Qt.ShiftModifier) !== 0,
                        (m.modifiers & Qt.ControlModifier) !== 0);
        if (right && entryRow.actionable) root.openMenuAt(entryRow, m);
      }
      onDoubleClicked: entryRow.opened()
    }

    // Lit while a drag is over this directory, so a drop says where it is
    // going before you let go of it.
    Rectangle {
      anchors.fill: parent
      z: 6
      visible: entryRow.dropTarget
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
      border.width: 1
      border.color: Zenon.cyan
      radius: 4
    }

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 3
      height: parent.height - 8
      radius: 2
      visible: entryRow.ticked
      color: Zenon.cyan
    }


    Row {
      anchors.fill: parent
      leftPadding: 12
      rightPadding: 12

      // the same inner-width arithmetic the headings use, so a cell is always
      // under the heading that names it
      Item {
        width: (parent.width - 24)
          * (entryRow.showMeta ? entryRow.frac.name : 1.0)
        height: parent.height

        // ── what git thinks of this row ─────────────────────────────
        // A one-character gutter, and only while the mode is on: it takes no
        // width otherwise, so a listing outside a repository looks exactly as
        // it did. The mark is git's own letter where git has one, which makes
        // it free to learn for anyone who has read a `git status`.
        Text {
          id: entryGit
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          readonly property string state: (root.git && entryRow.entry)
            ? (root.gitMarks[entryRow.entry.path] || "") : ""
          visible: root.git
          width: root.git ? Math.round(18 * root.zoom) : 0
          horizontalAlignment: Text.AlignHCenter
          text: Terminus.gitMark(entryGit.state)
          color: root.gitInk(entryGit.state)
          opacity: entryRow.dim ? 0.65 : 1
          font.family: Zenon.faceMono
          font.weight: Font.Bold
          // The FILE ICON's size, not something smaller. It was 13 against a
          // 16px name and an 18px glyph, which made the whole gutter read as a
          // footnote — and the one mark that is not a letter disappeared
          // outright. A mark you have to look for twice is not doing the job a
          // gutter exists for.
          font.pixelSize: Math.round(18 * root.zoom)
        }

        Text {
          id: entryGlyph
          anchors.left: entryGit.right
          anchors.verticalCenter: parent.verticalCenter
          // A fixed COLUMN, not the glyph's own width. The nerd font is
          // proportional, so a wide icon and a narrow one ended the glyph at
          // different places and the name followed — which made the gap read
          // as cramped after the wide ones and left the names ragged down the
          // list. A column of constant width fixes both: the icons sit on one
          // centre line and every name starts at the same x.
          width: Math.round(24 * root.zoom)
          horizontalAlignment: Text.AlignHCenter
          text: entryRow.entry ? entryRow.entry.glyph : ""
          color: entryRow.rowInk
          opacity: entryRow.dim ? 0.65 : 1
          font.family: Zenon.face
          // a step above the name it sits beside, as it always was
          font.pixelSize: Math.round(18 * root.zoom)
        }

        // ── the bookmark, beside the name ─────────────────────────
        // So that `b b` is a key you can aim. The toggle goes both ways and
        // the only way to know which way it will go was to open the sidebar
        // and read the list; now the row says so itself. Same glyph the
        // sidebar lists it under, because it is the same fact.
        Text {
          id: entryBookmark
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          visible: !!entryRow.entry && root.isBookmarked(entryRow.entry.path)
          text: "\uF02E"
          color: Zenon.sand
          opacity: entryRow.dim ? 0.65 : 1
          font.family: Zenon.face
          font.pixelSize: Math.round(13 * root.zoom)
        }

        Text {
          id: entryName
          anchors.left: entryGlyph.right
          anchors.leftMargin: 12
          anchors.right: entryBookmark.visible ? entryBookmark.left : parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          visible: !entryRow.editing
          text: entryRow.entry
            ? entryRow.entry.name + (entryRow.entry.isLink ? " →" : "") : ""
          elide: Text.ElideMiddle
          color: entryRow.rowInk
          // The leading dot already says a file is hidden. Dimming it as well
          // said it twice and made half of ~ harder to read for nothing.
          opacity: entryRow.dim ? 0.65 : 1
          font.family: Zenon.face
          font.weight: entryRow.current ? Font.Bold : Font.Medium
          // 16, the same number the grid's tile labels and the preview pane's
          // metadata rows use. Three different places were showing the same
          // filename at three different sizes, and a window reads as one thing
          // or it does not.
          font.pixelSize: Math.round(16 * root.zoom)
        }

        // ── renaming, IN PLACE ──────────────────────────────────────
        // The name is edited where the name is. A dialog for this asked you to
        // read the old name off a card that was covering the list it came
        // from, and answered a question you could see the answer to.
        //
        // The STEM is selected and the extension is not: renaming is almost
        // always about the name and almost never about the type, and a
        // selection that includes ".jpg" makes the common case start with an
        // arrow key.
        //
        // BEHIND A LOADER, and that is a performance change rather than a
        // structural one. A TextInput is among the heaviest items Qt Quick
        // has — an input-method bridge, a selection model, a cursor delegate —
        // and with reuseItems and a cacheBuffer this deep a directory keeps
        // upwards of a hundred delegates alive, every one of which was
        // carrying an edit field and its retry Timer for a rename that only
        // ever happens on one row. Now the field exists while there is
        // something to type into, which is also why the setup moved from
        // onVisibleChanged to Component.onCompleted: being created IS the
        // event.
        Loader {
          id: entryEditBox
          anchors.left: entryGlyph.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          height: entryRow.height
          active: entryRow.editing
          sourceComponent: entryEditField
        }

        Component {
          id: entryEditField

          TextInput {
          id: entryEdit
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          color: Zenon.white
          selectionColor: Zenon.selBg
          selectedTextColor: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Math.round(16 * root.zoom)
          clip: true

          Component.onCompleted: {
            entryEdit.hadFocus = false;
            // blank for something just made — see the note on the tile's field
            const madeNow = root.freshPath !== "" && entryRow.entry
              && entryRow.entry.path === root.freshPath;
            entryEdit.text = madeNow ? "" : (entryRow.entry ? entryRow.entry.name : "");
            if (!madeNow) {
              const stem = Terminus.stem(entryEdit.text);
              entryEdit.select(0, stem.length > 0 ? stem.length : entryEdit.text.length);
            }
            entryEdit.forceActiveFocus();
            editClaim.tries = 0;
            editClaim.restart();
          }

          // ASK UNTIL IT HAS IT, the same as the window's own focusClaim.
          //
          // A rename opened by `r` is asking for focus on an item that has
          // been on screen for a while, and that works first time. Creating
          // something does not: the row is built by the listing that arrives
          // after the file is made, so the forceActiveFocus above lands on an
          // item the scene has not finished placing and is dropped. The field
          // was visible and the keyboard was still in the listing, which is
          // exactly "it makes the file and will not let me name it".
          Timer {
            id: editClaim
            interval: 40
            repeat: true
            property int tries: 0
            onTriggered: {
              if (!entryRow.editing || entryEdit.activeFocus
                  || editClaim.tries++ > 12) {
                editClaim.stop();
                return;
              }
              entryEdit.forceActiveFocus();
            }
          }

          Keys.onReturnPressed: (e) => {
            e.accepted = true;
            root.commitRename(entryRow.entry, entryEdit.text);
          }
          Keys.onEnterPressed: (e) => {
            e.accepted = true;
            root.commitRename(entryRow.entry, entryEdit.text);
          }
          Keys.onEscapePressed: (e) => { e.accepted = true; root.endRename(true); }
          // Clicking away is not an answer either way, so it is a cancel —
          // the same as Escape, and never a silent rename you did not ask for.
          // Clicking away is not an answer either way, so it is a cancel — but
          // only once the field has actually HAD the keyboard, or the retry
          // above would be cancelling the very edit it is trying to open.
          onActiveFocusChanged: {
            if (activeFocus) { entryEdit.hadFocus = true; return; }
            // Only once it has STOPPED asking. editClaim runs until the field
            // has the keyboard or it gives up; a loss while it is still trying
            // is the scene settling, not you clicking away.
            if (entryRow.editing && entryEdit.hadFocus && !editClaim.running)
              root.endRename(false);
          }
          // Nothing to reset per edit any more — the field IS the edit now,
          // and it is destroyed with it. It used to be one field per recycled
          // row, which is why this had to be cleared by hand or a row would
          // carry "I once had focus" into the next file it was reused for and
          // cancel the moment anything blinked.
          property bool hadFocus: false
          }
        }
      }

      // WHERE it was found, and only while there is a search to have found it.
      //
      // A result carries its whole path and the NAME column shows the last
      // component of it, which for a search across a tree is the half you
      // cannot act on: two files called notes.md are the same row twice until
      // this column says which is which. Written relative to the directory the
      // search started in — see Terminus.whereOf — because the absolute path
      // is mostly a prefix repeated down every row.
      Text {
        width: (parent.width - 24) * entryRow.frac.where
        height: parent.height
        visible: entryRow.showMeta && entryRow.frac.where > 0
        verticalAlignment: Text.AlignVCenter
        text: entryRow.entry && entryRow.frac.where > 0
          ? Terminus.whereOf(entryRow.entry.path, root.cwd) : ""
        // The FRONT is what repeats. Two results deep in the same tree differ
        // at the end of the path, so eliding the tail would leave two rows
        // reading the same and eliding the head keeps them apart.
        elide: Text.ElideLeft
        color: Zenon.muted
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.face
        font.pixelSize: Math.round(13 * root.zoom)
      }

      // What KIND of thing it is, under the heading that sorts by it. The word
      // rather than the extension: the sort groups by kind, so the column has
      // to show the thing being grouped or the arrangement looks arbitrary.
      Text {
        width: (parent.width - 24) * entryRow.frac.kind
        height: parent.height
        visible: entryRow.showMeta && entryRow.frac.kind > 0
        verticalAlignment: Text.AlignVCenter
        text: entryRow.entry ? root.kindOf(entryRow.entry) : ""
        elide: Text.ElideRight
        color: Zenon.muted
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.face
        font.pixelSize: Math.round(13 * root.zoom)
      }

      // ── the size cell, and in the usage view its bar ────────────
      //
      // The bar itself lives in UsageBar.qml, shared with the disks down the
      // sidebar — the same measurement drawn the same way in both halves of
      // the window. What is decided here is only what this column measures
      // against, and how far along it this row sits.
      Item {
        id: sizeCell
        width: (parent.width - 24) * entryRow.frac.size
        height: parent.height
        visible: entryRow.showMeta && entryRow.frac.size > 0

        readonly property bool on: root.usage && !!entryRow.entry
        // ONE call, not three. usageOf was asked once by `frac` and twice by
        // `biggest`, and it reads root.dirSizes — so the read has to stay a
        // property read for the dependency, but it only has to happen once.
        readonly property real bytes:
          sizeCell.on ? root.usageOf(entryRow.entry) : 0
        // This row's share of the biggest thing here. 0 before anything is
        // measured, which draws an empty track rather than a lie.
        // WHICH LISTING THIS ROW IS ONE OF. `live` is already the window's
        // word for "in the listing the cursor moves through", so the second
        // pane's rows measure against the second pane's own contents. The
        // parent and preview columns draw no bar at all — showMeta is false
        // there — so they need no third answer.
        readonly property real ceiling:
          entryRow.live ? root.usageMax : root.otherUsageMax
        readonly property real frac: (sizeCell.on && sizeCell.ceiling > 0)
          ? sizeCell.bytes / sizeCell.ceiling : 0
        // The row the mode was opened to find. Warmer, so "which is the big
        // one" is answered before any bar has been compared to any other.
        readonly property bool biggest: sizeCell.on && sizeCell.ceiling > 0
          && sizeCell.bytes >= sizeCell.ceiling
        // Measured, or still being walked. An empty track says "asked, no
        // answer yet"; no track at all would say "not part of this".
        readonly property bool pending: sizeCell.on && !!entryRow.entry
          && entryRow.entry.isDir && root.dirSizes[entryRow.entry.path] === undefined

        UsageBar {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height - 9
          // outside the usage mode this column is a figure, not a proportion
          bars: sizeCell.on
          // grows leftwards, so it ends where the number ends and the two
          // share an edge rather than merely overlapping
          fromRight: true
          frac: sizeCell.frac
          pending: sizeCell.pending
          accent: sizeCell.biggest ? Zenon.sand : Zenon.cyan
          // Brighter in the usage view than the muted grey it uses elsewhere,
          // because grey on a tinted band is the one place that colour stops
          // being readable.
          ink: sizeCell.on
            ? (sizeCell.biggest ? Zenon.sand : Zenon.white) : Zenon.muted
          fontSize: Math.round(14 * root.zoom)
          fontWeight: sizeCell.on ? Font.Medium : Font.Normal
          label: {
            const e = entryRow.entry;
            if (!e) return "";
            if (!e.isDir) return root.sizeTextOf(e);
            // a dash until someone asks, and the real number afterwards
            const walked = root.dirSizes[e.path];
            return walked === undefined ? "\u2014" : Terminus.formatSize(walked);
          }
        }
      }

      Text {
        width: (parent.width - 24) * entryRow.frac.time
        height: parent.height
        visible: entryRow.showMeta && entryRow.frac.time > 0
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        text: entryRow.entry ? root.whenOf(entryRow.entry) : ""
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: Math.round(14 * root.zoom)
      }
    }
  }

  // ── a scrollbar you can actually grab ───────────────────────────────────
  // The rest of the shell wears a 3px position REPORT — right for a popup
  // where the wheel is the only thing that scrolls. A folder of thumbnails is
  // a different problem: it can be hundreds of tiles deep, and dragging to the
  // middle of it beats forty flicks of the wheel.
  //
  // Takes its target as a PROPERTY rather than reaching for an id, because an
  // inline component cannot see the ids of the document that declares it.
  //
  // It hides itself when everything already fits, so attaching one to a view
  // costs nothing in the common case of a short directory.
  // ── A ROW LIGHTS UP BEFORE IT ACTS ──────────────────────────────────────
  // Return used to act with the sheet vanishing on the keystroke, which leaves
  // you unsure which row you were on at the moment it went. Sixty milliseconds
  // up, a hundred and thirty down, and the verb runs on the tail of it.
  //
  // SHARED, because four sheets wore it and each carried its own copy of the
  // same four things: an index, an ink, a SequentialAnimation and an overlay
  // rectangle. Twenty-four references to one idea — which is why two of the
  // three sheets written most recently shipped without it and had to be told.
  // A sheet gets this by asking for it now, not by remembering it.
  //
  // WHAT RUNS ON THE TAIL is handed in as `onDone` rather than hard-wired,
  // because what each sheet does at the end of the flash is the one part of
  // this that genuinely differs: go somewhere, run a verb, launch an
  // application.
  component RowFlash: Item {
    id: flash
    property int at: -1
    property real ink: 0
    property var onDone: null
    readonly property bool running: flashRun.running

    // Returns whether it took, so a caller can hold its own pending state only
    // when there is going to be a tail to spend it on.
    function fire(index) {
      if (flashRun.running) return false;
      flash.at = index;
      flashRun.restart();
      return true;
    }

    // Stopped, so the ScriptAction on the end never runs: leaving is a
    // decision not to, and a flash still in flight would have acted a tenth of
    // a second later.
    function cancel() {
      flashRun.stop();
      flash.ink = 0;
      flash.at = -1;
    }

    SequentialAnimation {
      id: flashRun
      NumberAnimation { target: flash; property: "ink"; to: 1;
                        duration: 60; easing.type: Easing.OutQuad }
      NumberAnimation { target: flash; property: "ink"; to: 0;
                        duration: 130; easing.type: Easing.InQuad }
      ScriptAction {
        script: {
          const f = flash.onDone;
          flash.at = -1;
          if (f) f();
        }
      }
    }
  }

  // The lit row itself. Over everything else on it, so the whole row lights
  // rather than the gaps between a glyph, a label and a key chip.
  component FlashOver: Rectangle {
    property var flash: null
    property int index: -1
    anchors.fill: parent
    z: 3
    visible: !!flash && index === flash.at && flash.ink > 0
    color: flash
      ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.55 * flash.ink)
      : "transparent"
  }

  // ── THE SELECTION, AS ONE BAR THAT MOVES ────────────────────────────────
  // A fill on each delegate cannot travel: the row you leave and the row you
  // arrive at are two different rectangles, so the mark blinks off one and on
  // to the other. The view's own `highlight` is no good either — these views
  // call positionViewAtIndex on every index change, and repositioning the view
  // snaps the highlight to its new row. Measured: with the duration set to
  // five SECONDS the highlight still arrived within one frame.
  //
  // So it is a bar of ours, on its own layer under the list and clipped to it
  // so it cannot ride out over a footer when the list is scrolled. A SIBLING
  // of the view, because a child of it is a child of contentItem, and the view
  // manages the geometry of what it holds.
  //
  // THE ROW IS ANIMATED AND THE SCROLL IS NOT. One expression for both eases
  // the list's own scrolling as well, so the bar lags behind the rows it is
  // marking; the slot is where the cursor is and travels, contentY is where
  // the list has got to and is followed exactly.
  // ── THE SAME CURSOR, ON A GRID ──────────────────────────────────────────
  // A list has one axis and an index is a row; a grid has two and an index is
  // a row AND a column, so the bar travels diagonally between tiles that are
  // not neighbours. Everything else is SelectBar's argument unchanged — one
  // rectangle that moves, not a fill that blinks from one cell to the next.
  //
  // HOW MANY COLUMNS is not something GridView will tell you, so it is worked
  // out the same way the view works it out: the pane's width over the cell's.
  // Asking the delegates instead would mean asking an item that may not exist,
  // because the view only builds the cells it can see.
  //
  // INSET BY 4 WITH A RADIUS OF 6, which is the tile's own fill — this stands
  // exactly where that stood, so nothing about the grid's spacing changes.
  component SelectCell: Item {
    id: cell
    property GridView view: null
    property int index: 0
    property bool on: true
    property bool animate: true

    readonly property int cols: (cell.view && cell.view.cellWidth > 0)
      ? Math.max(1, Math.floor(cell.view.width / cell.view.cellWidth)) : 1

    // NOTHING TO MARK WHEN THERE IS NOTHING THERE. `on` is about whether this
    // list wants a cursor at all; this is about whether it has a row to put
    // one on. An empty directory drew the bar at index 0 anyway — a lone
    // rectangle in the corner of a pane that says "Empty" underneath it.
    //
    // Asked of the VIEW rather than of the caller, so every list that wears
    // one of these is covered by construction and no call site has to
    // remember. Flickable has no `count`; ListView and GridView both do, and
    // the guard is for the moment before `view` is assigned.
    readonly property bool filled: !!cell.view && cell.view.count > 0


    // Parented to the view for the reasons SelectBar gives: outside anyone's
    // layout, and outside contentItem, whose children the view repositions.
    parent: cell.view
    anchors.fill: cell.view
    clip: true
    z: -1

    // ── ON THE RENDER THREAD, for the reason SelectBar's note gives ─────
    // And this is the view that needs it most: a grid is where the thumbnails
    // are, so the GUI thread is at its busiest exactly when the cursor is
    // being run down it.
    //
    // Split the same way — the wrapper takes the scroll on the GUI thread, the
    // cell inside takes the travel on the render thread. Two axes here, so
    // both x and y get an Animator.
    Item {
      width: parent.width
      height: parent.height
      y: -(cell.view ? cell.view.contentY : 0)

      Rectangle {
        readonly property real cw: cell.view ? cell.view.cellWidth : 0
        readonly property real ch: cell.view ? cell.view.cellHeight : 0

        x: (cell.index % cell.cols) * cw + 4
        y: Math.floor(cell.index / cell.cols) * ch + 4
        Behavior on x {
          enabled: cell.animate && root.cursorSlide
          XAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }
        Behavior on y {
          enabled: cell.animate && root.cursorSlide
          YAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }

        width: Math.max(0, cw - 8)
        height: Math.max(0, ch - 8)
        radius: 6
        color: Zenon.selBg
        // See the note on Tile's border: over a thumbnail the fill is
        // hidden by the picture, so the outline is what says "here" —
        // and it has to be on the thing that travels.
        border.width: 1
        border.color: Zenon.cyan
        visible: cell.on && cell.filled
      }
    }
  }

  component SelectBar: Item {
    id: bar
    property Flickable view: null
    property int index: 0
    property real rowH: 30
    property bool on: true
    // False where a change of index is not the cursor MOVING — the miller
    // columns rotate, and every rotation hands all three views a new index at
    // once. Eased, that read as the highlight replaying on every step in and
    // out rather than as a cursor going anywhere.
    property bool animate: true

    // NOTHING TO MARK WHEN THERE IS NOTHING THERE. `on` is about whether this
    // list wants a cursor at all; this is about whether it has a row to put
    // one on. An empty directory drew the bar at index 0 anyway — a lone
    // rectangle in the corner of a pane that says "Empty" underneath it.
    //
    // Asked of the VIEW rather than of the caller, so every list that wears
    // one of these is covered by construction and no call site has to
    // remember. Flickable has no `count`; ListView and GridView both do, and
    // the guard is for the moment before `view` is assigned.
    readonly property bool filled: !!bar.view && bar.view.count > 0

    // ── PARENTED TO THE VIEW, not left where it was declared ────────────
    // It has to be a sibling of the rows rather than one of them, and
    // "declare it next to the ListView" is not enough: a list inside a Column
    // has its neighbours LAID OUT, so the bar was given a slot in the column
    // and its anchors thrown away — open-with drew nothing at all.
    //
    // A direct child of the view is outside anybody's layout, and outside
    // contentItem, which is the other thing that cannot hold it: the view
    // manages the geometry of what contentItem holds and overwrites the
    // animation every frame.
    parent: bar.view
    anchors.fill: bar.view
    clip: true
    z: -1

    // ── THE TRAVEL RUNS ON THE RENDER THREAD ──────────────────────────
    // A NumberAnimation is driven on the GUI thread, which is also where this
    // window parses listings and builds previews. Run the cursor down a
    // directory whose thumbnails are still generating and the bar simply STOPS
    // mid-flight: measured off a 60fps capture, frozen for 20 frames — a third
    // of a second — then again for 13, then 11. Between the stalls it eased
    // perfectly. The animation was never wrong, it was starved.
    //
    // YAnimator runs on the render thread and keeps going while the GUI thread
    // is busy. It can only animate x, y, width, height, opacity, scale and
    // rotation — not a custom `slot` property — so the position is split in
    // two:
    //
    //   the WRAPPER follows the SCROLL, instantly and on the GUI thread, which
    //   is right — contentY is the list moving under the cursor, and a bar
    //   that eased that would lag the rows it is marking;
    //
    //   the BAR inside follows the CURSOR, eased and on the render thread.
    Item {
      width: parent.width
      height: parent.height
      y: -(bar.view ? bar.view.contentY : 0)

      Rectangle {
        width: parent.width
        height: bar.rowH
        y: bar.index * bar.rowH
        // The caller's own `animate` AND the setting: a column that must not
        // ease during a rotation still must not, whatever the switch says.
        Behavior on y {
          enabled: bar.animate && root.cursorSlide
          YAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }
        color: Zenon.selBg
        visible: bar.on && bar.filled
      }
    }
  }

  component ScrollRail: Item {
    id: rail
    required property Flickable target
    // false while its view is not the one on screen
    property bool on: true

    // how far there is left to scroll; 0 when it all fits
    readonly property real over: Math.max(0, rail.target.contentHeight - rail.target.height)
    readonly property bool needed: rail.over > 0
    readonly property real thumbH: rail.needed
      ? Math.max(28, rail.height * (rail.target.height / rail.target.contentHeight))
      : 0
    // how far the thumb's top can travel
    readonly property real span: Math.max(0, rail.height - rail.thumbH)

    width: 10
    // ABOVE THE BODY'S OWN OVERLAYS. A scrollbar has to be the topmost thing
    // along its own strip or it is not a scrollbar, and this had no z at all —
    // so it sat under the empty-space MouseArea that covers the whole body at
    // z 5. Below the last tile in a grid that overlay is enabled, so it took
    // the press and the bar never saw it. For a while the rubber band hid the
    // problem by stealing the gesture first and drawing a selection box; with
    // the band correctly disarmed over the rail, the press simply went
    // nowhere. 9 clears the body's overlays and stays under the dialogs.
    z: 9
    visible: rail.on && rail.needed
    // never eat a click when there is nothing to scroll
    enabled: rail.visible

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 2
      anchors.bottomMargin: 2
      radius: width / 2
      color: Zenon.msgBorder
      opacity: railArea.containsMouse || railArea.dragging ? 0.30 : 0.0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }

    Rectangle {
      id: railThumb
      x: (rail.width - width) / 2
      width: railArea.containsMouse || railArea.dragging ? 6 : 4
      height: rail.thumbH
      radius: width / 2
      color: Zenon.keyInk
      opacity: railArea.dragging ? 0.90 : (railArea.containsMouse ? 0.70 : 0.40)
      // a binding, never written to: dragging moves contentY and the thumb
      // follows from it, so the bar can never disagree with the view
      y: rail.needed ? (rail.target.contentY / rail.over) * rail.span : 0
      Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }

    // One MouseArea over the whole rail rather than one on the thumb: a click
    // on the empty track should jump there too, and hit-testing a 4px thumb
    // with a pointer is a game nobody wants to play.
    MouseArea {
      id: railArea
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: root.railHover = railArea.containsMouse
      // The rail lies OVER a Flickable, and a Flickable steals the mouse grab
      // as soon as it decides a press has become a flick — so a drag down the
      // bar was handed to the view mid-stroke and the thumb stopped following
      // the pointer. preventStealing keeps the grab here for the whole press.
      preventStealing: true
      // where in the thumb it was grabbed, so the point under the pointer
      // stays under the pointer; -1 when not dragging
      property real grab: -1
      readonly property bool dragging: railArea.grab >= 0

      function scrollTo(y) {
        if (rail.span <= 0) return;
        const cy = (y / rail.span) * rail.over;
        rail.target.contentY = Math.max(0, Math.min(rail.over, cy));
      }

      // preventStealing holds off the FLICKABLE, and that was enough while the
      // Flickable was the only thing above the rows. It is not any more: the
      // rubber band is a DragHandler declaring CanTakeOverFromAnything, and
      // below the last row — where hoverRow is false, so the band is armed —
      // it took the gesture off the rail mid-stroke and the thumb stopped
      // following the pointer. A handler cannot be out-ranked, so it is told
      // instead: while the rail has the pointer, the band is not armed.
      onPressed: (m) => {
        const top = railThumb.y;
        if (m.y >= top && m.y <= top + rail.thumbH) {
          railArea.grab = m.y - top;
        } else {
          // clicked the bare track: take the thumb by its middle and go there
          railArea.grab = rail.thumbH / 2;
          railArea.scrollTo(m.y - railArea.grab);
        }
        root.railDragging = true;
      }
      onReleased: { railArea.grab = -1; root.railDragging = false; }
      onCanceled: { railArea.grab = -1; root.railDragging = false; }
      onPositionChanged: (m) => {
        if (!railArea.dragging) return;
        railArea.scrollTo(m.y - railArea.grab);
      }
    }
  }

  component SideHead: Item {
    id: sideHead
    property string label: ""
    // The room above a heading separates it from the group BEFORE it, so the
    // first one does not want any — it would just be a gap under the
    // breadcrumb with nothing on the other side of it to separate from.
    property bool first: false
    width: parent ? parent.width : 0
    // MORE ROOM, NOW THAT THERE IS NO RULE. Space is what separates the groups
    // instead — which is the usual answer and the better one, but it only
    // works if there is enough of it. 44 above, against the 34 that was mostly
    // taken up by the line.
    height: visible ? (sideHead.first ? 24 : 44) : 0

    Text {
      id: sideHeadText
      // 26, which is where a row's LABEL starts: the glyph column is 20 wide
      // from 12, and this puts the heading on the same left edge as the names
      // under it instead of on the icons' edge.
      anchors.left: parent.left
      anchors.leftMargin: 26
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 7
      text: sideHead.label
      // ── A MARK BEFORE IT, NOT A RULE AFTER IT ──────────────────────────
      // The heading was a word with a hairline running off it to the right
      // edge — "BOOKMARKS ————", the group's own underscore. That is a divider
      // doing a heading's job: it carries the eye ACROSS the column, away from
      // the rows the heading is announcing, and it is the loudest thing in a
      // panel whose whole point is the list under it. Taking it away left the
      // label correct and unfurnished.
      //
      // So the weight moved to the FRONT, where a heading's weight belongs: a
      // short cyan tick in the glyph column, the same column every row's icon
      // stands in, so the headings and the rows share one left edge and the
      // label starts where a row's label starts. It marks the group in the one
      // place the eye is already travelling down.
      color: Zenon.keyInk
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 11
      font.letterSpacing: 1.8
    }

    Rectangle {
      anchors.right: sideHeadText.left
      anchors.rightMargin: 9
      anchors.verticalCenter: sideHeadText.verticalCenter
      width: 3
      height: 11
      radius: 1.5
      color: Zenon.cyan
      opacity: 0.85
    }
  }

  // One row of the sidebar: a bookmark or a disk. The disk half adds the mount
  // switch on the right, because "go there" and "make it possible to go there"
  // are two different actions and a single click cannot be both.
  component SideRow: Item {
    id: sideRow
    property string label: ""
    property string detail: ""
    property string glyph: ""
    property bool active: false
    property bool mounted: false
    property bool showMount: false
    // A bookmark can be taken off the list from the row itself. Middle-click
    // already did it and always will, but a middle click is not a thing you
    // find — it is a thing you are told about.
    property bool showRemove: false

    // 0..1 for a mounted disk, -1 when there is nothing to show a gauge from
    property real used: -1

    signal chosen()
    signal removed()
    signal toggledMount()

    // ── CARRYING ONE UP OR DOWN THE LIST ────────────────────────────────
    // Its place among the bookmarks, or -1 for a row that is not one — the
    // disks and the two fixed entries are not in an order anybody chose, so
    // they do not move.
    property int slot: -1

    readonly property bool dragging: sideDrag.active
    // Moved by a TRANSFORM rather than by y: the rows live in a Column and a
    // Column owns its children's y, so setting it would be overwritten on the
    // next layout pass. A transform moves the pixels and leaves the layout
    // believing nothing happened, which is exactly the lie wanted here.
    // A BINDING, never written to. Assigned imperatively it could be left
    // stranded: a hot reload during a drag orphaned the row off-screen with
    // the drop line parked behind it, and the sidebar read as having lost a
    // bookmark. Off `active`, the moment the grab ends — however it ends — the
    // row is home.
    readonly property real dragY:
      sideRow.dragging ? sideDrag.translation.y : 0
    transform: Translate { y: sideRow.dragY }
    z: sideRow.dragging ? 2 : 0
    opacity: sideRow.dragging ? 0.8 : 1

    // The colour a gauge is drawn in. Nearly full is worth saying in colour
    // rather than making you read the number and do the arithmetic.
    readonly property color gaugeInk: sideRow.used > 0.95 ? Zenon.red
      : (sideRow.used > 0.85 ? Zenon.yellow : Zenon.cyan)

    // A gauged row is two lines — the name, and the band with the figure in
    // it — so it is taller. A bookmark has one line and keeps the old height:
    // the sidebar should not grow by a third to hold rows with nothing to
    // measure.
    height: sideRow.used >= 0 ? 46 : 32

    // NO FILL AND NO HOVER TINT. The cursor is sideBar, one rectangle the
    // column slides between rows — a fill here is a mark that can only blink.
    // And the hover never coloured anything after the listing's argument was
    // applied here: the cursor is already marked, and a third highlight
    // following the pointer made the list twitch as it crossed. The hover is
    // still WATCHED, because it is what reveals the remove cross.
    //
    // THE ACTIVE ROW ANNOUNCES ITSELF rather than the bar hunting for it. The
    // rows are of two heights in two Repeaters under a Column, so there is no
    // index the bar could count with; the one row that knows it is the one is
    // the row itself.
    onActiveChanged: if (sideRow.active) root.sideAt = sideRow
    Component.onCompleted: if (sideRow.active) root.sideAt = sideRow

    // The active row gets a bar rather than only a fill — the same mark the
    // listing puts on a selected file, so "this is the one" reads the same way
    // in both halves of the window.
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 3
      height: parent.height - 10
      radius: 2
      visible: sideRow.active
      color: Zenon.cyan
    }
    HoverHandler { id: sideHover }

    // ── WHERE IT WOULD LAND ─────────────────────────────────────────────
    // An INSERTION POINT, 0..n, not a row index: there are n rows and n+1
    // places to put one, and the place after the last row is a real answer.
    // Indexed by row, the line simply vanished the moment you dragged past the
    // bottom of the bookmarks and into the disks — which is exactly where a
    // hand goes when it means "put it at the end", so the gesture went dark at
    // the one moment it needed to say something.
    //
    // One line rather than the whole list shuffling live: the tab strip's note
    // argues for moving pixels and committing on release, and this is the same
    // gesture on a shorter list.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 2
      radius: 1
      color: Zenon.cyan
      visible: root.markDragFrom >= 0 && !sideRow.dragging
               && sideRow.slot === root.markDragTo
    }

    // The last row carries the other end of it, because nothing below it is a
    // bookmark and the disks must not draw a line they cannot answer for.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 2
      radius: 1
      color: Zenon.cyan
      visible: root.markDragFrom >= 0 && !sideRow.dragging
               && sideRow.slot >= 0
               && sideRow.slot === root.bookmarks.length - 1
               && root.markDragTo >= root.bookmarks.length
    }

    DragHandler {
      id: sideDrag
      enabled: sideRow.slot >= 0
      // Nothing to move on our behalf — the transform above is the movement,
      // so the handler only has to report the distance.
      target: null
      xAxis.enabled: false

      onActiveChanged: {
        if (sideDrag.active) {
          root.markDragFrom = sideRow.slot;
          root.markDragTo = sideRow.slot;
          return;
        }
        // The line is drawn BEFORE row `to`; pulling this row out first
        // shifts everything after it down one, so a drop below its old home
        // lands one short unless that is taken off here.
        const at = root.markDragTo;
        const to = at > sideRow.slot ? at - 1 : at;
        root.markDragFrom = -1;
        root.markDragTo = -1;
        root.moveBookmark(sideRow.slot, to);
      }

      onTranslationChanged: {
        if (!sideDrag.active) return;
        // Clamped to the insertion points rather than to the rows, so carrying
        // one down over the disks parks the line under the last bookmark
        // instead of leaving it nowhere.
        const slots = Math.round(sideRow.dragY / Math.max(1, sideRow.height));
        root.markDragTo = Math.max(0,
          Math.min(root.bookmarks.length, sideRow.slot + slots));
      }
    }

    MouseArea {
      anchors.fill: parent
      // BELOW the drag handler, which claims the press first once it decides
      // the pointer is travelling. A click that never travelled still lands
      // here, so tapping a bookmark goes there as it always did.
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      onClicked: (m) => {
        if (sideRow.dragging) return;
        if (m.button === Qt.MiddleButton) sideRow.removed();
        else sideRow.chosen();
      }
    }

    Text {
      id: sideGlyph
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      // A fixed column, for the same reason the listing's glyphs got one: the
      // nerd font is proportional, so a wide icon and a narrow one ended their
      // labels at different places and the names came out ragged.
      width: 20
      horizontalAlignment: Text.AlignHCenter
      text: sideRow.glyph
      color: sideRow.active ? Zenon.cyan : Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 15
    }

    // The name and the figure are TWO items, not one string.
    //
    // They were concatenated — "nvme0n1p8  855.7G free" in a single Text — so
    // a long disk label pushed the figure off the end and elided away the one
    // part you were looking for. Separated, the name gives up its own width
    // and the figure always survives.
    Text {
      id: sideLabel
      anchors.left: sideGlyph.right
      anchors.leftMargin: 8
      anchors.right: sideDetail.visible ? sideDetail.left
        : (mountBtn.visible ? mountBtn.left
          : (removeBtn.visible ? removeBtn.left : sideRow.right))
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      // Above the band rather than centred on the row, once there is a band.
      anchors.verticalCenterOffset: sideRow.used >= 0 ? -11 : 0
      text: sideRow.label
      elide: Text.ElideMiddle
      color: sideRow.active ? Zenon.white : Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 15
    }

    Text {
      id: sideDetail
      anchors.right: mountBtn.visible ? mountBtn.left : parent.right
      anchors.rightMargin: mountBtn.visible ? 8 : 12
      anchors.verticalCenter: sideLabel.verticalCenter
      // Only when there is no band to put it in. A mounted disk writes its
      // figure INSIDE the gauge — the size column does the same thing, and one
      // reading beside a bar plus another on it would be the same number twice.
      visible: sideRow.detail !== "" && sideRow.used < 0
      text: sideRow.detail
      color: Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 13
    }

    // How full it is, under the name it belongs to, and how much is left
    // written inside it. A figure tells you the amount; a bar tells you whether
    // that is a lot — and which of three disks is the one filling up.
    //
    // THE SAME BAR the size column draws, from UsageBar.qml. It used to be a
    // 2px hairline with the figure sitting off to the side, which was a second
    // answer to a question the listing had already settled on an answer for.
    // Only for a mounted filesystem: an unmounted one reports no figures, and
    // a bar drawn from a guess is worse than no bar.
    UsageBar {
      id: gauge
      anchors.left: sideGlyph.right
      anchors.leftMargin: 8
      anchors.right: mountBtn.visible ? mountBtn.left : parent.right
      anchors.rightMargin: mountBtn.visible ? 8 : 12
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 7
      height: 16
      visible: sideRow.used >= 0
      // a disk fills from the left, the way every gauge does
      frac: sideRow.used
      accent: sideRow.gaugeInk
      label: sideRow.detail
      ink: sideRow.used > 0.85 ? sideRow.gaugeInk
        : (sideRow.active ? Zenon.white : Zenon.keyInk)
      fontSize: 13
    }

    Text {
      id: removeBtn
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      // Only while the row is under the pointer: a column of crosses down the
      // sidebar would be four ways to delete something you were only trying to
      // click on.
      visible: sideRow.showRemove && sideHover.hovered
      text: "\uf00d"   // nf-fa-times
      color: removeHov.hovered ? Zenon.red : Zenon.muted
      font.family: Zenon.faceMono
      font.pixelSize: 13

      HoverHandler { id: removeHov }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        onClicked: sideRow.removed()
      }
    }

    Text {
      id: mountBtn
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      visible: sideRow.showMount
      // eject when it is mounted, mount when it is not — the glyph is the
      // action the click performs, not the state it is in
      text: sideRow.mounted ? "\uF052" : "\uF0AB"
      color: mountHov.hovered ? Zenon.cyan
        : (sideRow.mounted ? Zenon.green : Zenon.muted)
      font.family: Zenon.face
      font.pixelSize: 14

      HoverHandler { id: mountHov }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        onClicked: sideRow.toggledMount()
      }
    }
  }

  // A column label that sorts, which is the only header behaviour this window
  // has. The caret marks the active column, the same way zeus' does.
  // ── the row of column headings ──────────────────────────────────────────
  // Both panes need one and neither can borrow the other's, because each is
  // its own view at its own width. The single-pane case still uses the strip
  // above the body; this is what goes inside a half.
  // ── a button ────────────────────────────────────────────────────────────
  // The picker's shape, used by every dialog as well. There were four sets of
  // them — the picker's bordered pills, the confirm card's tinted half-widths,
  // the permissions card's two flat words, the properties card's one — and
  // they agreed on nothing: not the height, not the corner, not what "this is
  // the one Return takes" looks like.
  //
  // `ink` is the colour it answers in and `primary` says it is the default.
  // The primary one BREATHES, because a card whose default action is the
  // dangerous one should say which is which without being read twice.
  // ── a row of exclusive choices in the settings panel ────────────────────
  // The view and the sort key are the same control twice — a strip of buttons
  // where exactly one is lit — so they are one component rather than two
  // Repeaters that would drift apart the first time either was touched.
  component PrefSeg: Item {
    id: seg
    property var options: []
    property string current: ""
    // Values that can actually be picked. null means all of them; anything
    // left out is shown REFUSING rather than hidden, because a button that
    // vanishes teaches nothing about why.
    property var allowed: null
    signal chose(string value)

    // ── WALKED ALONG RATHER THAN FLIPPED ────────────────────────────────
    // A segment is a row of buttons, so the arrows step between them and
    // return takes the next one — skipping any the panel is currently
    // refusing, because landing on a button that will not be pressed is the
    // same dead end the action row avoids.
    readonly property bool cursored: root.prefAt() === seg
    readonly property bool reachable: true
    function activate() { seg.nudge(1); }
    function nudge(d) {
      const o = seg.options;
      const n = o.length;
      if (n === 0) return;
      let i = o.indexOf(seg.current);
      if (i < 0) i = 0;
      for (let t = 0; t < n; t++) {
        i = (i + d + n) % n;
        if (seg.allowed === null || seg.allowed.indexOf(o[i]) >= 0) {
          seg.chose(o[i]);
          return;
        }
      }
    }
    Component.onCompleted: root.prefEnrol(seg)

    width: parent ? parent.width : 0
    height: 34

    Row {
      id: segRow
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      height: 28
      spacing: 6

      Repeater {
        model: seg.options

        delegate: Rectangle {
          id: segBtn
          required property var modelData
          width: (segRow.width - 6 * Math.max(0, seg.options.length - 1))
            / Math.max(1, seg.options.length)
          height: 28
          radius: 5
          readonly property bool ok: seg.allowed === null
            || seg.allowed.indexOf(segBtn.modelData) >= 0
          readonly property bool on: seg.current === segBtn.modelData
          color: segBtn.on
            ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
            : (segHov.hovered && segBtn.ok ? Zenon.surface : "transparent")
          border.width: 1
          border.color: segBtn.on ? Zenon.cyan : Zenon.msgBorder
          opacity: segBtn.ok ? 1 : 0.35
          Behavior on color { ColorAnimation { duration: Zenon.fast } }

          Text {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: segBtn.modelData
            elide: Text.ElideRight
            color: segBtn.on ? Zenon.cyan : Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 14
          }

          HoverHandler { id: segHov; enabled: segBtn.ok }
          MouseArea {
            anchors.fill: parent
            enabled: segBtn.ok
            onClicked: seg.chose(segBtn.modelData)
          }
        }
      }
    }
  }

  // ── a continuous setting in the settings panel ──────────────────────────
  // Opacity and zoom are both a narrow useful range where the difference
  // between two neighbouring values is something you judge by looking at the
  // window rather than by counting presses. Which is a slider, twice.
  component PrefSlider: Item {
    id: sl
    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property string readout: ""
    // dimmed when the value is the ordinary one, so it reads as "normal"
    // rather than as something you have changed
    property real neutral: -1
    // Wide enough for the longest label the panel actually uses. At 88 "Text
    // size" came out as "Text s…", which is a slider labelled by a guess.
    property real labelW: 116
    // One notch of the wheel. A fraction of the span by default, so a slider
    // that says nothing still behaves; the zoom passes the same 0.1 its keys
    // and ctrl+wheel already use, because three ways of doing one thing that
    // move by different amounts is three things to learn.
    property real wheelStep: sl.span / 20
    signal moved(real v)

    // Nudged by the WHEEL'S OWN NOTCH, so the arrows and the wheel and the
    // keys that already step the zoom all move it by the same amount. Nothing
    // to activate: a slider has no state to flip.
    readonly property bool cursored: root.prefAt() === sl
    readonly property bool reachable: true
    function activate() {}
    function nudge(d) {
      const v = Math.max(sl.from,
                         Math.min(sl.to, sl.value + d * sl.wheelStep));
      if (v !== sl.value) sl.moved(v);
    }
    Component.onCompleted: root.prefEnrol(sl)

    width: parent ? parent.width : 0
    height: 34

    readonly property real span: sl.to - sl.from
    readonly property real frac: sl.span > 0
      ? Math.max(0, Math.min(1, (sl.value - sl.from) / sl.span)) : 0

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: slTrack.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: sl.label
      elide: Text.ElideRight
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 15
    }

    Text {
      id: slRead
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 38
      horizontalAlignment: Text.AlignRight
      text: sl.readout
      color: (sl.neutral >= 0 && Math.abs(sl.value - sl.neutral) < 0.001)
        ? Zenon.muted : Zenon.cyan
      font.family: Zenon.face
      font.pixelSize: 13
    }

    Rectangle {
      id: slTrack
      anchors.left: parent.left
      anchors.leftMargin: sl.labelW
      anchors.right: slRead.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      height: 4
      radius: 2
      color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.10)

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.round(sl.frac * slTrack.width)
        radius: 2
        color: Zenon.cyan
      }

      Rectangle {
        x: Math.round(sl.frac * slTrack.width) - 6
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: 6
        color: slArea.pressed ? Zenon.white : Zenon.cyan
        border.width: 1
        border.color: Zenon.black
      }

      // GRABBABLE, which a 4px line is not. The negative margins give the
      // pointer ten pixels either side — and mean a position has to have
      // those ten taken back off it before it is a fraction of the track.
      MouseArea {
        id: slArea
        anchors.fill: parent
        anchors.margins: -10

        function seek(x) {
          if (slTrack.width <= 0) return;
          const f = Math.max(0, Math.min(1, (x - 10) / slTrack.width));
          sl.moved(sl.from + f * sl.span);
        }
        onPressed: (m) => slArea.seek(m.x)
        onPositionChanged: (m) => { if (slArea.pressed) slArea.seek(m.x); }

        // The wheel steps it. Accepted rather than passed on, so a wheel
        // aimed at the slider does not scroll the panel out from under it —
        // the pointer is on the control, so the control is what it means.
        onWheel: (w) => {
          const d = w.angleDelta.y > 0 ? sl.wheelStep : -sl.wheelStep;
          sl.moved(Math.max(sl.from, Math.min(sl.to, sl.value + d)));
          w.accepted = true;
        }
      }
    }
  }

  // ── one switch in the settings panel ────────────────────────────────────
  // A name, the key that does the same thing, and the state as something you
  // can click. Its own component because four of these written out by hand is
  // four chances for one to drift from the other three.
  // ── a preference you DO rather than one you set ─────────────────────────
  // PrefRow's shape — the same height, the same hover, the same label — so the
  // panel stays one list. What differs is the right-hand end: a switch says
  // "this is how things are" and would be a lie here, because nothing stays
  // on afterwards. A verb says what will happen, and a count beside it says
  // how much there is to happen to, which is also how you know whether the row
  // is worth pressing at all.
  // A verb on the batch-rename card. Chip-shaped, like every other small
  // pressable thing in this window, and able to stay LIT — the two on the
  // right are switches and the rest are one-shot actions, but a user should
  // not have to learn two shapes to find that out: the lit ones are the ones
  // that are still true after you let go.
  component BulkVerb: Rectangle {
    id: verb
    property string label: ""
    property bool on: false
    // Nothing to do, said quietly. Still pressable — a disabled control you
    // cannot press and cannot ask why is worse than one that does nothing.
    property bool dim: false
    signal clicked()

    opacity: verb.dim ? 0.4 : 1
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    implicitWidth: verbText.implicitWidth + 18
    implicitHeight: 24
    radius: 5
    color: verb.on
      ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
      : (verbHov.hovered ? Zenon.headBg
         : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05))
    border.width: 1
    border.color: verb.on ? Zenon.cyan : Zenon.msgBorder
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

    Text {
      id: verbText
      anchors.centerIn: parent
      text: verb.label
      color: verb.on ? Zenon.cyan : Zenon.white
      font.family: Zenon.face
      font.pixelSize: 13
    }

    HoverHandler { id: verbHov }
    MouseArea {
      anchors.fill: parent
      onClicked: verb.clicked()
    }
  }

  component PrefAction: Item {
    id: act
    property string label: ""
    // What the row is about to do, or what there is to do it to.
    property string verb: ""
    property bool enabled: true
    signal triggered()

    // The one row that can refuse: with nothing remembered there is nothing to
    // forget, and the cursor steps straight over it rather than landing on a
    // row where return does nothing.
    readonly property bool cursored: root.prefAt() === act
    readonly property bool reachable: act.enabled
    function activate() { if (act.enabled) act.triggered(); }
    function nudge(d) {}
    Component.onCompleted: root.prefEnrol(act)

    width: parent ? parent.width : 0
    height: 32
    opacity: act.enabled ? 1 : 0.45

    // Kept for the verb at the end of the row, which goes cyan under the
    // pointer — a word lighting up is a button saying it is one, and that is
    // not the same thing as a band across the row. The cursor itself is
    // prefBar; see its note.
    HoverHandler { id: actHov }
    MouseArea {
      anchors.fill: parent
      enabled: act.enabled
      onClicked: act.triggered()
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: actVerb.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: act.label
      elide: Text.ElideRight
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 15
    }

    Text {
      id: actVerb
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      text: act.verb
      color: actHov.hovered && act.enabled ? Zenon.cyan : Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 13
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
    }
  }

  // ── A LINE YOU TYPE INTO, ON THE SETTINGS PANEL ────────────────────────
  // The panel had switches, segments, sliders and one action — every control
  // it needed while every setting was a choice between things the window
  // already knew about. A terminal command is not: it is a string only you
  // know, so it needs somewhere to put one.
  //
  // Committed on Return or on losing the field, never per keystroke: half a
  // command is not a command, and writing one to disk on every letter would
  // persist a dozen broken ones on the way to a good one.
  component PrefText: Item {
    id: ptext
    property string label: ""
    property string value: ""
    property string ghost: ""
    signal committed(string v)

    // Worked by being TYPED INTO, so return on it hands the field the keyboard
    // rather than doing something to it. From there the field has the keys and
    // this branch of the handler never runs — see ptextIn's own Tab.
    readonly property bool cursored: root.prefAt() === ptext
    readonly property bool reachable: true
    function activate() { ptextIn.forceActiveFocus(); }
    function nudge(d) {}
    Component.onCompleted: root.prefEnrol(ptext)

    width: parent ? parent.width : 0
    height: 34

    // No ground: the cursor is prefBar. The field's own border goes cyan when
    // it has the keyboard, which is already a mark and a better one.

    Text {
      id: ptextLabel
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 116
      text: ptext.label
      elide: Text.ElideRight
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 13
    }

    Rectangle {
      anchors.left: ptextLabel.right
      anchors.leftMargin: 6
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      height: 24
      radius: 4
      color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
      border.width: 1
      border.color: ptextIn.activeFocus ? Zenon.cyan : Zenon.msgBorder
      Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: ptextIn.forceActiveFocus()
      }

      Text {
        anchors.fill: parent
        anchors.leftMargin: 8
        verticalAlignment: Text.AlignVCenter
        visible: ptextIn.text === "" && !ptextIn.activeFocus
        text: ptext.ghost
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: 12
      }

      TextInput {
        id: ptextIn
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        text: ptext.value
        color: Zenon.white
        selectionColor: Zenon.selBg
        selectedTextColor: Zenon.white
        font.family: Zenon.face
        font.pixelSize: 12
        clip: true
        onEditingFinished: ptext.committed(ptextIn.text)

        // TAB LEAVES THE FIELD RATHER THAN PUTTING A TAB IN IT. While the
        // field has the keyboard, dialogKeys does not — so the panel's own Tab
        // handler never sees this one, and the walk would have stopped dead at
        // the one row you can type into. Commits on the way out, the same as
        // clicking away does.
        Keys.onPressed: (e) => {
          if (e.key !== Qt.Key_Tab && e.key !== Qt.Key_Backtab) return;
          e.accepted = true;
          ptext.committed(ptextIn.text);
          dialogKeys.forceActiveFocus();
          root.prefStep(e.key === Qt.Key_Tab ? 1 : -1);
        }

        // BACK TO THE PANEL, not to the listing. Focusing content left the
        // panel open with nothing holding the keyboard, so the next Tab went
        // nowhere.
        Keys.onEscapePressed: (e) => {
          e.accepted = true;
          ptextIn.text = ptext.value;
          if (prefs.open) dialogKeys.forceActiveFocus();
          else content.forceActiveFocus();
        }
      }
    }
  }

  component PrefRow: Item {
    id: pref
    property string label: ""
    // The key that already did this. The panel's job is partly to teach them.
    property string hint: ""
    property bool on: false
    signal toggled()

    // ── WHAT THE PANEL'S CURSOR NEEDS OF A ROW ──────────────────────────
    // Three things, and every kind of row answers the same three: whether the
    // cursor is on it, whether the cursor may land on it at all, and what
    // happens when it is worked. A switch is worked by being flipped and has
    // nothing to nudge.
    readonly property bool cursored: root.prefAt() === pref
    readonly property bool reachable: true
    function activate() { pref.toggled(); }
    function nudge(d) {}
    Component.onCompleted: root.prefEnrol(pref)

    width: parent ? parent.width : 0
    height: 32

    // NO GROUND OF ITS OWN. The cursor is prefBar, one rectangle the panel
    // slides between rows; a fill here would be a second mark that can only
    // blink. And no hover tint either, which is the listing's own rule — a
    // highlight that follows the pointer made the panel twitch as the mouse
    // crossed it.
    MouseArea {
      anchors.fill: parent
      onClicked: pref.toggled()
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: prefHint.visible ? prefHint.left : prefSwitch.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: pref.label
      elide: Text.ElideRight
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 15
    }

    // A CHIP, like every other key this window writes down. It was bare muted
    // text, which is what a footnote looks like — and the context menu, the
    // F1 sheet and the pending-prefix bar all draw the same fact as a key cap.
    // Three places saying "press this" one way and a fourth saying it another
    // is the panel looking like it came from somewhere else.
    KeyChip {
      id: prefHint
      anchors.right: prefSwitch.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      label: pref.hint
    }

    // A SWITCH, not a tick. A tick says "chosen from a list" and these are not
    // a list — they are four things that are each either on or off, and the
    // knob moving is what makes flipping one feel like flipping a switch.
    Rectangle {
      id: prefSwitch
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 30
      height: 16
      radius: 8
      color: pref.on
        ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.32)
        : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.07)
      border.width: 1
      border.color: pref.on ? Zenon.cyan : Zenon.msgBorder
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

      Rectangle {
        y: 3
        x: pref.on ? parent.width - width - 3 : 3
        width: 10
        height: 10
        radius: 5
        color: pref.on ? Zenon.cyan : Zenon.muted
        Behavior on x {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
        }
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
      }
    }
  }

  // ── a small field on a card ─────────────────────────────────────────────
  // The bulk rename card's two pattern boxes. A bare TextInput on a black card
  // has no frame to say where it is or that it can be typed into, so two of
  // them side by side read as two floating words.
  // ── the shield a modal card stands behind ───────────────────────────────
  //
  // Everything a dialog has to STOP, in one place, because seven dialogs each
  // had a bare `MouseArea { anchors.fill: parent }` and each one leaked the
  // same three ways.
  //
  // ACCEPTS EVERY BUTTON. A MouseArea takes the left button only, so a right
  // click over the scrim went straight through to the listing and opened the
  // actions menu behind the card.
  //
  // EATS THE WHEEL, which a MouseArea does not see at all — so the rows kept
  // scrolling underneath a panel that was describing one of them, and the
  // cursor came back to a list that had moved.
  //
  // And the CARD gets one of its own, below its contents. A card is a plain
  // Rectangle: a press on its empty space is not accepted by anything, falls
  // through to the scrim behind, and dismissed the dialog you were filling in.
  // Declared first inside a card so the buttons and fields above it still get
  // their own clicks.
  // ── a key, drawn as a key ─────────────────────────────────────────────
  // The context menu and the F1 list are both answering the same question —
  // what do I press — and they were answering it in two different voices: one
  // in a border colour at 30% alpha that barely arrived on screen, the other
  // as plain bold text that read as a second label competing with the first.
  //
  // One shape for both. A chip says "this is a thing you type" without having
  // to be loud about it, which is what lets the ink come back up to something
  // legible: it is the outline doing the separating now, not the dimness.
  // ── A SHEET, WHICH IS WHAT EVERY CARD IN THIS WINDOW IS NOW ────────────
  // The send picker proved the shape and the rest of the dialogs were still
  // cards appearing in the middle of the screen from nowhere. A sheet says
  // where it came from: it hangs off the chrome, it is clipped by a well that
  // starts below the bar, and the way in is the way out reversed.
  //
  // Everything specific to one dialog is passed in — how wide, how tall, and
  // whether it is up. Everything that makes it a sheet lives here once, so
  // six dialogs cannot drift into six slightly different sheets.
  //
  // `fromTop` IS PASSED IN rather than read off the chrome. An inline
  // component does not see the ids of the file it is declared in, and the
  // band above the well is the tab strip plus the path bar — which only the
  // caller can measure.
  component Sheet: Item {
    id: sheet
    anchors.fill: parent

    property bool shown: false
    property real fromTop: 0
    // What the CONTENT wants. The corner radius is added on top, because the
    // card's top sits that far above the clip and those pixels are cut away.
    property real cardW: 560
    property real cardH: 200
    default property alias body: sheetBody.data

    // A SHEET IS SLOWER THAN A MENU. It is a bigger object and it travels
    // further, so the shared durations — sized for a card that appears where
    // the pointer already is — read as a snap here. Multiples of the token,
    // so turning the desktop's motion down turns these down too.
    //
    // On the sheet's root rather than on the card, because the scrim and the
    // blur behind it have to move at the same speed: a window that went soft
    // before the sheet had left the bar was two events where there is one.
    readonly property int slideIn: Math.round(Zenon.slow * 2.0)
    readonly property int slideOut: Math.round(Zenon.slow * 1.3)

    // HOW FAR ALONG THE ARRIVAL IS, for anything outside the sheet that has
    // to move with it — the bar's own header, and the blur behind. Read off
    // the card rather than the overlay, which never fades.
    readonly property real cardInk: sheetCard.opacity

    // WHERE IT MEETS THE BAR. The well spans the window, so the card's own x
    // is already the window's — which is what the bar needs to open a gap in
    // its bottom edge exactly this wide, exactly here.
    readonly property real drawnX: sheetCard.x
    readonly property real drawnW: sheetCard.width

    // WHAT IS NOT CONTENT: the corner radius, which is cut away above the
    // clip, and nothing else.
    //
    // NO AIR OF ITS OWN, and that is the whole of the rule. Every card's
    // first row already carries its own — a field centred in a 46px row
    // leaves 11 above it, a line of text with a 12px margin leaves 12 — which
    // is what put the air under the caption band when there was one. Adding
    // more here does not replace that, it stacks on it: measured at 23px of
    // nothing between the bar and the first field of the rename card, which
    // is this 12 plus that 11.
    readonly property real cut: Zenon.dialogRadius

    // The well is everything BELOW the chrome and it clips, so the sheet is
    // genuinely hidden behind the bar rather than fading out on top of it.
    Item {
      id: well
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: sheet.fromTop
      anchors.bottom: parent.bottom
      clip: true

      // Inside the well, so the part that would fall across the bar is cut
      // off with it: a sheet hanging from the chrome does not cast upwards.
      MenuShadow {
        panel: sheetCard
        cornerRadius: Zenon.dialogRadius
        opacity: sheetCard.opacity
      }

      ClippingRectangle {
        id: sheetCard
        anchors.horizontalCenter: parent.horizontalCenter
        // THE BORDER IS NOT PART OF THE ROOM. A ClippingRectangle insets what
        // it holds by its own border on every side, so a card built to hold
        // exactly cardH gave its contents cardH LESS TWO — measured: a 466
        // card handing its body 464, and a palette that asks for fourteen
        // 30px rows getting 418 pixels and slicing the fourteenth.
        //
        // Added to the card rather than subtracted from the caller, because
        // cardW and cardH are what the CONTENT wants and no caller should have
        // to know what the frame around it costs.
        //
        // BOTH AXES. The height was fixed when a sheet sliced a row; the width
        // was left because nothing depended on it being exact — which is only
        // true until something does, and then it is two pixels nobody can
        // find. The well's cap is left alone: that is a ceiling against the
        // window, not a request.
        width: Math.min(sheet.cardW + 2 * sheetCard.border.width,
                        well.width - 40)
        height: Math.min(sheet.cardH + sheet.cut + 2 * sheetCard.border.width,
                         well.height - 40)
        Behavior on width {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }
        Behavior on height {
          NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
        }

        // AT REST ITS TOP SITS ABOVE THE CLIP by exactly the corner radius,
        // so the rounded top corners are cut away and the sheet reads as
        // hanging FROM the bar rather than floating below it. Rounded at the
        // bottom, square at the top.
        y: sheet.shown ? -Zenon.dialogRadius : -sheetCard.height - 2

        // Down on a curve that settles, up on one that accelerates away: a
        // sheet arrives and is dismissed, it does not do the same thing twice.
        Behavior on y {
          NumberAnimation {
            duration: sheet.shown ? sheet.slideIn : sheet.slideOut
            easing.type: sheet.shown ? Easing.OutCubic : Easing.InCubic
          }
        }
        opacity: sheet.shown ? 1 : 0
        Behavior on opacity {
          NumberAnimation {
            duration: sheet.shown ? sheet.slideIn : sheet.slideOut
            easing.type: sheet.shown ? Easing.OutCubic : Easing.InCubic
          }
        }

        color: Zenon.black
        border.color: Zenon.surfaceBorder
        border.width: 1
        radius: Zenon.dialogRadius

        // The card keeps its own clicks, so a press on its empty space does
        // not fall through to the scrim behind and dismiss what you are
        // filling in.
        InputShield {}

        // Below the cut. Everything a caller puts in the sheet lands here, so
        // no caller has to know that the top of the card is not the top of
        // the sheet.
        Item {
          id: sheetBody
          anchors.fill: parent
          anchors.topMargin: sheet.cut
        }
      }
    }
  }

  // ── HOW A CARD ARRIVES, AND LEAVES THE SAME WAY ────────────────────────
  // Seven cards carried `Translate { y: (1 - card.opacity) * 10 }`, which is
  // not an animation but a side effect of one: the travel was a FUNCTION of
  // the fade, so the two could never have different curves, different
  // durations, or different shapes, and ten pixels of drift welded to an
  // opacity ramp is what "static" looks like.
  //
  // Driven by `shown` instead, so the motion is its own animation with its
  // own easing — travelEase, the curve the columns and the sheet move on,
  // rather than the fade's. And ASYMMETRIC: arriving takes the full normal,
  // leaving takes fast, which is the rule the send sheet already follows. The
  // duration binding is read when the animation starts, by which time `shown`
  // is already the value being animated TO, so one expression gives both.
  component CardRise: Translate {
    required property bool shown
    y: shown ? 0 : 14
    Behavior on y {
      NumberAnimation {
        duration: shown ? Zenon.normal : Zenon.fast
        easing.type: Zenon.travelEase
      }
    }
  }

  // The other half. A card that grows the last few percent into place reads
  // as arriving; one that only slides reads as being moved.
  component CardGrow: Scale {
    required property bool shown
    // The card being scaled, so the growth happens about its middle. Not
    // `parent` — a Transform has no parent to ask.
    property Item card: null
    origin.x: card ? card.width / 2 : 0
    origin.y: card ? card.height / 2 : 0
    xScale: shown ? 1 : 0.96
    yScale: shown ? 1 : 0.96
    Behavior on xScale {
      NumberAnimation {
        duration: shown ? Zenon.normal : Zenon.fast
        easing.type: Zenon.travelEase
      }
    }
    Behavior on yScale {
      NumberAnimation {
        duration: shown ? Zenon.normal : Zenon.fast
        easing.type: Zenon.travelEase
      }
    }
  }

  component KeyChip: Rectangle {
    id: chip
    property string label: ""
    // the menu is a compact card and the F1 list is a page you read across the
    // room, so the same chip has to be able to be both sizes
    property int fontSize: 12
    implicitWidth: chipLabel.implicitWidth + Math.round(chip.fontSize * 1.15)
    implicitHeight: chip.fontSize + 8
    radius: 5
    color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.30)
    visible: chip.label !== ""

    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.label
      color: Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: chip.fontSize
    }
  }

  // ── why there is no elastic here ────────────────────────────────────────
  // There was, three times over, and it cannot coexist with the rule above.
  //
  // The rows divide the pane exactly so that nothing is ever half drawn. Any
  // give displaces them, and displacing them reveals a strip at one edge and
  // cuts a row off at the other — so every elastic bounce clips precisely what
  // the fitting exists to prevent, and a gentler bounce only clips less. The
  // last attempt got around it by making the displacement fall off with
  // distance so the far edge never moved, which works and reads as the list
  // stretching; it was still a lot of machinery running on every row to buy an
  // effect that has to fight the layout to exist.
  //
  // One or the other. Not clipping won. If elastic is ever wanted back, this
  // is the trade being reopened, not a bug being fixed.
  //
  // Two things it is worth not rediscovering: a WheelHandler declared inside a
  // Flickable never fires at all — Flickable's default property parents
  // non-Item children to contentItem as a plain QObject, so the handler is
  // registered on nothing (the overlay below says the same) — and Qt's own
  // overshoot is unreachable from here anyway, because the wheel is taken by
  // that overlay and never reaches the flick engine.

  component InputShield: MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    // claimed as well, so nothing behind lights up under the pointer
    hoverEnabled: true
    WheelHandler {
      // every device, and nothing passed on
      onWheel: (e) => { e.accepted = true; }
    }
  }

  component BulkField: Rectangle {
    id: fld
    property string ghost: ""
    property alias text: fldIn.text
    signal accepted()
    // Where Tab goes from here. The card owns the ring — a field should not
    // know what is next to it.
    signal tabbed()
    signal backTabbed()

    function claim() { fldIn.forceActiveFocus(); fldIn.selectAll(); }

    // WHETHER IT ACTUALLY HAS THE KEYBOARD. The retry that opens the card has
    // to ask the field, not the scope around it: activeFocus propagates up a
    // FocusScope, so a scope that got focus while the claim inside it was
    // dropped looks exactly like success from the outside.
    readonly property alias focused: fldIn.activeFocus

    height: 26
    radius: 4
    color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
    border.width: 1
    border.color: fldIn.activeFocus ? Zenon.cyan : Zenon.msgBorder
    Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

    // Declared FIRST, so the input above it still gets the clicks that place
    // its own caret. This one only catches the padding either side of the
    // text, which is otherwise a strip of field that does not focus it.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: fldIn.forceActiveFocus()
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: 8
      verticalAlignment: Text.AlignVCenter
      visible: fldIn.text === ""
      text: fld.ghost
      color: Zenon.muted
      font.family: Zenon.face
      font.pixelSize: 14
    }

    TextInput {
      id: fldIn
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      verticalAlignment: Text.AlignVCenter
      color: Zenon.white
      selectionColor: Zenon.selBg
      selectedTextColor: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 14
      clip: true
      // Before the specific handlers below, which is where Tab has to be
      // caught: a TextInput otherwise hands it to the scene's own focus chain,
      // which in a card full of list delegates lands somewhere arbitrary.
      Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Tab) { e.accepted = true; fld.tabbed(); return; }
        if (e.key === Qt.Key_Backtab) { e.accepted = true; fld.backTabbed(); return; }
      }
      Keys.onReturnPressed: (e) => { e.accepted = true; fld.accepted(); }
      Keys.onEnterPressed: (e) => { e.accepted = true; fld.accepted(); }
    }
  }

  component DialogButton: Rectangle {
    id: btn
    property string label: ""
    property color ink: Zenon.muted
    property bool primary: false
    property bool ready: true
    signal clicked()
    // so a card can keep its keyboard highlight and the pointer in step
    signal hovered()

    implicitWidth: Math.max(96, btnText.implicitWidth + 34)
    implicitHeight: 28
    radius: 4
    // three states, and the pressed one is the point: a button that looks the
    // same under the finger as it does under the pointer has not confirmed
    // anything
    color: !btn.ready ? "transparent"
      : Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b,
                btnArea.pressed ? 0.45 : (btnHover.hovered ? 0.22
                  : (btn.primary ? 0.12 : 0.0)))
    border.width: 1
    border.color: btn.ready ? btn.ink : Zenon.msgBorder
    opacity: btn.ready ? 1 : 0.55

    Behavior on color {
      ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
    }

    // The pulse lives on a child rather than on the button, so hovering can
    // brighten it without fighting an animation for the same property.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: "transparent"
      border.width: 1
      border.color: btn.ink
      visible: btn.primary && btn.ready
      SequentialAnimation on opacity {
        running: btn.primary && btn.ready
        loops: Animation.Infinite
        NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.85; duration: 900; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.ready ? btn.ink : Zenon.muted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 15
    }

    HoverHandler {
      id: btnHover
      enabled: btn.ready
      onHoveredChanged: if (hovered) btn.hovered()
    }
    MouseArea {
      id: btnArea
      anchors.fill: parent
      enabled: btn.ready
      onClicked: btn.clicked()
    }
  }

  component ColHeadBar: Rectangle {
    id: headBar
    y: 0
    height: 22
    color: Zenon.headBg
    // Below this the size and date columns are dropped and the name gets the
    // whole width — a half-width pane cannot carry three columns, and trying
    // ran "5.2 KiB" straight through the end of the filename. Matched by
    // EntryRow.showMeta, so the headings and the rows always agree.
    readonly property bool meta: headBar.width >= root.metaMinWidth
    // False on the pane the keyboard is NOT in. Search results only ever
    // replace the ACTIVE listing, so only the active half grows a WHERE column
    // — the other pane is still showing a directory and would have headed an
    // empty column with it.
    property bool live: true
    readonly property var frac:
      (root.searchMode !== "" && headBar.live) ? root.colFound : root.colPlain

    Row {
      anchors.fill: parent
      leftPadding: 12
      rightPadding: 12

      // THE FRACTIONS ARE OF THE INNER WIDTH, not of the whole row, and they
      // come from root.colPlain / root.colFound so the rows underneath cannot
      // disagree with the headings.
      //
      // A Row's padding comes out of the space its children have, and these
      // used to sum to 0.96 of the full width — which happened to leave about
      // enough for the 24px of padding and no more. Adding the KIND column
      // took them to a round 1.00 and the last one, MODIFIED, was pushed 24px
      // past the right edge: the "sunken" column. Subtracting the padding
      // first makes the arithmetic exact at any width, and makes the headings
      // line up with the cells under them by construction.
      ColHead {
        width: (parent.width - 24) * (headBar.meta ? headBar.frac.name : 1.0)
        label: "NAME"
        sortKey: "name"
      }
      // Only while there are results to place. No sort key: the order of a
      // search is the order the search returned, and a heading that changed it
      // would be offering to re-rank the answer by the one field the ranking
      // was never about.
      ColHead {
        width: headBar.meta ? (parent.width - 24) * headBar.frac.where : 0
        visible: headBar.meta && headBar.frac.where > 0
        label: "WHERE"
      }
      // Sorting by kind arrived without a column to click, so it was the one
      // arrangement you could only reach through a menu or a two-key sequence.
      ColHead {
        width: headBar.meta ? (parent.width - 24) * headBar.frac.kind : 0
        visible: headBar.meta
        label: "KIND"
        sortKey: "kind"
      }
      ColHead {
        width: headBar.meta ? (parent.width - 24) * headBar.frac.size : 0
        visible: headBar.meta
        // The heading says which question the column is answering: in the
        // usage mode it is no longer "how big is this file" but "how much of
        // this directory is this", and the bars under it are not sizes.
        label: root.usage ? "USAGE" : "SIZE"
        sortKey: root.usage ? "usage" : "size"
        rightAlign: true
      }
      ColHead {
        width: headBar.meta ? (parent.width - 24) * headBar.frac.time : 0
        visible: headBar.meta
        label: "MODIFIED"
        sortKey: "time"
        rightAlign: true
        // flush, like the times below it
        padRight: 0
      }
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Zenon.msgBorder
    }
  }

  component ColHead: Item {
    id: head
    property string label: ""
    property string sortKey: ""
    property bool rightAlign: false
    // Matched to the DATA cell this names, not assumed. The size column keeps
    // a 14px gutter before the modified column; the modified column is the
    // last one and sits flush. A single hard-coded pad here put MODIFIED 14px
    // to the left of the times underneath it, which read as centred.
    property real padRight: 14
    height: 22

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: head.rightAlign ? Text.AlignRight : Text.AlignLeft
      rightPadding: head.rightAlign ? head.padRight : 0
      text: head.sortKey !== "" && root.sortKey === head.sortKey
        ? head.label + (root.sortDesc ? " ▾" : " ▴") : head.label
      color: head.sortKey !== "" && root.sortKey === head.sortKey ? Zenon.cyan
        : (headMa.containsMouse ? Zenon.keyInk : Zenon.muted)
      font.family: Zenon.faceFixed
      font.pixelSize: 12
    }

    MouseArea {
      id: headMa
      anchors.fill: parent
      hoverEnabled: true
      // A heading with no key sorts nothing, so it does not offer to: the
      // pointer stays an arrow rather than promising a click that would set
      // the sort key to the empty string and leave the list in no order at all.
      enabled: head.sortKey !== ""
      onClicked: {
        if (root.sortKey === head.sortKey) root.sortDesc = !root.sortDesc;
        else { root.sortKey = head.sortKey; root.sortDesc = false; }
      }
    }
  }


}
