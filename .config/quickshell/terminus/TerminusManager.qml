// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' windows, and the one voice that speaks for them.
//
// There can be several now, which is the whole reason this file exists: two
// TerminusWindows would mean two IpcHandlers claiming the same "Terminus" target,
// and only one of them would win. So the handler lives out here and picks a
// window to act on, and the windows themselves carry no ipc at all.
//
// Window 0 is the one SUPER+E toggles and the one the portal is handed to. The
// rest are spares you asked for with N, and they retire when you close them.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "terminus.js" as Terminus

Scope {
  id: mgr

  // Windows are CREATED, not modelled.
  //
  // The first version put an Instantiator over a JS array of ids and pushed a
  // new id onto it. Replacing the array makes the Instantiator rebuild every
  // delegate, not just add one — so the second press destroyed the window you
  // already had (recreating it hidden, which read as "it closed the first
  // one") and built the rest from scratch at the same time. Exactly the bug
  // reported.
  //
  // createObject touches nothing that already exists, which is the whole
  // requirement here. `wins` holds the live objects so a binding on it — the
  // ipc handler's `w` — re-evaluates when one arrives or leaves; a function
  // call in a binding would not have.
  property var wins: []
  property int nextId: 0

  // The yank buffer, held here rather than in a window, so the windows
  // acknowledge each other: copy in one, paste in another. It was per-window
  // before, which meant two terminus windows side by side could not hand a file
  // between them at all — the only route was a drag, and dragging out of a
  // quickshell surface does not currently work.
  property var clipboard: null

  Component {
    id: winComp
    TerminusWindow { }
  }

  function make(path) {
    const w = winComp.createObject(mgr, { winId: mgr.nextId++, mgr: mgr });
    if (!w) return null;
    const next = mgr.wins.slice();
    next.push(w);
    mgr.wins = next;
    if (path && path !== "") w.goTo(path);
    return w;
  }

  // Window 0, or null. A FUNCTION and not a property on the handler: an
  // IpcHandler exposes its declared properties over ipc, and a var is a
  // QVariant, which cannot cross that boundary — declaring one there logged
  // "Type QVariant cannot be used across IPC" on every load.
  function win() { return mgr.wins.length > 0 ? mgr.wins[0] : null; }

  function spawn(path) {
    const w = mgr.make(path && path !== "" ? path : Paths.home());
    if (!w) return null;
    w.shown = true;
    w.takeFocus();
    return w;
  }

  function retire(id) {
    // the last window is kept: it is the one the keybind and the portal reach,
    // and a manager with nothing in it has nowhere to put the next request
    if (mgr.wins.length < 2) return;
    const keep = [];
    let doomed = null;
    for (const w of mgr.wins) {
      if (w && w.winId === id) doomed = w;
      else keep.push(w);
    }
    if (!doomed) return;
    mgr.wins = keep;
    doomed.destroy();
  }

  // ── the portal's own window ─────────────────────────────────────────────
  // A file dialog is not the same object as your file manager.
  //
  // The portal used to be handed window 0, and the cost of that was hidden in
  // plain sight: a "save as" from a browser navigated the terminus you were
  // browsing in, flipped it to columns view, and hid it once you answered. If
  // window 0 happened to be open already, `shown = true` changed nothing and
  // no dialog ever came forward.
  //
  // So a request gets a window of its own, made on demand and destroyed when
  // it answers. It is deliberately NOT in `wins`: `win()` must stay "window
  // 0", `windows()` lists what you opened, and retire()'s keep-the-last guard
  // must not count a dialog as your last file manager.
  property var pickerWin: null

  // WHERE YOU LAST SAVED SOMETHING, held HERE rather than on the dialog.
  //
  // The dialog is destroyed the moment it answers, and the preference write
  // behind it is debounced — so a value recorded on the window went to the
  // grave with it every single time, and the next save opened wherever the
  // asking program suggested all over again. The manager outlives every
  // picker, which is the whole reason it is the one holding this.
  property string lastSaveDir: ""

  // Recorded, and asked to be written down. Window 0 owns the preferences
  // file; a dialog has no business writing it and will not be alive to.
  function noteSaveDir(d) {
    if (!d || d === "") return;
    mgr.lastSaveDir = d;
    const w = mgr.win();
    if (w) w.persistPrefs();
  }

  function picker() {
    // A DEAD POINTER IS NOT A WINDOW. The dialog can go away by routes this
    // manager never hears about — the compositor closing it, a destroy that
    // raced a new request — and a destroyed QObject held in a `var` does not
    // become null, it simply throws the moment anything is read off it. So the
    // stale pointer was handed the next request, setting `portal` on it threw,
    // the portal was never answered and never will be, and no dialog could be
    // opened again for the life of the shell.
    //
    // Reading one property is the only way to ask "are you still there".
    if (mgr.pickerWin) {
      try {
        if (mgr.pickerWin.winId === -1) return mgr.pickerWin;
      } catch (e) {
        // fall through and build a fresh one
      }
      mgr.pickerWin = null;
    }
    // winId -1 so the window knows it is a dialog rather than a file manager
    mgr.pickerWin = winComp.createObject(mgr, { winId: -1, mgr: mgr });
    return mgr.pickerWin;
  }

  function retirePicker() {
    const w = mgr.pickerWin;
    if (!w) return;
    mgr.pickerWin = null;
    w.shown = false;
    // Deferred: retirePicker is reached from inside the window's own
    // portalAnswer, and destroying an object while its method is still on the
    // stack is the one way to turn a working dialog into a crash.
    Qt.callLater(() => { if (w) w.destroy(); });
  }

  // The reply is written HERE, not in the window that was asked, because that
  // window is destroyed the moment it answers — a Process owned by it would be
  // torn down mid-write and the portal would sit forever waiting on a `.done`
  // marker that never arrived.
  //
  // Queued for the same reason zeus' mixer queues its pactl calls: the log
  // shows requests arriving a second apart, and a second answer must not
  // reset the command of a process still writing the first.
  property var replies: []

  Process {
    id: answerProc
    onExited: mgr.drainReplies()
  }

  function answerPortal(out, paths) {
    if (!out || out === "") return;
    const body = paths.length === 0 ? ":"
      : "printf '%s\n' " + paths.map((p) => Strings.shellQuote(p)).join(" ")
        + " > " + Strings.shellQuote(out);
    // the marker last, and always: it is what the wrapper is waiting on
    mgr.replies.push(["sh", "-c",
      body + "; : > " + Strings.shellQuote(out + ".done")]);
    mgr.drainReplies();
  }

  function drainReplies() {
    if (mgr.replies.length === 0 || answerProc.running) return;
    answerProc.command = mgr.replies.shift();
    answerProc.running = true;
  }

  // One window from the start, hidden, so there is always something for the
  // keybind to reveal.
  // Guarded, because a reload does not always start from nothing: quickshell
  // reuses what it can, and this ran again on a manager that still held its
  // windows — leaving a second one hidden in `wins` that nothing could reach,
  // since spawn() only ever reuses window 0.
  Component.onCompleted: if (mgr.wins.length === 0) mgr.make("")

    IpcHandler {
        target: "Terminus"


      function toggle(): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.shown = !w.shown;
        if (w.shown) { w.refresh(); w.takeFocus(); }
        return w.shown ? "open" : "closed";
      }

      function open(path: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        // SHOWN FIRST, THEN THE DESTINATION. Being shown is what clears the
        // session when "restore session" is off, and a clear that lands after
        // the navigation undoes it — `Terminus open ~/Documents` opened at
        // home. Asking for somewhere always beats the reset.
        w.shown = true;
        w.goTo(path === "" ? Paths.home() : path);
        w.takeFocus();
        return w.cwd;
      }

      function cwd(): string {
        const w = mgr.win();
        if (!w) return "no window"; return w.cwd; }

      // What SUPER+E does. Never hides: a keybind called "open the file
      // manager" that closes it half the time is a coin toss, which is what
      // `toggle` was once there could be more than one window.
      //
      // Window 0 is reused while it is hidden, so the first press does not
      // leave an unreachable hidden window behind a visible new one. After
      // that every press is a new window.
      function spawn(path: string): string {
        // the hidden first window is reused, so the opening press does not
        // leave an unreachable window behind a visible new one
        const first = mgr.wins.length > 0 ? mgr.wins[0] : null;
        if (first && !first.shown) {
          // ONLY when a path was asked for. Falling back to home here is what
          // quietly emptied the restored session: window 0 comes back from
          // disk holding the tabs of the last one, SUPER+E sends no path, and
          // a goTo(home) on the way in walked the tab that was showing to the
          // home directory — overwriting the cwd that had just been restored,
          // and saving it there 400ms later. Do it across a few tabs over a
          // few days and every one of them reads "~".
          //
          // A window that is merely hidden is still WHERE IT WAS. Showing it
          // again is not navigation, so it should not be a navigation; only
          // `open`, which is handed somewhere to go, is.
          // shown first for the reason `open` gives: the clean slate that a
          // disabled "restore session" performs happens on the way in, and a
          // destination asked for afterwards is the one that should stick.
          first.shown = true;
          if (path && path !== "") first.goTo(path);
          first.takeFocus();
          return "window " + first.winId;
        }
        const w = mgr.spawn(path);
        return w ? "window " + w.winId : "failed";
      }

      // Close one by id. `windows` is how you find the id.
      function close(id: int): string {
        mgr.retire(id);
        return mgr.wins.length + " window(s) left";
      }

      function windows(): string {
        // `wins` holds the window OBJECTS now, not ids — looking each one up
        // by treating it as an id printed the QML type name instead
        let s = mgr.wins.length + " window(s):";
        for (const x of mgr.wins) {
          if (!x) { s += " [gone]"; continue; }
          s += " [" + x.winId + (x.shown ? " shown " : " hidden ") + x.cwd + "]";
        }
        // The picker is not one of `wins`, but "is there a dialog up?" is
        // exactly the question this is here to answer.
        const p = mgr.pickerWin;
        if (p) s += " + picker[" + (p.shown ? "shown " : "hidden ") + p.cwd + "]";
        return s;
      }

      // What it currently is, for when something is not behaving and the
      // question is which half is wrong. Every other layer here carries one.
      function status(): string {
        // The picker when there is one, because that is the half that is
        // usually being asked about; window 0 otherwise.
        const w = mgr.pickerWin ? mgr.pickerWin : mgr.win();
        if (!w) return "no window";
        return "visible=" + w.shown
          + " focus=" + w.hasFocus
          + " preview=" + w.previewKind
          + " dual=" + w.dual
          + " other=" + w.otherCwd + "@" + w.otherSel
          + " side=" + w.paneSide + " split=" + w.paneFrac.toFixed(3)
          + " views=" + JSON.stringify(w.paneViews)
          + " renaming=" + w.renaming
          + " marked=" + w.markedCount
          + " view=" + w.viewMode
          + " picking=" + w.picking
          + " cwd=" + w.cwd
          + " rows=" + w.view.length
          + " sel=" + w.sel;
      }

      // Which layout, by name. `v` cycles them from the keyboard; this is the
      // same switch for anything that wants to open terminus already in the view
      // that suits what it is opening — a picture folder in grid, say.
      // The portal's request, handed over by the wrapper script. Everything is a
      // string because that is what ipc arguments are; "1"/"0" is the shape
      // xdg-desktop-portal-termfilechooser already uses for its own flags.
      function pick(multiple: string, directory: string, save: string,
                    path: string, out: string): string {
        // Everything that can throw happens BEFORE any window state is
        // assigned, and that ORDER is the bug this once had.
        //
        // `portal` was set first and Terminus.basename called second — and
        // terminus.js was not imported in this file, so every SAVE request threw
        // a ReferenceError right there. The window was left hidden with
        // picking=true, no dialog appeared, and the next SUPER+E hit spawn()'s
        // "reuse the hidden first window" path and revealed the stale picker
        // instead of a file manager. The portal log said it plainly: every
        // save=0 request answered "picking", every save=1 answered nothing.
        //
        // A save request arrives with a suggested FILE; the others arrive with
        // a directory to start in. Landing in the file's parent with its name
        // already in the field is what every other save dialog does.
        const saving = save === "1";
        let start = path;
        let suggested = "";
        if (saving && path !== "") {
          suggested = Terminus.basename(path);
          start = Terminus.dirname(path);
        }

        const w = mgr.picker();
        if (!w) return "no window";
        // WHERE YOU LAST SAVED beats where the program suggests — see
        // lastSaveDir in the window. The NAME still comes from the request:
        // the program knows what the file should be called, it just has no
        // idea where you keep things.
        if (saving && mgr.lastSaveDir !== "") start = mgr.lastSaveDir;
        w.portal = {
          multiple: multiple === "1",
          directory: directory === "1",
          save: saving,
          out: out
        };
        w.goTo(start === "" ? Paths.home() : start);
        w.setSaveName(suggested);
        w.setView("columns");
        // and one pane: a dialog picks a file, it does not move files about
        w.dual = false;
        w.shown = true;
        // Not takeFocus/focusSaveField: forcing focus on the frame `visible`
        // is set is dropped on the floor, because the surface is not mapped
        // yet. claimFocus keeps trying, and knows a save dialog wants the
        // name field rather than the listing.
        w.claimFocus();
        return "picking";
      }

      function view(mode: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.setView(mode);
        return w.viewMode;
      }
    }
}
